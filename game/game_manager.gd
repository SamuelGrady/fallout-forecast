extends Node
## Autoload "GameManager": run state the host owns and everyone sees.
## - shared decon charge pool, enemy scaling by player count
## - interact requests (client -> host)
## - win / lose checks, run stats, results
## - effect RPCs that every peer must play (spore projectiles and clouds)
## WeatherManager owns the phase timers; GameManager reacts to its phases.

signal combat_hit(killed: bool, critical: bool)
signal decon_changed(charges: int)
signal weapon_unlocked(weapon_name: String)
signal run_finished(won: bool, results: Dictionary)
signal banner(text: String, color: Color, seconds: float)
signal tape_choice_changed

const SporeProjectile := preload("res://enemies/mister/spore_projectile.gd")
const MutationRoll := preload("res://game/mutation_roll.gd")
const CrateManager := preload("res://game/crate_manager.gd")
const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")
const FeatTracker := preload("res://game/feat_tracker.gd")

## Index = player count (1-4); from the design doc's scaling table.
const ENEMY_COUNT_SCALE := [1.0, 1.0, 1.6, 2.2, 2.8]
const ENEMY_HEALTH_SCALE := [1.0, 1.0, 1.1, 1.2, 1.3]
const DECON_CHARGES := [4, 4, 5, 6, 7]

var decon_charges := 4
var decon_max := 4
## peer id -> {name, kills, revives, turned, cursed}
var stats := {}
var run_active := false
var finished := false
## Set the moment Cumulus dies so a late wipe can't turn the win into a loss.
var victory_locked := false
var awaiting_tape_choice := false
var endless := false
var endless_score := 0
var _waves_survived := 0
var _drafted_wave := 0
var _run_id := 0
var last_results := {}
var map_id := Maps.DEFAULT_ID

var _lose_check := 0.0
var mutations: Node
var crates: Node
## Feats and achievements (game/feat_tracker.gd): host confirms, players save.
var feats: Node


func _ready() -> void:
	WeatherManager.phase_changed.connect(_on_phase_changed)
	WeatherManager.lightning_struck.connect(_on_lightning_struck)
	Net.run_peer_loaded.connect(_on_run_peer_loaded)
	mutations = MutationRoll.new()
	mutations.name = "MutationRoll"
	add_child(mutations)
	crates = CrateManager.new()
	crates.name = "CrateManager"
	add_child(crates)
	feats = FeatTracker.new()
	feats.name = "Feats"
	add_child(feats)


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
	_waves_survived = 0
	_drafted_wave = 0
	_set_tape_state(false, false, false)
	_run_id += 1
	_run_started_ms = Time.get_ticks_msec()
	run_active = true
	stats.clear()
	if mutations:
		mutations.reset_run()
	for p in players():
		p.set("max_health", 100.0)
		_stat(p)
	feats.reset_run()
	var n := player_count()
	decon_max = DECON_CHARGES[n]
	_set_decon(decon_max)
	var loot := RunLoot.find(get_tree())
	loot.begin(_run_id)
	crates.begin_run()
	WeatherManager.start_run()
	for peer: int in Net.run_peers:
		_on_run_peer_loaded(peer)
		loot.sync_to_peer(peer)


## Host: send the current state once the peer has finished loading the map.
func _sync_run_to_peer(peer_id: int) -> void:
	if not is_host() or not run_active:
		return
	WeatherManager.sync_to_peer(peer_id)
	_sync_decon.rpc_id(peer_id, decon_charges)
	if mutations:
		mutations.sync_to_peer(peer_id)
	if crates:
		crates.sync_to_peer(peer_id)
	var world := _world()
	var spawner := world.get_node_or_null("Enemies") if world else null
	if spawner:
		spawner.sync_to_peer(peer_id)
	var boss := get_tree().get_first_node_in_group("boss") as Node3D
	if boss and not boss.get("dead"):
		_spawn_boss.rpc_id(peer_id, boss.global_position)


