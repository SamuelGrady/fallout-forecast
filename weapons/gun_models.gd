class_name GunModels
## Custom low-poly gun models, built from boxes and cylinders in code so they
## read as real firearms (not sci-fi blasters) and carry their own sights.
##
## Units are meters at viewmodel scale (about 60% of real size). Forward is -Z,
## up is +Y. Every model sets two metas:
## - "muzzle": where tracers and flashes start.
## - "sight": the point that sits dead center on screen while aiming
##   (Vector3.INF when the gun has no sight).
## Optional named children the WeaponHolder animates: "Pump" (shotgun forend),
## "Barrel" (flare gun break action).

const GUNMETAL := Color("#2b3038")
const POLYMER := Color("#1c1f25")
const STEEL := Color("#5d6670")
const WOOD := Color("#6e4a2c")
const WOOD_DARK := Color("#4f3420")
const BRASS := Color("#d9b45a")
const SAFETY_ORANGE := Color("#ff7a2e")
const HAZARD_YELLOW := Color("#f2c53d")
const TOXIC_GREEN := Color("#9be04a")
const NEON_PINK := Color("#ff4fa3")
const NEON_TEAL := Color("#4fe6d8")

static var _materials := {}


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Gun_" + id
	root.set_meta("sight", Vector3.INF)
	match id:
		"rifle":
			_rifle(root)
		"shotgun":
			_shotgun(root)
		"flare":
			_flare_gun(root)
		"dome":
			_dome_grenade(root)
		"bug_bomb":
			_bug_bomb(root)
		"frag":
			_frag(root)
		"revolver":
			_revolver(root)
		"service_revolver":
			_revolver(root, true)
		"nailgun":
			_nailgun(root)
		"boombox":
			_boombox(root)
		_:
			push_warning("Unknown gun model " + id)
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


# ------------------------------------------------------------------ guns
## Compact carbine with a top rail and a reflex red-dot sight.
static func _rifle(root: Node3D) -> void:
	# Receiver group.
	_box(root, Vector3(0.046, 0.05, 0.2), Vector3(0, 0, -0.02), GUNMETAL, 0.55)
	_box(root, Vector3(0.04, 0.036, 0.12), Vector3(0, -0.042, 0.0), GUNMETAL, 0.55)
	_box(root, Vector3(0.03, 0.008, 0.31), Vector3(0, 0.029, -0.07), POLYMER)
	for i in 9:
		_box(root, Vector3(0.034, 0.004, 0.012), Vector3(0, 0.035, 0.07 - i * 0.032), STEEL, 0.6)
	_box(root, Vector3(0.012, 0.012, 0.03), Vector3(0.026, 0.01, 0.03), STEEL, 0.7)  # charging handle
	_box(root, Vector3(0.006, 0.02, 0.05), Vector3(0.024, -0.005, -0.04), POLYMER)  # ejection cover
	# Handguard with vent slots.
	_box(root, Vector3(0.052, 0.05, 0.17), Vector3(0, 0, -0.205), POLYMER)
	for i in 4:
		_box(root, Vector3(0.054, 0.012, 0.022), Vector3(0, 0.0, -0.15 - i * 0.04), GUNMETAL, 0.4)
	# Barrel, gas block, flash hider.
	_cylinder(root, 0.008, 0.13, Vector3(0, 0.0, -0.355), STEEL, 0.75)
	_box(root, Vector3(0.022, 0.03, 0.02), Vector3(0, 0.006, -0.305), GUNMETAL, 0.6)
	_cylinder(root, 0.012, 0.04, Vector3(0, 0.0, -0.43), POLYMER, 0.5)
	# Magazine, grip, trigger guard.
	_box(root, Vector3(0.03, 0.095, 0.045), Vector3(0, -0.1, -0.035), POLYMER, 0.0, Vector3(12, 0, 0)).name = "Magazine"
	_box(root, Vector3(0.03, 0.07, 0.034), Vector3(0, -0.085, 0.058), POLYMER, 0.0, Vector3(-22, 0, 0))
	_box(root, Vector3(0.008, 0.006, 0.05), Vector3(0, -0.068, 0.025), GUNMETAL, 0.6)
	# Stock tube and adjustable stock.
	_cylinder(root, 0.013, 0.11, Vector3(0, -0.006, 0.135), GUNMETAL, 0.5)
	_box(root, Vector3(0.036, 0.06, 0.09), Vector3(0, -0.02, 0.2), POLYMER)
	_box(root, Vector3(0.04, 0.075, 0.012), Vector3(0, -0.022, 0.248), Color("#121418"))
	# Reflex sight: low-profile mount, open wide hood, ultra-clear lens, crisp dot.
	_box(root, Vector3(0.03, 0.008, 0.044), Vector3(0, 0.037, -0.005), GUNMETAL, 0.6)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.003, 0.036, 0.022), Vector3(side * 0.021, 0.060, -0.008), GUNMETAL, 0.6)
	_box(root, Vector3(0.045, 0.0035, 0.022), Vector3(0, 0.079, -0.008), GUNMETAL, 0.6)
	_box(root, Vector3(0.009, 0.009, 0.009), Vector3(0.025, 0.047, 0.002), GUNMETAL, 0.6)  # brightness knob
	var glass := MeshInstance3D.new()
	var lens := QuadMesh.new()
	lens.size = Vector2(0.039, 0.036)
	glass.mesh = lens
	glass.position = Vector3(0, 0.060, -0.015)
	glass.material_override = _glass()
	root.add_child(glass)
	var dot_at := Vector3(0, 0.060, -0.016)
	_dot(root, dot_at, Color(1.0, 0.14, 0.12), 0.0013)
	root.set_meta("sight", dot_at)
	root.set_meta("muzzle", Vector3(0, 0.0, -0.455))


