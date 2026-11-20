class_name ItemModels
## Utility equipment in GunModels' view space (metres, +Y up, -Z forward).
## Animate these direct children relative to their initial transform:
## nail_driver: Magazine; hunting_rifle: Barrel, Bolt; pressure_washer: Wand;
## rock_salt: Barrel; battery_zapper: Clamps; flare_launcher: Barrel;
## harpoon: Spool (X axle), Harpoon; leaf_blower: Fan (X axle);
## disruptor: Dish; sandbag: Sack; umbrella: Canopy; lightning_rod: Spike;
## bleach_bomb: Cap; med_tin: Lid; suit_patch: Patch; bait_radio: Antenna.
## projectile("harpoon") has a CableStart marker. Deployed variants use a
## ground-level origin; all projectile calls return a Node3D, empty for hitscan.
## crate_station: Door (left Y hinge), Beacon (emissive mesh).
## airdrop: Lid (rear X hinge), Parachute (includes suspension lines).

const G := preload("res://weapons/gun_models.gd")
const LETTERS := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const CREAM := Color("#f2e1bd")
const ENAMEL := Color("#268782")
const TOMATO := Color("#cf493b")
const CANVAS := Color("#b08a55")
const INDIGO := Color("#474263")
const COPPER := Color("#bd7453")
const UPRIGHT := Vector3.ZERO
const AXLE := Vector3(0, 0, 90)
const MUZZLES := {
	"nail_driver": Vector3(0, -0.018, -0.198),
	"hunting_rifle": Vector3(0, 0.014, -0.485),
	"pressure_washer": Vector3(0, 0.012, -0.407),
	"rock_salt": Vector3(0, 0.02, -0.34),
	"battery_zapper": Vector3(0, 0.038, -0.192),
	"flare_launcher": Vector3(0, 0.028, -0.235),
	"harpoon": Vector3(0, 0.038, -0.395),
	"leaf_blower": Vector3(0, -0.012, -0.38),
	"disruptor": Vector3(0, 0.092, -0.255),
	"sandbag": Vector3(0, 0.05, -0.09),
	"umbrella": Vector3(0, 0.07, -0.216),
	"lightning_rod": Vector3(0, 0.07, -0.24),
	"bleach_bomb": Vector3(0, 0.091, -0.025),
	"med_tin": Vector3(0, 0.045, -0.055),
	"suit_patch": Vector3(0, 0.028, -0.065),
	"bait_radio": Vector3(0, 0.065, -0.045),
}
static var _pickup_meshes: Dictionary[String, Mesh] = {}


static func has(id: String) -> bool:
	return MUZZLES.has(id)


