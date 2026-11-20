extends Node3D
## Finite waves arrive in bursts, with recovery windows between groups.
## The last infected must be killed before a normal Downpour can clear.
##
## The host runs all of this and replicates: one reliable spawn per enemy, one
## reliable despawn per death (with whatever it dropped), and one unreliable
## packet per tick carrying every enemy's position. Clients never run the AI,
## they only draw.
##
## Debug (debug builds, host only): F3 spawns a Drip, F4 a Gutter, F5 a Mister.

@export var drip_scene: PackedScene = preload("res://enemies/drip/drip.tscn")
@export var gutter_scene: PackedScene = preload("res://enemies/gutter/gutter.tscn")
@export var mister_scene: PackedScene = preload("res://enemies/mister/mister.tscn")
@export var drizzle_breather := 8.0
@export var downpour_breather := 6.0
@export var max_alive := 30
@export_group("Weights")
@export var drip_weight := 10.0
@export var gutter_weight := 1.5
@export var mister_weight := 1.2
@export var mister_first_wave := 2

## Position broadcasts per second when the host is relaying to clients.
const NET_HZ := 10.0

var _timer := 0.0
var _next_net_id := 1
var _net_sync := 0.0
var _wave := 0
var _budget := 0
var _spawned := 0
var _burst_left := 0
var _reveal_timer := 0.0
var _supplies_pending := false
## One authored beat per wave (from wave 2), fired halfway through Downpour.
var _beat_done := false


func _ready() -> void:
	WeatherManager.phase_changed.connect(_on_phase)


func _on_phase(phase: int, wave: int) -> void:
	if wave != _wave or phase == WeatherManager.Phase.CALM:
		_wave = wave
		_budget = roundi((18 + wave * 8) * GameManager.enemy_spawn_scale())
		_spawned = 0
		_supplies_pending = true
		_beat_done = false
	_timer = 1.5
	_burst_left = 0


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not GameManager.run_active or GameManager.finished:
		return
	if Net.is_online():
		_net_sync -= delta
		if _net_sync <= 0.0:
			_net_sync = 1.0 / NET_HZ
			_push_enemies()
	if _supplies_pending:
		_spawn_street_supplies()
		_supplies_pending = false
	if WeatherManager.phase not in [WeatherManager.Phase.DRIZZLE, WeatherManager.Phase.DOWNPOUR]:
		return
	# Mutation rolls resolve after Calm, so include their population effect here.
	_budget = roundi((18 + _wave * 8) * GameManager.enemy_spawn_scale())
	var limit := ceili(_budget * 0.35) if WeatherManager.phase == WeatherManager.Phase.DRIZZLE else _budget
	_timer -= delta
	if _timer <= 0.0 and _spawned < limit and alive_count() < mini(60, roundi(max_alive * GameManager.enemy_spawn_scale())):
		if _burst_left <= 0:
			_burst_left = 4 + _wave
		var enemy := spawn(_pick_scene())
		if enemy:
			_spawned += 1
			_burst_left -= 1
		if _burst_left <= 0:
			_timer = drizzle_breather if WeatherManager.phase == WeatherManager.Phase.DRIZZLE else downpour_breather
		else:
			_timer = 0.5
	if not _beat_done and WeatherManager.phase == WeatherManager.Phase.DOWNPOUR and _spawned >= ceili(_budget * 0.5):
		_beat_done = true
		_run_beat(_wave)
	_reveal_timer -= delta
	if _spawned >= _budget and alive_count() <= 5 and _reveal_timer <= 0.0:
		_reveal_timer = 1.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.reveal(1.2)


## Memorable mid-wave encounters on top of the count-based horde. Beat
## enemies are extra: they show up in alive_count() but not the budget.
func _run_beat(wave: int) -> void:
	var players := GameManager.players().filter(func(p): return p.state == "ok")
	if players.is_empty():
		return
	var focus: Node3D = players.pick_random()
	match wave:
		2:
			# Supply ambush: Gutters burst out around the supply pack nearest a player.
			var packs := get_tree().get_nodes_in_group("street_supplies")
			var at := focus.global_position
			var best := INF
			for pack in packs:
				var d: float = pack.global_position.distance_to(focus.global_position)
				if d < best:
					best = d
					at = pack.global_position
			GameManager.show_banner("SUPPLY AMBUSH", Color("ff8a4c"), 2.0)
			for i in 3 + GameManager.player_count():
				_spawn_near(gutter_scene, at, 6.0)
		3:
			# Street push: a wall of Drips from one direction at once.
			var origin: Variant = _marker_position("enemy_spawn")
			if origin == null:
				return
			GameManager.show_banner("STREET PUSH", Color("ff5a6e"), 2.0)
			for i in 8 + 3 * GameManager.player_count():
				_spawn_near(drip_scene, origin, 4.0)
		4:
			# Elite squad: Misters with a Gutter escort, briefly revealed.
			var origin: Variant = _marker_position("enemy_spawn")
			if origin == null:
				return
			GameManager.show_banner("ELITE SQUAD", Color("b48cff"), 2.0)
			for i in 2 + GameManager.player_count():
				var mister := _spawn_near(mister_scene, origin, 3.0)
				if mister:
					mister.reveal(3.0)
			for i in 2:
				_spawn_near(gutter_scene, origin, 3.0)