## Pump shotgun: wood furniture, vent rib, brass bead and a rear notch.
static func _shotgun(root: Node3D) -> void:
	_box(root, Vector3(0.046, 0.062, 0.16), Vector3(0, 0, 0), GUNMETAL, 0.55)
	_box(root, Vector3(0.006, 0.022, 0.06), Vector3(0.024, 0.006, -0.01), Color("#0d0f12"))  # ejection port
	_cylinder(root, 0.011, 0.38, Vector3(0, 0.014, -0.27), STEEL, 0.75)
	_cylinder(root, 0.0095, 0.3, Vector3(0, -0.017, -0.23), GUNMETAL, 0.6)
	_cylinder(root, 0.012, 0.012, Vector3(0, -0.017, -0.385), STEEL, 0.75)  # mag cap
	_box(root, Vector3(0.012, 0.006, 0.37), Vector3(0, 0.028, -0.265), GUNMETAL, 0.6)  # vent rib
	var pump := Node3D.new()
	pump.name = "Pump"
	root.add_child(pump)
	_box(pump, Vector3(0.052, 0.042, 0.11), Vector3(0, -0.016, -0.2), WOOD)
	for i in 5:
		_box(pump, Vector3(0.054, 0.006, 0.008), Vector3(0, -0.016, -0.16 - i * 0.02), WOOD_DARK)
	# Stock with a wrist, trigger guard.
	_box(root, Vector3(0.036, 0.05, 0.08), Vector3(0, -0.026, 0.11), WOOD, 0.0, Vector3(-14, 0, 0))
	_box(root, Vector3(0.042, 0.07, 0.13), Vector3(0, -0.05, 0.21), WOOD, 0.0, Vector3(-6, 0, 0))
	_box(root, Vector3(0.044, 0.078, 0.014), Vector3(0, -0.056, 0.28), Color("#16120e"), 0.0, Vector3(-6, 0, 0))
	_box(root, Vector3(0.008, 0.006, 0.05), Vector3(0, -0.04, 0.03), GUNMETAL, 0.6)
	# Rear notch: two short posts on the receiver; front brass bead.
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.006, 0.01, 0.008), Vector3(side * 0.007, 0.036, 0.06), GUNMETAL, 0.6)
	var bead_at := Vector3(0, 0.034, -0.445)
	_dot(root, bead_at, Color(1.0, 0.86, 0.45), 0.0032)
	root.set_meta("sight", bead_at)
	root.set_meta("muzzle", Vector3(0, 0.014, -0.465))