static func muzzle(id: String) -> Vector3:
	return MUZZLES.get(id, Vector3.ZERO)


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Gun_" + id
	root.set_meta("muzzle", muzzle(id))
	root.set_meta("sight", Vector3.INF)
	_model(root, id, true)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func pickup(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Pickup_" + id
	if not has(id):
		return root
	if not _pickup_meshes.has(id):
		_model(root, id, false)
		# Bake the stationary pickup once. Preserve local pivot offsets off-tree.
		for pivot in root.get_children():
			if pivot is MeshInstance3D:
				continue
			for part in pivot.get_children():
				var mesh := part as MeshInstance3D
				var baked: Transform3D = (pivot as Node3D).transform * mesh.transform
				mesh.reparent(root, false)
				mesh.transform = baked
			pivot.free()
		var merged := MeshMerge.merge_children(root)
		_pickup_meshes[id] = merged.mesh
	else:
		var instance := MeshInstance3D.new()
		instance.mesh = _pickup_meshes[id]
		root.add_child(instance)
	# Keep pocket supplies legible at the same pickup distance as long guns.
	var pocket_item := id in ["bleach_bomb", "med_tin", "suit_patch", "bait_radio"]
	root.scale = Vector3.ONE * (2.5 if pocket_item else 1.65)
	return root


static func _model(root: Node3D, id: String, detail: bool) -> void:
	match id:
		"nail_driver": _nail_driver(root, detail)
		"hunting_rifle": _hunting_rifle(root, detail)
		"pressure_washer": _pressure_washer(root, detail)
		"rock_salt": _rock_salt(root, detail)
		"battery_zapper": _battery_zapper(root, detail)
		"flare_launcher": _flare_launcher(root, detail)
		"harpoon": _harpoon(root, detail)
		"leaf_blower": _leaf_blower(root, detail)
		"disruptor": _disruptor(root, detail)
		"sandbag": _sandbag(root, detail)
		"umbrella": _umbrella(root, detail)
		"lightning_rod": _lightning_rod(root, detail)
		"bleach_bomb": _bleach_bomb(root, detail)
		"med_tin": _med_tin(root, detail)
		"suit_patch": _suit_patch(root, detail)
		"bait_radio": _bait_radio(root, detail)


static func _pivot(parent: Node3D, label: String, at := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = at
	parent.add_child(node)
	return node


## A faceted shell of revolution, also used for hollow scope bells and the dish.
## Profile points are (radius, height) in order around the section. Consecutive
## points form a strip; repeat the first point to close a hollow cross-section.
static func _turned(parent: Node3D, profile: PackedVector2Array, sides: int, at: Vector3,
		color: Color, rot := Vector3.ZERO, alternate := Color.TRANSPARENT) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in sides:
		var a := TAU * i / sides
		var b := TAU * (i + 1) / sides
		var d := Vector3(cos(a), 0, sin(a))
		var e := Vector3(cos(b), 0, sin(b))
		if alternate.a > 0:
			st.set_color(color if i % 2 == 0 else alternate)
		for j in range(profile.size() - 1):
			var p := profile[j]
			var q := profile[j + 1]
			var u := d * p.x + Vector3.UP * p.y
			var v := e * p.x + Vector3.UP * p.y
			var w := d * q.x + Vector3.UP * q.y
			var x := e * q.x + Vector3.UP * q.y
			if p.x > 0:
				for point: Vector3 in [u, v, w]:
					st.add_vertex(point)
			if q.x > 0:
				for point: Vector3 in [v, x, w]:
					st.add_vertex(point)
	st.generate_normals()
	st.index()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.position = at
	instance.rotation_degrees = rot
	instance.material_override = MeshMerge.lit_material() if alternate.a > 0 else G._material(color, 0.25)
	parent.add_child(instance)
	return instance


## Stock or casing defined by an extruded side outline.
## Each point is (Z, Y). The two flat ends share the same silhouette.
static func _profile(parent: Node3D, width: float, outline: PackedVector2Array, color: Color) -> MeshInstance3D:
	if Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for p in outline:
		left.append(Vector3(-width * 0.5, p.y, p.x))
		right.append(Vector3(width * 0.5, p.y, p.x))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var faces := Geometry2D.triangulate_polygon(outline)
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		for point: Vector3 in [right[a], right[b], right[c], left[a], left[c], left[b]]:
			st.add_vertex(point)
	for i in outline.size():
		var j := (i + 1) % outline.size()
		for point: Vector3 in [left[i], right[j], right[i], left[i], left[j], right[j]]:
			st.add_vertex(point)
	st.generate_normals()
	st.index()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	parent.add_child(instance)
	instance.material_override = G._material(color, 0.0)
	return instance


## Wide roofing nailer with a slung coil drum and stamped nose shoe.
static func _nail_driver(root: Node3D, detail: bool) -> void:
	var magazine := _pivot(root, "Magazine", Vector3(0, -0.048, -0.066))
	_profile(root, 0.065, PackedVector2Array([
		Vector2(-0.132, -0.018), Vector2(-0.119, 0.029), Vector2(-0.058, 0.058),
		Vector2(-0.023, 0.051), Vector2(-0.002, 0.016), Vector2(-0.013, -0.018)]), G.SAFETY_ORANGE)
	G._cylinder(root, 0.038, 0.016, Vector3(0, 0.043, -0.054), G.GUNMETAL, 0.3, UPRIGHT)
	G._box(root, Vector3(0.032, 0.085, 0.04), Vector3(0, -0.035, 0.018), G.POLYMER, 0, Vector3(-19, 0, 0))
	G._box(root, Vector3(0.042, 0.035, 0.057), Vector3(0, 0.002, -0.003), TOMATO, 0, Vector3(-12, 0, 0))
	G._box(root, Vector3(0.026, 0.023, 0.056), Vector3(0, -0.017, -0.142), G.STEEL, 0.6)
	G._box(root, Vector3(0.013, 0.012, 0.032), Vector3(0, -0.018, -0.181), G.POLYMER)
	G._cylinder(magazine, 0.049, 0.047, Vector3.ZERO, G.GUNMETAL, 0, UPRIGHT)
	G._cylinder(magazine, 0.051, 0.009, Vector3(0, -0.02, 0), G.SAFETY_ORANGE, 0, UPRIGHT)
	if not detail:
		return
	G._cylinder(magazine, 0.048, 0.008, Vector3(0, 0.022, 0), G.STEEL, 0.45, UPRIGHT)
	G._cylinder(magazine, 0.014, 0.009, Vector3(0, 0.029, 0), G.BRASS, 0.4, UPRIGHT)
	G._box(root, Vector3(0.055, 0.013, 0.057), Vector3(0, 0.052, -0.056), G.SAFETY_ORANGE)
	G._box(root, Vector3(0.034, 0.017, 0.049), Vector3(0, -0.074, 0.03), G.GUNMETAL)
	G._box(root, Vector3(0.026, 0.014, 0.059), Vector3(0, -0.06, -0.018), G.STEEL, 0.5, Vector3(-12, 0, 0))
	G._box(root, Vector3(0.069, 0.011, 0.06), Vector3(0, 0.008, -0.069), CREAM)
	for i in 3:
		G._box(root, Vector3(0.068, 0.012, 0.007), Vector3(0, 0.027, -0.045 - 0.014 * i), G.POLYMER)
	G._box(root, Vector3(0.024, 0.008, 0.026), Vector3(0, -0.029, -0.181), G.STEEL, 0.6)


## Walnut comb and slim bolt action under an open-through four-power scope.
static func _hunting_rifle(root: Node3D, detail: bool) -> void:
	var barrel := _pivot(root, "Barrel", Vector3(0, 0.014, -0.077))
	var bolt := _pivot(root, "Bolt", Vector3(0, 0.014, 0.028))
	_profile(root, 0.037, PackedVector2Array([
		Vector2(-0.219, -0.007), Vector2(-0.206, 0.007), Vector2(0.044, 0.008),
		Vector2(0.075, -0.011), Vector2(0.067, -0.032), Vector2(-0.177, -0.029)]), G.WOOD)
	_profile(root, 0.042, PackedVector2Array([
		Vector2(0.047, -0.023), Vector2(0.104, -0.012), Vector2(0.214, -0.009),
		Vector2(0.22, -0.076), Vector2(0.109, -0.062), Vector2(0.067, -0.042)]), G.WOOD)
	G._box(root, Vector3(0.044, 0.068, 0.012), Vector3(0, -0.042, 0.219), G.WOOD_DARK, 0, Vector3(-4, 0, 0))
	G._box(root, Vector3(0.045, 0.056, 0.023), Vector3(0, -0.039, 0.147), G.SAFETY_ORANGE, 0, Vector3(-8, 0, 0))
	G._cylinder(barrel, 0.01, 0.402, Vector3(0, 0, -0.201), G.STEEL, 0.6)
	G._cylinder(root, 0.018, 0.13, Vector3(0, 0.011, -0.013), G.GUNMETAL, 0.5)
	_turned(root, PackedVector2Array([
		Vector2(0.02, -0.07), Vector2(0.02, 0.07), Vector2(0.015, 0.07),
		Vector2(0.015, -0.07), Vector2(0.02, -0.07)]), 12, Vector3(0, 0.065, -0.033), G.GUNMETAL, Vector3(90, 0, 0))
	G._cylinder(bolt, 0.01, 0.042, Vector3.ZERO, G.STEEL, 0.6)
	for mount_z: float in [-0.067, 0.016]:
		G._box(root, Vector3(0.019, 0.034, 0.018), Vector3(0, 0.037, mount_z), G.GUNMETAL)
	if not detail:
		return
	G._cylinder(bolt, 0.005, 0.034, Vector3(0.024, -0.007, 0.003), G.STEEL, 0.7, Vector3(0, 0, 62))
	G._cylinder(bolt, 0.01, 0.016, Vector3(0.04, -0.015, 0.003), G.WOOD_DARK, 0, AXLE)
	G._box(root, Vector3(0.009, 0.008, 0.053), Vector3(0, -0.044, 0.022), G.GUNMETAL)
	G._box(root, Vector3(0.009, 0.021, 0.007), Vector3(0, -0.035, -0.004), G.GUNMETAL)
	G._box(root, Vector3(0.039, 0.008, 0.011), Vector3(0, -0.008, -0.193), G.WOOD_DARK)
	# The visible reticle and the holder's ADS anchor are in the same plane.
	_turned(root, PackedVector2Array([
		Vector2(0.018, -0.016), Vector2(0.026, -0.006), Vector2(0.026, 0.013),
		Vector2(0.023, 0.013), Vector2(0.015, -0.012), Vector2(0.018, -0.016)]), 12, Vector3(0, 0.065, -0.106), G.GUNMETAL, Vector3(-90, 0, 0))
	_turned(root, PackedVector2Array([
		Vector2(0.018, -0.01), Vector2(0.023, 0), Vector2(0.023, 0.013),
		Vector2(0.02, 0.013), Vector2(0.015, -0.008), Vector2(0.018, -0.01)]), 12, Vector3(0, 0.065, 0.044), G.POLYMER, Vector3(90, 0, 0))
	G._cylinder(root, 0.01, 0.013, Vector3(0, 0.087, -0.027), G.GUNMETAL, 0.45, UPRIGHT)
	G._box(root, Vector3(0.026, 0.001, 0.001), Vector3(0, 0.065, 0.044), G.STEEL)
	G._box(root, Vector3(0.001, 0.026, 0.001), Vector3(0, 0.065, 0.044), G.STEEL)
	root.set_meta("sight", Vector3(0, 0.065, 0.044))


## Portable wash gun with an enamel pump, ribbed coupling and brass lance.
static func _pressure_washer(root: Node3D, detail: bool) -> void:
	var wand := _pivot(root, "Wand", Vector3(0, 0.012, -0.103))
	_profile(root, 0.062, PackedVector2Array([
		Vector2(-0.135, -0.008), Vector2(-0.12, 0.032), Vector2(-0.067, 0.041),
		Vector2(0.018, 0.023), Vector2(0.035, -0.001), Vector2(0.016, -0.022),
		Vector2(-0.101, -0.025)]), ENAMEL)
	G._box(root, Vector3(0.036, 0.09, 0.043), Vector3(0, -0.047, 0.02), G.POLYMER, 0, Vector3(-20, 0, 0))
	G._cylinder(wand, 0.015, 0.066, Vector3(0, 0, -0.03), G.BRASS, 0.45)
	G._cylinder(wand, 0.007, 0.21, Vector3(0, 0, -0.166), G.STEEL, 0.6)
	_turned(wand, PackedVector2Array([
		Vector2(0.005, -0.022), Vector2(0.015, -0.003), Vector2(0.012, 0.015),
		Vector2(0, 0.015)]), 8, Vector3(0, 0, -0.281), G.SAFETY_ORANGE, Vector3(-90, 0, 0))
	G._box(root, Vector3(0.02, 0.023, 0.07), Vector3(0, -0.074, -0.01), ENAMEL, 0, Vector3(10, 0, 0))
	if not detail:
		return
	G._cylinder(wand, 0.019, 0.029, Vector3(0, 0, -0.01), G.POLYMER)
	for i in 4:
		G._cylinder(wand, 0.016, 0.004, Vector3(0, 0, -0.031 - 0.008 * i), G.GUNMETAL)
	G._cylinder(root, 0.025, 0.01, Vector3(-0.031, 0.007, -0.066), CREAM, 0, AXLE)
	G._cylinder(root, 0.003, 0.024, Vector3(-0.039, 0.011, -0.067), TOMATO, 0, Vector3(35, 0, 0))
	G._box(root, Vector3(0.065, 0.008, 0.069), Vector3(0, 0.005, -0.062), G.NEON_TEAL)
	G._box(root, Vector3(0.012, 0.038, 0.013), Vector3(0, -0.039, -0.051), G.GUNMETAL, 0, Vector3(20, 0, 0))
	G._cylinder(root, 0.012, 0.023, Vector3(0, -0.091, 0.033), G.BRASS, 0.45, UPRIGHT)


## Twin blued tubes, striped salt shells and a worn red butt pad.
static func _rock_salt(root: Node3D, detail: bool) -> void:
	var barrel := _pivot(root, "Barrel", Vector3(0, 0.02, -0.03))
	_profile(root, 0.045, PackedVector2Array([
		Vector2(-0.068, -0.024), Vector2(-0.066, 0.015), Vector2(0.039, 0.02),
		Vector2(0.065, -0.01), Vector2(0.04, -0.036), Vector2(-0.016, -0.037)]), G.GUNMETAL)
	_profile(root, 0.041, PackedVector2Array([
		Vector2(0.026, -0.016), Vector2(0.084, -0.014), Vector2(0.166, -0.026),
		Vector2(0.16, -0.078), Vector2(0.09, -0.062), Vector2(0.048, -0.042)]), G.WOOD)
	G._box(root, Vector3(0.043, 0.052, 0.012), Vector3(0, -0.052, 0.165), TOMATO, 0, Vector3(7, 0, 0))
	for side: float in [-0.016, 0.016]:
		G._cylinder(barrel, 0.015, 0.31, Vector3(side, 0, -0.155), G.GUNMETAL, 0.5)
	G._box(barrel, Vector3(0.06, 0.026, 0.125), Vector3(0, -0.02, -0.1), G.WOOD)
	for shell_z: float in [0.094, 0.12]:
		G._cylinder(root, 0.009, 0.04, Vector3(-0.025, -0.039, shell_z), TOMATO, 0, UPRIGHT)
	if not detail:
		return
	for side: float in [-0.016, 0.016]:
		G._cylinder(barrel, 0.0115, 0.002, Vector3(side, 0, -0.31), G.POLYMER)
	G._box(barrel, Vector3(0.007, 0.007, 0.29), Vector3(0, 0.013, -0.152), G.STEEL, 0.45)
	G._box(barrel, Vector3(0.005, 0.006, 0.005), Vector3(0, 0.019, -0.303), G.BRASS)
	for shell_z: float in [0.094, 0.12]:
		G._cylinder(root, 0.0095, 0.009, Vector3(-0.025, -0.02, shell_z), G.BRASS, 0.5, Vector3.ZERO)
	G._box(root, Vector3(0.048, 0.013, 0.062), Vector3(0, -0.036, 0.109), G.WOOD_DARK)
	G._box(root, Vector3(0.01, 0.007, 0.053), Vector3(0, -0.046, 0.025), G.GUNMETAL)
	root.set_meta("sight", Vector3(0, 0.039, -0.333))


## Rectangular garage battery; insulated leads arch out to copper teeth.
static func _battery_zapper(root: Node3D, detail: bool) -> void:
	var clamps := _pivot(root, "Clamps", Vector3(0, 0.037, -0.135))
	G._box(root, Vector3(0.118, 0.094, 0.13), Vector3(0, -0.009, -0.001), INDIGO)
	G._box(root, Vector3(0.124, 0.014, 0.138), Vector3(0, 0.041, -0.001), G.POLYMER)
	G._box(root, Vector3(0.12, 0.031, 0.09), Vector3(0, -0.009, 0.007), CREAM)
	# Cast lightning flash on the battery jacket, visible from either side.
	_profile(root, 0.123, PackedVector2Array([Vector2(-0.018, -0.019), Vector2(-0.002, -0.006),
		Vector2(-0.009, -0.006), Vector2(0.019, 0.004), Vector2(0.004, -0.01),
		Vector2(0.01, -0.01)]), TOMATO)
	for sign_x: float in [-1, 1]:
		var boot := TOMATO if sign_x < 0 else G.POLYMER
		var x := 0.039 * sign_x
		G._cylinder(root, 0.009, 0.024, Vector3(x, 0.057, -0.04), G.BRASS, 0.5, UPRIGHT)
		_lead(root, Vector3(x, 0.064, -0.04), Vector3(x, 0.079, -0.095), 0.006, boot)
		_lead(root, Vector3(x, 0.079, -0.095), Vector3(x, 0.04, -0.131), 0.006, boot)
		G._box(clamps, Vector3(0.021, 0.022, 0.057), Vector3(x, 0, 0), boot)
		for jaw: float in [-1, 1]:
			G._box(clamps, Vector3(0.015, 0.005, 0.035), Vector3(x, 0.001 + jaw * 0.006, -0.04), COPPER, 0.45, Vector3(jaw * 9, 0, 0))
	if not detail:
		return
	G._box(root, Vector3(0.068, 0.012, 0.015), Vector3(0, 0.074, 0.015), G.POLYMER)
	for x: float in [-0.03, 0.03]:
		G._box(root, Vector3(0.01, 0.03, 0.015), Vector3(x, 0.06, 0.015), G.POLYMER)
	G._box(root, Vector3(0.094, 0.013, 0.005), Vector3(0, 0.012, 0.066), G.HAZARD_YELLOW)
	G._box(root, Vector3(0.013, 0.006, 0.008), Vector3(-0.039, 0.049, 0.024), TOMATO)
	G._box(root, Vector3(0.005, 0.006, 0.016), Vector3(-0.039, 0.049, 0.024), TOMATO)


## Municipal signal pistol with a flared orange bell and break-action hinge.
static func _flare_launcher(root: Node3D, detail: bool) -> void:
	var barrel := _pivot(root, "Barrel", Vector3(0, 0.028, -0.019))
	_turned(barrel, PackedVector2Array([
		Vector2(0, 0), Vector2(0.032, 0), Vector2(0.032, 0.148),
		Vector2(0.041, 0.168), Vector2(0.041, 0.216), Vector2(0.03, 0.216),
		Vector2(0.027, 0.175), Vector2(0, 0.175)]), 10, Vector3.ZERO, G.SAFETY_ORANGE, Vector3(-90, 0, 0))
	_profile(root, 0.046, PackedVector2Array([
		Vector2(-0.095, -0.01), Vector2(-0.068, 0.024), Vector2(0.026, 0.019),
		Vector2(0.05, -0.004), Vector2(0.029, -0.023), Vector2(-0.055, -0.03)]), CREAM)
	G._box(root, Vector3(0.037, 0.095, 0.042), Vector3(0, -0.057, 0.036), G.POLYMER, 0, Vector3(-20, 0, 0))
	_turned(barrel, PackedVector2Array([
		Vector2(0.042, -0.007), Vector2(0.042, 0.007), Vector2(0.04, 0.007),
		Vector2(0.04, -0.007), Vector2(0.042, -0.007)]), 10, Vector3(0, 0, -0.201), CREAM, Vector3(90, 0, 0))
	if not detail:
		return
	G._cylinder(root, 0.012, 0.052, Vector3(0, 0.002, -0.063), G.BRASS, 0.45, AXLE)
	G._cylinder(barrel, 0.034, 0.012, Vector3(0, 0, -0.03), G.GUNMETAL)
	G._box(root, Vector3(0.011, 0.02, 0.016), Vector3(0, 0.023, 0.032), G.GUNMETAL, 0, Vector3(-20, 0, 0))
	G._box(root, Vector3(0.009, 0.008, 0.051), Vector3(0, -0.04, -0.003), G.GUNMETAL)
	G._box(root, Vector3(0.009, 0.023, 0.009), Vector3(0, -0.03, -0.028), G.GUNMETAL)
	for i in 3:
		G._box(root, Vector3(0.04, 0.006, 0.034), Vector3(0, -0.045 - 0.015 * i, 0.031 + 0.005 * i), G.STEEL, 0.15)
	G._box(barrel, Vector3(0.008, 0.009, 0.015), Vector3(0, 0.044, -0.193), G.POLYMER)


## Harbor salvage reel with a crosswise axle and a separate loaded spear.
static func _harpoon(root: Node3D, detail: bool) -> void:
	var spool := _pivot(root, "Spool", Vector3(-0.017, -0.026, -0.063))
	var spear := _pivot(root, "Harpoon", Vector3(0, 0.038, -0.17))
	_profile(root, 0.045, PackedVector2Array([
		Vector2(-0.275, -0.008), Vector2(-0.267, 0.015), Vector2(-0.023, 0.018),
		Vector2(0.055, 0.003), Vector2(0.058, -0.024), Vector2(-0.165, -0.026)]), ENAMEL)
	G._box(root, Vector3(0.032, 0.08, 0.037), Vector3(0, -0.049, 0.026), G.WOOD_DARK, 0, Vector3(-21, 0, 0))
	G._cylinder(spool, 0.044, 0.045, Vector3(-0.009, 0, 0), CANVAS, 0, AXLE)
	for x: float in [-0.035, 0.017]:
		G._cylinder(spool, 0.051, 0.009, Vector3(x, 0, 0), TOMATO, 0.25, AXLE)
	G._cylinder(spear, 0.006, 0.337, Vector3(0, 0, -0.004), G.STEEL, 0.5)
	_profile(spear, 0.01, PackedVector2Array([Vector2(-0.225, 0), Vector2(-0.165, 0.017), Vector2(-0.175, 0.002), Vector2(-0.157, -0.012)]), G.STEEL)
	G._box(root, Vector3(0.017, 0.022, 0.24), Vector3(0, 0.023, -0.138), G.GUNMETAL)
	if not detail:
		return
	G._box(root, Vector3(0.047, 0.015, 0.024), Vector3(0, 0.023, -0.244), G.BRASS)
	G._cylinder(spool, 0.017, 0.01, Vector3(-0.042, 0, 0), G.BRASS, 0.5, AXLE)
	G._box(spool, Vector3(0.008, 0.054, 0.008), Vector3(-0.05, 0.014, 0), G.POLYMER, 0, Vector3(22, 0, 0))
	G._cylinder(spool, 0.007, 0.02, Vector3(-0.058, 0.036, 0.009), G.WOOD, 0, AXLE)
	for i in 4:
		G._cylinder(spool, 0.045, 0.0025, Vector3(-0.028 + 0.01 * i, 0, 0), CREAM, 0, AXLE)
	G._box(root, Vector3(0.041, 0.055, 0.069), Vector3(0, -0.016, 0.099), G.WOOD, 0, Vector3(-10, 0, 0))
	G._box(root, Vector3(0.036, 0.026, 0.064), Vector3(0, -0.004, 0.053), ENAMEL)
	G._box(spear, Vector3(0.013, 0.012, 0.031), Vector3(0, 0, 0.145), G.SAFETY_ORANGE)


## Lawn-crew squirrel-cage blower with an open carry handle and flared intake.
static func _leaf_blower(root: Node3D, detail: bool) -> void:
	var fan := _pivot(root, "Fan", Vector3(-0.053, 0, -0.018))
	G._cylinder(root, 0.081, 0.095, Vector3(0, 0, -0.018), G.SAFETY_ORANGE, 0, AXLE)
	G._box(root, Vector3(0.082, 0.084, 0.082), Vector3(0, -0.006, 0.049), CREAM)
	_turned(root, PackedVector2Array([
		Vector2(0.035, 0), Vector2(0.039, 0.045), Vector2(0.035, 0.11),
		Vector2(0.023, 0.171), Vector2(0.021, 0.23), Vector2(0.032, 0.246),
		Vector2(0.032, 0.258), Vector2(0.024, 0.258), Vector2(0.021, 0.246),
		Vector2(0, 0.23)]), 10, Vector3(0, -0.012, -0.122), G.GUNMETAL, Vector3(-90, 0, 0))
	G._box(root, Vector3(0.072, 0.07, 0.074), Vector3(0, -0.01, -0.096), G.SAFETY_ORANGE)
	G._cylinder(fan, 0.061, 0.015, Vector3.ZERO, G.POLYMER, 0, AXLE)
	G._cylinder(fan, 0.018, 0.015, Vector3(-0.012, 0, 0), G.SAFETY_ORANGE, 0, AXLE)
	G._box(root, Vector3(0.027, 0.016, 0.104), Vector3(0, 0.103, 0.012), G.POLYMER)
	for z: float in [-0.034, 0.062]:
		G._box(root, Vector3(0.023, 0.058, 0.016), Vector3(0, 0.079, z), G.SAFETY_ORANGE, 0, Vector3(10, 0, 0))
	if not detail:
		return
	for i in 6:
		var theta := TAU * i / 6.0
		G._box(fan, Vector3(0.009, 0.034, 0.014), Vector3(-0.009, 0.032 * cos(theta), 0.032 * sin(theta)), G.STEEL, 0.3, Vector3(rad_to_deg(theta) + 25, 0, 0))
	G._cylinder(root, 0.04, 0.012, Vector3(0, -0.012, -0.156), G.POLYMER)
	for i in 4:
		G._box(root, Vector3(0.086, 0.006, 0.039), Vector3(0, -0.024 + 0.014 * i, 0.053), G.POLYMER)
	G._box(root, Vector3(0.02, 0.012, 0.021), Vector3(0, 0.113, 0.041), TOMATO)


## Civil-defense receiver. The parabolic reflector faces the storm; the hot
## cathodes, frequency scale and pointer sit on the operator's side.
static func _disruptor(root: Node3D, detail: bool) -> void:
	var dish := _pivot(root, "Dish", Vector3(0, 0.092, -0.157))
	G._box(root, Vector3(0.128, 0.088, 0.195), Vector3(0, -0.005, -0.006), INDIGO)
	G._cylinder(root, 0.034, 0.012, Vector3(-0.064, -0.005, 0.012), G.POLYMER, 0, AXLE)
	G._cylinder(root, 0.013, 0.006, Vector3(-0.071, -0.005, 0.012), COPPER, 0.35, AXLE)
	G._box(root, Vector3(0.131, 0.068, 0.036), Vector3(0, -0.004, 0.085), CREAM)
	G._box(root, Vector3(0.107, 0.015, 0.004), Vector3(0, 0.013, 0.105), G.POLYMER)
	G._box(root, Vector3(0.082, 0.006, 0.005), Vector3(0, 0.014, 0.108), G.NEON_TEAL).material_override = G._glow(G.NEON_TEAL, 0.7)
	G._box(root, Vector3(0.032, 0.056, 0.031), Vector3(0, 0.052, -0.106), G.GUNMETAL, 0, Vector3(25, 0, 0))
	_turned(dish, PackedVector2Array([
		Vector2(0, -0.026), Vector2(0.021, -0.024), Vector2(0.068, -0.005),
		Vector2(0.09, 0.02), Vector2(0.09, 0.026), Vector2(0.079, 0.019),
		Vector2(0.06, 0.003), Vector2(0.019, -0.017), Vector2(0, -0.015)]), 12, Vector3.ZERO, COPPER, Vector3(-90, 0, 0))
	G._cylinder(dish, 0.007, 0.106, Vector3(0, 0, -0.041), G.BRASS, 0.5)
	G._cylinder(dish, 0.013, 0.012, Vector3(0, 0, -0.092), G.NEON_TEAL)
	for x: float in [-0.039, 0, 0.039]:
		var tube := _turned(root, PackedVector2Array([Vector2(0, 0), Vector2(0.009, 0),
			Vector2(0.009, 0.006), Vector2(0.014, 0.013), Vector2(0.014, 0.029),
			Vector2(0.009, 0.035), Vector2(0.004, 0.042), Vector2(0, 0.042)]),
			8, Vector3(x, 0.044, -0.028), G.NEON_PINK)
		tube.material_override = G._glow(G.NEON_PINK, 0.85)
	if not detail:
		return
	for x: float in [-0.039, 0, 0.039]:
		G._cylinder(root, 0.017, 0.009, Vector3(x, 0.043, -0.028), G.GUNMETAL, 0.4, UPRIGHT)
		G._cylinder(root, 0.0145, 0.004, Vector3(x, 0.069, -0.028), COPPER, 0.4, UPRIGHT)
	for i in 6:
		G._box(root, Vector3(0.002, 0.004 + 0.003 * (i % 2), 0.003), Vector3(-0.037 + 0.015 * i, 0.018, 0.111), CREAM)
	for i in 3:
		G._box(root, Vector3(0.006, 0.005, 0.05), Vector3(-0.073, -0.015 + i * 0.01, 0.012), G.STEEL)
	# The twin cable guards frame the hot vacuum tubes from the operator's view.
	for x: float in [-0.058, 0.058]:
		_lead(root, Vector3(x, 0.039, 0.049), Vector3(x, 0.055, 0.035), 0.003, COPPER)
		_lead(root, Vector3(x, 0.055, 0.035), Vector3(x, 0.055, -0.068), 0.003, COPPER)
		_lead(root, Vector3(x, 0.055, -0.068), Vector3(x, 0.039, -0.081), 0.003, COPPER)
	G._box(root, Vector3(0.004, 0.016, 0.004), Vector3(0.015, 0.014, 0.112), G.SAFETY_ORANGE)
	for x: float in [-0.044, 0.044]:
		G._cylinder(root, 0.013, 0.016, Vector3(x, -0.018, 0.109), G.POLYMER)
	G._box(root, Vector3(0.04, 0.008, 0.006), Vector3(0, -0.016, 0.104), G.STEEL)
	G._box(root, Vector3(0.036, 0.055, 0.037), Vector3(0, -0.065, 0.04), G.GUNMETAL, 0, Vector3(-14, 0, 0))


## Cylindrical cable, rib or brace between two endpoints in parent space.
static func _lead(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var link := G._cylinder(parent, radius, a.distance_to(b), (a + b) * 0.5, color, 0, UPRIGHT)
	link.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


## A stuffed burlap sack has rolled ends, a stitched hem and faded mill bands.
static func _sandbag(root: Node3D, detail: bool) -> void:
	var sack := _pivot(root, "Sack")
	_burlap(sack)
	if not detail:
		return
	for i in 6:
		G._box(sack, Vector3(0.005, 0.002, 0.009), Vector3(0.126, 0.005, -0.034 + 0.013 * i), CREAM, 0, Vector3(0, -25, 0))
	G._box(sack, Vector3(0.068, 0.002, 0.026), Vector3(0, 0.034, 0), CANVAS)
	G._box(sack, Vector3(0.041, 0.002, 0.006), Vector3(0, 0.036, -0.005), G.WOOD_DARK)
	G._box(sack, Vector3(0.029, 0.002, 0.005), Vector3(0, 0.036, 0.005), G.WOOD_DARK)


static func _burlap(parent: Node3D) -> void:
	var bag := _turned(parent, PackedVector2Array([Vector2(0, -0.124), Vector2(0.016, -0.119),
		Vector2(0.054, -0.096), Vector2(0.064, -0.071), Vector2(0.064, 0.071),
		Vector2(0.054, 0.098), Vector2(0.016, 0.119), Vector2(0, 0.124)]), 8, Vector3.ZERO, CANVAS, AXLE)
	bag.scale = Vector3(0.54, 1, 1.03)
	bag.material_override = G._material(CANVAS, 0)
	for side: float in [-1, 1]:
		var band := _turned(parent, PackedVector2Array([Vector2(0.066, -0.006), Vector2(0.066, 0.006)]),
			8, Vector3(side * 0.061, 0, 0), G.WOOD_DARK, AXLE)
		band.scale = bag.scale
		band.material_override = G._material(G.WOOD_DARK, 0)
		G._box(parent, Vector3(0.023, 0.008, 0.088), Vector3(side * 0.122, 0, 0), CANVAS, 0, Vector3(0, side * 4, 0))


## Folded triangular panels around a telescoping pole and weighted shoe.
static func _umbrella(root: Node3D, detail: bool) -> void:
	var canopy := _pivot(root, "Canopy", Vector3(0, 0.022, -0.074))
	_turned(canopy, PackedVector2Array([
		Vector2(0, -0.092), Vector2(0.027, -0.085), Vector2(0.035, -0.056),
		Vector2(0.026, 0.028), Vector2(0.006, 0.124), Vector2(0, 0.129)]), 8, Vector3.ZERO, ENAMEL, Vector3(-70, 0, 0))
	G._cylinder(root, 0.007, 0.316, Vector3(0, 0.017, -0.065), G.STEEL, 0.45, Vector3(-70, 0, 0))
	G._cylinder(root, 0.04, 0.02, Vector3(0, -0.037, 0.084), G.GUNMETAL, 0.3, Vector3(-70, 0, 0))
	G._cylinder(canopy, 0.028, 0.014, Vector3(0, 0.004, -0.011), G.HAZARD_YELLOW, 0, Vector3(-70, 0, 0))
	if not detail:
		return
	for i in 8:
		var angle := TAU * i / 8
		var edge := Vector3(cos(angle), 0, sin(angle))
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-70))
		_lead(canopy, tilt * (edge * 0.034 - Vector3.UP * 0.056), tilt * (edge * 0.006 + Vector3.UP * 0.123), 0.0018, G.NEON_TEAL)
	G._cylinder(root, 0.015, 0.052, Vector3(0, -0.03, 0.067), G.POLYMER, 0, Vector3(-70, 0, 0))
	G._box(canopy, Vector3(0.011, 0.008, 0.013), Vector3(-0.025, 0.003, -0.011), G.BRASS)


## Survey stake with stacked porcelain insulators and a copper pickup fork.
static func _lightning_rod(root: Node3D, detail: bool) -> void:
	var spike := _pivot(root, "Spike")
	_turned(spike, PackedVector2Array([
		Vector2(0, -0.127), Vector2(0.009, -0.085), Vector2(0.009, 0.078),
		Vector2(0.004, 0.1), Vector2(0, 0.111)]), 8, Vector3(0, 0, -0.022), COPPER, Vector3(-72, 0, 0))
	for i in 3:
		var at := Vector3(0, 0.005 + 0.0037 * i, -0.032 - 0.012 * i)
		G._cylinder(spike, 0.024, 0.009, at, CREAM, 0.1, Vector3(-72, 0, 0))
	for side: float in [-1, 1]:
		_lead(spike, Vector3(0, 0.024, -0.093), Vector3(side * 0.032, 0.04, -0.142), 0.005, COPPER)
		_lead(spike, Vector3(side * 0.032, 0.04, -0.142), Vector3(side * 0.032, 0.054, -0.186), 0.004, G.BRASS)
	G._cylinder(spike, 0.004, 0.144, Vector3(0, 0.048, -0.169), G.BRASS, 0.45, Vector3(-72, 0, 0))
	if not detail:
		return
	G._cylinder(spike, 0.014, 0.045, Vector3(0, -0.012, 0.018), G.POLYMER, 0, Vector3(-72, 0, 0))
	G._cylinder(spike, 0.015, 0.008, Vector3(0, -0.007, 0.002), G.HAZARD_YELLOW, 0, Vector3(-72, 0, 0))
	G._box(spike, Vector3(0.032, 0.005, 0.019), Vector3(0, 0.017, -0.073), COPPER)


## Laundry jug with a punched-out handle and a sharply contrasting label.
static func _bleach_bomb(root: Node3D, detail: bool) -> void:
	var cap := _pivot(root, "Cap", Vector3(-0.015, 0.063, -0.01))
	_profile(root, 0.068, PackedVector2Array([
		Vector2(-0.048, -0.051), Vector2(-0.048, 0.016), Vector2(-0.03, 0.051),
		Vector2(0.008, 0.052), Vector2(0.03, 0.022), Vector2(0.041, -0.044),
		Vector2(0.034, -0.052)]), CREAM)
	G._cylinder(cap, 0.017, 0.027, Vector3.ZERO, TOMATO, 0, UPRIGHT)
	G._box(root, Vector3(0.07, 0.054, 0.06), Vector3(0, -0.014, -0.004), ENAMEL)
	_lead(root, Vector3(0, 0.043, 0.009), Vector3(0, 0.051, 0.046), 0.008, CREAM)
	_lead(root, Vector3(0, 0.051, 0.046), Vector3(0, 0.007, 0.056), 0.008, CREAM)
	_lead(root, Vector3(0, 0.007, 0.056), Vector3(0, -0.003, 0.031), 0.008, CREAM)
	if not detail:
		return
	G._box(root, Vector3(0.072, 0.021, 0.021), Vector3(0, -0.013, -0.006), G.HAZARD_YELLOW, 0, Vector3(45, 0, 0))
	G._box(root, Vector3(0.074, 0.013, 0.004), Vector3(0, -0.01, -0.006), G.GUNMETAL)
	G._box(root, Vector3(0.074, 0.004, 0.004), Vector3(0, -0.022, -0.006), G.GUNMETAL)
	G._cylinder(cap, 0.018, 0.006, Vector3(0, -0.008, 0), G.POLYMER, 0, UPRIGHT)
	G._box(root, Vector3(0.069, 0.007, 0.056), Vector3(0, -0.043, -0.004), G.TOXIC_GREEN)


## Shallow enamel first-aid tin with a cross on the lid and front latch.
static func _med_tin(root: Node3D, detail: bool) -> void:
	var lid := _pivot(root, "Lid", Vector3(0, 0.013, -0.05))
	G._box(root, Vector3(0.146, 0.052, 0.101), Vector3(0, -0.009, 0), ENAMEL)
	G._box(lid, Vector3(0.151, 0.014, 0.106), Vector3(0, 0.004, 0.05), CREAM)
	G._box(lid, Vector3(0.059, 0.003, 0.018), Vector3(0, 0.013, 0.05), TOMATO)
	G._box(lid, Vector3(0.018, 0.003, 0.059), Vector3(0, 0.013, 0.05), TOMATO)
	G._box(root, Vector3(0.025, 0.017, 0.007), Vector3(0, 0, 0.052), G.BRASS)
	if not detail:
		return
	G._box(root, Vector3(0.148, 0.005, 0.102), Vector3(0, -0.026, 0), G.GUNMETAL)
	for x: float in [-0.052, 0.052]:
		G._cylinder(root, 0.006, 0.025, Vector3(x, 0.011, -0.052), G.STEEL, 0.55, AXLE)
	G._box(root, Vector3(0.096, 0.014, 0.003), Vector3(0, -0.011, 0.052), CREAM)
	G._box(root, Vector3(0.051, 0.005, 0.004), Vector3(0, -0.012, 0.054), ENAMEL)


## An orange repair patch on a peel-back foil carrier, with a shield insignia.
static func _suit_patch(root: Node3D, detail: bool) -> void:
	var patch := _pivot(root, "Patch")
	G._box(root, Vector3(0.118, 0.012, 0.15), Vector3(0, -0.001, 0), CREAM)
	G._box(patch, Vector3(0.104, 0.008, 0.125), Vector3(-0.002, 0.009, 0.002), G.SAFETY_ORANGE)
	G._box(patch, Vector3(0.055, 0.004, 0.055), Vector3(-0.002, 0.015, 0), G.POLYMER, 0, Vector3(0, 45, 0))
	G._box(patch, Vector3(0.03, 0.004, 0.03), Vector3(-0.002, 0.018, 0), G.HAZARD_YELLOW, 0, Vector3(0, 45, 0))
	G._box(root, Vector3(0.031, 0.006, 0.024), Vector3(0.04, 0.008, 0.068), G.STEEL, 0, Vector3(-15, 0, 0))
	if not detail:
		return
	for side: float in [-1, 1]:
		for i in 6:
			G._box(patch, Vector3(0.002, 0.002, 0.01), Vector3(side * 0.045 - 0.002, 0.014, -0.047 + 0.019 * i), CREAM)
	G._box(patch, Vector3(0.032, 0.003, 0.006), Vector3(-0.002, 0.021, 0), G.POLYMER)
	G._box(patch, Vector3(0.006, 0.003, 0.032), Vector3(-0.002, 0.021, 0), G.POLYMER)


## Pocket AM set, offset speaker cone and a brass telescoping antenna.
static func _bait_radio(root: Node3D, detail: bool) -> void:
	var antenna := _pivot(root, "Antenna", Vector3(-0.059, 0.043, -0.013))
	G._box(root, Vector3(0.152, 0.097, 0.057), Vector3(0, -0.004, 0), TOMATO)
	G._box(root, Vector3(0.145, 0.086, 0.005), Vector3(0, -0.003, 0.03), CREAM)
	G._cylinder(root, 0.031, 0.006, Vector3(-0.032, -0.009, 0.034), G.POLYMER)
	G._box(root, Vector3(0.053, 0.017, 0.006), Vector3(0.039, 0.017, 0.033), G.GUNMETAL)
	G._cylinder(antenna, 0.003, 0.109, Vector3(0.01, 0.048, 0), G.STEEL, 0.6, Vector3(0, 0, -12))
	G._box(root, Vector3(0.064, 0.008, 0.01), Vector3(0.019, 0.061, -0.003), G.POLYMER)
	for x: float in [-0.009, 0.047]:
		G._box(root, Vector3(0.008, 0.019, 0.01), Vector3(x, 0.052, -0.003), G.POLYMER)
	if not detail:
		return
	for i in 5:
		G._box(root, Vector3(0.049 - 0.007 * absi(2 - i), 0.003, 0.004), Vector3(-0.032, -0.029 + 0.01 * i, 0.039), G.STEEL)
	G._box(root, Vector3(0.041, 0.005, 0.004), Vector3(0.039, 0.018, 0.037), G.NEON_TEAL).material_override = G._glow(G.NEON_TEAL, 0.45)
	G._box(root, Vector3(0.003, 0.013, 0.004), Vector3(0.044, 0.018, 0.039), TOMATO)
	for x: float in [0.024, 0.052]:
		G._cylinder(root, 0.009, 0.009, Vector3(x, -0.013, 0.037), G.POLYMER)
	G._cylinder(antenna, 0.005, 0.01, Vector3(0.021, 0.102, 0), G.BRASS, 0.35, UPRIGHT)


static func projectile(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Projectile_" + id
	match id:
		"nail_driver", "nail":
			G._cylinder(root, 0.0025, 0.079, Vector3.ZERO, G.STEEL, 0.6)
			G._cylinder(root, 0.009, 0.004, Vector3(0, 0, 0.04), G.STEEL, 0.6)
			_turned(root, PackedVector2Array([Vector2(0.0025, 0), Vector2(0, 0.011)]), 5, Vector3(0, 0, -0.039), G.STEEL, Vector3(-90, 0, 0))
		"harpoon", "harpoon_bolt":
			G._cylinder(root, 0.008, 0.58, Vector3.ZERO, G.STEEL, 0.6)
			_profile(root, 0.016, PackedVector2Array([Vector2(-0.39, 0), Vector2(-0.25, 0.029), Vector2(-0.27, 0), Vector2(-0.24, -0.022)]), G.STEEL)
			G._cylinder(root, 0.012, 0.05, Vector3(0, 0, 0.265), G.SAFETY_ORANGE)
			var tail := Marker3D.new()
			tail.name = "CableStart"
			tail.position.z = 0.29
			root.add_child(tail)
		"flare_launcher", "road_flare", "flare":
			G._cylinder(root, 0.017, 0.23, Vector3.ZERO, TOMATO)
			G._cylinder(root, 0.018, 0.018, Vector3(0, 0, 0.09), CREAM)
			var ember := G._cylinder(root, 0.02, 0.041, Vector3(0, 0, -0.123), G.SAFETY_ORANGE)
			ember.material_override = G._glow(G.SAFETY_ORANGE, 2.4)
			var flame := _turned(root, PackedVector2Array([
				Vector2(0, 0), Vector2(0.017, 0.005), Vector2(0.012, 0.033),
				Vector2(0, 0.067)]), 6, Vector3(0, 0, -0.137), CREAM, Vector3(-65, 0, 0))
			flame.material_override = G._glow(G.HAZARD_YELLOW, 2.0)
		"sandbag_wall":
			# Three staggered courses, centered with the bottom at ground level.
			for row in 3:
				var count := 3 if row != 1 else 4
				for i in count:
					var half_bag := row == 1 and (i == 0 or i == count - 1)
					var x := (i - (count - 1) * 0.5) * 0.64
					if half_bag:
						x -= signf(x) * 0.16
					var bag := _pivot(root, "Course%dBag%d" % [row, i], Vector3(x, 0.113 + row * 0.209, 0))
					_burlap(bag)
					bag.rotation.y = 0.04 * sin(3 * row + i)
					bag.scale = Vector3(1.4 if half_bag else 2.8, 3.6, 3.5)
					MeshMerge.merge_children(bag)
		"umbrella_open":
			_open_umbrella(root)
		"crate_station":
			_station(root)
		"airdrop":
			_airdrop(root)
		"lightning_rod":
			var stake := _pivot(root, "Planted", Vector3(0, 0.19, 0))
			_lightning_rod(stake, false)
			stake.rotation_degrees.x = 72
			stake.scale = Vector3.ONE * 2.0
		"sandbag", "umbrella", "bleach_bomb", "med_tin", "suit_patch", "bait_radio":
			var prop := pickup(id)
			root.add_child(prop)
			prop.scale = Vector3.ONE * 1.65
			if id == "sandbag":
				prop.scale = Vector3(2.8, 3.6, 3.5)
	return root


static func _open_umbrella(root: Node3D) -> void:
	G._cylinder(root, 0.285, 0.085, Vector3(0, 0.043, 0), G.GUNMETAL, 0.25, UPRIGHT)
	G._cylinder(root, 0.03, 2.47, Vector3(0, 1.27, 0), G.STEEL, 0.5, UPRIGHT)
	_turned(root, PackedVector2Array([
		Vector2(0, 0.018), Vector2(0.16, 0.017), Vector2(1.2, -0.25),
		Vector2(1.5, -0.51), Vector2(1.5, -0.482), Vector2(1.21, -0.22),
		Vector2(0.15, 0.045), Vector2(0, 0.045)]), 8, Vector3(0, 2.49, 0), ENAMEL, UPRIGHT, G.NEON_TEAL)
	G._cylinder(root, 0.048, 0.115, Vector3(0, 2.55, 0), G.HAZARD_YELLOW, 0, UPRIGHT)
	for i in 8:
		var radial := Vector3(cos(TAU * i / 8), 0, sin(TAU * i / 8))
		_lead(root, Vector3.UP * 2.44, Vector3.UP * 2.18 + radial * 1.22, 0.012, G.STEEL)
		_lead(root, Vector3.UP * 2.18 + radial * 1.22, Vector3.UP * 1.995 + radial * 1.49, 0.012, G.STEEL)
	G._cylinder(root, 0.048, 0.22, Vector3(0, 1.15, 0), G.HAZARD_YELLOW, 0, UPRIGHT)



static func _stencil(parent: Node3D, words: String, at: Vector3, height: float, ink: Color) -> void:
	var label := Label3D.new()
	label.text = words
	label.font = LETTERS
	label.font_size = 48
	label.pixel_size = height / 48.0
	label.outline_size = 0
	label.modulate = ink
	label.position = at
	label.double_sided = false
	parent.add_child(label)


## A shallow vending cabinet. The door covers a hollow, shelved compartment.
static func _station(root: Node3D) -> void:
	G._box(root, Vector3(1.2, 0.13, 0.76), Vector3(0, 0.065, 0), G.GUNMETAL)
	G._box(root, Vector3(1.18, 1.7, 0.07), Vector3(0, 0.98, -0.335), ENAMEL)
	for x: float in [-0.56, 0.56]:
		G._box(root, Vector3(0.065, 1.71, 0.70), Vector3(x, 0.97, 0), ENAMEL)
	G._box(root, Vector3(1.19, 0.295, 0.73), Vector3(0, 1.69, 0), ENAMEL)
	G._box(root, Vector3(1.22, 0.055, 0.77), Vector3(0, 1.855, 0), CREAM)
	G._box(root, Vector3(1.11, 0.028, 0.65), Vector3(0, 0.825, -0.008), G.STEEL)
	G._box(root, Vector3(1.11, 0.03, 0.65), Vector3(0, 0.15, -0.008), G.STEEL)
	G._box(root, Vector3(0.3, 1.38, 0.65), Vector3(0.41, 0.841, 0.009), G.GUNMETAL)
	G._box(root, Vector3(0.258, 1.1, 0.037), Vector3(0.415, 0.922, 0.345), CREAM)
	G._box(root, Vector3(0.164, 0.095, 0.021), Vector3(0.414, 1.192, 0.373), G.STEEL)
	G._box(root, Vector3(0.107, 0.015, 0.008), Vector3(0.414, 1.201, 0.386), G.POLYMER)
	G._box(root, Vector3(0.12, 0.145, 0.014), Vector3(0.414, 0.975, 0.372), G.POLYMER)
	G._box(root, Vector3(0.077, 0.032, 0.018), Vector3(0.414, 1.005, 0.382), G.HAZARD_YELLOW)
	G._box(root, Vector3(0.16, 0.15, 0.028), Vector3(0.416, 0.61, 0.369), ENAMEL)
	_stencil(root, "SCRAP", Vector3(0.415, 1.30, 0.371), 0.068, G.GUNMETAL)
	_stencil(root, "SUPPLY   /   87", Vector3(0.01, 1.69, 0.37), 0.162, CREAM)
	var door := _pivot(root, "Door", Vector3(-0.528, 0.84, 0.356))
	G._box(door, Vector3(0.764, 1.374, 0.053), Vector3(0.382, 0, 0), ENAMEL)
	G._box(door, Vector3(0.692, 0.578, 0.012), Vector3(0.38, 0.264, 0.033), CREAM)
	G._box(door, Vector3(0.692, 0.059, 0.014), Vector3(0.38, 0.52, 0.04), G.SAFETY_ORANGE)
	_stencil(door, "WEATHER\nSERVICE", Vector3(0.38, 0.30, 0.042), 0.155, ENAMEL)
	_stencil(door, "FIELD STORES   •   04", Vector3(0.38, 0.066, 0.042), 0.057, G.GUNMETAL)
	G._box(door, Vector3(0.043, 0.212, 0.065), Vector3(0.688, -0.111, 0.052), G.POLYMER)
	for i in 4:
		G._box(door, Vector3(0.42, 0.019, 0.015), Vector3(0.32, -0.31 - 0.052 * i, 0.033), G.GUNMETAL)
	for hinge_y: float in [-0.46, 0.46]:
		G._cylinder(door, 0.025, 0.13, Vector3(0, hinge_y, 0), G.STEEL, 0.5, UPRIGHT)
	G._cylinder(root, 0.112, 0.038, Vector3(0.39, 1.9, -0.075), G.POLYMER, 0, UPRIGHT)
	MeshMerge.merge_children(door)
	MeshMerge.merge_children(root)
	var beacon := _turned(root, PackedVector2Array([
		Vector2(0, 0), Vector2(0.088, 0), Vector2(0.087, 0.098),
		Vector2(0.057, 0.132), Vector2(0, 0.132)]), 10, Vector3(0.39, 1.915, -0.075), G.HAZARD_YELLOW)
	beacon.name = "Beacon"
	# Emission pulses belong to this station even when several are in view.
	beacon.material_override = G._glow(Color("#ffae38"), 1.15).duplicate() as StandardMaterial3D


## Lines are children of the canopy so gameplay can hide the whole rig.
static func _airdrop(root: Node3D) -> void:
	G._box(root, Vector3(1.39, 0.12, 1.38), Vector3(0, 0.06, 0), G.WOOD_DARK)
	for side: float in [-1, 1]:
		G._box(root, Vector3(0.052, 1.14, 1.32), Vector3(side * 0.634, 0.659, 0), CANVAS)
		G._box(root, Vector3(1.216, 1.14, 0.052), Vector3(0, 0.659, side * 0.634), CANVAS)
	G._box(root, Vector3(1.36, 0.08, 1.36), Vector3(0, 0.2, 0), G.WOOD)
	for x: float in [-0.45, 0.45]:
		for z: float in [-0.665, 0.665]:
			G._box(root, Vector3(0.105, 1.12, 0.026), Vector3(x, 0.676, z), ENAMEL)
		G._box(root, Vector3(0.138, 0.13, 0.034), Vector3(x, 0.47, 0.69), G.BRASS, 0.4)
		G._box(root, Vector3(0.08, 0.06, 0.038), Vector3(x, 0.47, 0.691), G.POLYMER)
	G._box(root, Vector3(0.76, 0.45, 0.018), Vector3(0, 0.82, 0.665), CREAM)
	G._box(root, Vector3(0.76, 0.064, 0.022), Vector3(0, 1.02, 0.668), G.SAFETY_ORANGE)
	_stencil(root, "WEATHER SERVICE", Vector3(0, 0.87, 0.679), 0.115, ENAMEL)
	_stencil(root, "AIR SUPPLY   /   87", Vector3(0, 0.73, 0.679), 0.071, G.GUNMETAL)
	var lid := _pivot(root, "Lid", Vector3(0, 1.24, -0.66))
	G._box(lid, Vector3(1.4, 0.152, 1.4), Vector3(0, 0.076, 0.66), G.WOOD)
	for x: float in [-0.45, 0.45]:
		G._box(lid, Vector3(0.105, 0.165, 1.402), Vector3(x, 0.076, 0.66), ENAMEL)
	for side: float in [-1, 1]:
		G._box(root, Vector3(0.022, 0.11, 0.73), Vector3(side * 0.67, 0.78, 0), CREAM, 0, Vector3(-34, 0, 0))
	MeshMerge.merge_children(lid)
	MeshMerge.merge_children(root)
	var chute := _pivot(root, "Parachute", Vector3(0, 3.50, 0))
	for i in 12:
		var a := TAU * i / 12
		var edge := Vector3(2 * cos(a), -0.065, 2 * sin(a))
		var quadrant := a + PI / 12
		var corner := Vector3(0.59 * signf(cos(quadrant)), -2.11, 0.59 * signf(sin(quadrant)))
		_lead(chute, edge, corner, 0.012, CREAM)
	MeshMerge.merge_children(chute)
	_turned(chute, PackedVector2Array([
		Vector2(0, 0.62), Vector2(0.34, 0.615), Vector2(1.21, 0.46),
		Vector2(1.71, 0.19), Vector2(2, -0.07), Vector2(2, -0.03),
		Vector2(1.73, 0.242), Vector2(1.24, 0.516), Vector2(0.36, 0.68),
		Vector2(0, 0.682)]), 12, Vector3.ZERO, G.SAFETY_ORANGE, UPRIGHT, CREAM)
