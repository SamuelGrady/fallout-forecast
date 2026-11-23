extends Node3D
## Finite waves arrive in bursts, with recovery windows between groups.
## Clearing retires the tail of a spent wave once its main threat is down.
##
## The host runs all of this and replicates: one reliable spawn per enemy, one
## reliable despawn per death (with whatever it dropped), and one unreliable
## packet per tick carrying every enemy's position. Clients never run the AI,
## they only draw.
##
## F3-F5 spawn the original roster. Shift+F3-F8 spawn weather infected.
signal group_incoming(at: Vector3)

const WavePlan := preload("res://enemies/wave_plan.gd")
const Kind := WavePlan.Kind
const WEATHER_SCENES := [
	preload("res://enemies/sleet/sleet.tscn"),
	preload("res://enemies/hailstone/hailstone.tscn"),
	preload("res://enemies/undertow/undertow.tscn"),
	preload("res://enemies/static/static.tscn"),
	preload("res://enemies/smog/smog.tscn"),
	preload("res://enemies/thunderhead/thunderhead.tscn"),
]

@export var drip_scene: PackedScene = preload("res://enemies/drip/drip.tscn")
@export var gutter_scene: PackedScene = preload("res://enemies/gutter/gutter.tscn")
@export var mister_scene: PackedScene = preload("res://enemies/mister/mister.tscn")
@export var drizzle_breather := 7.5
@export var downpour_breather := 5.0
@export var max_alive := 26

## Position broadcasts per second when the host is relaying to clients.
const NET_HZ := 20.0
const MIN_ARRIVAL_DISTANCE := 12.0
const PREFERRED_ARRIVAL_DISTANCE := 45.0
const MINIBOSS_WAVE := 3

var _timer := 0.0
var _next_net_id := 1
var _enemies_by_id: Dictionary[int, EnemyBase] = {}
var _seen_types: Dictionary[String, bool] = {}
var _net_sync := 0.0
var _wave := 0
var _budget := 0
var _spawned := 0
var _group: Array = []
var _group_origin := Vector3.ZERO
var _group_warned := false
var _opening_group := true
var _phase := -1
var _extras := 0
var _progress_tick := 0.0
var _remote_wave := 0
var _remote_remaining := 0
var _remote_total := 0
var _remote_recovery := 0.0
var _reveal_timer := 0.0
var _supplies_pending := false
## One authored beat per wave (from wave 2), fired halfway through Downpour.
var _beat_done := false
## False Clearing mutation: mid-Downpour lull + elite spawn.
var _false_clearing_done := false
var _false_clearing_left := 0.0
var _cleanup_left := 5.0
var _miniboss_spawned := false


func _ready() -> void:
	add_to_group("enemy_spawner")
	WeatherManager.phase_changed.connect(_on_phase)


