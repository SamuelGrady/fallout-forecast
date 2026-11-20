extends "res://enemies/weather_enemy.gd"
## Hangs back, then lobs clearly marked pools that deny a lane.

const KEEP_AWAY := 10.0


func in_range_move(to_target: Vector3, buff: float) -> Vector3:
	if to_target.length() >= KEEP_AWAY:
		return Vector3.ZERO
	var away := -to_target.normalized()
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.ZERO
	for angle in [0.0, .62, -.62, 1.26, -1.26]:
		var direction := away.rotated(Vector3.UP, angle)
		var probe := global_position + direction * 2.0
		var snapped := NavigationServer3D.map_get_closest_point(map, probe)
		if Vector2(snapped.x - probe.x, snapped.z - probe.z).length() < .55 and not test_move(global_transform, direction):
			return direction * data.move_speed * buff * 1.25
	return Vector3.ZERO


func _begin_attack(victim: Node3D, amount: float) -> void:
	_attack_victim = victim
	_attack_amount = amount
	_windup_left = .64
	announce_tell("smog_spit", _windup_left, -9.0)


func attack(victim: Node3D, amount: float) -> void:
	var start := global_position - global_basis.z.normalized() * .56 + Vector3.UP * 1.61 * scale.y
	GameManager.spawn_spore(start, victim.global_position + Vector3.UP * .045, 1.45, amount, true, self)
	attacked.emit(victim, amount)


func is_critical_hit(height: float, _source: Node) -> bool:
	return height >= 1.47
