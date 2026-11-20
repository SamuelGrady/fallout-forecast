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
var _base_ambient_energy := 1.0
var _base_sun_energy := 1.0
var _shelter_query := PhysicsPointQueryParameters3D.new()
var _wet_materials: Dictionary[Material, Vector3] = {}
var _wet_colors: Dictionary[Material, Color] = {}
var _wetness := -1.0
var _wind_props: Array[Node3D] = []
var _wind_rest: Array[Basis] = []
var _wind_clock := 0.0
var _wind_was_active := false
var _sun_rest := Basis.IDENTITY
var _sun_color := Color.WHITE
var _sun_blur := 0.0
var _strike_frames := 0
var _warming_rain := false

const WET_TEXTURES := [
	"asphalt.png", "sidewalk.png", "pavers.png", "shingles_teal.png",
	"canopy.png", "awning_cyan.png", "awning_pink.png", "quay_steel.png", "diamond_plate.png",
]
const WET_SURFACE := &"storm_wet_surface"


func _ready() -> void:
	if Net.dedicated or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_shelter_query.collide_with_areas = true
	_shelter_query.collide_with_bodies = false
	_shelter_query.collision_mask = 1 << 3
	_build_rain()


func _process(delta: float) -> void:
	flash = maxf(flash - flash_fade * delta, 0.0)
	var intensity := WeatherManager.storm_intensity
	_update_wet_surfaces(intensity)
	_update_wind(intensity, delta)
	# 0 at Downpour and below, 1 at the full Acid Storm.
	var acid := clampf((intensity - 0.7) / 0.3, 0.0, 1.0)

	var camera := get_viewport().get_camera_3d()
	if camera:
		var p := camera.global_position
		var rain_position := p + Vector3.UP * spawn_height
		if _web_rain:
			if _warming_rain:
				rain_position = p - camera.global_basis.z * 6.0 + Vector3.UP
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
		_web_rain.emitting = intensity > 0.01 or _warming_rain
		_web_rain_material.set_shader_parameter("rain_color", color)
		_update_web_shelter_hole(player)
	else:
		_rain.amount_ratio = maxf(rain_intensity, 0.02 if _warming_rain else 0.0)
		_rain.emitting = intensity > 0.01 or _warming_rain
		_rain_material.albedo_color = color

	var blackout := WeatherManager.wave_modifier() == WeatherManager.WavePlan.BLACKOUT and WeatherManager.is_storm_active()
	var darken := .62 if blackout else 1.0
	if _environment:
		# The fog variant is set before Level enters the tree.
		var fog := _sample_fog(intensity)
		if blackout:
			fog = fog * 1.4 + minf(intensity, .3) * .036
		_environment.fog_density = fog * (0.65 if flare_cover else 1.0)
		_environment.fog_light_color = fog_color.lerp(acid_fog_color, acid)
		_environment.background_energy_multiplier = lerpf(_base_sky_energy, min_sky_energy, minf(intensity / 0.7, 1.0)) * darken + flash * 3.0
		_environment.ambient_light_energy = _base_ambient_energy * lerpf(1.0, darken, minf(intensity / .3, 1.0))
		if _strike_frames > 0:
			_environment.ambient_light_energy *= 1.0 - 0.28 * Settings.flash_scale()
		_environment.fog_density *= 1.0 - flash * 0.6
	if _sun:
		_sun.light_energy = lerpf(_base_sun_energy, min_sun_energy, minf(intensity / 0.7, 1.0)) * darken + flash * 1.65
		if _strike_frames > 0:
			_sun.light_energy += 2.7 * Settings.flash_scale()
			_strike_frames -= 1
		elif _sun.basis != _sun_rest:
			_sun.basis = _sun_rest
			_sun.light_color = _sun_color
			_sun.shadow_blur = _sun_blur


## Use the existing shadow-casting sun for two rendered frames. Its shadow
## variant stays resident, while the light swings around to the strike.
func light_strike(at: Vector3) -> void:
	if OS.has_feature("web") or _sun == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var direction := at - camera.global_position
	direction.y = 0.0
	if direction.length_squared() < 1.0:
		direction = Vector3.BACK
	direction = direction.normalized() + Vector3.UP * 0.7
	_sun.look_at(_sun.global_position - direction)
	_sun.light_color = Color("#dfeaff")
	_sun.shadow_blur = 0.15
	_strike_frames = 2


func warm_rain(value: bool) -> void:
	_warming_rain = value


static func is_wet_surface(material: StandardMaterial3D) -> bool:
	return material.has_meta(WET_SURFACE) or material.resource_name == "roof" or (
		material.albedo_texture != null and material.albedo_texture.resource_path.get_file() in WET_TEXTURES)


func _collect_surface(material: Material) -> void:
	if material == null or _wet_materials.has(material):
		return
	if material is StandardMaterial3D and is_wet_surface(material):
		_wet_materials[material] = Vector3(material.roughness, material.metallic_specular, 0.0)
		_wet_colors[material] = material.albedo_color
	elif material is ShaderMaterial and material.has_meta(WET_SURFACE):
		_wet_materials[material] = Vector3.ZERO


func refresh_wet_surfaces(level: Node3D) -> void:
	if Net.dedicated or DisplayServer.get_name() == "headless" or level == null:
		return
	_update_wet_surfaces(0.0)
	_wet_materials.clear()
	_wet_colors.clear()
	_collect_surface_finish(level)


