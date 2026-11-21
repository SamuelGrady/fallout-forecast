extends EnemyBase
## Mister: ranged. Holds at data.attack_range from its target, backs away when
## a player gets closer than keep_away, and lobs spore arcs that leave a short
## damage cloud where they land. Its attack_cooldown is the time between lobs.

@export var keep_away := 7.0
@export var flight_time := 1.2

var _cast_rain_ring := false


func in_range_move(to_target: Vector3, buff: float) -> Vector3:
	if to_target.length() >= keep_away:
		return Vector3.ZERO
	# Back away along whichever direction still lands on the navmesh, so a
	# Mister doesn't grind into a dead corner.
	var away := -to_target.normalized()
	var map := get_world_3d().navigation_map
	for angle in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var dir := away.rotated(Vector3.UP, angle)
		var probe := global_position + dir * 2.0
		var snapped := NavigationServer3D.map_get_closest_point(map, probe)
		if Vector2(snapped.x - probe.x, snapped.z - probe.z).length() < 0.6:
			return dir * data.move_speed * buff
	return Vector3.ZERO


func attack(victim: Node3D, amount: float) -> void:
	if miniboss_wave == 3:
		_cloudburst_attack(victim.global_position, amount)
		attacked.emit(victim, amount)
		return
	var start := global_position + Vector3.UP * 1.8
	GameManager.spawn_spore(start, victim.global_position, flight_time, amount, true, self)
	attacked.emit(victim, amount)


func _cloudburst_attack(aim: Vector3, amount: float) -> void:
	_attack_timer = 4.8
	var start := global_position + Vector3.UP * 2.4
	var forward := aim - global_position
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.01 else -global_basis.z
	var across := forward.cross(Vector3.UP)
	if _cast_rain_ring:
		# Four pools close off straight exits. The eye and diagonal gaps are dry.
		for direction in [forward, across, -forward, -across]:
			GameManager.spawn_spore(start, aim + direction * 5.8, 1.65, amount, true, self)
	else:
		# The rain front sweeps across the player's lane at three marked timings.
		for step in 3:
			var landing := aim + across * ((step - 1) * 6.8)
			GameManager.spawn_spore(start, landing, 1.15 + step * 0.28, amount, true, self)
	_cast_rain_ring = not _cast_rain_ring