func _on_run_peer_loaded(peer_id: int) -> void:
	if not is_host() or not run_active or finished:
		return
	_sync_tape_state.rpc_id(peer_id, awaiting_tape_choice, endless, victory_locked)
	_sync_run_to_peer(peer_id)
	WeatherManager.sync_puddles_to_peer(peer_id)


func players() -> Array:
	return get_tree().get_nodes_in_group("players")


func player_count() -> int:
	return clampi(players().size(), 1, 4)


func is_solo() -> bool:
	return player_count() == 1


func enemy_count_scale() -> float:
	return ENEMY_COUNT_SCALE[player_count()]


func enemy_health_scale() -> float:
	var escalation := 1.0 + clampf(WeatherManager.wave - WeatherManager.FINAL_WAVE, 0.0, 10.0) * .08
	return ENEMY_HEALTH_SCALE[player_count()] * escalation * (0.5 if has_mutation("swarm") else 1.0)


## How many enemies to keep alive and how fast to spawn them, vs. solo.
func enemy_spawn_scale() -> float:
	return ENEMY_COUNT_SCALE[player_count()] * (2.0 if has_mutation("swarm") else 1.0)


func enemy_speed_scale() -> float:
	var escalation := 1.0 + clampf((WeatherManager.wave - WeatherManager.FINAL_WAVE) * .025, 0.0, .42)
	return escalation * (1.4 if has_mutation("runners") else 1.0)


func has_mutation(id: String) -> bool:
	return mutations != null and mutations.has(id)


# ------------------------------------------------------------------ player mutations
## Players mutate right alongside the infected: every Mutation Draft grants the
## squad a persistent bio-mutation (2 on a Jackpot) that stacks across the run.
const PLAYER_MUTATIONS := {
	"acid_blood": {
		"name": "ACID BLOOD",
		"desc": "Taking health damage splashes burning acid around you",
		"color": Color(0.62, 1.0, 0.25),
	},
	"chitin_suit": {
		"name": "CHITIN SUIT",
		"desc": "+25 max health and suit drains 35% slower in rain",
		"color": Color(0.45, 0.92, 0.88),
	},
	"adrenaline_glands": {
		"name": "ADRENALINE",
		"desc": "Move 18% faster and jump 20% higher",
		"color": Color(1.0, 0.72, 0.25),
	},
	"bone_piercer": {
		"name": "BONE PIERCER",
		"desc": "Headshots deal 2.6x damage and shots pierce +1 enemy",
		"color": Color(1.0, 0.42, 0.56),
	},
	"reflex_tendons": {
		"name": "REFLEX TENDONS",
		"desc": "Reload 35% faster and fire 20% faster",
		"color": Color(1.0, 0.88, 0.35),
	},
	"magnet_hands": {
		"name": "MAGNET HANDS",
		"desc": "Pull scrap & pickups from 3x range and gain +25% bonus scrap",
		"color": Color(0.45, 0.82, 1.0),
	},
	"voltaic_veins": {
		"name": "VOLTAIC VEINS",
		"desc": "Every 4th shot arcs lightning to 2 nearby enemies",
		"color": Color(0.48, 0.94, 1.0),
	},
	"vampiric_siphon": {
		"name": "BIO-SIPHON",
		"desc": "Every kill restores +5 health and +6% suit integrity",
		"color": Color(0.96, 0.32, 0.62),
	},
	"blast_glands": {
		"name": "VOLATILE ROUNDS",
		"desc": "+30% blast radius & damage; kills can pop a shockwave",
		"color": Color(1.0, 0.54, 0.22),
	},
	"hydro_skin": {
		"name": "HYDRO-SKIN",
		"desc": "Rain heals +2.5 HP/s while your suit holds; resists Undertow",
		"color": Color(0.32, 0.88, 0.74),
	},
	"hyper_focus": {
		"name": "PREDATOR EYES",
		"desc": "ADS cuts spread & recoil sharply and deals +25% damage",
		"color": Color(0.76, 0.58, 1.0),
	},
}


func has_player_mutation(id: String) -> bool:
	return mutations != null and mutations.has_player(id)