func _on_phase(phase: int, wave: int) -> void:
	if wave == _wave and phase == _phase:
		return
	_phase = phase
	var fresh_wave := wave != _wave or phase == WeatherManager.Phase.CALM
	_wave = wave
	if not Net.is_host():
		return
	if _false_clearing_left > 0.0:
		_false_clearing_left = 0.0
		if get_tree().get_nodes_in_group("boss").is_empty() and not GameManager.victory_locked:
			WeatherManager.set_intensity_override(-1.0)
	if fresh_wave:
		_spawned = 0
		_extras = 0
		_supplies_pending = true
		_beat_done = false
		_false_clearing_done = false
		_cleanup_left = 5.0
		_miniboss_spawned = false
	if phase == WeatherManager.Phase.DRIZZLE or fresh_wave:
		_budget = _wave_budget(wave, GameManager.enemy_spawn_scale())
	if phase == WeatherManager.Phase.CLEARING:
		retire_stragglers()
	_group.clear()
	_opening_group = true
	_timer = 1.25 if phase == WeatherManager.Phase.DRIZZLE else 2.1
	_progress_tick = 0.0


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not GameManager.run_active or GameManager.finished:
		return
	if _false_clearing_left > 0.0:
		_false_clearing_left -= delta
		if _false_clearing_left <= 0.0 and get_tree().get_nodes_in_group("boss").is_empty():
			WeatherManager.set_intensity_override(-1.0)
	if Net.is_online():
		_net_sync -= delta
		if _net_sync <= 0.0:
			_net_sync = 1.0 / NET_HZ
			_push_enemies()
		_progress_tick -= delta
		if _progress_tick <= 0.0:
			_progress_tick = .28
			Net.rpc_to_run(_sync_progress, [_wave, remaining(), wave_total(), recovery_time(), GameManager.endless_score])
	if _supplies_pending:
		_spawn_street_supplies()
		_supplies_pending = false
	if GameManager.victory_locked or _phase not in [WeatherManager.Phase.DRIZZLE, WeatherManager.Phase.DOWNPOUR]:
		return
	var spawn_scale := GameManager.enemy_spawn_scale()
	# Preserve the current group's composition when the roster changes.
	if _group.is_empty():
		_budget = maxi(_spawned, _wave_budget(_wave, spawn_scale))
	var downpour := _phase == WeatherManager.Phase.DOWNPOUR
	var limit := _budget if downpour else ceili(_budget * .35)
	_timer -= delta
	var cap := mini(60, roundi(max_alive * spawn_scale))
	if _timer <= 0.0 and _spawned < limit and alive_count() < cap:
		_spawn_group_member(limit, downpour)
	if not _false_clearing_done and GameManager.has_mutation("false_clearing") and WeatherManager.phase == WeatherManager.Phase.DOWNPOUR and _spawned >= ceili(_budget * 0.35):
		_false_clearing_done = true
		_trigger_false_clearing()
	var drop = GameManager.crates.airdrop
	var drop_landed: bool = GameManager.crates.last_drop_position.is_finite() \
			and (not is_instance_valid(drop) or drop.descent_left <= 0.0)
	var ambush := _wave == 2 and drop_landed and _spawned >= 2
	var late_beat := _wave != 2 and downpour and _spawned >= ceili(_budget * 0.5)
	if not _beat_done and (ambush or late_beat):
		_beat_done = true
		_run_beat(_wave)
	if downpour and _awaiting_miniboss() and _spawned >= ceili(_budget * 0.5):
		_miniboss_spawned = spawn_miniboss(_wave) != null
	if _spawned >= _budget and alive_count() <= 3:
		_cleanup_left = maxf(0.0, _cleanup_left - delta)
	else:
		_cleanup_left = 5.0
	_reveal_timer -= delta
	if _spawned >= _budget and alive_count() <= 5 and _reveal_timer <= 0.0:
		_reveal_timer = 1.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.has_method("expose_for_cleanup"):
				enemy.expose_for_cleanup()
			enemy.reveal(1.2)


func _wave_budget(wave: int, spawn_scale: float) -> int:
	var campaign := 18 + 8 * mini(wave, WeatherManager.FINAL_WAVE)
	var endless := clampi(wave - WeatherManager.FINAL_WAVE, 0, 6) * 6
	return roundi((campaign + endless) * spawn_scale)


func _spawn_group_member(limit: int, downpour: bool) -> void:
	if _group.is_empty() and not _plan_group(limit - _spawned, downpour):
		_timer = 1.0
		return
	var kind: int = _group.pop_front()
	var puddle := _wet_puddle() if kind == Kind.UNDERTOW else null
	var point := _group_origin
	if puddle:
		point = puddle.global_position
	elif kind == Kind.GUTTER and _group_warned == false:
		var drain: Variant = _gutter_spawn_point()
		if drain is Vector3:
			point = drain
			_group_origin = drain
	var enemy := _spawn_near(_scene_of(kind), point, 0.0 if puddle else 1.8)
	if enemy:
		_spawned += 1
		if not _group_warned:
			_group_warned = true
			_warn_group(enemy.global_position)
		if puddle:
			enemy.bind_puddle(puddle)
	if not _group.is_empty():
		_timer = .28
	else:
		_timer = maxf(2.7, downpour_breather - (_wave - 1) * .25) if downpour else drizzle_breather
		if alive_count() > 7:
			_timer += 1.6


