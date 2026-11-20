extends Node3D
## Local-only weather visuals driven by WeatherManager.storm_intensity:
## rain particles that follow the active camera (and stop on roofs), fog,
## and a darker sky and sun as the storm builds. Nothing here is networked;
## each client draws its own weather.

@export_group("Rain")
@export var max_drops := 8000
@export var area_size := 50.0
@export var spawn_height := 18.0
@export var fall_speed := 22.0
@export var rain_color := Color(0.75, 0.82, 0.9, 0.35)
@export var acid_color := Color(0.55, 1.0, 0.3, 0.45)

@export_group("Fog")
## Fog density at storm_intensity 0, 0.3, 0.7, 1.0 (Clear, Drizzle, Downpour, Acid Storm).
@export var fog_density_curve := PackedFloat32Array([0.0, 0.012, 0.035, 0.04])
@export var fog_color := Color(0.42, 0.38, 0.52)
@export var acid_fog_color := Color(0.18, 0.32, 0.12)

@export_group("Light")
@export var min_sky_energy := 0.35
@export var min_sun_energy := 0.15

## Lightning flash, 0-1. LightningFX sets it; it fades on its own.
var flash := 0.0
@export var flash_fade := 4.0

var _rain: GPUParticles3D
var _web_rain: CPUParticles3D
var _rain_material: StandardMaterial3D
var _web_rain_material: ShaderMaterial
var _collision: GPUParticlesCollisionHeightField3D
var _environment: Environment
var _sun: DirectionalLight3D
var _base_sky_energy := 1.0
var _base_sun_energy := 1.0
var _shelter_query := PhysicsPointQueryParameters3D.new()


func _ready() -> void:
	_shelter_query.collide_with_areas = true
	_shelter_query.collide_with_bodies = false
	_shelter_query.collision_mask = 1 << 3
	_build_rain()
	_find_scene_lighting.call_deferred()


func _process(delta: float) -> void:
	flash = maxf(flash - flash_fade * delta, 0.0)
	var intensity := WeatherManager.storm_intensity
	# 0 at Downpour and below, 1 at the full Acid Storm.
	var acid := clampf((intensity - 0.7) / 0.3, 0.0, 1.0)

	var camera := get_viewport().get_camera_3d()
	if camera:
		var p := camera.global_position
		var rain_position := p + Vector3.UP * spawn_height
		if _web_rain:
			_web_rain.global_position = rain_position
		else:
			_rain.global_position = rain_position
			# Only rerender the heightfield when the camera moves to another cell.
			_collision.global_position = p.snapped(Vector3.ONE * 4.0)

	var flare_cover := camera and preload("res://weapons/projectile.gd").protects(camera.global_position, get_tree())
	var rain_intensity := intensity * (0.25 if flare_cover else 1.0)
	var color := rain_color.lerp(acid_color, acid)
	if _web_rain:
		# Keep rain pouring visibly outside while cutting a dry hole over the
		# shelter the local player stands under.
		var player := get_tree().get_first_node_in_group("local_player") as Player
		color.a *= rain_intensity
		_web_rain.emitting = intensity > 0.01
		_web_rain_material.set_shader_parameter("rain_color", color)
		_update_web_shelter_hole(player)
	else:
		_rain.amount_ratio = rain_intensity
		_rain.emitting = intensity > 0.01
		_rain_material.albedo_color = color

	if _environment:
		_environment.fog_enabled = intensity > 0.01
		_environment.fog_density = _sample_fog(intensity) * (0.65 if flare_cover else 1.0)
		_environment.fog_light_color = fog_color.lerp(acid_fog_color, acid)
		_environment.background_energy_multiplier = lerpf(_base_sky_energy, min_sky_energy, minf(intensity / 0.7, 1.0)) + flash * 3.0
		_environment.fog_density *= 1.0 - flash * 0.6
	if _sun:
		_sun.light_energy = lerpf(_base_sun_energy, min_sun_energy, minf(intensity / 0.7, 1.0)) + flash * 2.5


func _update_web_shelter_hole(player: Player) -> void:
	if player == null or not player.sheltered:
		_web_rain_material.set_shader_parameter("hole_active", 0.0)
		return
	var hole_min := player.global_position + Vector3(-3.4, -2.0, -3.4)
	var hole_max := player.global_position + Vector3(3.4, 4.5, 3.4)
	var space := get_world_3d().direct_space_state
	_shelter_query.position = player.head.global_position
	var hits := space.intersect_point(_shelter_query, 1)
	if not hits.is_empty():
		var area := hits[0].collider as Area3D
		if area:
			for child in area.get_children():
				if child is CollisionShape3D and child.shape:
					var ext := Vector3(3.4, 2.5, 3.4)
					if child.shape is BoxShape3D:
						ext = (child.shape as BoxShape3D).size * 0.5
					elif child.shape is CylinderShape3D:
						var cyl := child.shape as CylinderShape3D
						ext = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
					var c: Vector3 = (child as Node3D).global_position
					# Transform box corners to world AABB so rotated shelters match too.
					var b: Basis = (child as Node3D).global_basis
					var wx := absf(b.x.x) * ext.x + absf(b.y.x) * ext.y + absf(b.z.x) * ext.z
					var wy := absf(b.x.y) * ext.x + absf(b.y.y) * ext.y + absf(b.z.y) * ext.z
					var wz := absf(b.x.z) * ext.x + absf(b.y.z) * ext.y + absf(b.z.z) * ext.z
					hole_min = Vector3(c.x - wx, c.y - wy - 1.5, c.z - wz)
					hole_max = Vector3(c.x + wx, c.y + wy + 0.5, c.z + wz)
					break
	_web_rain_material.set_shader_parameter("hole_active", 1.0)
	_web_rain_material.set_shader_parameter("hole_min", hole_min)
	_web_rain_material.set_shader_parameter("hole_max", hole_max)


