extends "res://enemies/weather_enemy.gd"
## A skittering flanker that commits to a short, low leap.

var _skitter := randf_range(0.0, TAU)
var _leap_left := 0.0
var _leap_direction := Vector3.ZERO
var _leap_hit := false


func _physics_process(delta: float) -> void:
	_skitter += delta * 9.0
	if _leap_left <= 0.0:
		super._physics_process(delta)
		return
	_leap_left -= delta
	move_special(delta, _leap_direction * 10.5 * speed_multiplier())
	if not _leap_hit:
		for victim in targetable_players():
			if global_position.distance_to(victim.global_position) < 1.25 and _has_attack_los(victim):
				_leap_hit = true
				super.attack(victim, data.damage * damage_multiplier())
				break
	if is_on_wall() or (_leap_left < .25 and is_on_floor()):
		_leap_left = 0.0
		_recover_left = .28


func chase_direction(destination: Vector3) -> Vector3:
	var direction := super.chase_direction(destination)
	return direction.rotated(Vector3.UP, sin(_skitter) * .64)


func _begin_attack(victim: Node3D, amount: float) -> void:
	_attack_victim = victim
	_attack_amount = amount
	_windup_left = .24
	announce_tell("sleet_leap", _windup_left, -11.0)


func attack(victim: Node3D, amount: float) -> void:
	if global_position.distance_to(victim.global_position) <= 1.1:
		super.attack(victim, amount)
		return
	_leap_direction = flat_direction(victim.global_position)
	_leap_left = .47
	_leap_hit = false
	velocity.y = 3.5


func stagger(duration: float) -> void:
	super.stagger(duration)
	_leap_left = 0.0


func is_critical_hit(height: float, _source: Node) -> bool:
	return height >= .80