func _spawn_near(scene: PackedScene, center: Vector3, spread: float) -> EnemyBase:
	if not Net.is_host() or alive_count() >= 60:
		return null
	var point := center + Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	var where := point + Vector3(0, 0.15, 0)
	var enemy := _make(scene, where, false)
	if enemy and Net.is_online():
		_spawn_enemy.rpc(enemy.net_id, _kind_of(scene), where, false)
	return enemy


func can_finish_wave() -> bool:
	return _spawned >= _budget and alive_count() == 0


func remaining() -> int:
	return maxi(0, _budget - _spawned) + alive_count()


func combat_status() -> String:
	if WeatherManager.phase not in [WeatherManager.Phase.DRIZZLE, WeatherManager.Phase.DOWNPOUR]:
		return ""
	if _spawned >= _budget:
		return "CLEAR THE LAST %d" % alive_count() if alive_count() > 0 else "AREA CLEAR"
	return "%d REMAINING  /  %s" % [remaining(), "RELOAD + RESUPPLY" if _timer > 1.0 else "HORDE INCOMING"]


func _spawn_street_supplies() -> void:
	for old in get_tree().get_nodes_in_group("street_supplies"):
		old.queue_free()
	if Net.is_online():
		_clear_supplies.rpc()
	# Main Street, parking lot and park: open approaches with multiple exits.
	for point in [Vector3(-30, 0.12, 2.5), Vector3(28, 0.12, -2.5), Vector3(4, 0.12, 42), Vector3(46, 0.12, 34)]:
		spawn_drop(point, "supply", 600.0)
		if Net.is_online():
			_spawn_supply.rpc(point)


