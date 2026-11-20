extends Area3D
## A puddle that grows while it rains and dries up when it stops.
## Players standing in one are exposed even under a roof (they detect it with
## a point query on physics layer 5). Gutters can crawl out of a puddle once
## it is half grown. A Bug Bomb dries it instantly with clear().
##
## Growth follows WeatherManager.storm_intensity, which every client already
## has, so each client grows its puddles locally; nothing is networked.

@export var max_radius := 2.5
## Seconds of full-intensity rain to grow from dry to max_radius.
@export var grow_time := 45.0
## Seconds to dry from full size once the rain stops.
@export var dry_time := 25.0
@export var color := Color(0.25, 0.35, 0.3, 0.75)
@export var acid_color := Color(0.35, 0.7, 0.2, 0.8)

## 0 = dry, 1 = full size.
var growth := 0.0

var _shape := CylinderShape3D.new()
var _collision := CollisionShape3D.new()
var _mesh := MeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _draw_water := false
static var _marked_first_wet := false


func _ready() -> void:
	add_to_group("puddles")
	collision_layer = 1 << 4
	collision_mask = 0
	monitoring = false
	_shape.height = 0.4
	_collision.shape = _shape
	add_child(_collision)

	_draw_water = not Net.dedicated and DisplayServer.get_name() != "headless"
	if not _draw_water:
		_mesh.free()
		_apply()
		return
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 20
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 0.05
	_material.metallic = 0.6
	_material.albedo_color = color
	disc.material = _material
	_mesh.mesh = disc
	_mesh.position.y = 0.075
	add_child(_mesh)
	_apply()


var _tick_elapsed := 0.0


func _physics_process(delta: float) -> void:
	_tick_elapsed += delta
	if _tick_elapsed < 0.1:
		return
	var dt := _tick_elapsed
	_tick_elapsed = 0.0
	var raining := WeatherManager.is_raining()
	if not raining and growth <= 0.0:
		return
	var intensity := WeatherManager.storm_intensity
	if raining:
		var growth_rate := 3.0 if WeatherManager.wave_modifier() == WeatherManager.WavePlan.FLOOD else 1.0
		var cap := _sandbag_growth_cap()
		growth = minf(growth + intensity * growth_rate * dt / grow_time, cap)
	else:
		growth = maxf(growth - dt / dry_time, 0.0)
	_apply()
	if not _draw_water:
		return
	var base := color.lerp(acid_color, clampf((intensity - 0.7) / 0.3, 0.0, 1.0))
	if GameManager.has_mutation("undertow"):
		var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		base = base.lerp(Color(0.22, 0.82, 0.9, 0.88), pulse)
	_material.albedo_color = base
	if raining and growth > 0.3 and randf() < intensity * (0.35 if OS.has_feature("web") else 0.8):
		_ripple()


static var _ripple_mesh: TorusMesh
var _ripples := 0


## A raindrop ring: expands and fades at a random spot on the puddle.
func _ripple() -> void:
	if _ripples >= 3:
		return
	if _ripple_mesh == null:
		_ripple_mesh = TorusMesh.new()
		_ripple_mesh.inner_radius = 0.85
		_ripple_mesh.outer_radius = 1.0
		_ripple_mesh.rings = 16
		_ripple_mesh.ring_segments = 3
	var ring := MeshInstance3D.new()
	ring.mesh = _ripple_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.5)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var r := radius() * 0.8
	var a := randf() * TAU
	ring.position = Vector3(cos(a), 0.0, sin(a)) * randf() * r + Vector3.UP * 0.02
	ring.scale = Vector3(0.05, 0.05, 0.05)
	_ripples += 1
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(0.35, 0.05, 0.35), 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(func():
		_ripples -= 1
		ring.queue_free())


func radius() -> float:
	return max_radius * growth


func can_spawn_gutter() -> bool:
	return growth >= 0.5


## Dry the puddle at once (Bug Bomb).
func clear() -> void:
	set_growth(0.0)


func set_growth(value: float) -> void:
	growth = clampf(value, 0.0, 1.0)
	_apply()


func _apply() -> void:
	var r := radius()
	var wet := r > 0.25
	_collision.disabled = not wet
	if wet:
		_shape.radius = r
	if _draw_water:
		if wet and not _marked_first_wet:
			_marked_first_wet = true
			Perf.mark("first puddle visible")
		_mesh.visible = wet
		if wet:
			_mesh.scale = Vector3(r, 1.0, r)


func _sandbag_growth_cap() -> float:
	var limit := max_radius
	for wall: Node3D in get_tree().get_nodes_in_group("sandbag_walls"):
		var local := wall.to_local(global_position)
		if absf(local.y) > 0.7:
			continue
		var edge := Vector2(maxf(absf(local.x) - 0.9, 0.0), maxf(absf(local.z) - 0.36, 0.0)).length()
		limit = minf(limit, edge)
	# Cap the circular edge against the nearest wall.
	return clampf(limit / maxf(max_radius, 0.01), 0.0, 1.0)