func _plan_group(slots: int, downpour: bool) -> bool:
	var marker: Variant = _marker_position("enemy_spawn")
	if marker == null:
		return false
	_group_origin = marker
	_group_warned = false
	if _opening_group:
		_group = WavePlan.opener(_wave, downpour)
		_group.resize(mini(slots, _group.size()))
		_opening_group = false
		return true
	# Squads clear more per burst. Give them more bodies in each arrival
	# instead of stretching the same small groups over a much longer wave.
	var squad_slots := ceili((GameManager.player_count() - 1) * 1.5)
	var size := mini(slots, clampi(4 + _wave + squad_slots, 5, 12 + squad_slots))
	var mix := WavePlan.weights(_wave, downpour)
	var special_count := 0
	while _group.size() < size:
		var kind := RNG.weighted_index(mix)
		_group.append(kind)
		if kind >= Kind.SLEET:
			special_count += 1
			mix[kind] = 0
			if special_count == 2:
				for special in range(Kind.SLEET, mix.size()):
					mix[special] = 0
	return true


func _warn_group(at: Vector3) -> void:
	group_incoming.emit(at)
	if Net.is_online():
		Net.rpc_to_run(_receive_group_warning, [at])


@rpc("authority", "call_remote", "reliable")
func _receive_group_warning(at: Vector3) -> void:
	group_incoming.emit(at)


## False Clearing mutation: rain briefly pauses while a heavy revealed elite enters.
func _trigger_false_clearing() -> void:
	if get_tree().get_nodes_in_group("boss").is_empty():
		WeatherManager.set_intensity_override(0.05)
		_false_clearing_left = 6.5
	GameManager.show_banner("FALSE CLEARING", Color("8ce8ff"), 2.4)
	var elite_kind: int = [Kind.SLEET, Kind.HAILSTONE, Kind.UNDERTOW, Kind.STATIC, Kind.SMOG, Kind.THUNDERHEAD][clampi(_wave - 1, 0, 5)]
	var elite_scene := _scene_of(elite_kind)
	var at: Variant = _marker_position("enemy_spawn")
	if at == null:
		return
	var point: Vector3 = at
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	var where := point + Vector3(0, 0.15, 0)
	var enemy := _make(elite_scene, where, false, 0, true)
	if enemy:
		_extras += 1
		if Net.is_online():
			Net.rpc_to_run(_spawn_enemy, [enemy.net_id, elite_kind, where, false, true])
		_warn_group(where)


## Memorable mid-wave encounters on top of the count-based horde. Beat
## enemies are extra: they show up in alive_count() but not the budget.
func _run_beat(wave: int) -> void:
	if _living_players().is_empty():
		return
	match wave:
		2:
			var target: Vector3 = GameManager.crates.last_drop_position
			var drains := get_tree().get_nodes_in_group("drain_spawn")
			var closest := INF
			var origin: Variant = null
			for drain: Node3D in drains:
				var length := drain.global_position.distance_to(target)
				if length < closest and _safe_spawn(drain.global_position, MIN_ARRIVAL_DISTANCE) \
						and _is_connected(drain.global_position, target):
					closest = length
					origin = drain.global_position
			if origin == null:
				origin = _gutter_spawn_point()
			if origin is Vector3:
				GameManager.show_banner("GUTTER AMBUSH", Color("#ffc365"), 2.0)
				_warn_group(origin)
				for i in 3 + GameManager.player_count():
					_spawn_extra(gutter_scene, origin, 2.0)
		_:
			if wave > WeatherManager.FINAL_WAVE and WavePlan.modifier(wave) == WavePlan.HEAVY_WEATHER:
				var origin: Variant = _marker_position("enemy_spawn")
				if origin is Vector3:
					_warn_group(origin)
					_spawn_extra(_scene_of(Kind.THUNDERHEAD), origin, 0.0)


