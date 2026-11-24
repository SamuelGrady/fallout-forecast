extends Node3D
## A spore glob on a ballistic arc. When it lands (or hits something) it leaves
## a SporeCloud. Spawned by the host; damage happens only on the host.

const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")
const CLOUDBURST_CUE := preload("res://enemies/mister/cloudburst_cue.gdshader")
const ACID_RADIUS := 3.0

var damage_per_second := 6.0
var source: Node = null
var acid := false
var cloudburst := false
var hazard_id := 0

var _velocity := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _age := 0.0
var _trail_left := 0.0
var _marker: MeshInstance3D
var _cue_material: ShaderMaterial
var _cue_duration := 0.0


func _ready() -> void:
	add_to_group("enemy_hazards")
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.radius = 0.2
	sphere.height = 0.4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ecfb5b") if acid else Color(0.5, 1.0, 0.3)
	material.emission_enabled = true
	material.emission = material.albedo_color
	sphere.material = material
	mesh.mesh = sphere
	add_child(mesh)


## Aim so the glob lands on `target` after `time` seconds.
func launch(from: Vector3, target: Vector3, time: float) -> void:
	global_position = from
	_velocity = (target - from) / time + Vector3.UP * 0.5 * _gravity * time
	if cloudburst:
		if not Net.dedicated and DisplayServer.get_name() != "headless":
			_make_cloudburst_cue()
		return
	# Landing ring at the target so players can step out before it bursts.
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = ACID_RADIUS if acid else 2.5
	torus.inner_radius = torus.outer_radius - .20
	torus.rings = 24
	torus.ring_segments = 4
	_marker.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, .87, .22, .9) if acid else Color(0.7, 1.0, 0.3, 0.7)
	_marker.material_override = material
	get_parent().add_child(_marker)
	_marker.global_position = target + Vector3.UP * 0.06
	_marker.scale = Vector3.ONE * 0.3
	_marker.create_tween().tween_property(_marker, "scale", Vector3.ONE, time)


func _make_cloudburst_cue() -> void:
	# Trace the same fixed-step arc against world geometry. The nominal aim can
	# sit over a curb, or the glob can strike a facade before reaching it.
	var space := get_world_3d().direct_space_state
	var point := global_position
	var velocity := _velocity
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var query := PhysicsRayQueryParameters3D.create(point, point, 1)
	while _cue_duration <= 5.0:
		_cue_duration += dt
		velocity.y -= _gravity * dt
		query.from = point
		query.to = point + velocity * dt
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			point = hit.position
			break
		if _cue_duration <= 5.0:
			point = query.to

	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * ACID_RADIUS * 2.0
	_cue_material = ShaderMaterial.new()
	_cue_material.shader = CLOUDBURST_CUE
	_marker = MeshInstance3D.new()
	_marker.mesh = plane
	_marker.material_override = _cue_material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(_marker)
	_marker.global_position = _acid_floor(point) + Vector3.UP * 0.11
	_update_cloudburst_cue()


func _update_cloudburst_cue() -> void:
	# The shrinking inner line gives the order of impact. Keep the full-size
	# footprint and hatch steady, and drop the moving line with reduced flash.
	var countdown := -1.0 if Settings.reduced_flash else lerpf(0.80, 0.12, clampf(_age / _cue_duration, 0.0, 1.0))
	_cue_material.set_shader_parameter("countdown", countdown)


func _physics_process(delta: float) -> void:
	if GameManager.victory_locked or GameManager.finished:
		queue_free()
		return
	_age += delta
	if _cue_material:
		_update_cloudburst_cue()
	_velocity.y -= _gravity * delta
	var step := _velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + step, 1 << 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() or _age > 5.0:
		_burst(hit.get("position", global_position))
		return
	# A Shield Dome stops globs at its shell: they splash off it harmlessly.
	if SporeCloud._in_dome(global_position + step, get_tree()) and not SporeCloud._in_dome(global_position, get_tree()):
		if not Net.dedicated:
			ShotFX.puff(get_parent(), global_position, Color(0.55, 0.95, 1.0, 0.8), 0.35, 0.45)
		Sound.play_at("spore_burst", global_position, -8.0)
		queue_free()
		return
	global_position += step
	_trail_left -= delta
	if _trail_left <= 0.0 and not Net.dedicated:
		_trail_left = 0.05
		var color := Color(.84, .83, .18, .8) if acid else Color(0.55, 1.0, 0.3, 0.7)
		ShotFX.puff(get_parent(), global_position, color, 0.1, 0.35)


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


func _burst(at: Vector3) -> void:
	if acid:
		at = _acid_floor(at)
	Sound.play_at("smog_splash" if acid else "spore_burst", at)
	SporeCloud.spawn(get_parent(), at, acid, ACID_RADIUS if acid else 2.5, 6.0 if acid else 4.0, damage_per_second, source if is_instance_valid(source) else null, hazard_id)
	queue_free()


func _acid_floor(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * .16, at + Vector3.DOWN * 12.0, 1)
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
	return floor_hit.get("position", at)
