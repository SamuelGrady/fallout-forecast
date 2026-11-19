class_name Player
extends CharacterBody3D
## First-person hazmat exterminator: walk, sprint, crouch, jump, mouse/pad look.
## Also works out whether the player is exposed to the rain:
## - sheltered: a roof above the head (raycast) or the head inside a Shelter
##   area on physics layer 4 (garages, awnings, bus stop, a teammate's Tarp).
## - in_puddle: feet inside a Puddle area on physics layer 5. Puddles drain the
##   suit even under a roof.
## exposed = not sheltered or in_puddle. The owning client works it out and
## reports it to the host, which does the suit-integrity math (the host reads
## `exposed`, scaled by WeatherManager.suit_loss_per_second()).

signal sheltered_changed(is_sheltered: bool)
signal exposed_changed(is_exposed: bool)

const WORLD_LAYER := 1 << 0
const SHELTER_LAYER := 1 << 3
const PUDDLE_LAYER := 1 << 4

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var crouch_speed := 2.5
@export var ground_accel := 60.0
@export var air_accel := 12.0
@export var jump_velocity := 4.8
@export var coyote_time := 0.12
@export var jump_buffer := 0.12

@export_group("Crouch")
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var crouch_transition_speed := 8.0

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var pad_look_speed := 3.0
@export var max_pitch_degrees := 88.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching := false
var is_sprinting := false
var sheltered := false
var in_puddle := false
## What the host reads for suit integrity and Drip targeting.
var exposed := true

var _height := 1.8
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pitch := 0.0
var _shelter_query := PhysicsPointQueryParameters3D.new()
var _puddle_query := PhysicsPointQueryParameters3D.new()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var roof_check: RayCast3D = $RoofCheck


func _ready() -> void:
	add_to_group("players")
	# Each player crouches on its own, so it needs its own capsule.
	collider.shape = collider.shape.duplicate()
	_height = stand_height
	_apply_height()

	_shelter_query.collide_with_areas = true
	_shelter_query.collide_with_bodies = false
	_shelter_query.collision_mask = SHELTER_LAYER
	_puddle_query.collide_with_areas = true
	_puddle_query.collide_with_bodies = false
	_puddle_query.collision_mask = PUDDLE_LAYER

	if is_multiplayer_authority():
		add_to_group("local_player")
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var pad_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if pad_look != Vector2.ZERO:
		_look(pad_look * pad_look_speed * delta)

	# Gravity and coyote time.
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		velocity.y -= gravity * delta
		_coyote_timer -= delta

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer
	else:
		_jump_buffer_timer -= delta

	# Crouch: hold to crouch, stay down while something is overhead.
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false
	var target_height := crouch_height if is_crouching else stand_height
	if not is_equal_approx(_height, target_height):
		_height = move_toward(_height, target_height, crouch_transition_speed * delta)
		_apply_height()

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not is_crouching:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# Horizontal movement relative to where the body faces.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and input.y < -0.1
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed

	var accel := ground_accel if is_on_floor() else air_accel
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
		Vector2(direction.x, direction.z) * speed, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	move_and_slide()
	_update_shelter()


func get_move_state() -> String:
	if not is_on_floor():
		return "air"
	if is_crouching:
		return "crouch"
	if Vector2(velocity.x, velocity.z).length() < 0.1:
		return "idle"
	return "sprint" if is_sprinting else "walk"


func _look(amount: Vector2) -> void:
	rotate_y(-amount.x)
	var limit := deg_to_rad(max_pitch_degrees)
	_pitch = clampf(_pitch - amount.y, -limit, limit)
	head.rotation.x = _pitch


func _apply_height() -> void:
	var capsule := collider.shape as CapsuleShape3D
	capsule.height = _height
	collider.position.y = _height * 0.5
	head.position.y = _height - 0.15


func _can_stand() -> bool:
	return not test_move(global_transform, Vector3.UP * (stand_height - _height + 0.05))


func is_exposed() -> bool:
	return exposed


func _update_shelter() -> void:
	var space := get_world_3d().direct_space_state
	_shelter_query.position = head.global_position
	var in_shelter_area := not space.intersect_point(_shelter_query, 1).is_empty()
	_puddle_query.position = global_position + Vector3.UP * 0.05
	var now_in_puddle := not space.intersect_point(_puddle_query, 1).is_empty()
	var now_sheltered := roof_check.is_colliding() or in_shelter_area
	if now_sheltered != sheltered or now_in_puddle != in_puddle:
		_set_exposure(now_sheltered, now_in_puddle)
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			_report_exposure.rpc_id(1, sheltered, in_puddle)


## Client -> host: this player's shelter and puddle state changed.
@rpc("any_peer", "call_remote", "reliable")
func _report_exposure(is_sheltered: bool, is_in_puddle: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_set_exposure(is_sheltered, is_in_puddle)


func _set_exposure(is_sheltered: bool, is_in_puddle: bool) -> void:
	in_puddle = is_in_puddle
	if is_sheltered != sheltered:
		sheltered = is_sheltered
		sheltered_changed.emit(sheltered)
	var now_exposed := not sheltered or in_puddle
	if now_exposed != exposed:
		exposed = now_exposed
		exposed_changed.emit(exposed)
