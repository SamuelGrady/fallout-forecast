extends Node
## Autoload "GameManager": run state the host owns and everyone sees.
## - shared decon charge pool, enemy scaling by player count
## - interact requests (client -> host)
## - win / lose checks, run stats, results
## - effect RPCs that every peer must play (spore projectiles and clouds)
## WeatherManager owns the phase timers; GameManager reacts to its phases.

signal combat_hit(killed: bool, critical: bool)
signal decon_changed(charges: int)
signal run_finished(won: bool, results: Dictionary)
signal banner(text: String, color: Color, seconds: float)

const SporeProjectile := preload("res://enemies/mister/spore_projectile.gd")
const MutationRoll := preload("res://game/mutation_roll.gd")
const CrateManager := preload("res://game/crate_manager.gd")
const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")

## Index = player count (1-4); from the design doc's scaling table.
const ENEMY_COUNT_SCALE := [1.0, 1.0, 1.6, 2.2, 2.8]
const ENEMY_HEALTH_SCALE := [1.0, 1.0, 1.1, 1.2, 1.3]
const DECON_CHARGES := [4, 4, 5, 6, 7]
const CRATES_PER_CALM := [3, 3, 4, 5, 6]

var decon_charges := 4
var decon_max := 4
## peer id -> {name, kills, revives, turned, cursed}
var stats := {}
var run_active := false
var finished := false
var last_results := {}

var _lose_check := 0.0
var mutations: Node
var crates: Node


func _ready() -> void:
	WeatherManager.phase_changed.connect(_on_phase_changed)
	mutations = MutationRoll.new()
	mutations.name = "MutationRoll"
	add_child(mutations)
	crates = CrateManager.new()
	crates.name = "CrateManager"
	add_child(crates)


func _process(delta: float) -> void:
	if not run_active or finished or not is_host():
		return
	_lose_check -= delta
	if _lose_check <= 0.0:
		_lose_check = 0.5
		_check_lose()


# ------------------------------------------------------------------ run
## Host: called by main when the level is ready.
func start_run() -> void:
	if not is_host():
		return
	finished = false
	run_active = true
	stats.clear()
	for p in players():
		_stat(p)
	var n := player_count()
	decon_max = DECON_CHARGES[n]
	_set_decon(decon_max)
	WeatherManager.start_run()


func players() -> Array:
	return get_tree().get_nodes_in_group("players")


func player_count() -> int:
	return clampi(players().size(), 1, 4)


func is_solo() -> bool:
	return player_count() == 1


func enemy_count_scale() -> float:
	return ENEMY_COUNT_SCALE[player_count()]


func enemy_health_scale() -> float:
	return ENEMY_HEALTH_SCALE[player_count()] * (0.5 if has_mutation("swarm") else 1.0)


## How many enemies to keep alive and how fast to spawn them, vs. solo.
func enemy_spawn_scale() -> float:
	return ENEMY_COUNT_SCALE[player_count()] * (2.0 if has_mutation("swarm") else 1.0)


func enemy_speed_scale() -> float:
	return 1.4 if has_mutation("runners") else 1.0


func has_mutation(id: String) -> bool:
	return mutations != null and mutations.has(id)


func lever_prompt(player: Node) -> String:
	return mutations.lever_prompt(player)


func pull_lever() -> void:
	var p := get_tree().get_first_node_in_group("local_player")
	if p:
		mutations.pull(p)


func is_voting() -> bool:
	return mutations.is_voting()


func player_for_peer(peer: int) -> Node:
	for p in players():
		if p.get_multiplayer_authority() == peer:
			return p
	return null


func _on_phase_changed(phase: int, _wave: int) -> void:
	if not is_host() or not run_active:
		return
	match phase:
		WeatherManager.Phase.CALM:
			crates.spawn_for_calm()
			# Clear weather: showers refill one charge.
			if decon_charges < decon_max:
				_set_decon(decon_charges + 1)
		WeatherManager.Phase.MUTATION_ROLL:
			mutations.begin()
		WeatherManager.Phase.DOWNPOUR:
			if _wave == WeatherManager.FINAL_WAVE:
				spawn_boss()
		WeatherManager.Phase.CLEARING:
			show_banner("WAVE %d CLEARED  /  RESUPPLY" % _wave, Color("#66dfda"), 3.0)
			Sound.play("reel_land", -6.0)
			var unlocks := {1: "spray_rifle", 2: "flare_gun", 3: "bug_bomb"}
			if unlocks.has(_wave):
				var gun := load("res://weapons/%s.tres" % unlocks[_wave]) as WeaponData
				Settings.unlock_gun(gun.resource_path)
				for p in players():
					p.grant("weapon:" + gun.resource_path)
				show_banner("WAVE %d CLEARED\nUNLOCKED  %s" % [_wave, gun.display_name.to_upper()], Color("#66dfda"))
			mutations.clear()
			for p in players():
				if p.has_method("on_clearing"):
					p.on_clearing()


# ------------------------------------------------------------------ interact
## Local client: use an interactable. Runs on the host directly, or asks it.
func interact(target: Node, player: Node) -> void:
	if is_host():
		_do_interact(target, player)
	else:
		_request_interact.rpc_id(1, target.get_path())


@rpc("any_peer", "call_remote", "reliable")
func _request_interact(path: NodePath) -> void:
	if not is_host():
		return
	var player := player_for_peer(multiplayer.get_remote_sender_id())
	var target := get_node_or_null(path)
	if player and target is Interactable:
		_do_interact(target, player)


func _do_interact(target: Interactable, player: Node) -> void:
	var reach: float = target.radius + 1.5
	if player.global_position.distance_to(target.global_position) <= reach and target.can_interact(player):
		target.interact(player)