func active_player_mutations() -> Array:
	var out := []
	if mutations:
		for id in mutations.player_mutations:
			if PLAYER_MUTATIONS.has(id):
				out.append(PLAYER_MUTATIONS[id])
	return out


func headshot_multiplier() -> float:
	return 2.6 if has_player_mutation("bone_piercer") else 2.0


func extra_pierce() -> int:
	return 1 if has_player_mutation("bone_piercer") else 0


func reload_scale() -> float:
	return 0.65 if has_player_mutation("reflex_tendons") else 1.0


func fire_rate_scale() -> float:
	return 0.8 if has_player_mutation("reflex_tendons") else 1.0


func player_speed_scale() -> float:
	return 1.18 if has_player_mutation("adrenaline_glands") else 1.0


func jump_scale() -> float:
	return 1.2 if has_player_mutation("adrenaline_glands") else 1.0


func ammo_pickup_fraction() -> float:
	return 0.6 if has_player_mutation("magnet_hands") else 0.4


func pickup_reach() -> float:
	return 5.0 if has_player_mutation("magnet_hands") else 1.8


func scrap_pickup_scale() -> float:
	return 1.25 if has_player_mutation("magnet_hands") else 1.0


func suit_drain_scale() -> float:
	return 0.65 if has_player_mutation("chitin_suit") else 1.0


func bonus_max_health() -> float:
	return 25.0 if has_player_mutation("chitin_suit") else 0.0


func ads_damage_scale() -> float:
	return 1.25 if has_player_mutation("hyper_focus") else 1.0


func explosive_damage_scale() -> float:
	return (1.35 if has_mutation("pressure_front") else 1.0) * (1.3 if has_player_mutation("blast_glands") else 1.0)


func explosive_knockback_scale() -> float:
	return 2.0 if has_mutation("pressure_front") else 1.0


func explosive_radius_scale() -> float:
	return 1.3 if has_player_mutation("blast_glands") else 1.0


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


# ------------------------------------------------------------------ global pause
## In a session, a pause stops the game for everyone (host-authoritative), and
## anyone can resume. Solo play just pauses locally as before.
signal global_pause_changed(paused: bool, by: String)
var global_paused := false
var paused_by := ""


func request_pause(paused: bool) -> void:
	if not _online():
		return
	var who := Net.local_name if Net.local_name != "" else "A PLAYER"
	if is_host():
		_apply_pause(paused, who)
		_sync_pause.rpc(paused, who)
	else:
		_request_pause_rpc.rpc_id(1, paused, who)


@rpc("any_peer", "call_remote", "reliable")
func _request_pause_rpc(paused: bool, who: String) -> void:
	if not is_host():
		return
	_apply_pause(paused, who)
	_sync_pause.rpc(paused, who)


@rpc("authority", "call_remote", "reliable")
func _sync_pause(paused: bool, who: String) -> void:
	_apply_pause(paused, who)


func _apply_pause(paused: bool, who: String) -> void:
	global_paused = paused
	paused_by = who if paused else ""
	get_tree().paused = paused or not MenuState.stack.is_empty()
	global_pause_changed.emit(paused, who)


# ------------------------------------------------------------------ ready up
signal ready_changed(ready_count: int, needed: int)
var _ready_peers := {}
var ready_count := 0


func can_ready_up() -> bool:
	return run_active and not finished and not WeatherManager.hold \
			and WeatherManager.phase in [WeatherManager.Phase.CALM, WeatherManager.Phase.CLEARING] \
			and WeatherManager.phase_time_left > 3.0


## Owner: this player is done looting and wants the next phase now.
func ready_up() -> void:
	if not can_ready_up():
		return
	if is_host():
		_mark_ready(multiplayer.get_unique_id() if _online() else 1)
	else:
		_request_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_ready() -> void:
	if is_host():
		_mark_ready(multiplayer.get_remote_sender_id())


func _mark_ready(peer: int) -> void:
	if not can_ready_up():
		return
	_ready_peers[peer] = true
	_broadcast_ready(_ready_peers.size(), player_count())
	if _ready_peers.size() >= player_count():
		_ready_peers.clear()
		WeatherManager.skip_wait()