func _collect_surface_finish(level: Node3D) -> void:
	for node in level.find_children("*", "GeometryInstance3D", true, false):
		if node is MeshInstance3D and node.mesh:
			for i in node.mesh.get_surface_count():
				_collect_surface(node.get_active_material(i))
		elif node is CSGPrimitive3D:
			_collect_surface(node.material)
	_wetness = -1.0


func _update_wet_surfaces(intensity: float) -> void:
	# Quantize while ramping. At a steady intensity neither renderer has to
	# resend material data, even when the map has hundreds of wet surfaces.
	var wet := snappedf(intensity, 0.025)
	if is_equal_approx(wet, _wetness):
		return
	_wetness = wet
	for material in _wet_materials:
		if material is ShaderMaterial:
			material.set_shader_parameter("wetness", wet)
		else:
			var dry: Vector3 = _wet_materials[material]
			var tint: Color = _wet_colors[material]
			material.albedo_color = tint.darkened(wet * 0.24)
			material.roughness = lerpf(dry.x, 0.25, wet)
			material.metallic_specular = lerpf(dry.y, 0.54, wet)


func _exit_tree() -> void:
	_update_wet_surfaces(0.0)


func _update_wind(intensity: float, delta: float) -> void:
	if _wind_props.is_empty() or (intensity <= 0.0 and not _wind_was_active):
		return
	_wind_clock += delta
	_wind_was_active = intensity > 0.0
	# Only authored visual roots move. Their trunks/posts, world collision and
	# navigation stay in place. A common gust with phase offsets avoids lockstep.
	var gust := intensity * (0.6 + 0.4 * sin(_wind_clock * 1.35))
	for i in _wind_props.size():
		var phase := _wind_clock * 2.8 + i * 1.73
		var node := _wind_props[i]
		node.basis = Basis.from_euler(Vector3(sin(phase) * gust * 0.026, 0.0,
			(sin(phase * 0.8) + 0.45) * gust * 0.045)) * _wind_rest[i]


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
	mesh.size = Vector2(0.036, 0.78)
	mesh.material = _web_rain_material

	_web_rain = CPUParticles3D.new()
	_web_rain.name = "Rain"
	_web_rain.amount = mini(max_drops, 220)
	_web_rain.lifetime = (spawn_height + 10.0) / fall_speed
	_web_rain.fixed_fps = 24
	_web_rain.emitting = false
	_web_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_web_rain.emission_box_extents = Vector3(area_size * 0.3, 1.0, area_size * 0.3)
	_web_rain.direction = Vector3(0.05, -1.0, 0.0)
	_web_rain.spread = 2.0
	_web_rain.initial_velocity_min = fall_speed * 0.9
	_web_rain.initial_velocity_max = fall_speed * 1.1
	_web_rain.gravity = Vector3.ZERO
	_web_rain.mesh = mesh
	add_child(_web_rain)


func configure_level(level: Node3D, map_id: String) -> void:
	if Net.dedicated or DisplayServer.get_name() == "headless":
		return
	match map_id:
		"harbor":
			fog_color = Color(0.37, 0.45, 0.53)
			fog_density_curve = PackedFloat32Array([0.0, 0.011, 0.029, 0.04])
			min_sun_energy = 0.24
		"maple_hollow":
			fog_color = Color(0.43, 0.40, 0.49)
			fog_density_curve = PackedFloat32Array([0.0, 0.012, 0.031, 0.04])
			min_sun_energy = 0.22
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var world_env := node as WorldEnvironment
		if world_env.environment:
			_environment = world_env.environment.duplicate() as Environment
			world_env.environment = _environment
		break
	for node in level.find_children("*", "DirectionalLight3D", true, false):
		_sun = node
		break
	if _environment:
		_base_sky_energy = _environment.background_energy_multiplier
		_base_ambient_energy = _environment.ambient_light_energy
		_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		_environment.fog_enabled = true
		_environment.fog_density = 0.0
		if _web_rain:
			_environment.glow_enabled = false
			_environment.ssao_enabled = false
			_environment.ssil_enabled = false
			_environment.sdfgi_enabled = false
	if _sun:
		_base_sun_energy = _sun.light_energy
		_sun_rest = _sun.basis
		_sun_color = _sun.light_color
		_sun_blur = _sun.shadow_blur
		if _web_rain:
			# Disable real-time sun shadow map on WebGL2: cuts full-scene geometry
			# draw calls in half while keeping directional lighting and fog intact.
			_base_sun_energy *= 0.75
			_sun.shadow_enabled = false
	if _web_rain:
		# Aggressively fade distant streetlamps so WebGL2 forward shaders only
		# evaluate nearby lights.
		for light in level.find_children("*", "OmniLight3D", true, false):
			var omni := light as OmniLight3D
			if omni:
				omni.shadow_enabled = false
				omni.distance_fade_enabled = true
				omni.distance_fade_begin = 14.0
				omni.distance_fade_length = 6.0
	elif DisplayServer.get_name() != "headless":
		for node in level.find_children("*", "Node3D", true, false):
			if node.is_in_group("wind_sway"):
				_wind_props.append(node)
				_wind_rest.append(node.basis)
	# Run after RetroScreen converts the already attached map geometry.
	_collect_surface_finish.call_deferred(level)


func _sample_fog(intensity: float) -> float:
	var stops := WeatherManager.STORM_INTENSITY
	for i in range(1, stops.size()):
		if intensity <= stops[i]:
			var t := inverse_lerp(stops[i - 1], stops[i], intensity)
			return lerpf(fog_density_curve[i - 1], fog_density_curve[i], t)
	return fog_density_curve[fog_density_curve.size() - 1]