# ------------------------------------------------------------------ decon
func use_decon(player: Node) -> void:
	if decon_charges <= 0 or float(player.get("suit_integrity")) >= 99.0:
		return
	Sound.play("decon")
	player.set("suit_integrity", 100.0)
	_set_decon(decon_charges - 1)


func add_decon_charge(amount := 1) -> void:
	_set_decon(decon_charges + amount)


func _set_decon(value: int) -> void:
	decon_charges = maxi(value, 0)
	decon_changed.emit(decon_charges)
	if _online():
		_sync_decon.rpc(decon_charges)


@rpc("authority", "call_remote", "reliable")
func _sync_decon(value: int) -> void:
	decon_charges = value
	decon_changed.emit(value)


# ------------------------------------------------------------------ stats
func _stat(player: Node) -> Dictionary:
	var peer := player.get_multiplayer_authority()
	if not stats.has(peer):
		var display = player.get("display_name")
		stats[peer] = {"name": str(display) if display != null else "Player %d" % peer,
			"kills": 0, "revives": 0, "turned": 0, "cursed": ""}
	return stats[peer]


func record_kill(source: Node) -> void:
	if is_host() and source and source.is_in_group("players"):
		_stat(source).kills += 1


func record_revive(reviver: Node) -> void:
	if is_host() and reviver:
		_stat(reviver).revives += 1


func record_turned(player: Node) -> void:
	if is_host() and player:
		_stat(player).turned += 1


func record_cursed(player: Node, weapon_name: String) -> void:
	if is_host() and player:
		_stat(player).cursed = weapon_name


# ------------------------------------------------------------------ boss
## Host: Cumulus rolls in over Main Street; the Acid Storm won't end until it dies.
func spawn_boss() -> void:
	if not get_tree().get_nodes_in_group("boss").is_empty():
		return
	var world := _world()
	var spawner := world.get_node_or_null("Enemies") if world else null
	var anchor := get_tree().get_first_node_in_group("boss_anchor") as Node3D
	if spawner == null:
		return
	var boss: Node3D = (load("res://enemies/boss/boss_cumulus.tscn") as PackedScene).instantiate()
	spawner.add_child(boss, true)
	boss.global_position = anchor.global_position if anchor else Vector3(0, 18, 0)
	WeatherManager.hold = true
	WeatherManager.intensity_override = 1.0
	show_banner("CUMULUS IS HERE: burst its three sacs!", Color("8FD65A"), 4.0)


## Host: the core popped. Clear skies, then the win.
func boss_defeated() -> void:
	WeatherManager.intensity_override = 0.0
	WeatherManager.hold = false
	show_banner("CUMULUS BROKE: the storm is over!", Color(0.4, 1, 0.6), 4.0)
	get_tree().create_timer(5.0).timeout.connect(finish.bind(true))


# ------------------------------------------------------------------ win / lose
func _check_lose() -> void:
	var all := players()
	if all.is_empty():
		return
	for p in all:
		var s := str(p.get("state"))
		if s == "ok":
			return
		if s == "downed" and p.has_method("can_self_revive") and p.can_self_revive():
			return
	finish(false)


func finish(won: bool) -> void:
	if finished or not is_host():
		return
	finished = true
	var results := {
		"won": won,
		"waves": WeatherManager.wave if won else WeatherManager.wave - 1,
		"players": stats.duplicate(true),
	}
	if _online():
		_finish.rpc(won, results)
	_finish(won, results)


@rpc("authority", "call_remote", "reliable")
func _finish(won: bool, results: Dictionary) -> void:
	finished = true
	run_active = false
	last_results = results
	banner.emit("PINECREST IS SAFE" if won else "PINECREST IS LOST", Color(0.4, 1, 0.6) if won else Color(1, 0.3, 0.3), 4.0)
	run_finished.emit(won, results)


# ------------------------------------------------------------------ shared effects
## Host: a spore glob on an arc, simulated on every peer; only the host's cloud hurts.
func spawn_spore(from: Vector3, to: Vector3, flight: float, damage_per_second: float) -> void:
	if _online():
		_spawn_spore.rpc(from, to, flight, damage_per_second)
	_spawn_spore(from, to, flight, damage_per_second)


@rpc("authority", "call_remote", "reliable")
func _spawn_spore(from: Vector3, to: Vector3, flight: float, damage_per_second: float) -> void:
	var world := _world()
	if world == null:
		return
	var spore := SporeProjectile.new()
	spore.damage_per_second = damage_per_second
	world.add_child(spore)
	spore.launch(from, to, flight)


## Host: a spore cloud right here (Spores mutation, boss).
func spawn_cloud(at: Vector3, damage_per_second: float, radius := 2.5) -> void:
	if _online():
		_spawn_cloud.rpc(at, damage_per_second, radius)
	_spawn_cloud(at, damage_per_second, radius)


@rpc("authority", "call_remote", "reliable")
func _spawn_cloud(at: Vector3, damage_per_second: float, radius: float) -> void:
	var world := _world()
	if world == null:
		return
	var cloud := SporeCloud.new()
	cloud.damage_per_second = damage_per_second
	cloud.radius = radius
	world.add_child(cloud)
	cloud.global_position = at


func show_banner(text: String, color: Color, seconds := 3.0) -> void:
	if _online():
		_banner.rpc(text, color, seconds)
	_banner(text, color, seconds)


@rpc("authority", "call_remote", "reliable")
func _banner(text: String, color: Color, seconds: float) -> void:
	banner.emit(text, color, seconds)


func _world() -> Node:
	var scene := get_tree().current_scene
	if scene:
		return scene
	var root := get_tree().root
	return root.get_child(root.get_child_count() - 1)


func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
