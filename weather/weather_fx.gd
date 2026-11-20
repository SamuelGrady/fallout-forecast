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
var _rain_material: StandardMaterial3D
var _collision: GPUParticlesCollisionHeightField3D
var _environment: Environment
var _sun: DirectionalLight3D
var _base_sky_energy := 1.0
var _base_sun_energy := 1.0


func _ready() -> void:
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
		_rain.global_position = Vector3(p.x, p.y + spawn_height, p.z)
		# Snap to a 4 m grid: the heightfield only re-renders when it moves,
		# instead of every frame.
		_collision.global_position = Vector3(snappedf(p.x, 4.0), snappedf(p.y, 4.0), snappedf(p.z, 4.0))

	var flare_cover := camera and preload("res://weapons/projectile.gd").protects(camera.global_position, get_tree())
	_rain.amount_ratio = intensity * (0.25 if flare_cover else 1.0)
	_rain.emitting = intensity > 0.01
	_rain_material.albedo_color = rain_color.lerp(acid_color, acid)

	if _environment:
		_environment.fog_enabled = intensity > 0.01
		_environment.fog_density = _sample_fog(intensity) * (0.65 if flare_cover else 1.0)
		_environment.fog_light_color = fog_color.lerp(acid_fog_color, acid)
		_environment.background_energy_multiplier = lerpf(_base_sky_energy, min_sky_energy, minf(intensity / 0.7, 1.0)) + flash * 3.0
		_environment.fog_density *= 1.0 - flash * 0.6
	if _sun:
		_sun.light_energy = lerpf(_base_sun_energy, min_sun_energy, minf(intensity / 0.7, 1.0)) + flash * 2.5


func _build_rain() -> void:
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
	_rain.draw_pass_1 = mesh
	add_child(_rain)

	# Heightfield around the camera so drops vanish on roofs and awnings.
	_collision = GPUParticlesCollisionHeightField3D.new()
	_collision.name = "RainCollision"
	_collision.size = Vector3(area_size, 60.0, area_size)
	_collision.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_collision.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(_collision)


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
	if _sun:
		_base_sun_energy = _sun.light_energy


func _sample_fog(intensity: float) -> float:
	var stops := WeatherManager.STORM_INTENSITY
	for i in range(1, stops.size()):
		if intensity <= stops[i]:
			var t := inverse_lerp(stops[i - 1], stops[i], intensity)
			return lerpf(fog_density_curve[i - 1], fog_density_curve[i], t)
	return fog_density_curve[fog_density_curve.size() - 1]
