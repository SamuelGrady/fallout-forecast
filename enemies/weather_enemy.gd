extends EnemyBase
## Shared movement and lightweight world-space tells for the weather roster.

static var _ring_mesh: TorusMesh
static var _lane_mesh: BoxMesh
var _warning: MeshInstance3D
var _warning_life := 0.0
var _warning_left := 0.0
var _warning_radius := 0.0
var _warning_is_lane := false


func model_script() -> Script:
	return preload("res://enemies/weather_infected_model.gd")


func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_warning) or _warning_left <= 0.0:
		return
	_warning_left = maxf(0.0, _warning_left - delta)
	var progress := 1.0 - _warning_left / _warning_life
	var width := (0.27 + 0.73 * progress) * _warning_radius / scale.x
	if _warning_is_lane:
		_warning.scale = Vector3(.78 + .32 * progress, 1.0, width)
		_warning.position.z = -width * .5
	else:
		_warning.scale = Vector3(width, .20, width)
	_warning.visible = _warning_left > 0.0


func show_warning(duration: float, radius: float, color: Color, lane := false) -> void:
	if Net.dedicated:
		return
	if _warning == null:
		_warning = MeshInstance3D.new()
		_warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_warning.position.y = .075
		add_child(_warning)
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = .89
		_ring_mesh.outer_radius = 1.0
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 4
		_lane_mesh = BoxMesh.new()
		_lane_mesh.size = Vector3(1.0, .025, 1.0)
	_warning.mesh = _lane_mesh if lane else _ring_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	_warning.material_override = material
	_warning.position.z = 0.0
	_warning_radius = radius
	_warning_life = duration
	_warning_left = duration
	_warning_is_lane = lane
	_warning.visible = true


func flat_direction(to: Vector3) -> Vector3:
	return Vector3(to.x - global_position.x, 0, to.z - global_position.z).normalized()


func move_special(delta: float, flat_velocity: Vector3) -> void:
	_tick_status(delta)
	velocity.x = flat_velocity.x + _push.x
	velocity.z = flat_velocity.z + _push.z
	velocity.y -= _gravity * delta
	_push = _push.move_toward(Vector3.ZERO, 25.0 * delta)
	move_and_slide()
	_record_position()