func _spawn_extra(scene: PackedScene, center: Vector3, spread: float, elite := false) -> void:
	if _spawn_near(scene, center, spread, elite):
		_extras += 1


func _spawn_near(scene: PackedScene, center: Vector3, spread: float, elite := false) -> EnemyBase:
	if not Net.is_host() or alive_count() >= 60:
		return null
	var point := center + Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
		if spread > 0.0:
			var origin := NavigationServer3D.map_get_closest_point(map, center)
			var players := _living_players()
			# The jitter must preserve cover and can't jump to another floor.
			if absf(point.y - origin.y) > 1.0 or not _safe_spawn(point, 7.5) \
					or (_hidden_from_players(origin, players) and not _hidden_from_players(point, players)):
				point = origin
	var where := point + Vector3(0, 0.15, 0)
	var enemy := _make(scene, where, false, 0, elite)
	if Net.is_online():
		Net.rpc_to_run(_spawn_enemy, [enemy.net_id, _kind_of(scene), where, false, elite])
	return enemy


## Host: bring in the named giant while its horde is still arriving.
func spawn_miniboss(wave: int) -> EnemyBase:
	if not Net.is_host():
		return null
	var scene := drip_scene
	match wave:
		2:
			scene = gutter_scene
		3:
			scene = mister_scene
		_:
			scene = drip_scene
	var at: Variant = _marker_position("enemy_spawn")
	if at == null:
		return null
	var point: Vector3 = at
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	var where := point + Vector3(0, 0.15, 0)
	var enemy := _make(scene, where, false, 0, false, wave)
	if enemy:
		_extras += 1
		if Net.is_online():
			Net.rpc_to_run(_spawn_enemy, [enemy.net_id, _kind_of(scene), where, false, false, wave])
		_warn_group(where)
		Sound.play("storm_arrival", -6.0, 0.72)
		GameManager.show_banner(str(enemy.miniboss_name).to_upper(), Color("ff5689"), 3.2)
	return enemy


func can_finish_wave() -> bool:
	if _spawned < _budget or _pending_copies > 0 or _awaiting_miniboss():
		return false
	if alive_count() == 0:
		return true
	if _cleanup_left > 0.0:
		return false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_elite or enemy.miniboss_wave > 0:
			return false
	return true


func retire_stragglers() -> void:
	var ids := PackedInt32Array()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		ids.append(enemy.net_id)
	if ids.is_empty():
		return
	_retire_enemies(ids)
	Net.rpc_to_run(_retire_enemies, [ids])


@rpc("authority", "call_remote", "reliable")
func _retire_enemies(ids: PackedInt32Array) -> void:
	for id in ids:
		var enemy := _find_net(id)
		if enemy:
			enemy.remove_from_group("enemies")
			enemy.queue_free()


func remaining() -> int:
	if not Net.is_host():
		return _remote_remaining if _remote_wave == _wave else 0
	if GameManager.victory_locked:
		return 0
	return maxi(0, _budget - _spawned) + alive_count() + int(_awaiting_miniboss())


func wave_total() -> int:
	if not Net.is_host():
		return _remote_total if _remote_wave == _wave else 0
	return _budget + _extras + int(_awaiting_miniboss())


func _awaiting_miniboss() -> bool:
	return _wave == MINIBOSS_WAVE and not _miniboss_spawned


func recovery_time() -> float:
	if not Net.is_host():
		return _remote_recovery if _remote_wave == _wave else 0.0
	var downpour := _phase == WeatherManager.Phase.DOWNPOUR
	var limit := _budget if downpour else ceili(_budget * .35)
	return maxf(0.0, _timer) if _spawned < limit and _group.is_empty() else 0.0


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_progress(wave: int, left: int, total: int, recovery: float, score: int) -> void:
	_remote_wave = wave
	_remote_remaining = left
	_remote_total = total
	_remote_recovery = recovery
	GameManager.endless_score = score


