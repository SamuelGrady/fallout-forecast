extends EnemyBase
## Gutter: ambusher. Crawls out of storm drains and puddles, low to the ground,
## and lunges at the legs of anyone within lunge_range.

@export var lunge_range := 6.0
@export var lunge_speed := 11.0
@export var lunge_up := 2.5
@export var lunge_cooldown := 3.0
@export var lunge_time := 0.55

var _windup := 0.0
var _recovery := 0.0
var _direction := Vector3.ZERO
var _telegraph: MeshInstance3D

func attack(_victim: Node3D, _amount: float) -> void:
	pass

func _ready() -> void:
	super._ready()
	_telegraph = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = .65
	ring.outer_radius = .75
	_telegraph.mesh = ring
	_telegraph.position.y = .12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ff783e")
	_telegraph.material_override = material
	add_child(_telegraph)
	_telegraph.visible = false

var _lunge_left := 0.0
var _lunge_cooldown_left := 0.0
var _lunge_hit := false


func _physics_process(delta: float) -> void:
	_lunge_cooldown_left -= delta
	if _recovery > 0.0:
		_recovery -= delta
		velocity.x = 0
		velocity.z = 0
		velocity.y -= _gravity * delta
		move_and_slide()
		return
	if _windup > 0.0:
		_windup -= delta
		_telegraph.scale = Vector3.ONE * (1.0 + _windup)
		if _windup <= 0.0:
			_telegraph.visible = false
			_start_lunge(_direction)
		return
	if _lunge_left > 0.0:
		_lunge_left -= delta
		velocity += _push
		_push = Vector3.ZERO
		velocity.y -= _gravity * delta
		move_and_slide()
		if not _lunge_hit and is_instance_valid(target) \
				and global_position.distance_to(target.global_position) < data.attack_range:
			_lunge_hit = true
			super.attack(target, data.damage * WeatherManager.enemy_buff())
		if _lunge_left <= 0.0:
			_recovery = 1.0
		return

	super._physics_process(delta)

	if is_instance_valid(target) and is_on_floor() and _lunge_cooldown_left <= 0.0:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance < lunge_range and distance > 0.5:
			_direction = to_target.normalized()
			_windup = 0.65
			_telegraph.visible = true
			Sound.play_at("spore_burst", global_position, -16.0)


func _start_lunge(direction: Vector3) -> void:
	_lunge_left = lunge_time
	_lunge_cooldown_left = lunge_cooldown
	_lunge_hit = false
	var speed := lunge_speed * WeatherManager.enemy_buff()
	velocity = direction * speed + Vector3.UP * lunge_up
