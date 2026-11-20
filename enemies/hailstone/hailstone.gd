extends "res://enemies/weather_enemy.gd"
## Flank the plates or bait a committed charge into a wall.

var _charge_left := 0.0
var _charge_direction := Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _charge_left <= 0.0:
		super._physics_process(delta)
		return
	_charge_left -= delta
	move_special(delta, _charge_direction * 13.0 * speed_multiplier())
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		var body := hit.get_collider() as Node3D
		if body and body.is_in_group("players") and body.get("state") == "ok":
			super.attack(body, _attack_amount)
			_charge_left = 0.0
			_recover_left = .7
			return
		if absf(hit.get_normal().y) < .45 and hit.get_normal().dot(_charge_direction) < -.35:
			if body is CollisionObject3D and (body.collision_layer & 1) == 0:
				continue
			stagger(2.0)
			announce_tell("hailstone_crash", 0.0, -4.0)
			GameManager.broadcast_blast(global_position + Vector3.UP * .55, .8, Color("#c6e3ed"))
			return


func _begin_attack(victim: Node3D, amount: float) -> void:
	_attack_victim = victim
	_attack_amount = amount
	_windup_left = .9
	_charge_direction = flat_direction(victim.global_position)
	_face(_charge_direction)
	announce_tell("hailstone_charge", _windup_left, -7.0)


func _can_attack(_victim: Node3D) -> bool:
	# After warning the charge always goes down the original lane.
	return true


func in_range_move(to_target: Vector3, buff: float) -> Vector3:
	if _windup_left > 0.0 or to_target.length() < 1.8:
		return Vector3.ZERO
	return to_target.normalized() * data.move_speed * buff * .72


func attack(_victim: Node3D, _amount: float) -> void:
	_charge_left = .67


func stagger(duration: float) -> void:
	_charge_left = 0.0
	super.stagger(duration)
	_warning_left = 0.0
	if _warning:
		_warning.hide()


func play_tell(cue: String, duration: float, volume: float) -> void:
	super.play_tell(cue, duration, volume)
	if cue == "hailstone_charge":
		show_warning(duration, 8.5, Color(1.0, .43, .16, .76), true)
	elif cue == "hailstone_crash" and _warning:
		_warning.hide()


func is_critical_hit(height: float, source: Node) -> bool:
	return height >= .94 and height <= 1.94 and source is Node3D and _facing_source(source) < -.35


func take_damage(amount: float, source: Node = null) -> void:
	if Net.is_host() and health > 0.0 and source is Node3D and _facing_source(source) > .30:
		amount *= .22
		var at := _last_bullet_point if _last_bullet_point != Vector3.ZERO else global_position + Vector3.UP * 1.4
		ShotFX.sparks(get_parent(), at, -global_basis.z, 5)
		Sound.play_at("hailstone_crash", at, -20.0, 1.5)
	super.take_damage(amount, source)


func _facing_source(source: Node3D) -> float:
	return (-global_basis.z.normalized()).dot(flat_direction(source.global_position))