## Free street supply crates are retired: ammo only comes from vending
## stations and supply drops. Clears any leftovers from an older run.
func _spawn_street_supplies() -> void:
	var loot := RunLoot.find(get_tree())
	if Net.is_host() and loot:
		loot.clear_supplies()


func _unhandled_input(event: InputEvent) -> void:
	if not (OS.is_debug_build() and Net.is_host() and event is InputEventKey and event.pressed and not event.echo):
		return
	if event.shift_pressed and event.keycode >= KEY_F3 and event.keycode <= KEY_F8:
		spawn(WEATHER_SCENES[event.keycode - KEY_F3])
		get_viewport().set_input_as_handled()
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
	if not Net.is_host() or GameManager.victory_locked:
		return null
	var kind := _kind_of(scene)
	var puddle := _wet_puddle() if kind == Kind.UNDERTOW else null
	var at: Variant = _gutter_spawn_point() if kind == Kind.GUTTER else _marker_position("enemy_spawn")
	if puddle:
		at = puddle.global_position
	if at == null:
		at = _marker_position("enemy_spawn")
	if at == null:
		push_warning("No spawn point for %s" % scene.resource_path)
		return null
	if kind == Kind.SLEET:
		for i in 2:
			_spawn_near(scene, at, 2.4)
	var enemy := _spawn_near(scene, at, 0.0)
	if enemy and puddle:
		enemy.bind_puddle(puddle)
	return enemy


## Splitters: a small copy of `enemy` at `at`.
var _pending_copies := 0


func spawn_copy(enemy: EnemyBase, at: Vector3, small: bool) -> void:
	if not Net.is_host() or alive_count() + _pending_copies >= 60:
		return
	var scene := load(enemy.scene_file_path) as PackedScene
	if scene == null:
		return
	_pending_copies += 1
	_add_copy.call_deferred(scene, at, small)


func _add_copy(scene: PackedScene, at: Vector3, small: bool) -> void:
	_pending_copies -= 1
	if GameManager.victory_locked or GameManager.finished:
		return
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		at = NavigationServer3D.map_get_closest_point(map, at) + Vector3.UP * 0.15
	var copy := _make(scene, at, small)
	_extras += 1
	if Net.is_online():
		Net.rpc_to_run(_spawn_enemy, [copy.net_id, _kind_of(scene), at, small, false])


## Build one enemy on this peer. `is_small`, `is_elite`, `miniboss_wave` and net_id
## are set before add_child because EnemyBase._ready() reads them.
func _make(scene: PackedScene, at: Vector3, small: bool, forced_id := 0, elite := false, miniboss_wave := 0) -> EnemyBase:
	var kind_name := scene.resource_path.get_file().get_basename()
	if not _seen_types.has(kind_name):
		_seen_types[kind_name] = true
		Perf.mark("first spawn " + kind_name)
	elif miniboss_wave > 0:
		Perf.mark("spawn miniboss " + kind_name)
	elif elite:
		Perf.mark("spawn elite " + kind_name)
	var enemy := scene.instantiate() as EnemyBase
	enemy.is_small = small
	enemy.is_elite = elite
	enemy.miniboss_wave = miniboss_wave
	if forced_id > 0:
		enemy.net_id = forced_id
	else:
		enemy.net_id = _next_net_id
		_next_net_id += 1
	enemy.position = to_local(at)
	add_child(enemy, true)
	_enemies_by_id[enemy.net_id] = enemy
	var id := enemy.net_id
	enemy.tree_exiting.connect(func(): _enemies_by_id.erase(id))
	if elite or miniboss_wave > 0:
		enemy.reveal(10.0)
	return enemy