## Break-action flare pistol: chunky orange frame, wide bore.
static func _flare_gun(root: Node3D) -> void:
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	barrel.position = Vector3(0, 0.0, -0.02)  # hinge
	root.add_child(barrel)
	_cylinder(barrel, 0.02, 0.17, Vector3(0, 0.022, -0.085), SAFETY_ORANGE, 0.0)
	_cylinder(barrel, 0.014, 0.172, Vector3(0, 0.022, -0.085), Color("#140c08"))  # bore
	_cylinder(barrel, 0.023, 0.02, Vector3(0, 0.022, -0.16), Color("#d9581c"))
	_box(root, Vector3(0.034, 0.05, 0.075), Vector3(0, 0.012, 0.025), SAFETY_ORANGE)
	_box(root, Vector3(0.032, 0.085, 0.04), Vector3(0, -0.05, 0.055), Color("#2a1d18"), 0.0, Vector3(-16, 0, 0))
	for i in 4:
		_box(root, Vector3(0.034, 0.005, 0.03), Vector3(0, -0.03 - i * 0.016, 0.05 + i * 0.004), Color("#3d2a22"))
	_box(root, Vector3(0.008, 0.02, 0.012), Vector3(0, 0.045, 0.06), STEEL, 0.7)  # hammer
	_box(root, Vector3(0.008, 0.006, 0.04), Vector3(0, -0.02, 0.0), STEEL, 0.6)  # trigger guard
	root.set_meta("muzzle", Vector3(0, 0.022, -0.18))


## Shield Dome: a squat emitter canister with a glowing projector ring.
static func _dome_grenade(root: Node3D) -> void:
	_cylinder(root, 0.034, 0.075, Vector3(0, 0, 0), Color("#d8dee4"), 0.5, Vector3.ZERO)
	var ring := _cylinder(root, 0.036, 0.014, Vector3(0, 0.012, 0), NEON_TEAL, 0.0, Vector3.ZERO)
	ring.material_override = _glow(NEON_TEAL, 2.4)
	_cylinder(root, 0.028, 0.016, Vector3(0, 0.045, 0), Color("#2b3038"), 0.6, Vector3.ZERO)
	var lens := _cylinder(root, 0.016, 0.01, Vector3(0, 0.056, 0), NEON_TEAL, 0.0, Vector3.ZERO)
	lens.material_override = _glow(NEON_TEAL, 3.0)
	for i in 3:
		var angle := TAU * i / 3.0
		_box(root, Vector3(0.012, 0.03, 0.012), Vector3(cos(angle) * 0.03, -0.045, sin(angle) * 0.03), Color("#2b3038"), 0.6)  # feet
	_box(root, Vector3(0.008, 0.02, 0.03), Vector3(0.036, 0.02, 0), Color("#e23b2e"))  # arming switch
	root.set_meta("muzzle", Vector3(0, 0.06, 0))


## Frag grenade: segmented olive body, fuse head, spoon and pull ring.
static func _frag(root: Node3D) -> void:
	var olive := Color("#4b5a32")
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.032
	sphere.height = 0.075
	sphere.radial_segments = 10
	sphere.rings = 6
	body.mesh = sphere
	body.material_override = _material(olive, 0.15)
	root.add_child(body)
	# Pineapple segmentation: raised bands both ways.
	for i in 3:
		_cylinder(root, 0.0335, 0.006, Vector3(0, -0.02 + i * 0.02, 0), olive.darkened(0.3), 0.1, Vector3.ZERO)
	for i in 4:
		_box(root, Vector3(0.006, 0.066, 0.068), Vector3.ZERO, olive.darkened(0.3), 0.1, Vector3(0, i * 45.0, 0))
	_cylinder(root, 0.013, 0.022, Vector3(0, 0.045, 0), STEEL, 0.7, Vector3.ZERO)  # fuse head
	_box(root, Vector3(0.012, 0.07, 0.006), Vector3(0, 0.02, -0.036), STEEL, 0.7, Vector3(-8, 0, 0))  # spoon
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.rings = 24
	torus.ring_segments = 6
	torus.inner_radius = 0.008
	torus.outer_radius = 0.012
	ring.mesh = torus
	ring.position = Vector3(0.018, 0.05, 0)
	ring.rotation_degrees = Vector3(0, 0, 90)
	ring.material_override = _material(STEEL, 0.7)
	root.add_child(ring)
	root.set_meta("muzzle", Vector3(0, 0.06, 0))


