extends "res://enemies/weather_enemy.gd"
## Repositions in short bursts and chains its shock through nearby players.

const SHOCK_COLOR := Color("#fff074")
var _charged_left := 0.0
var _blink_left := 2.0


func _ready() -> void:
	super._ready()
	if Net.is_host():
		WeatherManager.lightning_struck.connect(_on_lightning)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_blink_left -= delta
	if _blink_left > 0.0 or _windup_left > 0.0 or _stagger_left > 0.0 or not is_instance_valid(target):
		return
	var distance := _flat_distance(target.global_position)
	if distance > 17.0 or distance < 2.5 or not _has_attack_los(target):
		return
	_blink_left = 2.3 if _charged_left > 0.0 else 4.5
	_blink()


func _blink() -> void:
	var forward := flat_direction(target.global_position)
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	for side in [-1.0, 1.0]:
		var offset := forward.rotated(Vector3.UP, side * .94) * 3.6
		var desired := global_position + offset
		var floor_point := NavigationServer3D.map_get_closest_point(map, desired)
		var motion := Vector3(offset.x, 0, offset.z)
		if Vector2(floor_point.x - desired.x, floor_point.z - desired.z).length() > .55 or absf(floor_point.y - desired.y) > 1.25:
			continue
		if test_move(global_transform, motion):
			continue
		var before := global_position
		global_position += motion
		_repath_timer = 0.0
		_record_position()
		GameManager.broadcast_arc([before + Vector3.UP, global_position + Vector3.UP], SHOCK_COLOR)
		announce_tell("static_blink", 0.0, -11.0)
		return


func _on_lightning(at: Vector3, _strike_seed: int) -> void:
	if _dead or _flat_distance(at) > 25.0:
		return
	_attack_timer = 0.0
	_blink_left = minf(_blink_left, .45)
	announce_tell("static_power", 0.0, -8.0)


func speed_multiplier() -> float:
	return super.speed_multiplier() * (1.46 if _charged_left > 0.0 else 1.0)


func _begin_attack(victim: Node3D, amount: float) -> void:
	_attack_victim = victim
	_attack_amount = amount
	_windup_left = .57
	announce_tell("static_shock", _windup_left, -8.0)


func attack(victim: Node3D, amount: float) -> void:
	var pool := targetable_players()
	var points: Array = [global_position + Vector3.UP * 1.38]
	var hop := victim
	for i in (4 if is_elite or _charged_left > 0.0 else 3):
		if hop == null:
			break
		pool.erase(hop)
		var at := hop.global_position + Vector3.UP
		points.append(at)
		super.attack(hop, amount * pow(.78, i))
		if _dead:
			break
		hop = null
		var closest := 5.4 if _charged_left > 0.0 else 4.5
		for node in pool:
			var candidate := node as Node3D
			var endpoint := candidate.global_position + Vector3.UP
			var distance := at.distance_to(endpoint)
			if distance >= closest:
				continue
			var ray := PhysicsRayQueryParameters3D.create(at, endpoint, 1)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				closest = distance
				hop = candidate
	GameManager.broadcast_arc(points, SHOCK_COLOR)
	GameManager.achievement_event("static_chain", victim, points.size() - 1)


func play_tell(cue: String, duration: float, volume: float) -> void:
	super.play_tell(cue, duration, volume)
	if cue == "static_power":
		_charged_left = 5.5
	elif cue == "static_shock":
		show_warning(duration, 2.2, Color(1.0, .91, .32, .8))


func _process(delta: float) -> void:
	super._process(delta)
	_charged_left = maxf(0.0, _charged_left - delta)
	if _model:
		_model.charge_amount = 1.0 if _charged_left > 0.0 else 0.0


func is_critical_hit(height: float, _source: Node) -> bool:
	return height >= 1.58