func _broadcast_ready(count: int, needed: int) -> void:
	if _online():
		_ready_changed.rpc(count, needed)
	ready_count = count
	ready_changed.emit(count, needed)


@rpc("authority", "call_remote", "reliable")
func _ready_changed(count: int, needed: int) -> void:
	ready_count = count
	ready_changed.emit(count, needed)


func _on_phase_changed(phase: int, _wave: int) -> void:
	if is_host() and not _ready_peers.is_empty():
		_ready_peers.clear()
		_broadcast_ready(0, player_count())
	if not is_host() or not run_active:
		return
	feats.on_phase(phase, _wave)
	match phase:
		WeatherManager.Phase.DRIZZLE:
			crates.start_drizzle()
		WeatherManager.Phase.CALM:
			crates.start_calm()
			# Clear weather: showers refill one charge.
			if decon_charges < decon_max:
				_set_decon(decon_charges + 1)
			# Right after a cleared wave the Mutation Draft opens inside Calm.
			# It holds the Calm countdown until the result shows.
			if _wave >= 2 and _drafted_wave < _wave:
				_drafted_wave = _wave
				mutations.begin()
		WeatherManager.Phase.MUTATION_ROLL:
			# Legacy phase value (never entered by next_phase any more).
			if mutations.stage == "":
				mutations.begin()
		WeatherManager.Phase.DOWNPOUR:
			if _wave == WeatherManager.FINAL_WAVE:
				spawn_boss()
		WeatherManager.Phase.CLEARING:
			crates.end_wave()
			var newly_cleared := _wave > _waves_survived
			if newly_cleared:
				_waves_survived = _wave
				if endless:
					endless_score += 500 + 100 * (_wave - WeatherManager.FINAL_WAVE)
			show_banner("WAVE %d CLEAR" % _wave, Color("#66dfda"), 2.2)
			if not endless:
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
	player.set("suit_integrity", 100.0)
	feats.on_decon(player)
	_set_decon(decon_charges - 1)


func add_decon_charge(amount := 1) -> void:
	_set_decon(decon_charges + amount)


func _set_decon(value: int) -> void:
	decon_charges = maxi(value, 0)
	decon_changed.emit(decon_charges)
	if _online():
		Net.rpc_to_all(_sync_decon, [decon_charges])


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


var _volatile_popping := false


func record_kill(source: Node, at := Vector3.INF, elite := false, _miniboss := false) -> void:
	if not is_host() or not source or not source.is_in_group("players"):
		return
	_stat(source).kills += 1
	# Scrap is no longer paid per kill: infected drop ground scrap pickups.
	if endless:
		endless_score += 250 if elite else 100
	# Bio-Siphon: each kill restores health and suit integrity.
	if has_player_mutation("vampiric_siphon"):
		if source.has_method("heal"):
			source.heal(5.0)
		var suit := float(source.get("suit_integrity"))
		source.set("suit_integrity", minf(100.0, suit + 6.0))
	# Volatile Rounds: kills have a 25% chance to pop a 3.8 m shockwave.
	if has_player_mutation("blast_glands") and at != Vector3.INF and not _volatile_popping and randf() < 0.25:
		_volatile_popping = true
		var pop_radius := 3.8 * explosive_radius_scale()
		var pop_dmg := 35.0 * explosive_damage_scale()
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as EnemyBase
			if enemy == null or enemy.health <= 0.0:
				continue
			if enemy.global_position.distance_to(at) <= pop_radius:
				var push := enemy.global_position - at
				push.y = 0.0
				enemy.take_blast(pop_dmg, source, at, push.normalized() * 6.0 * explosive_knockback_scale())
		broadcast_blast(at + Vector3.UP * 0.6, pop_radius * 0.35, Color(1.0, 0.54, 0.22, 0.85))
		_volatile_popping = false