## Bug Bomb: a pressurized insecticide canister with a pull ring.
static func _bug_bomb(root: Node3D) -> void:
	_cylinder(root, 0.032, 0.09, Vector3(0, 0, 0), HAZARD_YELLOW, 0.2, Vector3.ZERO)
	_cylinder(root, 0.0325, 0.018, Vector3(0, 0.015, 0), Color("#1d1f22"), 0.0, Vector3.ZERO)  # stripe
	_cylinder(root, 0.024, 0.02, Vector3(0, 0.055, 0), STEEL, 0.7, Vector3.ZERO)
	_cylinder(root, 0.008, 0.02, Vector3(0, 0.072, 0), Color("#e23b2e"), 0.0, Vector3.ZERO)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.rings = 24
	torus.ring_segments = 6
	torus.inner_radius = 0.009
	torus.outer_radius = 0.013
	ring.mesh = torus
	ring.position = Vector3(0.018, 0.075, 0)
	ring.rotation_degrees = Vector3(0, 0, 90)
	ring.material_override = _material(STEEL, 0.7)
	root.add_child(ring)
	_dot(root, Vector3(0, 0.02, -0.033), TOXIC_GREEN, 0.006)  # skull-ish hazard light
	root.set_meta("muzzle", Vector3(0, 0.08, 0))


## Lucky Penny: a gold snub revolver with a copper cylinder.
static func _revolver(root: Node3D, service := false) -> void:
	var frame := STEEL if service else BRASS
	var cylinder := Color("#596875") if service else Color("#b4643c")
	_cylinder(root, 0.011, 0.11, Vector3(0, 0.02, -0.08), frame, 0.8)
	_box(root, Vector3(0.012, 0.01, 0.1), Vector3(0, 0.033, -0.075), frame, 0.8)  # top strap
	_cylinder(root, 0.024, 0.045, Vector3(0, 0.012, -0.01), cylinder, 0.8).name = "Cylinder"
	_box(root, Vector3(0.028, 0.045, 0.06), Vector3(0, 0.0, 0.03), frame, 0.8)
	_box(root, Vector3(0.03, 0.08, 0.036), Vector3(0, -0.05, 0.06), Color("#3a2a1c"), 0.0, Vector3(-18, 0, 0))
	_dot(root, Vector3(0, 0.044, -0.12), Color(1.0, 0.86, 0.45), 0.0025)
	root.set_meta("sight", Vector3(0, 0.044, -0.12))
	root.set_meta("muzzle", Vector3(0, 0.02, -0.14))


## Leaky Nailgun: a yellow power tool with a dripping green canister.
static func _nailgun(root: Node3D) -> void:
	_box(root, Vector3(0.05, 0.07, 0.2), Vector3(0, 0.01, -0.04), HAZARD_YELLOW)
	_box(root, Vector3(0.03, 0.05, 0.05), Vector3(0, -0.005, -0.17), Color("#22262b"))
	_box(root, Vector3(0.012, 0.012, 0.06), Vector3(0, -0.01, -0.22), STEEL, 0.7)
	_box(root, Vector3(0.034, 0.09, 0.04), Vector3(0, -0.065, 0.05), Color("#22262b"), 0.0, Vector3(-14, 0, 0))
	_box(root, Vector3(0.02, 0.1, 0.03), Vector3(0, -0.06, -0.12), STEEL, 0.6).name = "Magazine"
	var tank := _cylinder(root, 0.022, 0.08, Vector3(0.04, 0.03, 0.02), TOXIC_GREEN, 0.0)
	tank.material_override = _glow(TOXIC_GREEN, 0.8)
	root.set_meta("muzzle", Vector3(0, -0.01, -0.25))