## Which kind of enemy this is, for the wire. Compares resource paths rather
## than instances, because splitters reload the scene by path.
func _kind_of(scene: PackedScene) -> int:
	if scene.resource_path == gutter_scene.resource_path:
		return Kind.GUTTER
	if scene.resource_path == mister_scene.resource_path:
		return Kind.MISTER
	for i in WEATHER_SCENES.size():
		if scene.resource_path == WEATHER_SCENES[i].resource_path:
			return i + Kind.SLEET
	return Kind.DRIP


func _scene_of(kind: int) -> PackedScene:
	match kind:
		Kind.DRIP: return drip_scene
		Kind.GUTTER: return gutter_scene
		Kind.MISTER: return mister_scene
	return WEATHER_SCENES[kind - Kind.SLEET]


func _wet_puddle() -> Node3D:
	var players := _living_players()
	if players.is_empty():
		return null
	var candidates: Array[Node3D] = []
	var map := get_world_3d().navigation_map
	for node in get_tree().get_nodes_in_group("puddles"):
		var puddle := node as Node3D
		if puddle == null or not puddle.has_method("radius") or float(puddle.call("radius")) <= .25:
			continue
		if puddle.has_meta("undertow") or _distance_to_players(puddle.global_position, players) < 6.5:
			continue
		var floor_point := NavigationServer3D.map_get_closest_point(map, puddle.global_position)
		var near := _distance_to_players(puddle.global_position, players)
		if floor_point.distance_to(puddle.global_position) <= 1.05 and near <= 42.0:
			candidates.append(puddle)
	return candidates.pick_random() if not candidates.is_empty() else null


func _safe_spawn(point: Vector3, distance: float) -> bool:
	return _distance_to_players(point, _living_players()) >= distance


func _living_players() -> Array:
	return GameManager.players().filter(func(p): return p.state == "ok")


func _distance_to_players(point: Vector3, players: Array) -> float:
	var distance := INF
	for player: Node3D in players:
		distance = minf(distance, player.global_position.distance_to(point))
	return distance


func _hidden_from_players(point: Vector3, players: Array) -> bool:
	var space := get_world_3d().direct_space_state
	for player: Player in players:
		var sight := PhysicsRayQueryParameters3D.create(player.head.global_position, point + Vector3.UP * 1.0, 1)
		if space.intersect_ray(sight).is_empty():
			return false
	return true


func _is_connected(from: Vector3, to: Vector3) -> bool:
	var map := get_world_3d().navigation_map
	var end := NavigationServer3D.map_get_closest_point(map, to)
	var path := NavigationServer3D.map_get_path(map, from, end, true)
	return not path.is_empty() and path[-1].distance_squared_to(end) < 1.0


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
	var players := _living_players()
	if points.is_empty() or players.is_empty():
		return null
	var preferred: Array[Vector3] = []
	var distant_cover: Array[Vector3] = []
	var furthest := MIN_ARRIVAL_DISTANCE
	var fallback: Variant = null
	for point: Vector3 in points:
		var distance := _distance_to_players(point, players)
		if distance >= MIN_ARRIVAL_DISTANCE and _hidden_from_players(point, players):
			if distance <= PREFERRED_ARRIVAL_DISTANCE:
				preferred.append(point)
			else:
				distant_cover.append(point)
		if distance > furthest:
			furthest = distance
			fallback = point
	if not preferred.is_empty():
		return preferred.pick_random()
	if not distant_cover.is_empty():
		return distant_cover.pick_random()
	if fallback != null:
		return fallback
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return null
	for origin: Vector3 in points:
		for i in 8:
			var probe := origin + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0) * 10.0
			var point := NavigationServer3D.map_get_closest_point(map, probe)
			if probe.distance_to(point) >= 2.0 or _distance_to_players(point, players) < 7.5:
				continue
			if _hidden_from_players(point, players):
				return point
			if fallback == null:
				fallback = point
	return fallback


# ------------------------------------------------------------------ network
const SCRAP_LIFETIME := 45.0