func _unhandled_input(event: InputEvent) -> void:
	if not (OS.is_debug_build() and Net.is_host() and event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F3:
			spawn(drip_scene)
		KEY_F4:
			spawn(gutter_scene)
		KEY_F5:
			spawn(mister_scene)


func alive_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func spawn(scene: PackedScene) -> EnemyBase:
	# The host owns spawns; a client asking would make an enemy that never
	# thinks and never replicates.
	if not Net.is_host():
		return null
	var at: Variant = _gutter_spawn_point() if scene == gutter_scene else _marker_position("enemy_spawn")
	if at == null:
		push_warning("No spawn point for %s" % scene.resource_path)
		return null
	var point: Vector3 = at
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	var where := point + Vector3(0, 0.15, 0)
	var enemy := _make(scene, where, false)
	if enemy and Net.is_online():
		_spawn_enemy.rpc(enemy.net_id, _kind_of(scene), where, false)
	return enemy


## Splitters: a small copy of `enemy` at `at`.
func spawn_copy(enemy: EnemyBase, at: Vector3, small: bool) -> void:
	var scene := load(enemy.scene_file_path) as PackedScene
	if scene == null:
		return
	# Deferred: this runs from inside the parent's death.
	var copy := scene.instantiate() as EnemyBase
	copy.is_small = small
	copy.net_id = _next_net_id
	_next_net_id += 1
	add_child.call_deferred(copy, true)
	copy.set_deferred("global_position", at)
	if Net.is_online():
		_spawn_enemy.rpc(copy.net_id, _kind_of(scene), at, small)


## Build one enemy on this peer. `is_small` and net_id are set before add_child
## because EnemyBase._ready() reads them. Clients pass the host's id in; only
## the host hands out new ones.
func _make(scene: PackedScene, at: Vector3, small: bool, forced_id := 0) -> EnemyBase:
	var enemy := scene.instantiate() as EnemyBase
	enemy.is_small = small
	if forced_id > 0:
		enemy.net_id = forced_id
	else:
		enemy.net_id = _next_net_id
		_next_net_id += 1
	add_child(enemy, true)
	enemy.global_position = at
	return enemy


## Which kind of enemy this is, for the wire. Compares resource paths rather
## than instances, because splitters reload the scene by path.
func _kind_of(scene: PackedScene) -> int:
	var path := scene.resource_path
	if path == gutter_scene.resource_path:
		return 1
	if path == mister_scene.resource_path:
		return 2
	return 0


func _scene_of(kind: int) -> PackedScene:
	match kind:
		1:
			return gutter_scene
		2:
			return mister_scene
	return drip_scene


func _pick_scene() -> PackedScene:
	var specials := get_tree().get_nodes_in_group("enemies").filter(func(enemy): return enemy.data.display_name != "Drip")
	if specials.size() >= 3:
		return drip_scene
	var options := [[drip_scene, drip_weight], [gutter_scene, gutter_weight]]
	if WeatherManager.wave >= mister_first_wave:
		options.append([mister_scene, mister_weight])
	var total := 0.0
	for o in options:
		total += o[1]
	var roll := randf() * total
	for o in options:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return drip_scene


## Gutters crawl out of storm drains, or out of any puddle big enough.
func _gutter_spawn_point() -> Variant:
	var points: Array = []
	for marker in get_tree().get_nodes_in_group("drain_spawn"):
		points.append((marker as Node3D).global_position)
	for puddle in get_tree().get_nodes_in_group("puddles"):
		if puddle.has_method("can_spawn_gutter") and puddle.can_spawn_gutter():
			points.append((puddle as Node3D).global_position)
	return _near_players(points)


func _marker_position(group: String) -> Variant:
	var points: Array = []
	for marker in get_tree().get_nodes_in_group(group):
		points.append(marker.global_position)
	return _near_players(points)


func _near_players(points: Array) -> Variant:
	var players := GameManager.players().filter(func(p): return p.state == "ok")
	if points.is_empty() or players.is_empty():
		return null
	var candidates: Array = []
	for point in points:
		var distance := INF
		for player in players:
			distance = minf(distance, player.global_position.distance_to(point))
		if distance >= 12.0 and distance <= 45.0:
			candidates.append(point)
	# Never spawn on top of a player, even if every marker is crowded.
	if candidates.is_empty():
		for point in points:
			if players.all(func(player): return player.global_position.distance_to(point) >= 12.0):
				candidates.append(point)
	return candidates.pick_random() if not candidates.is_empty() else null


# ------------------------------------------------------------------ network
## A drop every peer will see: it is collected locally by whoever walks over
## it, so the node has to exist on every machine.
func spawn_drop(at: Vector3, kind := "ammo", expires := 35.0) -> void:
	var drop := Node3D.new()
	drop.set_script(preload("res://weapons/ammo_drop.gd"))
	# Set before add_child: ammo_drop's _ready() reads both.
	drop.set("kind", kind)
	drop.set("expires_after", expires)
	add_child(drop)
	drop.global_position = at
	if kind == "supply":
		drop.add_to_group("street_supplies")


@rpc("authority", "call_remote", "reliable")
func _spawn_supply(point: Vector3) -> void:
	spawn_drop(point, "supply", 600.0)


@rpc("authority", "call_remote", "reliable")
func _clear_supplies() -> void:
	for old in get_tree().get_nodes_in_group("street_supplies"):
		old.queue_free()


@rpc("authority", "call_remote", "reliable")
func _spawn_enemy(net_id: int, kind: int, at: Vector3, small: bool) -> void:
	if _find_net(net_id) != null:
		return
	_make(_scene_of(kind), at, small, net_id)


func notify_tell(net_id: int, cue: String, duration: float, volume: float) -> void:
	Net.rpc_to_run(_play_enemy_tell, [net_id, cue, duration, volume])


@rpc("authority", "call_remote", "unreliable")
func _play_enemy_tell(net_id: int, cue: String, duration: float, volume: float) -> void:
	var enemy := _find_net(net_id)
	if enemy:
		enemy.play_tell(cue, duration, volume)


## Host: one enemy died. Tell the clients which one, and what it dropped.
func notify_despawn(enemy: EnemyBase, drops: Array) -> void:
	if Net.is_host() and Net.is_online():
		_despawn_enemy.rpc(enemy.net_id, drops)


@rpc("authority", "call_remote", "reliable")
func _despawn_enemy(net_id: int, drops: Array) -> void:
	var enemy := _find_net(net_id)
	if enemy:
		Sound.play_at("enemy_death", enemy.global_position)
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	for entry in drops:
		spawn_drop(entry[0], str(entry[1]))


## One packet per tick for every enemy rather than one per enemy: positions and
## yaws only, since the AI itself runs on the host alone.
func _push_enemies() -> void:
	var ids := PackedInt32Array()
	var places := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		ids.append(int(enemy.get("net_id")))
		places.append(enemy.global_position)
		yaws.append(enemy.rotation.y)
	if ids.is_empty():
		return
	_sync_enemies.rpc(ids, places, yaws)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemies(ids: PackedInt32Array, places: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	for i in ids.size():
		var enemy := _find_net(ids[i])
		if enemy:
			enemy.global_position = places[i]
			enemy.rotation.y = yaws[i]


func _find_net(net_id: int) -> EnemyBase:
	for node in get_tree().get_nodes_in_group("enemies"):
		if int(node.get("net_id")) == net_id:
			return node as EnemyBase
	return null