## Boombox Launcher: an 80s boombox with a launch tube bolted on.
static func _boombox(root: Node3D) -> void:
	_box(root, Vector3(0.18, 0.1, 0.05), Vector3(0, 0, 0.02), Color("#2b2d36"))
	for side in [-1.0, 1.0]:
		_cylinder(root, 0.03, 0.006, Vector3(side * 0.055, 0, -0.008), Color("#111215"), 0.0, Vector3(90, 0, 0))
		_cylinder(root, 0.012, 0.008, Vector3(side * 0.055, 0, -0.01), STEEL, 0.6, Vector3(90, 0, 0))
	_box(root, Vector3(0.05, 0.022, 0.004), Vector3(0, 0.02, -0.006), Color("#0d1012"))
	var display := _box(root, Vector3(0.04, 0.012, 0.004), Vector3(0, 0.02, -0.008), NEON_TEAL)
	display.material_override = _glow(NEON_TEAL, 1.6)
	_box(root, Vector3(0.14, 0.012, 0.012), Vector3(0, 0.065, 0.02), STEEL, 0.7)  # handle
	_cylinder(root, 0.026, 0.24, Vector3(0, 0.085, -0.08), Color("#3b3f4a"), 0.4)
	var stripe := _cylinder(root, 0.027, 0.02, Vector3(0, 0.085, -0.19), NEON_PINK, 0.0)
	stripe.material_override = _glow(NEON_PINK, 1.4)
	root.set_meta("muzzle", Vector3(0, 0.085, -0.2))


## What a thrown or launched round looks like in flight.
static func projectile(id: String) -> Node3D:
	if id == "bug_bomb" or id == "dome" or id == "frag":
		var canister := build(id)
		canister.scale = Vector3.ONE * 1.6
		return canister
	var root := Node3D.new()
	match id:
		"flare":
			var shell := _cylinder(root, 0.02, 0.07, Vector3.ZERO, SAFETY_ORANGE, 0.0)
			shell.material_override = _glow(Color(1.0, 0.3, 0.2), 3.0)
		"boombox":
			_cylinder(root, 0.03, 0.16, Vector3.ZERO, Color("#3b3f4a"), 0.4)
			var tip := _cylinder(root, 0.031, 0.03, Vector3(0, 0, -0.08), NEON_PINK, 0.0)
			tip.material_override = _glow(NEON_PINK, 2.0)
		_:
			_cylinder(root, 0.01, 0.04, Vector3.ZERO, BRASS, 0.8)
	return root


# ------------------------------------------------------------------ parts
static func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, metal := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.rotation_degrees = rot
	mesh.material_override = _material(color, metal)
	parent.add_child(mesh)
	return mesh


## Cylinders lie along -Z by default (barrels); pass rot = Vector3.ZERO to
## stand one upright.
static func _cylinder(parent: Node3D, radius: float, length: float, at: Vector3, color: Color, metal := 0.0, rot := Vector3(90, 0, 0)) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = 10
	cylinder.rings = 1
	mesh.mesh = cylinder
	mesh.position = at
	mesh.rotation_degrees = rot
	mesh.material_override = _material(color, metal)
	parent.add_child(mesh)
	return mesh


## A small glowing sphere drawn over everything: the red dot or a bead.
static func _dot(parent: Node3D, at: Vector3, color: Color, radius: float) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 20
	material.disable_fog = true
	mesh.material_override = material
	parent.add_child(mesh)


static func _material(color: Color, metal: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), metal]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metal
		material.roughness = 0.35 if metal > 0.0 else 0.8
		_materials[key] = material
	return _materials[key]


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(), energy]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
		_materials[key] = material
	return _materials[key]


static func _glass() -> StandardMaterial3D:
	if not _materials.has("glass"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.65, 0.9, 1.0, 0.04)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_fog = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials["glass"] = material
	return _materials["glass"]