## Conductors mutation: lightning snaps to an infected within 20 m and chains
## across up to 4 targets within 11 m of each hop.
func _on_lightning_struck(position: Vector3, _seed: int) -> void:
	if not is_host() or not run_active or finished or not has_mutation("conductors"):
		return
	var first: EnemyBase = null
	var best_d := 20.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.health <= 0.0:
			continue
		var d := Vector2(enemy.global_position.x - position.x, enemy.global_position.z - position.z).length()
		if d < best_d:
			best_d = d
			first = enemy
	if first == null:
		return
	var hit: Array[EnemyBase] = []
	var points: Array = [position + Vector3.UP * 10.0]
	var cur: EnemyBase = first
	for _hop in 4:
		if cur == null or cur.health <= 0.0:
			break
		hit.append(cur)
		var center := cur.global_position + Vector3.UP * 1.0
		points.append(center)
		cur.reveal(3.0)
		cur.stagger(0.45)
		cur.take_damage(35.0, null)
		var next: EnemyBase = null
		var next_d := 11.0
		for node in get_tree().get_nodes_in_group("enemies"):
			var cand := node as EnemyBase
			if cand == null or cand.health <= 0.0 or cand in hit:
				continue
			var d := cand.global_position.distance_to(center)
			if d < next_d:
				next_d = d
				next = cand
		cur = next
	broadcast_arc(points, Color(0.45, 0.95, 1.0))


func broadcast_arc(points: Array, color: Color) -> void:
	if points.size() < 2:
		return
	if _online():
		Net.rpc_to_all(_draw_arc, [points, color])
	_draw_arc(points, color)


@rpc("authority", "call_remote", "unreliable")
func _draw_arc(points: Array, color: Color) -> void:
	if Net.dedicated or points.size() < 2:
		return
	Perf.mark("arc fx")
	var world := _world()
	if world == null:
		return
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		ShotFX.tracer(world, a, b, color)
		ShotFX.sparks(world, b, Vector3.UP, 4)
	ShotFX.flash(world, points[points.size() - 1], color, 5.0, 0.08)
	Sound.play_at("dome_deploy", points[0], -14.0, 1.8)


func broadcast_blast(at: Vector3, size: float, color: Color) -> void:
	if _online():
		Net.rpc_to_all(_draw_blast, [at, size, color])
	_draw_blast(at, size, color)


@rpc("authority", "call_remote", "unreliable")
func _draw_blast(at: Vector3, size: float, color: Color) -> void:
	Perf.mark("blast fx")
	if Net.dedicated:
		return
	var world := _world()
	if world == null:
		return
	ShotFX.puff(world, at, color, size, 0.35)
	ShotFX.sparks(world, at, Vector3.UP, 8)
	ShotFX.flash(world, at, color, 6.0, 0.1)
	Sound.play_at("explosion", at, -12.0, 1.35)


func record_revive(reviver: Node, revived: Node = null) -> void:
	if is_host() and reviver:
		_stat(reviver).revives += 1
		feats.on_revive(reviver, revived)


func record_turned(player: Node) -> void:
	if is_host() and player:
		_stat(player).turned += 1
		feats.on_turned(player)


## Host: enemy/weapon code reports an achievement moment for `player`
## (game/feat_tracker.gd on_event). Keep these calls one line where they sit.
func achievement_event(event: String, player: Node, value := 0) -> void:
	if is_host():
		feats.on_event(event, player, value)


func record_cursed(player: Node, weapon_name: String) -> void:
	if is_host() and player:
		_stat(player).cursed = weapon_name


# ------------------------------------------------------------------ boss
## Host: Cumulus rolls in over the district. The Acid Storm lasts until it dies.
func spawn_boss() -> void:
	if not is_host() or victory_locked or not get_tree().get_nodes_in_group("boss").is_empty():
		return
	var world := _world()
	var spawner := world.get_node_or_null("Enemies") if world else null
	var anchor := get_tree().get_first_node_in_group("boss_anchor") as Node3D
	if spawner == null:
		return
	if anchor == null:
		push_warning("No boss_anchor in %s" % map_id)
		return
	var at := anchor.global_position
	_spawn_boss_node(spawner, at)
	if _online():
		Net.rpc_to_run(_spawn_boss, [at])
	WeatherManager.hold = true
	WeatherManager.set_intensity_override(1.0)
	show_banner("CUMULUS", Color("8FD65A"), 2.2)


