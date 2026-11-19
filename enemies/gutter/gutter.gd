extends EnemyBase
## Gutter: ambusher. Crawls out of storm drains and puddles, low to the ground,
## and lunges at the legs of anyone within lunge_range.

@export var lunge_range := 6.0
@export var lunge_speed := 11.0
@export var lunge_up := 2.5
@export var lunge_cooldown := 3.0
@export var lunge_time := 0.55

var _lunge_left := 0.0
var _lunge_cooldown_left := 0.0
var _lunge_hit := false


func _physics_process(delta: float) -> void:
	_lunge_cooldown_left -= delta
	if _lunge_left > 0.0:
		_lunge_left -= delta
		velocity.y -= _gravity * delta
		move_and_slide()
		if not _lunge_hit and is_instance_valid(target) \
				and global_position.distance_to(target.global_position) < data.attack_range:
			_lunge_hit = true
			attack(target, data.damage * WeatherManager.enemy_buff())
		return

	super._physics_process(delta)

	if is_instance_valid(target) and is_on_floor() and _lunge_cooldown_left <= 0.0:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance < lunge_range and distance > data.attack_range:
			_start_lunge(to_target.normalized())


func _start_lunge(direction: Vector3) -> void:
	_lunge_left = lunge_time
	_lunge_cooldown_left = lunge_cooldown
	_lunge_hit = false
	var speed := lunge_speed * WeatherManager.enemy_buff()
	velocity = direction * speed + Vector3.UP * lunge_up
