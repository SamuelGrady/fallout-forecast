extends Node3D
## Presentation for supply pickups, owned by RunLoot.
@export_enum("ammo", "health", "suit", "supply", "scrap", "scrap_large") var kind := "ammo"
var _age := 0.0
var _root := Node3D.new()
var _ring: MeshInstance3D

static var _mat_cache := {}
static var _ring_mats := {}
static var _ring_mesh: TorusMesh
static var _ring_meshes := {}

const SCRAP_AMBER := Color("#ffb33d")
const SCRAP_GOLD := Color("#ffd75e")
const SCRAP_BRASS := Color("#c98d3a")
const SCRAP_STEEL := Color("#4b4f52")


func _ready() -> void:
	add_child(_root)
	var colors := {"ammo": Color("#f6cf64"), "health": Color("#ff6e91"), "suit": Color("#66dfda"), "supply": Color("#b5ef82"),
		"scrap": SCRAP_AMBER, "scrap_large": SCRAP_GOLD}
	var accent: Color = colors.get(kind, Color("#f6cf64"))
	match kind:
		"scrap":
			_build_scrap(accent)
			_add_ring(accent, 0.26, 0.34, 0.75)
			return
		"scrap_large":
			_build_scrap_cache(accent)
			_add_ring(accent, 0.36, 0.45, 0.85)
			_add_ring(SCRAP_AMBER, 0.52, 0.57, 0.6)
			return
		"health":
			_build_medkit(accent)
		"suit":
			_build_canister(accent)
		"supply":
			_build_supply_case(accent)
		_:
			_build_ammo(accent)
	_ring = MeshInstance3D.new()
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 6
		_ring_mesh.inner_radius = 0.28
		_ring_mesh.outer_radius = 0.34
	_ring.mesh = _ring_mesh
	_ring.material_override = _ring_mat(accent)
	_ring.position.y = 0.04
	add_child(_ring)


static func _ring_mat(accent: Color, alpha := 0.45) -> StandardMaterial3D:
	var key := "%d_%d" % [accent.to_rgba32(), int(round(alpha * 100.0))]
	if _ring_mats.has(key):
		return _ring_mats[key]
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(accent.r, accent.g, accent.b, alpha)
	_ring_mats[key] = ring_mat
	return ring_mat


## Flat glowing ground ring; meshes are shared per size.
func _add_ring(accent: Color, inner: float, outer: float, alpha: float) -> void:
	var key := "%d_%d" % [int(inner * 100.0), int(outer * 100.0)]
	var mesh: TorusMesh = _ring_meshes.get(key)
	if mesh == null:
		mesh = TorusMesh.new()
		mesh.rings = 24
		mesh.ring_segments = 6
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		_ring_meshes[key] = mesh
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = _ring_mat(accent, alpha)
	ring.position.y = 0.04
	add_child(ring)
	if _ring == null:
		_ring = ring


func _build_scrap(accent: Color) -> void:
	# Small salvage bundle: steel plate, glowing brass cog and two bolts.
	_add_box(_root, Vector3(0, -0.02, 0), Vector3(0.3, 0.05, 0.22), SCRAP_STEEL)
	_add_box(_root, Vector3(0, 0.005, 0), Vector3(0.32, 0.015, 0.24), accent, 0.9)
	_add_cog(_root, Vector3(0.02, 0.07, 0.0), 0.1, accent, 1.1)
	_add_cyl(_root, Vector3(-0.11, 0.06, 0.06), 0.022, 0.12, SCRAP_BRASS, 0.5)
	_add_cyl(_root, Vector3(-0.11, 0.125, 0.06), 0.036, 0.025, SCRAP_BRASS, 0.5)
	_add_cyl(_root, Vector3(0.12, 0.05, -0.07), 0.02, 0.1, SCRAP_BRASS, 0.5)


func _build_scrap_cache(accent: Color) -> void:
	# Stacked salvage cache: two plates, a big gold cog, a small cog, bolt bundle.
	_add_box(_root, Vector3(0, -0.04, 0), Vector3(0.46, 0.06, 0.34), SCRAP_STEEL)
	_add_box(_root, Vector3(0, -0.005, 0), Vector3(0.48, 0.02, 0.36), SCRAP_AMBER, 1.0)
	_add_box(_root, Vector3(0.03, 0.04, 0.02), Vector3(0.36, 0.05, 0.26), SCRAP_BRASS, 0.35)
	_add_cog(_root, Vector3(-0.04, 0.11, 0.0), 0.14, accent, 1.6)
	_add_cog(_root, Vector3(0.16, 0.09, -0.07), 0.075, SCRAP_AMBER, 1.2)
	for x in [-0.17, -0.12]:
		_add_cyl(_root, Vector3(x, 0.12, 0.1), 0.024, 0.16, SCRAP_BRASS, 0.6)
		_add_cyl(_root, Vector3(x, 0.205, 0.1), 0.04, 0.025, SCRAP_BRASS, 0.6)