func _spawn_boss_node(parent: Node3D, at: Vector3) -> void:
	Perf.mark("spawn boss cumulus")
	var started := Time.get_ticks_usec()
	var boss := (load("res://enemies/boss/boss_cumulus.tscn") as PackedScene).instantiate() as Node3D
	boss.name = "BossCumulus"
	boss.position = parent.to_local(at)
	parent.add_child(boss, true)
	Perf.mark("boss built %.1f ms" % ((Time.get_ticks_usec() - started) / 1000.0))


@rpc("authority", "call_remote", "reliable")
func _spawn_boss(at: Vector3) -> void:
	var world := _world()
	var spawner := world.get_node_or_null("Enemies") if world else null
	if spawner == null or not get_tree().get_nodes_in_group("boss").is_empty():
		return
	_spawn_boss_node(spawner, at)


## Host: the core popped. Keep this run loaded until the squad chooses.
var _run_started_ms := 0


func boss_defeated() -> void:
	if not is_host() or victory_locked or finished or endless:
		return
	_waves_survived = WeatherManager.FINAL_WAVE
	feats.on_boss_defeated()
	_set_tape_state(false, false, true)
	WeatherManager.set_intensity_override(0.0)
	WeatherManager.hold = true
	show_banner("STORM CLEARED", Color(0.4, 1, 0.6), 2.5)
	# With Cumulus gone the infected lose their storm: the stragglers drop.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("take_damage"):
			e.take_damage(99999.0, null)
	var run := _run_id
	get_tree().create_timer(2.6, false).timeout.connect(func():
		if run == _run_id and run_active and not finished:
			_set_tape_state(true, false, true))


## The player-host makes the decision. On a dedicated server the first
## remaining roster peer takes that role.
func tape_decider() -> int:
	if Net.roster.has(1) or not Net.is_online():
		return 1
	var peers := Net.roster.keys()
	return int(peers[0]) if not peers.is_empty() else 0


func choose_tape(keep_playing: bool) -> void:
	if not awaiting_tape_choice:
		return
	if is_host():
		_apply_tape_choice(1, keep_playing)
	elif multiplayer.get_unique_id() == tape_decider():
		_request_tape_choice.rpc_id(1, keep_playing)


@rpc("any_peer", "call_remote", "reliable")
func _request_tape_choice(keep_playing: bool) -> void:
	if is_host():
		_apply_tape_choice(multiplayer.get_remote_sender_id(), keep_playing)


func _apply_tape_choice(peer: int, keep_playing: bool) -> void:
	if not awaiting_tape_choice or not run_active or finished or peer != tape_decider():
		return
	feats.on_tape_choice(keep_playing)
	if not keep_playing:
		_set_tape_state(false, false, true)
		finish(true)
		return
	for player in players():
		player.on_clearing()
		if player.state == "downed":
			player.revive(null)
	endless_score = 0
	_set_tape_state(false, true, false)
	WeatherManager.hold = false
	WeatherManager.set_intensity_override(-1.0)
	WeatherManager.set_phase(WeatherManager.Phase.CALM, WeatherManager.FINAL_WAVE + 1)


func _set_tape_state(choice: bool, is_endless: bool, locked: bool) -> void:
	Net.rpc_to_all(_sync_tape_state, [choice, is_endless, locked])
	_sync_tape_state(choice, is_endless, locked)


@rpc("authority", "call_remote", "reliable")
func _sync_tape_state(choice: bool, is_endless: bool, locked: bool) -> void:
	var changed := awaiting_tape_choice != choice
	if not is_host():
		finished = false
		run_active = true
	awaiting_tape_choice = choice
	endless = is_endless
	victory_locked = locked
	if not endless:
		endless_score = 0
	if changed:
		tape_choice_changed.emit()


