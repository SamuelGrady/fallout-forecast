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


func _ready() -> void:
	add_to_group("puddles")
	collision_layer = 1 << 4
	collision_mask = 0
	monitoring = false
	_shape.height = 0.4
	_collision.shape = _shape
	add_child(_collision)

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


var _tick_left := 0.0


func _physics_process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	var dt := 0.1
	_tick_left = dt
	var raining := WeatherManager.is_raining()
	if not raining and growth <= 0.0:
		return
	var intensity := WeatherManager.storm_intensity
	if raining:
		growth = minf(growth + intensity * dt / grow_time, 1.0)
	else:
		growth = maxf(growth - dt / dry_time, 0.0)
	var base := color.lerp(acid_color, clampf((intensity - 0.7) / 0.3, 0.0, 1.0))
	if GameManager.has_mutation("undertow"):
		var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
		base = base.lerp(Color(0.22, 0.82, 0.9, 0.88), pulse)
	_material.albedo_color = base
	_apply()


func radius() -> float:
	return max_radius * growth


func can_spawn_gutter() -> bool:
	return growth >= 0.5


## Dry the puddle at once (Bug Bomb).
func clear() -> void:
	growth = 0.0
	_apply()


func _apply() -> void:
	var r := radius()
	var wet := r > 0.25
	_mesh.visible = wet
	_collision.disabled = not wet
	if wet:
		_shape.radius = r
		_mesh.scale = Vector3(r, 1.0, r)