func _add_cog(parent: Node3D, at: Vector3, radius: float, color: Color, glow: float) -> void:
	var cog := Node3D.new()
	cog.position = at
	parent.add_child(cog)
	_add_cyl(cog, Vector3.ZERO, radius, radius * 0.4, color, glow)
	_add_cyl(cog, Vector3.ZERO, radius * 0.35, radius * 0.5, SCRAP_STEEL)
	for i in 6:
		var tooth := Node3D.new()
		tooth.rotation.y = i * TAU / 6.0
		cog.add_child(tooth)
		_add_box(tooth, Vector3(radius * 1.08, 0, 0), Vector3(radius * 0.32, radius * 0.4, radius * 0.3), color, glow)


func _build_ammo(accent: Color) -> void:
	# Brass/olive ammo tin with three standing cartridges on top.
	_add_box(_root, Vector3(0, 0, 0), Vector3(0.42, 0.22, 0.24), Color("#3c4b39"))
	_add_box(_root, Vector3(0, 0.02, 0), Vector3(0.44, 0.06, 0.26), accent, 0.45)
	for x in [-0.11, 0.0, 0.11]:
		_add_cyl(_root, Vector3(x, 0.18, 0), 0.035, 0.16, accent, 0.5)
		_add_cone(_root, Vector3(x, 0.29, 0), 0.034, 0.07, Color("#d6874a"), 0.35)


func _build_medkit(accent: Color) -> void:
	# White medical case with raised red/pink 3D cross on front, back and top + handle.
	_add_box(_root, Vector3.ZERO, Vector3(0.44, 0.3, 0.18), Color("#eff2ea"), 0.2)
	_add_box(_root, Vector3(0, 0.19, 0), Vector3(0.18, 0.06, 0.06), Color("#263444"))
	for z in [-0.095, 0.095]:
		_add_box(_root, Vector3(0, 0, z), Vector3(0.2, 0.065, 0.03), accent, 0.7)
		_add_box(_root, Vector3(0, 0, z), Vector3(0.065, 0.2, 0.03), accent, 0.7)
	_add_box(_root, Vector3(0, 0.155, 0), Vector3(0.16, 0.02, 0.055), accent, 0.6)
	_add_box(_root, Vector3(0, 0.155, 0), Vector3(0.055, 0.02, 0.14), accent, 0.6)


func _build_canister(accent: Color) -> void:
	# Pressurized cyan suit-repair canister with dark collar, valve cap and glowing level strip.
	_add_cyl(_root, Vector3(0, 0.04, 0), 0.14, 0.4, Color("#1f3542"))
	_add_cyl(_root, Vector3(0, 0.04, 0), 0.146, 0.22, accent, 0.65)
	_add_cyl(_root, Vector3(0, 0.26, 0), 0.11, 0.06, Color("#263444"))
	_add_cyl(_root, Vector3(0, 0.32, 0), 0.05, 0.08, Color("#d4dde0"))
	_add_box(_root, Vector3(0, 0.35, 0), Vector3(0.16, 0.03, 0.04), accent, 0.5)


func _build_supply_case(accent: Color) -> void:
	# Open field supply case with angled lid and visible ammo + med + canister inside.
	_add_box(_root, Vector3(0, -0.02, 0), Vector3(0.62, 0.24, 0.42), Color("#2b3a36"))
	_add_box(_root, Vector3(0, 0.09, 0), Vector3(0.64, 0.05, 0.44), accent, 0.4)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.1, -0.21)
	lid.rotation_degrees.x = -62.0
	_root.add_child(lid)
	_add_box(lid, Vector3(0, 0, 0.2), Vector3(0.62, 0.05, 0.42), Color("#364a42"))
	# Miniature contents peeking out of the open case.
	for x in [-0.19, -0.11]:
		_add_cyl(_root, Vector3(x, 0.17, 0.04), 0.03, 0.15, Color("#f6cf64"), 0.45)
	_add_box(_root, Vector3(0.02, 0.16, 0.02), Vector3(0.16, 0.14, 0.12), Color("#eff2ea"), 0.2)
	_add_box(_root, Vector3(0.02, 0.16, 0.085), Vector3(0.09, 0.03, 0.02), Color("#ff6e91"), 0.7)
	_add_box(_root, Vector3(0.02, 0.16, 0.085), Vector3(0.03, 0.09, 0.02), Color("#ff6e91"), 0.7)
	_add_cyl(_root, Vector3(0.2, 0.19, 0.02), 0.065, 0.22, Color("#66dfda"), 0.6)


static func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "%d_%d" % [color.to_rgba32(), int(round(glow * 100.0))]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mat_cache[key] = m
	return m


func _add_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)


func _add_cyl(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, glow := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)


func _add_cone(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, glow := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)


func _process(delta: float) -> void:
	_age += delta
	_root.position.y = 0.36 + sin(_age * 3.0) * 0.07
	_root.rotation.y += delta * 1.4