func spawn_drop(at: Vector3, kind := "ammo", expires := 35.0) -> void:
	var loot := RunLoot.find(get_tree())
	if Net.is_host() and loot:
		if kind.begins_with("scrap"):
			# Scrap lingers so players can sweep it up after clearing a group.
			expires = maxf(expires, SCRAP_LIFETIME)
		loot.spawn_pickup(null, at, kind, expires)


@rpc("authority", "call_remote", "reliable")
func _spawn_enemy(net_id: int, kind: int, at: Vector3, small: bool, elite := false, miniboss_wave := 0) -> void:
	if _find_net(net_id) != null:
		return
	_make(_scene_of(kind), at, small, net_id, elite, miniboss_wave)


func sync_to_peer(peer: int) -> void:
	if not Net.is_host():
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		var scene := load(enemy.scene_file_path) as PackedScene
		_spawn_enemy.rpc_id(peer, enemy.net_id, _kind_of(scene), enemy.global_position, enemy.is_small, enemy.is_elite, enemy.miniboss_wave)
		if enemy.has_method("sync_tells"):
			enemy.sync_tells(peer)
	_sync_progress.rpc_id(peer, _wave, remaining(), wave_total(), recovery_time(), GameManager.endless_score)


func notify_impacts(rows: Array) -> void:
	Net.rpc_to_run(_enemy_impacts, [rows])


@rpc("authority", "call_remote", "unreliable")
func _enemy_impacts(rows: Array) -> void:
	for row: Array in rows:
		var enemy := _find_net(row[0])
		if enemy:
			enemy.impact_reaction.emit(row[1], row[2])


func notify_miniboss_hp(net_id: int, hp: float, max_hp: float) -> void:
	Net.rpc_to_run(_sync_miniboss_hp, [net_id, hp, max_hp])


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_miniboss_hp(net_id: int, hp: float, max_hp: float) -> void:
	var enemy := _find_net(net_id)
	if enemy:
		enemy.health = hp
		enemy.max_health = max_hp


func notify_tell(net_id: int, cue: String, duration: float, volume: float) -> void:
	Net.rpc_to_run(_play_enemy_tell, [net_id, cue, duration, volume])


@rpc("authority", "call_remote", "reliable")
func _play_enemy_tell(net_id: int, cue: String, duration: float, volume: float) -> void:
	var enemy := _find_net(net_id)
	if enemy:
		enemy.play_tell(cue, duration, volume)


func notify_molt(net_id: int) -> void:
	Net.rpc_to_run(_play_enemy_molt, [net_id])


@rpc("authority", "call_remote", "reliable")
func _play_enemy_molt(net_id: int) -> void:
	var enemy := _find_net(net_id)
	if enemy:
		enemy.play_molt()


## Host: one enemy died. Tell clients which one, its drops, and death fragment launch.
func notify_despawn(enemy: EnemyBase, drops: Array, throw_vec := Vector3.ZERO, critical := false) -> void:
	if Net.is_host() and Net.is_online():
		Net.rpc_to_run(_despawn_enemy, [enemy.net_id, drops, enemy.global_position, throw_vec, critical])


@rpc("authority", "call_remote", "reliable")
func _despawn_enemy(net_id: int, drops: Array, at: Vector3, throw_vec: Vector3, critical: bool) -> void:
	var enemy := _find_net(net_id)
	var pos := enemy.global_position if enemy else at
	EnemyBase.spawn_death_fragments(self, pos, throw_vec, critical)
	Sound.play_at("enemy_death", pos)
	if enemy:
		enemy.make_corpse(throw_vec)
		enemy.remove_from_group("enemies")
		enemy.queue_free()


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
	Net.rpc_to_run(_sync_enemies, [ids, places, yaws])


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemies(ids: PackedInt32Array, places: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	for i in ids.size():
		var enemy := _find_net(ids[i])
		if enemy:
			enemy.set_net_state(places[i], yaws[i])


func _find_net(net_id: int) -> EnemyBase:
	return _enemies_by_id.get(net_id)
