extends Node3D
## Finite waves arrive in bursts, with recovery windows between groups.
## The last infected must be killed before a normal Downpour can clear.

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

var _timer := 0.0
var _wave := 0
var _budget := 0
var _spawned := 0
var _burst_left := 0
var _reveal_timer := 0.0
var _supplies_pending := false


func _ready() -> void:
	WeatherManager.phase_changed.connect(_on_phase)


func _on_phase(phase: int, wave: int) -> void:
	if wave != _wave or phase == WeatherManager.Phase.CALM:
		_wave = wave
		_budget = roundi((18 + wave * 8) * GameManager.enemy_spawn_scale())
		_spawned = 0
		_supplies_pending = true
	_timer = 1.5
	_burst_left = 0


func _physics_process(delta: float) -> void:
	if not _is_host() or not GameManager.run_active or GameManager.finished:
		return
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
	_reveal_timer -= delta
	if _spawned >= _budget and alive_count() <= 5 and _reveal_timer <= 0.0:
		_reveal_timer = 1.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.reveal(1.2)


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
	# Main Street, parking lot and park: open approaches with multiple exits.
	for point in [Vector3(-30, 0.12, 2.5), Vector3(28, 0.12, -2.5), Vector3(4, 0.12, 42), Vector3(46, 0.12, 34)]:
		var pack := Node3D.new()
		pack.set_script(preload("res://weapons/ammo_drop.gd"))
		pack.kind = "supply"
		pack.expires_after = 600.0
		add_child(pack)
		pack.global_position = point
		pack.add_to_group("street_supplies")


func _unhandled_input(event: InputEvent) -> void:
	if not (OS.is_debug_build() and _is_host() and event is InputEventKey and event.pressed and not event.echo):
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
	var at: Variant = _gutter_spawn_point() if scene == gutter_scene else _marker_position("enemy_spawn")
	if at == null:
		push_warning("No spawn point for %s" % scene.resource_path)
		return null
	var enemy := scene.instantiate() as EnemyBase
	add_child(enemy, true)
	var point: Vector3 = at
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	enemy.global_position = point + Vector3(0, 0.15, 0)
	return enemy


## Splitters: a small copy of `enemy` at `at`.
func spawn_copy(enemy: EnemyBase, at: Vector3, small: bool) -> void:
	var scene := load(enemy.scene_file_path) as PackedScene
	if scene == null:
		return
	var copy := scene.instantiate() as EnemyBase
	copy.is_small = small
	add_child.call_deferred(copy, true)
	copy.set_deferred("global_position", at)


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


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