# ------------------------------------------------------------------ win / lose
func _check_lose() -> void:
	if victory_locked:
		return
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
	feats.on_finish()
	finished = true
	for p in players():
		var s := _stat(p)
		var holder: Node = p.get_node_or_null("Head/Camera3D/WeaponHolder")
		if holder and holder.selected_weapon():
			s["weapon"] = holder.selected_weapon().display_name
	var squad: Array = []
	if mutations:
		for id in mutations.player_mutations:
			if PLAYER_MUTATIONS.has(id):
				squad.append(str(PLAYER_MUTATIONS[id].name))
	var results := {
		"won": won,
		"map_id": map_id,
		"waves": _waves_survived,
		"wave_reached": WeatherManager.wave,
		"endless": endless,
		"endless_score": endless_score,
		"seconds": int((Time.get_ticks_msec() - _run_started_ms) / 1000.0) if _run_started_ms > 0 else 0,
		"squad_mutations": squad,
		"players": stats.duplicate(true),
	}
	if _online():
		Net.rpc_to_all(_finish, [won, results])
	_finish(won, results)


func _announce_unlock(weapon_name: String) -> void:
	if _online():
		Net.rpc_to_all(_weapon_unlocked, [weapon_name])
	_weapon_unlocked(weapon_name)


@rpc("authority", "call_remote", "reliable")
func _weapon_unlocked(weapon_name: String) -> void:
	weapon_unlocked.emit(weapon_name)


@rpc("authority", "call_remote", "reliable")
func _finish(won: bool, results: Dictionary) -> void:
	finished = true
	run_active = false
	last_results = results
	# No banner: the defeat card / results screen carry the outcome.
	run_finished.emit(won, results)


# ------------------------------------------------------------------ shared effects
var _hazard_seq := 0


## Host: a glob on an arc, simulated on every peer; only the host's hazard hurts.
func spawn_spore(from: Vector3, to: Vector3, flight: float, damage_per_second: float, acid := false, source: Node = null, cloudburst := false) -> void:
	_hazard_seq += 1
	if _online():
		Net.rpc_to_run(_spawn_spore, [_hazard_seq, from, to, flight, damage_per_second, acid, cloudburst])
	_make_spore(_hazard_seq, from, to, flight, damage_per_second, acid, source, cloudburst)


@rpc("authority", "call_remote", "reliable")
func _spawn_spore(id: int, from: Vector3, to: Vector3, flight: float, damage_per_second: float, acid: bool, cloudburst: bool) -> void:
	_make_spore(id, from, to, flight, damage_per_second, acid, null, cloudburst)


func _make_spore(id: int, from: Vector3, to: Vector3, flight: float, damage_per_second: float, acid: bool, source: Node, cloudburst: bool) -> void:
	var world := _world()
	if world == null:
		return
	var spore := SporeProjectile.new()
	spore.damage_per_second = damage_per_second
	spore.acid = acid
	spore.hazard_id = id
	spore.source = source
	spore.cloudburst = cloudburst
	world.add_child(spore)
	spore.launch(from, to, flight)


## Host: a spore cloud right here (Spores mutation, boss).
func spawn_cloud(at: Vector3, damage_per_second: float, radius := 2.5) -> void:
	_hazard_seq += 1
	if _online():
		Net.rpc_to_run(_spawn_cloud, [_hazard_seq, at, damage_per_second, radius])
	_spawn_cloud(_hazard_seq, at, damage_per_second, radius)


@rpc("authority", "call_remote", "reliable")
func _spawn_cloud(id: int, at: Vector3, damage_per_second: float, radius: float) -> void:
	var world := _world()
	if world == null:
		return
	SporeCloud.spawn(world, at, false, radius, 4.0, damage_per_second, null, id)


func disperse_cloud(cloud: Node) -> void:
	Net.rpc_to_run(_disperse_cloud, [cloud.hazard_id])
	cloud.queue_free()


@rpc("authority", "call_remote", "reliable")
func _disperse_cloud(id: int) -> void:
	for cloud: Node in get_tree().get_nodes_in_group("spore_clouds"):
		var matched: bool = cloud.has_hazard_id(id) if cloud.has_method("has_hazard_id") else cloud.hazard_id == id
		if matched:
			cloud.queue_free()
			break


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
	return Net.is_online()


func is_host() -> bool:
	return Net.is_host()