func _build_rain() -> void:
	if OS.has_feature("web"):
		_build_web_rain()
		return

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.6)
	_rain_material = StandardMaterial3D.new()
	_rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_material.billboard_keep_scale = true
	_rain_material.albedo_color = rain_color
	_rain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = _rain_material

	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = max_drops
	_rain.lifetime = (spawn_height + 10.0) / fall_speed
	_rain.local_coords = false
	_rain.fixed_fps = 0
	_rain.visibility_aabb = AABB(Vector3(-area_size, -spawn_height - 20.0, -area_size), Vector3(area_size * 2.0, spawn_height + 30.0, area_size * 2.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(area_size * 0.5, 1.0, area_size * 0.5)
	process.direction = Vector3(0.05, -1.0, 0.0)
	process.spread = 2.0
	process.initial_velocity_min = fall_speed * 0.9
	process.initial_velocity_max = fall_speed * 1.1
	process.gravity = Vector3.ZERO
	process.particle_flag_align_y = true
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = process
	_rain.collision_base_size = 0.05

	_rain.draw_pass_1 = mesh
	add_child(_rain)

	# Heightfield around the camera so drops vanish on roofs and awnings.
	_collision = GPUParticlesCollisionHeightField3D.new()
	_collision.name = "RainCollision"
	_collision.size = Vector3(area_size, 60.0, area_size)
	_collision.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_collision.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collision)


func _build_web_rain() -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 rain_color : source_color = vec4(0.75, 0.82, 0.9, 0.35);
uniform float hole_active = 0.0;
uniform vec3 hole_min = vec3(0.0);
uniform vec3 hole_max = vec3(0.0);

varying vec3 world_pos;

void vertex() {
	// Fixed-Y billboard so streaks stay vertical while facing the camera.
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(vec3(INV_VIEW_MATRIX[3].x - center.x, 0.0, INV_VIEW_MATRIX[3].z - center.z));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 pos = center + right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	world_pos = pos;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(pos, 1.0);
}

void fragment() {
	if (hole_active > 0.5) {
		if (world_pos.x > hole_min.x && world_pos.x < hole_max.x &&
			world_pos.z > hole_min.z && world_pos.z < hole_max.z &&
			world_pos.y < hole_max.y) {
			discard;
		}
	}
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a;
}"""
	_web_rain_material = ShaderMaterial.new()
	_web_rain_material.shader = shader
	_web_rain_material.set_shader_parameter("rain_color", rain_color)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.032, 0.72)
	mesh.material = _web_rain_material

	_web_rain = CPUParticles3D.new()
	_web_rain.name = "Rain"
	_web_rain.amount = mini(max_drops, 380)
	_web_rain.lifetime = (spawn_height + 10.0) / fall_speed
	_web_rain.fixed_fps = 30
	_web_rain.emitting = false
	_web_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_web_rain.emission_box_extents = Vector3(area_size * 0.32, 1.0, area_size * 0.32)
	_web_rain.direction = Vector3(0.05, -1.0, 0.0)
	_web_rain.spread = 2.0
	_web_rain.initial_velocity_min = fall_speed * 0.9
	_web_rain.initial_velocity_max = fall_speed * 1.1
	_web_rain.gravity = Vector3.ZERO
	_web_rain.mesh = mesh
	add_child(_web_rain)


func _find_scene_lighting() -> void:
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_environment = (node as WorldEnvironment).environment
		break
	for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_sun = node
		break
	if _environment:
		_base_sky_energy = _environment.background_energy_multiplier
		_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		if _web_rain:
			_environment.glow_enabled = false
	if _sun:
		_base_sun_energy = _sun.light_energy
		if _web_rain:
			# Keep bright facades readable and cut WebGL2 shadow pass cost.
			_base_sun_energy *= 0.75
			_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			_sun.directional_shadow_max_distance = 40.0
			RenderingServer.directional_shadow_atlas_set_size(1024, false)
	if _web_rain:
		# Cull distant OmniLight3Ds so WebGL2 forward lighting stays fast.
		for light in get_tree().root.find_children("*", "OmniLight3D", true, false):
			var omni := light as OmniLight3D
			if omni and not omni.distance_fade_enabled:
				omni.distance_fade_enabled = true
				omni.distance_fade_begin = 26.0
				omni.distance_fade_length = 8.0


func _sample_fog(intensity: float) -> float:
	var stops := WeatherManager.STORM_INTENSITY
	for i in range(1, stops.size()):
		if intensity <= stops[i]:
			var t := inverse_lerp(stops[i - 1], stops[i], intensity)
			return lerpf(fog_density_curve[i - 1], fog_density_curve[i], t)
	return fog_density_curve[fog_density_curve.size() - 1]
