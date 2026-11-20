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
var _telegraph: Node3D

func attack(_victim: Node3D, _amount: float) -> void:
	pass

func _ready() -> void:
	super._ready()
	_telegraph = Node3D.new()
	_telegraph.position.y = 0.08
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.36, 0.16, 0.85)
	# Directional lunge lane + two forward chevron arrowheads pointing along -Z.
	var lane := MeshInstance3D.new()
	var lane_box := BoxMesh.new()
	lane_box.size = Vector3(0.32, 0.03, 2.2)
	lane.mesh = lane_box
	lane.position = Vector3(0, 0, -1.5)
	lane.material_override = material
	_telegraph.add_child(lane)
	for offset_z in [-2.0, -2.75]:
		for side in [-1.0, 1.0]:
			var wing := MeshInstance3D.new()
			var wbox := BoxMesh.new()
			wbox.size = Vector3(0.58, 0.04, 0.14)
			wing.mesh = wbox
			wing.position = Vector3(side * 0.24, 0.01, offset_z)
			wing.rotation_degrees.y = side * 42.0
			wing.material_override = material
			_telegraph.add_child(wing)
	add_child(_telegraph)
	_telegraph.visible = false

var _lunge_left := 0.0
var _lunge_cooldown_left := 0.0
var _lunge_hit := false


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _stagger_left > 0.0:
		super._physics_process(delta)
		return
	_tick_status(delta)
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
		var progress := clampf(1.0 - _windup / 0.65, 0.0, 1.0)
		_telegraph.scale = Vector3(1.0, 1.0, 0.55 + progress * 0.95)
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
				and _can_attack(target):
			_lunge_hit = true
			super.attack(target, data.damage * damage_multiplier())
		if _lunge_left <= 0.0:
			_recovery = 1.0
			if not _lunge_hit:
				# Missed: an audible skid and a splash so players know the
				# opening is now.
				announce_tell("gutter_skid", 0.0, -10.0)
				ShotFX.puff(get_parent(), global_position + Vector3.UP * 0.1, Color(0.5, 0.65, 0.7, 0.7), 0.35, 0.4)
		return

	super._physics_process(delta)

	if is_instance_valid(target) and is_on_floor() and _lunge_cooldown_left <= 0.0:
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		if distance < lunge_range and distance > 0.5:
			_direction = to_target.normalized()
			_face(_direction)
			_windup = 0.65
			_telegraph.visible = true
			announce_tell("gutter_windup", _windup, -12.0)


func _start_lunge(direction: Vector3) -> void:
	_lunge_left = lunge_time
	_lunge_cooldown_left = lunge_cooldown
	_lunge_hit = false
	var speed := lunge_speed * speed_multiplier()
	velocity = direction * speed + Vector3.UP * lunge_up


func stagger(duration: float) -> void:
	super.stagger(duration)
	_windup = 0.0
	_lunge_left = 0.0
	_recovery = 0.7
	_lunge_cooldown_left = lunge_cooldown
	if _telegraph:
		_telegraph.visible = false


func _begin_attack(_victim: Node3D, _amount: float) -> void:
	# Gutters use the committed pounce windup instead of standing melee.
	pass
