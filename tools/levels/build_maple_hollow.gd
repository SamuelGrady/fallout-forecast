extends "res://tools/levels/level_builder.gd"
## Maple Hollow: misty 1987 woodland around Wayside Chapel and Lowell Cemetery.
## Dense pine/oak/maple forest, Mill Creek with culverts and a footbridge,
## Ranger Station trailhead, Fire Lookout Tower, Campground, Cabins,
## and a Collapsed Logging Shed.

var _clear_rects: Array[Rect2] = []
var _clear_circles: Array[Vector3] = [] # x, z, radius
var _trail_segments: Array[Array] = [] # [Vector2 a, Vector2 b, float half_width]
var _mat_batches: Dictionary = {} # parent Node3D -> { key: [Material, bool cast_shadow, Array[[Mesh, Transform3D]]] }
var _cast_shadow := true
var _foliage := {}


func add_visual(kind: String, center: Vector3, size: Vector3, material: Material, rot: Vector3) -> void:
	# Merge ALL primitives sharing the same Material (and shadow setting) in a section
	# into a single ArrayMesh, keeping draw calls super low in Compatibility / WebGL2!
	if not _mat_batches.has(part):
		_mat_batches[part] = {}
	var bucket: Dictionary = _mat_batches[part]
	var key := "%d_%d" % [material.get_instance_id(), 1 if _cast_shadow else 0]
	if not bucket.has(key):
		bucket[key] = [material, _cast_shadow, []]
	var basis := Basis.from_euler(rot * PI / 180.0).scaled_local(size)
	var entries: Array = bucket[key][2]
	entries.append([primitive(kind), Transform3D(basis, center)])


func flush() -> void:
	for parent_key: Variant in _mat_batches:
		var parent := parent_key as Node3D
		var bucket: Dictionary = _mat_batches[parent]
		for data: Array in bucket.values():
			var mat := data[0] as Material
			var shadows: bool = data[1]
			var items: Array = data[2]
			var mi := add(parent, MeshInstance3D.new(), "Finish") as MeshInstance3D
			if items.size() == 1:
				var item0: Array = items[0]
				mi.mesh = item0[0] as Mesh
				mi.transform = item0[1] as Transform3D
			else:
				var st := SurfaceTool.new()
				for entry: Array in items:
					st.append_from(entry[0] as Mesh, 0, entry[1] as Transform3D)
				mi.mesh = st.commit()
			mi.material_override = mat
			if not shadows:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat_batches.clear()
	batches.clear()


## Leaves and needles that sway in the storm wind on desktop. The PS1 shader
## bends the vertices by height (see ps1.gdshader `foliage`), so merged
## forest batches sway without splitting into per-tree nodes. `sway` scales
## the bend; low ferns need more to read.
func foliage(color: String, sway := 1.0) -> Material:
	var key := "%s/%s" % [color, sway]
	if not _foliage.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(color)
		m.set_meta(&"wind_foliage", sway)
		_foliage[key] = m
	return _foliage[key]


func start_scene(title: String) -> void:
	super.start_scene(title)
	_mat_batches.clear()
	_cast_shadow = true


func build() -> void:
	district = "maple_hollow"
	_clear_rects.clear()
	_clear_circles.clear()
	_trail_segments.clear()

	# Reusable procedural props under props/maple_hollow/
	water_tower()
	mausoleum()
	church()
	october_maple()
	fire_tower()
	ranger_station()
	camp_shelter()
	lean_to()
	woodland_cabin()
	logging_shed()
	footbridge()
	fallen_log()
	rock_outcrop()

	# Build level scene
	begin_map("MapleHollow", false)
	forest_environment()
	register_clearances()
	terrain_and_trails()
	creek()
	chapel_and_cemetery()
	ranger_trailhead()
	tower_clearing()
	campground_and_cabins()
	logging_yard()
	forest_trees_and_undergrowth()
	fog_pockets()
	outlying_forest()
	markers()
	boundary()
	bake_map()


func forest_environment() -> void:
	# Moody forest twilight with purple/teal fog and cool moonlight dusk.
	var world_env := scene.get_node("WorldEnvironment") as WorldEnvironment
	var env := world_env.environment
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	sky_mat.sky_top_color = Color("#11172b")
	sky_mat.sky_horizon_color = Color("#544972")
	sky_mat.ground_horizon_color = Color("#1f2a38")
	sky_mat.ground_bottom_color = Color("#0d131e")
	sky_mat.sky_curve = 0.22
	sky_mat.sun_angle_max = 12.0

	env.ambient_light_color = Color("#768da3")
	env.ambient_light_energy = 0.74
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("#3b4c62")
	env.fog_density = 0.0085
	env.fog_sky_affect = 0.42
	env.glow_intensity = 0.55
	env.glow_bloom = 0.05

	var sun := scene.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-24.0, -38.0, 0.0)
	sun.light_color = Color("#c4d2e8")
	sun.light_energy = 0.78
	sun.shadow_enabled = true
	# 2 splits keeps crisp forest shadows while halving Compatibility shadow draw calls.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 82.0


func _reserve_rect(cx: float, cz: float, sx: float, sz: float) -> void:
	_clear_rects.append(Rect2(cx - sx * 0.5, cz - sz * 0.5, sx, sz))


func _reserve_circle(cx: float, cz: float, r: float) -> void:
	_clear_circles.append(Vector3(cx, cz, r))


func _reserve_trail(a: Vector2, b: Vector2, half_width: float) -> void:
	_trail_segments.append([a, b, half_width])


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _is_clear_for_tree(p: Vector2, extra_margin: float = 0.0) -> bool:
	if p.x > -52.5 - extra_margin and p.x < -40.5 + extra_margin:
		return false
	for r: Rect2 in _clear_rects:
		if r.grow(extra_margin).has_point(p):
			return false
	for c: Vector3 in _clear_circles:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + extra_margin:
			return false
	for seg: Array in _trail_segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var hw: float = seg[2]
		if _dist_to_segment(p, a, b) < hw + extra_margin:
			return false
	return true


func register_clearances() -> void:
	# Landmarks & clearings
	_reserve_rect(24.0, -45.0, 18.0, 24.0)      # Wayside Chapel + steps
	_reserve_rect(20.0, -22.0, 20.0, 18.0)      # Chapel dirt parking lot
	_reserve_rect(46.5, -24.0, 32.0, 56.0)      # Lowell Cemetery + Mausoleum boss arena
	_reserve_rect(-14.0, 44.0, 20.0, 16.0)      # Ranger Station + porch + parked SUV
	_reserve_circle(-4.0, 35.0, 10.5)           # Player spawn trailhead clearing
	_reserve_circle(-12.0, -4.0, 12.0)          # Fire Lookout Tower clearing
	_reserve_circle(-39.0, -1.0, 7.5)           # Footbridge East approach sightline
	_reserve_circle(-54.0, -2.0, 6.5)           # Footbridge West approach sightline
	_reserve_rect(-12.0, -38.0, 26.0, 20.0)     # Campground clearing
	_reserve_circle(-28.0, -46.0, 6.5)          # Lean-To #1
	_reserve_circle(-30.0, 12.0, 6.5)           # Lean-To #2
	_reserve_rect(2.0, -51.0, 13.0, 13.0)       # Pine Cabin #1
	_reserve_rect(-28.0, 21.0, 13.0, 13.0)      # Creek Cabin #2
	_reserve_rect(35.0, 33.0, 24.0, 18.0)       # Collapsed Logging Shed + yard
	_reserve_circle(-56.5, -47.0, 8.5)          # Municipal Water Tower

	# Main Gravel Logging Road
	_reserve_trail(Vector2(-64, 32), Vector2(-30, 32), 5.2)
	_reserve_trail(Vector2(-30, 32), Vector2(-4, 33), 5.4)
	_reserve_trail(Vector2(-4, 33), Vector2(16, 29), 5.2)
	_reserve_trail(Vector2(16, 29), Vector2(40, 21), 5.0)
	_reserve_trail(Vector2(40, 21), Vector2(64, 15), 5.0)

	# Chapel Spur Road
	_reserve_trail(Vector2(12, 29), Vector2(18, 6), 4.6)
	_reserve_trail(Vector2(18, 6), Vector2(20, -16), 4.8)

	# Central Spine Dirt Trail (Trailhead -> Fire Tower -> Campground)
	_reserve_trail(Vector2(-5, 33), Vector2(-9, 14), 4.4)
	_reserve_trail(Vector2(-9, 14), Vector2(-12, -4), 4.4)
	_reserve_trail(Vector2(-12, -4), Vector2(-12, -36), 4.4)

	# East-West Cross Trails
	_reserve_trail(Vector2(-56.5, -2), Vector2(-12, -4), 4.4)    # Footbridge -> Fire Tower
	_reserve_trail(Vector2(-12, -4), Vector2(16, -20), 4.2)      # Fire Tower -> Chapel Lot
	_reserve_trail(Vector2(-56.5, -34), Vector2(-12, -38), 4.4)  # North Culvert -> Campground
	_reserve_trail(Vector2(-8, -38), Vector2(22, -33), 4.2)      # Campground -> Chapel Steps
	_reserve_trail(Vector2(44, 19), Vector2(44, 2), 4.5)         # East Road -> Cemetery South Gate

	# West Bank Footpath
	_reserve_trail(Vector2(-56.5, -60), Vector2(-56.5, 60), 3.6)

	# Creek Bank Ramps
	_reserve_rect(-41.0, -25.0, 7.0, 7.0)
	_reserve_rect(-41.0, 22.0, 7.0, 7.0)


func _no_shadow_model(kit: String, id: String, at: Vector3, length: float, yaw: float = 0.0, block: bool = true, tint: String = "") -> Node3D:
	var holder := model(kit, id, at, length, yaw, block, tint)
	for mi_node: Node in holder.find_children("*", "MeshInstance3D", true, false):
		(mi_node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


# ==============================================================================
# PROCEDURAL PROPS (saved under res://props/maple_hollow/)
# ==============================================================================

func water_tower() -> void:
	start_scene("MunicipalTank")
	var iron := paint("#4a5361")
	var enamel := surface("#719e9b", "siding", 0.23)
	var stripe := paint("#c88965")
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			beam(Vector3(3.1 * x, 0.0, 3.1 * z), Vector3(2.15 * x, 12.0, 2.15 * z), 0.39, iron, true)
			beam(Vector3(2.98 * x, 1.4, 2.98 * z), Vector3(-2.55 * x, 7.3, 2.55 * z), 0.14, iron)
			beam(Vector3(2.98 * x, 1.4, 2.98 * z), Vector3(2.55 * x, 7.3, -2.55 * z), 0.14, iron)
			box(Vector3(3.1 * x, 0.24, 3.1 * z), Vector3(1.05, 0.48, 1.05), paint("#8c8a86"))
	tube(Vector3(0.0, 5.4, 0.0), 0.4, 10.8, iron, 1.0, true)
	tube(Vector3(0.0, 12.1, 0.0), 1.05, 3.5, enamel, 4.5)
	tube(Vector3(0.0, 16.15, 0.0), 4.72, 4.7, enamel)
	collider(Vector3(0.0, 16.15, 0.0), Vector3(9.44, 4.7, 9.44), Vector3.ZERO, true)
	tube(Vector3(0.0, 14.28, 0.0), 4.77, 0.56, stripe)
	tube(Vector3(0.0, 18.43, 0.0), 4.85, 0.2, iron)
	tube(Vector3(0.0, 19.24, 0.0), 4.85, 1.55, enamel, 0.09)
	tube(Vector3(0.0, 20.58, 0.0), 0.14, 1.35, iron)
	tube(Vector3(0.0, 21.3, 0.0), 0.17, 0.26, lit("#ff7e5f"))
	label("MAPLE", Vector3(0.0, 16.75, 4.76), 1.10, "#243b47")
	label("FOREST DIST.", Vector3(0.0, 15.6, 4.78), 0.46, "#2c3d4c")
	_cast_shadow = false
	for x: float in [-0.34, 0.34]:
		box(Vector3(x, 8.0, -4.78), Vector3(0.08, 16.0, 0.08), iron, false)
	for i: int in 30:
		box(Vector3(0.0, 0.4 + float(i) * 0.51, -4.78), Vector3(0.75, 0.06, 0.09), iron, false)
	_cast_shadow = true
	shelter("TankUnderside", Vector3(0.0, 4.9, 0.0), Vector3(6.5, 9.8, 6.5))
	finish_prop("municipal_tank")


func mausoleum() -> void:
	start_scene("LowellVault")
	var marble := surface("#afb2bc", "sidewalk", 0.35)
	var dark := paint("#4c4c5c")
	var bronze := paint("#69867a")
	box(Vector3(0.0, 2.8, -1.3), Vector3(12.2, 5.6, 7.8), marble)
	box(Vector3(0.0, 0.38, -1.3), Vector3(12.5, 0.76, 8.05), dark)
	box(Vector3(0.0, 5.65, 0.8), Vector3(13.6, 0.65, 12.5), dark)
	box(Vector3(0.0, 6.15, 0.8), Vector3(13.0, 0.48, 12.0), marble)
	for i: int in 6:
		box(Vector3(0.0, 6.48 + float(i) * 0.22, 0.8), Vector3(12.2 - float(i) * 1.9, 0.24, 11.7), marble, false)
	for x: float in [-5.45, -3.5, 3.5, 5.45]:
		box(Vector3(x, 0.26, 5.95), Vector3(1.05, 0.52, 1.05), dark)
		tube(Vector3(x, 2.83, 5.95), 0.37, 4.84, marble, 0.84, true)
		box(Vector3(x, 5.15, 5.95), Vector3(0.98, 0.4, 0.98), marble, false)
	box(Vector3(0.0, 2.2, 2.68), Vector3(3.4, 4.4, 0.32), dark, false)
	for x: float in [-0.66, 0.66]:
		box(Vector3(x, 1.75, 2.88), Vector3(1.26, 3.45, 0.18), bronze, false)
		for y: float in [0.95, 2.45]:
			box(Vector3(x, y, 3.0), Vector3(0.85, 0.85, 0.07), dark, false)
	box(Vector3(0.0, 5.65, 7.13), Vector3(5.45, 0.85, 0.15), dark, false)
	label("L O W E L L", Vector3(0.0, 5.68, 7.23), 0.54, "#dfc9a3")
	shelter("Portico", Vector3(0.0, 2.65, 4.8), Vector3(12.7, 5.3, 4.3))
	finish_prop("lowell_mausoleum")


func church() -> void:
	start_scene("WaysideChapel")
	var wall := surface("#e6cca9", "siding", 0.38)
	var roof := surface("#6d6480", "diamond_plate", 0.25)
	var frame := paint("#4e4654")
	var stone := surface("#8b8d94", "sidewalk", 0.35)
	box(Vector3(0.0, 3.3, 0.0), Vector3(11.0, 6.6, 17.0), wall)
	for side: float in [-1.0, 1.0]:
		box(Vector3(side * 2.92, 7.75, 0.0), Vector3(6.64, 0.38, 17.7), roof, true, Vector3(0.0, 0.0, -side * 25.0))
		for z: float in [-5.7, -1.9, 1.9, 5.7]:
			box(Vector3(side * 5.51, 3.7, z), Vector3(0.15, 3.2, 1.65), frame, false)
			box(Vector3(side * 5.62, 3.7, z), Vector3(0.07, 2.7, 1.27), lit("#dfaa7c"), false)
			box(Vector3(side * 5.71, 3.75, z), Vector3(0.08, 2.8, 0.11), frame, false)
			box(Vector3(side * 5.71, 3.75, z), Vector3(0.08, 0.1, 1.32), frame, false)
	for i: int in 7:
		box(Vector3(0.0, 6.67 + float(i) * 0.33, 0.0), Vector3(10.55 - float(i) * 1.45, 0.35, 16.98), wall, false)
	box(Vector3(0.0, 5.15, 7.4), Vector3(4.6, 10.3, 4.8), wall)
	box(Vector3(0.0, 10.25, 7.4), Vector3(5.0, 0.35, 5.2), frame)
	for x: float in [-1.65, 1.65]:
		for z: float in [5.75, 9.05]:
			box(Vector3(x, 11.65, z), Vector3(0.45, 2.65, 0.45), wall, false)
	tube(Vector3(0.0, 11.24, 7.4), 0.84, 0.95, paint("#8d775d"), 0.43)
	box(Vector3(0.0, 13.0, 7.4), Vector3(4.6, 0.4, 4.6), frame, false)
	tube(Vector3(0.0, 15.5, 7.4), 2.45, 5.0, roof, 0.035)
	box(Vector3(0.0, 18.65, 7.4), Vector3(0.17, 1.8, 0.17), wall, false)
	box(Vector3(0.0, 18.93, 7.4), Vector3(1.18, 0.16, 0.16), wall, false)
	box(Vector3(0.0, 1.76, 9.88), Vector3(2.4, 3.52, 0.22), frame, false)
	# Clock face overlooking the chapel clearing.
	tube(Vector3(0.0, 7.65, 9.89), 1.16, 0.20, frame, 1.0, false, Vector3(90.0, 0.0, 0.0))
	tube(Vector3(0.0, 7.65, 10.02), 1.02, 0.07, lit("#ecc596"), 1.0, false, Vector3(90.0, 0.0, 0.0))
	beam(Vector3(0.0, 7.65, 10.10), Vector3(-0.44, 8.21, 10.10), 0.12, frame)
	beam(Vector3(0.0, 7.65, 10.10), Vector3(0.54, 7.92, 10.10), 0.11, frame)
	# Covered porch, stone chapel steps & warm porch lantern
	box(Vector3(0.0, 3.95, 11.1), Vector3(5.35, 0.38, 3.2), roof)
	for x: float in [-2.4, 2.4]:
		box(Vector3(x, 1.9, 12.45), Vector3(0.22, 3.8, 0.22), wall)
	_cast_shadow = false
	box(Vector3(0.0, 0.12, 11.2), Vector3(5.2, 0.24, 2.8), stone, false)
	box(Vector3(0.0, 0.06, 12.95), Vector3(4.6, 0.12, 0.9), stone, false)
	box(Vector3(0.0, 3.45, 12.3), Vector3(0.32, 0.36, 0.32), lit("#ffd48e"), false)
	_cast_shadow = true
	shelter("ChapelPorch", Vector3(0.0, 1.84, 11.25), Vector3(5.2, 3.68, 2.85))
	finish_prop("wayside_chapel")


func october_maple() -> void:
	start_scene("OctoberMaple")
	var bark := surface("#5b4946", "wood", 0.45)
	var leaf_a := paint("#b86648")
	var leaf_b := paint("#cf8653")
	tube(Vector3(0.0, 1.95, 0.0), 0.42, 3.9, bark, 0.56, true)
	for i: int in 5:
		var a := float(i) * TAU / 5.0 + 0.4
		var tip := Vector3(2.1 * cos(a), 3.96 + 0.48 * float(i % 3), 2.1 * sin(a))
		beam(Vector3(0.0, 1.85 + 0.23 * float(i), 0.0), tip, 0.26, bark)
		var leaf := leaf_a if i % 2 == 0 else leaf_b
		tube(tip + Vector3.UP * 0.63, 0.97, 1.6, leaf, 2.12)
		tube(tip + Vector3.UP * 2.24, 2.06, 1.65, leaf, 0.34)
	tube(Vector3(0.0, 5.8, 0.0), 2.1, 2.3, leaf_b, 0.54)
	finish_prop("october_maple", true)


func fire_tower() -> void:
	start_scene("FireTower")
	var timber := surface("#755b4b", "wood", 0.36)
	var dark_wood := paint("#463936")
	var roof := surface("#486964", "shingles_teal", 0.30)
	var concrete := surface("#8f9096", "sidewalk", 0.35)
	var cab_wall := surface("#c4b299", "siding", 0.35)

	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			box(Vector3(2.65 * x, 0.25, 2.65 * z), Vector3(0.85, 0.5, 0.85), concrete)
			beam(Vector3(2.65 * x, 0.3, 2.65 * z), Vector3(1.85 * x, 12.6, 1.85 * z), 0.30, timber, true)
			for tier: int in 3:
				var y0 := 3.6 + float(tier) * 3.0
				var y1 := y0 + 3.0
				var r0 := lerpf(2.42, 1.85, (y0 - 0.3) / 12.3)
				var r1 := lerpf(2.42, 1.85, (y1 - 0.3) / 12.3)
				beam(Vector3(r0 * x, y0, r0 * z), Vector3(-r1 * x, y1, r1 * z), 0.13, dark_wood)
				beam(Vector3(r0 * x, y0, r0 * z), Vector3(r1 * x, y1, -r1 * z), 0.13, dark_wood)

	box(Vector3(0.0, 3.62, 0.0), Vector3(5.3, 0.32, 5.3), timber)
	box(Vector3(0.0, 3.82, 0.0), Vector3(5.5, 0.14, 5.5), roof, false)
	box(Vector3(0.0, 3.25, 0.0), Vector3(0.32, 0.38, 0.32), lit("#ffd18a"), false)
	shelter("TowerBase", Vector3(0.0, 1.75, 0.0), Vector3(4.9, 3.45, 4.9))

	for tier: int in 3:
		var y0 := 3.8 + float(tier) * 2.9
		var dir := 1.0 if tier % 2 == 0 else -1.0
		beam(Vector3(-1.1 * dir, y0, -0.7), Vector3(1.1 * dir, y0 + 2.8, 0.7), 0.24, timber)
		box(Vector3(1.1 * dir, y0 + 2.8, 0.0), Vector3(1.2, 0.16, 2.2), dark_wood, false)

	box(Vector3(0.0, 12.65, 0.0), Vector3(5.6, 0.30, 5.6), dark_wood)
	for s: float in [-2.68, 2.68]:
		box(Vector3(s, 13.65, 0.0), Vector3(0.12, 0.12, 5.5), timber, false)
		box(Vector3(0.0, 13.65, s), Vector3(5.5, 0.12, 0.12), timber, false)
		box(Vector3(s, 13.20, 0.0), Vector3(0.10, 0.10, 5.5), timber, false)
		box(Vector3(0.0, 13.20, s), Vector3(5.5, 0.10, 0.10), timber, false)
		for p: float in [-2.68, -0.9, 0.9, 2.68]:
			box(Vector3(s, 13.15, p), Vector3(0.12, 1.0, 0.12), dark_wood, false)
			box(Vector3(p, 13.15, s), Vector3(0.12, 1.0, 0.12), dark_wood, false)

	box(Vector3(0.0, 13.45, 0.0), Vector3(3.6, 1.35, 3.6), cab_wall)
	box(Vector3(0.0, 14.65, 0.0), Vector3(3.45, 1.15, 3.45), lit("#ffc37c"), false)
	for x: float in [-1.75, 0.0, 1.75]:
		for z: float in [-1.75, 1.75]:
			box(Vector3(x, 14.65, z), Vector3(0.16, 1.25, 0.16), dark_wood, false)
			box(Vector3(z, 14.65, x), Vector3(0.16, 1.25, 0.16), dark_wood, false)
	box(Vector3(0.0, 15.35, 0.0), Vector3(4.5, 0.28, 4.5), dark_wood, false)
	tube(Vector3(0.0, 16.3, 0.0), 3.1, 1.75, roof, 0.08)
	tube(Vector3(0.0, 17.85, 0.0), 0.07, 1.6, dark_wood)
	tube(Vector3(0.0, 18.75, 0.0), 0.18, 0.28, lit("#ff5e5b"))
	label("LOOKOUT 04", Vector3(0.0, 13.35, 1.86), 0.44, "#2f3d44")
	label("LOOKOUT 04", Vector3(0.0, 13.35, -1.86), 0.44, "#2f3d44", 180.0)
	finish_prop("fire_tower")


func ranger_station() -> void:
	start_scene("RangerStation")
	var log_wall := surface("#8b6a52", "wood", 0.34)
	var trim := paint("#3e4847")
	var roof := surface("#4c746c", "shingles_teal", 0.28)
	var stone := surface("#787980", "sidewalk", 0.35)
	var deck := surface("#7b6452", "wood", 0.32)

	box(Vector3(0.0, 2.2, -1.4), Vector3(12.0, 4.4, 7.4), log_wall)
	box(Vector3(0.0, 0.25, -1.4), Vector3(12.3, 0.5, 7.7), stone, false)
	box(Vector3(-6.45, 3.2, -1.4), Vector3(1.15, 6.4, 1.6), stone)
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.0, 5.15, 0.3 + side * 2.9), Vector3(13.0, 0.32, 6.5), roof, true, Vector3(side * 22.0, 0.0, 0.0))
	for i: int in 5:
		box(Vector3(0.0, 4.5 + float(i) * 0.28, -1.4), Vector3(11.9, 0.30, 7.2 - float(i) * 1.4), log_wall, false)

	box(Vector3(0.0, 1.35, 2.34), Vector3(1.5, 2.5, 0.16), trim, false)
	for x: float in [-3.6, 3.6]:
		box(Vector3(x, 2.15, 2.34), Vector3(2.2, 1.45, 0.16), trim, false)
		box(Vector3(x, 2.15, 2.42), Vector3(1.9, 1.15, 0.08), lit("#ffc67d"), false)
		box(Vector3(x, 2.15, 2.47), Vector3(0.10, 1.2, 0.08), trim, false)
	for side_x: float in [-6.05, 6.05]:
		box(Vector3(side_x, 2.15, -1.4), Vector3(0.14, 1.35, 2.2), lit("#e6a868"), false)

	box(Vector3(0.0, 0.12, 4.05), Vector3(12.0, 0.24, 3.5), deck, false)
	box(Vector3(0.0, 3.55, 4.15), Vector3(12.5, 0.28, 3.9), roof)
	for x: float in [-5.7, -2.0, 2.0, 5.7]:
		box(Vector3(x, 1.78, 5.65), Vector3(0.24, 3.56, 0.24), trim)
	for x: float in [-3.85, 3.85]:
		box(Vector3(x, 0.95, 5.65), Vector3(3.5, 0.12, 0.14), trim, false)
		box(Vector3(x, 0.45, 5.65), Vector3(3.5, 0.10, 0.12), trim, false)
	box(Vector3(1.25, 2.85, 2.55), Vector3(0.30, 0.36, 0.26), lit("#ffd898"), false)
	box(Vector3(0.0, 3.92, 5.95), Vector3(7.4, 0.85, 0.16), trim, false)
	label("RANGER STATION", Vector3(0.0, 3.93, 6.06), 0.56, "#ffe0a8")
	tube(Vector3(4.5, 7.6, -2.2), 0.08, 4.4, trim)
	box(Vector3(4.5, 9.2, -2.2), Vector3(1.8, 0.08, 0.08), trim, false)
	box(Vector3(4.5, 8.6, -2.2), Vector3(1.2, 0.08, 0.08), trim, false)
	shelter("RangerPorch", Vector3(0.0, 1.75, 4.1), Vector3(11.4, 3.3, 3.3))
	finish_prop("ranger_station")


func camp_shelter() -> void:
	start_scene("CampShelter")
	var timber := surface("#7c604c", "wood", 0.36)
	var dark := paint("#433834")
	var roof := surface("#53756c", "shingles_teal", 0.30)
	var pad := surface("#8f8a82", "sidewalk", 0.34)
	var bench_wood := surface("#9a785c", "wood", 0.38)

	_cast_shadow = false
	box(Vector3(0.0, 0.03, 0.0), Vector3(9.4, 0.06, 6.2), pad, false)
	_cast_shadow = true
	for x: float in [-4.2, 0.0, 4.2]:
		for z: float in [-2.6, 2.6]:
			box(Vector3(x, 1.65, z), Vector3(0.28, 3.3, 0.28), timber)
	for z: float in [-2.6, 2.6]:
		box(Vector3(0.0, 3.25, z), Vector3(9.0, 0.26, 0.26), dark, false)
	for x: float in [-4.2, 0.0, 4.2]:
		box(Vector3(x, 3.25, 0.0), Vector3(0.26, 0.26, 5.5), dark, false)
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.0, 3.92, side * 1.65), Vector3(9.8, 0.26, 3.7), roof, true, Vector3(side * 24.0, 0.0, 0.0))
	for x: float in [-2.1, 2.1]:
		box(Vector3(x, 0.78, 0.0), Vector3(2.2, 0.12, 0.92), bench_wood)
		for s: float in [-0.72, 0.72]:
			box(Vector3(x, 0.44, s), Vector3(2.2, 0.10, 0.34), bench_wood, false)
		for lx: float in [-0.82, 0.82]:
			box(Vector3(x + lx, 0.40, 0.0), Vector3(0.14, 0.76, 1.35), dark, false)
	box(Vector3(0.0, 3.05, 0.0), Vector3(0.28, 0.36, 0.28), lit("#ffd896"), false)
	shelter("PicnicPavilion", Vector3(0.0, 1.68, 0.0), Vector3(8.8, 3.3, 5.6))
	finish_prop("camp_shelter")


func lean_to() -> void:
	start_scene("LeanTo")
	var timber := surface("#775c48", "wood", 0.36)
	var dark := paint("#423632")
	var roof := surface("#5b6d62", "shingles_teal", 0.32)
	var floor_wood := surface("#8b7058", "wood", 0.36)

	box(Vector3(0.0, 0.12, 0.0), Vector3(5.2, 0.24, 3.2), floor_wood, false)
	box(Vector3(0.0, 1.05, -1.55), Vector3(5.3, 2.1, 0.22), timber)
	for sx: float in [-2.58, 2.58]:
		box(Vector3(sx, 1.25, 0.0), Vector3(0.22, 2.5, 3.2), timber)
	for sx: float in [-2.52, 2.52]:
		box(Vector3(sx, 1.55, 1.52), Vector3(0.22, 3.1, 0.22), dark)
	box(Vector3(0.0, 2.68, 0.05), Vector3(5.8, 0.24, 3.9), roof, true, Vector3(-16.0, 0.0, 0.0))
	for row: int in 3:
		for col: int in 3:
			tube(Vector3(3.15, 0.18 + float(row) * 0.24, -0.5 + float(col) * 0.26), 0.11, 0.85, dark, 1.0, false, Vector3(0.0, 0.0, 90.0))
	shelter("LeanToShelter", Vector3(0.0, 1.35, 0.05), Vector3(4.9, 2.6, 3.0))
	finish_prop("lean_to")


func woodland_cabin() -> void:
	start_scene("WoodlandCabin")
	var logs := surface("#7e5f48", "wood", 0.34)
	var trim := paint("#3c3534")
	var roof := surface("#4c6460", "shingles_teal", 0.30)
	var stone := surface("#74757c", "sidewalk", 0.35)

	box(Vector3(0.0, 2.0, -1.1), Vector3(7.4, 4.0, 6.2), logs)
	box(Vector3(3.95, 2.9, -1.1), Vector3(0.95, 5.8, 1.25), stone)
	for side: float in [-1.0, 1.0]:
		box(Vector3(side * 2.15, 4.85, 0.1), Vector3(5.1, 0.28, 9.2), roof, true, Vector3(0.0, 0.0, -side * 30.0))
	for i: int in 5:
		box(Vector3(0.0, 4.15 + float(i) * 0.34, -1.1), Vector3(7.1 - float(i) * 1.35, 0.36, 6.1), logs, false)
	box(Vector3(-1.3, 1.25, 2.04), Vector3(1.25, 2.35, 0.16), trim, false)
	box(Vector3(1.5, 1.95, 2.04), Vector3(1.65, 1.25, 0.16), trim, false)
	box(Vector3(1.5, 1.95, 2.11), Vector3(1.38, 0.98, 0.08), lit("#f0b26e"), false)
	box(Vector3(0.0, 0.10, 3.3), Vector3(7.4, 0.20, 2.6), logs, false)
	box(Vector3(0.0, 3.25, 3.35), Vector3(7.8, 0.24, 2.9), roof)
	for x: float in [-3.45, 3.45]:
		box(Vector3(x, 1.62, 4.45), Vector3(0.22, 3.25, 0.22), trim)
	shelter("CabinPorch", Vector3(0.0, 1.6, 3.35), Vector3(6.9, 3.1, 2.55))
	finish_prop("woodland_cabin")


func logging_shed() -> void:
	start_scene("LoggingShed")
	var timber := surface("#715949", "wood", 0.34)
	var rusted := surface("#7c635c", "diamond_plate", 0.28)
	var bark := surface("#5b463b", "wood", 0.42)
	var dark := paint("#3c3534")

	for x: float in [-5.2, -2.4, 0.4]:
		for z: float in [-2.8, 2.8]:
			box(Vector3(x, 1.75, z), Vector3(0.28, 3.5, 0.28), timber)
	box(Vector3(-2.4, 1.75, 2.9), Vector3(5.9, 3.4, 0.20), timber)
	box(Vector3(-2.4, 3.55, 0.0), Vector3(6.4, 0.22, 6.4), rusted, true, Vector3(6.0, 0.0, 0.0))
	box(Vector3(-2.4, 3.22, -2.4), Vector3(0.32, 0.26, 0.26), lit("#ffcb82"), false)
	shelter("LoggingShedDry", Vector3(-2.4, 1.68, 0.0), Vector3(5.6, 3.3, 5.6))

	beam(Vector3(3.4, 0.0, -2.7), Vector3(4.2, 2.2, -2.5), 0.26, timber, true)
	beam(Vector3(3.4, 0.0, 2.7), Vector3(4.5, 1.6, 2.4), 0.26, timber, true)
	box(Vector3(2.9, 1.95, 0.0), Vector3(5.4, 0.22, 6.0), rusted, true, Vector3(8.0, 0.0, -28.0))
	for row: int in 3:
		var count := 4 - row
		for col: int in count:
			var z_off := (float(col) - float(count - 1) * 0.5) * 0.62
			tube(Vector3(3.4, 0.30 + float(row) * 0.50, z_off), 0.28, 4.4, bark, 0.96, false, Vector3(0.0, 0.0, 90.0))
	collider(Vector3(3.4, 0.75, 0.0), Vector3(4.4, 1.5, 2.6))
	box(Vector3(5.6, 0.14, -1.6), Vector3(2.4, 0.14, 0.45), dark, false, Vector3(0.0, 22.0, 0.0))
	finish_prop("logging_shed")


func footbridge() -> void:
	start_scene("Footbridge")
	var plank := surface("#8c6d54", "wood", 0.36)
	var beam_wood := paint("#4e3e35")
	var stone := surface("#7a7d80", "sidewalk", 0.34)

	box(Vector3(0.0, -0.08, 0.0), Vector3(11.4, 0.24, 3.6), plank)
	for z: float in [-1.45, 0.0, 1.45]:
		box(Vector3(0.0, -0.34, z), Vector3(11.0, 0.32, 0.28), beam_wood, false)
	for x: float in [-4.8, 4.8]:
		box(Vector3(x, -1.2, 0.0), Vector3(1.2, 2.2, 4.0), stone, false)
	for z: float in [-1.72, 1.72]:
		for x: float in [-4.8, -2.4, 0.0, 2.4, 4.8]:
			box(Vector3(x, 0.58, z), Vector3(0.18, 1.25, 0.18), beam_wood, false)
		box(Vector3(0.0, 1.08, z), Vector3(10.0, 0.12, 0.14), plank, false)
		box(Vector3(0.0, 0.56, z), Vector3(10.0, 0.10, 0.12), plank, false)
		collider(Vector3(0.0, 0.55, z), Vector3(10.2, 1.1, 0.24))
	# Twin wooden bridge-entry lantern posts (warm glowing beacons across Mill Creek!)
	for x: float in [-4.8, 4.8]:
		box(Vector3(x, 1.55, 1.72), Vector3(0.18, 1.15, 0.18), beam_wood, false)
		box(Vector3(x, 2.24, 1.72), Vector3(0.32, 0.36, 0.32), lit("#ffd28a"), false)
		box(Vector3(x, 2.48, 1.72), Vector3(0.42, 0.10, 0.42), beam_wood, false)
	finish_prop("footbridge")


func fallen_log() -> void:
	start_scene("FallenLog")
	var bark := surface("#5b463c", "wood", 0.42)
	var moss := surface("#4c6449", "forest_floor", 0.45)
	_cast_shadow = false
	tube(Vector3(0.0, 0.42, 0.0), 0.44, 5.6, bark, 0.82, false, Vector3(0.0, 0.0, 90.0))
	tube(Vector3(-2.75, 0.55, 0.0), 0.62, 0.65, bark, 0.72, false, Vector3(0.0, 0.0, 76.0))
	beam(Vector3(0.9, 0.55, 0.15), Vector3(1.8, 1.15, 0.65), 0.18, bark)
	box(Vector3(-0.4, 0.83, 0.0), Vector3(3.6, 0.10, 0.48), moss, false)
	_cast_shadow = true
	collider(Vector3(0.0, 0.46, 0.0), Vector3(5.6, 0.92, 0.92))
	finish_prop("fallen_log")


func rock_outcrop() -> void:
	start_scene("RockOutcrop")
	var stone := surface("#666c75", "sidewalk", 0.30)
	var moss := surface("#4a624b", "forest_floor", 0.38)
	_cast_shadow = false
	box(Vector3(0.0, 0.85, 0.0), Vector3(2.8, 1.9, 2.3), stone, true, Vector3(6.0, 14.0, -8.0))
	box(Vector3(0.0, 1.78, 0.0), Vector3(2.2, 0.24, 1.8), moss, false, Vector3(6.0, 14.0, -8.0))
	box(Vector3(1.55, 0.55, 0.75), Vector3(1.8, 1.25, 1.6), stone, true, Vector3(-10.0, -24.0, 12.0))
	box(Vector3(-1.35, 0.48, -0.65), Vector3(1.6, 1.1, 1.5), stone, true, Vector3(11.0, 32.0, 7.0))
	_cast_shadow = true
	finish_prop("rock_outcrop")


# ==============================================================================
# LEVEL GEOMETRY & SECTIONS
# ==============================================================================

func _trail_ribbon(a: Vector2, b: Vector2, width: float, mat: Material, y: float = 0.025) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b) + width * 0.45
	var yaw := rad_to_deg(atan2(b.x - a.x, b.y - a.y))
	box(Vector3(mid.x, y, mid.y), Vector3(width, 0.04, length), mat, false, Vector3(0.0, yaw, 0.0))


func terrain_and_trails() -> void:
	section("ForestGround")
	_cast_shadow = false
	var floor_mat := surface("#9ea492", "forest_floor", 0.20)
	box(Vector3(10.75, -1.55, 0.0), Vector3(106.5, 3.1, 128.0), floor_mat)
	box(Vector3(-57.5, -1.55, 0.0), Vector3(13.0, 3.1, 128.0), floor_mat)

	# Mossy churchyard lawn (fits neatly inside the stone cemetery walls) & organic campground meadow
	var cemetery_grass := surface("#6f8268", "grass", 0.20)
	box(Vector3(46.6, 0.012, -24.0), Vector3(29.2, 0.024, 55.6), cemetery_grass, false)
	var camp_grass := surface("#77866a", "grass", 0.20)
	tube(Vector3(-12.0, 0.010, -38.0), 12.0, 0.022, camp_grass)
	tube(Vector3(-22.0, 0.010, -40.0), 8.0, 0.022, camp_grass)
	tube(Vector3(-2.0, 0.010, -36.0), 8.5, 0.022, camp_grass)

	section("TrailsAndRoads")
	var gravel := surface("#b6aca0", "dirt_trail", 0.24)
	var dirt := surface("#9a8b7b", "dirt_trail", 0.26)

	# Main Gravel Logging Road
	_trail_ribbon(Vector2(-64, 32), Vector2(-30, 32), 6.4, gravel, 0.026)
	_trail_ribbon(Vector2(-30, 32), Vector2(-4, 33), 6.8, gravel, 0.026)
	_trail_ribbon(Vector2(-4, 33), Vector2(16, 29), 6.4, gravel, 0.026)
	_trail_ribbon(Vector2(16, 29), Vector2(40, 21), 6.0, gravel, 0.026)
	_trail_ribbon(Vector2(40, 21), Vector2(64, 15), 5.8, gravel, 0.026)
	box(Vector3(-11.0, 0.024, 35.5), Vector3(22.0, 0.04, 11.5), gravel, false)

	# Chapel Spur Road & Dirt Parking Lot
	_trail_ribbon(Vector2(12, 29), Vector2(18, 6), 5.2, gravel, 0.024)
	_trail_ribbon(Vector2(18, 6), Vector2(20, -16), 5.4, gravel, 0.024)
	box(Vector3(20.0, 0.024, -22.5), Vector3(17.5, 0.04, 15.5), gravel, false)

	# Winding Dirt Woodland Trails
	_trail_ribbon(Vector2(-5, 33), Vector2(-9, 14), 4.6, dirt, 0.022)
	_trail_ribbon(Vector2(-9, 14), Vector2(-12, -4), 4.6, dirt, 0.022)
	_trail_ribbon(Vector2(-12, -4), Vector2(-12, -36), 4.6, dirt, 0.022)
	_trail_ribbon(Vector2(-56.5, -2), Vector2(-12, -4), 4.2, dirt, 0.022)
	_trail_ribbon(Vector2(-12, -4), Vector2(16, -20), 4.2, dirt, 0.022)
	_trail_ribbon(Vector2(-56.5, -34), Vector2(-12, -38), 4.6, dirt, 0.022)
	_trail_ribbon(Vector2(-8, -38), Vector2(22, -33), 4.2, dirt, 0.022)
	_trail_ribbon(Vector2(44, 19), Vector2(44, 2), 4.6, dirt, 0.022)
	_trail_ribbon(Vector2(26, -22), Vector2(36, -22), 4.4, dirt, 0.022)
	_trail_ribbon(Vector2(24, -34), Vector2(36, -34), 4.0, dirt, 0.022)
	_trail_ribbon(Vector2(-56.5, -58), Vector2(-56.5, 58), 3.6, dirt, 0.022)
	tube(Vector3(-12.0, 0.014, -4.0), 8.2, 0.028, dirt)
	box(Vector3(34.0, 0.022, 33.0), Vector3(20.0, 0.04, 14.0), dirt, false)
	_cast_shadow = true


func creek() -> void:
	section("MillCreek")
	var stone := surface("#888b92", "sidewalk", 0.32)
	var moss_stone := surface("#66766a", "sidewalk", 0.30)
	var gravel := surface("#b6aca0", "dirt_trail", 0.24)

	_cast_shadow = false
	box(Vector3(-46.75, -3.05, 0.0), Vector3(8.8, 0.4, 128.0), stone)
	box(Vector3(-46.75, -2.55, 0.0), Vector3(8.5, 0.06, 128.0), surface("#5f9ca1", "water", 0.17), false)
	var water := add(part, Area3D.new(), "CreekWater") as Area3D
	water.collision_layer = 16
	water.collision_mask = 0
	water.monitoring = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.4, 0.88, 128.0)
	var hit := add(water, CollisionShape3D.new(), "Waterline") as CollisionShape3D
	hit.shape = shape
	hit.position = Vector3(-46.75, -2.70, 0.0)

	# Mossy rocky retaining banks along creek sides
	for z: float in [-50.0, -18.0, 14.0, 48.0]:
		box(Vector3(-51.1, -1.5, z), Vector3(0.45, 2.8, 18.0), moss_stone, false)
	for z: float in [-50.0, 48.0]:
		box(Vector3(-42.4, -1.5, z), Vector3(0.45, 2.8, 20.0), moss_stone, false)
	_cast_shadow = true

	# Two stone/timber Culvert Crossings (North Z = -34, South Z = +32)
	for z: float in [-34.0, 32.0]:
		box(Vector3(-46.75, -0.15, z), Vector3(9.0, 0.36, 7.8), stone)
		_cast_shadow = false
		box(Vector3(-46.75, 0.035, z), Vector3(9.0, 0.04, 6.2), gravel, false)
		_cast_shadow = true
		for s: float in [-1.0, 1.0]:
			box(Vector3(-46.75, 0.42, z + s * 3.72), Vector3(9.0, 0.78, 0.34), moss_stone)
			for x: float in [-49.1, -44.4]:
				box(Vector3(x, -1.48, z + s * 3.75), Vector3(0.58, 2.65, 0.52), stone)
		shelter("Culvert", Vector3(-46.75, -1.58, z), Vector3(8.2, 2.42, 7.6))

	# Central Wooden Footbridge at Z = -2 + warm bridge lantern light
	prop("footbridge", Vector3(-46.75, 0.04, -2.0))
	lamp(Vector3(-42.5, 2.6, 0.0), "#ffbe74")

	# Two gentle East-bank maintenance ramps down into the creek bed (~11 deg slope)
	for ramp_z: float in [-18.0, 15.0]:
		var dir := -1.0 if ramp_z < 0.0 else 1.0
		box(Vector3(-44.6, -1.50, ramp_z), Vector3(3.8, 0.24, 14.8), stone, true, Vector3(-dir * 11.2, 0.0, 0.0))
		box(Vector3(-43.6, -0.14, ramp_z + dir * 7.2), Vector3(5.6, 0.30, 1.8), stone)

	# Distant Landmark: Municipal Water Tower on the west wooded rise
	prop("municipal_tank", Vector3(-56.5, 0.0, -47.0), 20.0)

	# Organic mossy boulders framing the creek banks and footbridge
	prop("rock_outcrop", Vector3(-41.2, -0.2, 3.2), 18.0)
	prop("rock_outcrop", Vector3(-52.6, -0.2, -7.0), -25.0)
	prop("rock_outcrop", Vector3(-52.4, -0.2, 9.5), 42.0)
	prop("rock_outcrop", Vector3(-41.0, -0.2, -44.0), -12.0)


func chapel_and_cemetery() -> void:
	section("WaysideGrounds")
	prop("wayside_chapel", Vector3(24.0, 0.0, -47.0), 0.0)
	prop("lowell_mausoleum", Vector3(47.0, 0.0, -4.0), 180.0)

	lamp(Vector3(24.0, 3.2, -35.2), "#ffc07a")
	lamp(Vector3(47.0, 3.6, -10.0), "#ffaa68")

	var timber := surface("#6a5446", "wood", 0.35)
	_cast_shadow = false
	for z: float in [-26.0, -21.0, -16.5]:
		box(Vector3(12.2, 0.14, z), Vector3(0.32, 0.28, 3.2), timber, false)
	_cast_shadow = true
	for x: float in [15.4, 18.6]:
		box(Vector3(x, 1.25, -31.5), Vector3(0.18, 2.5, 0.18), timber)
	box(Vector3(17.0, 1.85, -31.5), Vector3(3.8, 1.25, 0.18), paint("#3f4c4f"))
	label("WAYSIDE CHAPEL", Vector3(17.0, 2.02, -31.38), 0.36, "#f4d7ab")
	label("EST. 1891", Vector3(17.0, 1.56, -31.38), 0.26, "#d9b98c")

	# Old parked cars in the chapel dirt lot
	model("cars", "sedan", Vector3(14.5, 0.0, -25.8), 4.6, 82.0, true, "#8ea4ad")
	model("cars", "truck", Vector3(14.8, 0.0, -17.5), 5.0, 96.0, true, "#b38d6f")
	model("cars", "van", Vector3(26.5, 0.0, -14.8), 5.0, -15.0, true, "#9db3a6")

	var gravel := surface("#a9a2a8", "dirt_trail", 0.28)
	_cast_shadow = false
	box(Vector3(47.0, 0.022, -26.0), Vector3(3.0, 0.04, 34.0), gravel, false)
	_cast_shadow = true

	# Mossy Stone Walls surrounding the cemetery (with generous gates for kiting!)
	var stone_wall := surface("#777e78", "sidewalk", 0.32)
	var moss_cap := surface("#536852", "forest_floor", 0.36)
	var wall_runs: Array[Array] = [
		[Vector3(31.8, 0.65, -45.0), Vector3(0.65, 1.3, 13.0)],
		[Vector3(31.8, 0.65, -28.0), Vector3(0.65, 1.3, 5.2)],
		[Vector3(31.8, 0.65, -7.5), Vector3(0.65, 1.3, 21.0)],
		[Vector3(46.8, 0.65, -52.0), Vector3(29.5, 1.3, 0.65)],
		[Vector3(61.5, 0.65, -24.0), Vector3(0.65, 1.3, 56.0)],
		[Vector3(36.0, 0.65, 4.2), Vector3(8.5, 1.3, 0.65)],
		[Vector3(54.5, 0.65, 4.2), Vector3(14.0, 1.3, 0.65)],
	]
	for run: Array in wall_runs:
		var pos: Vector3 = run[0]
		var sz: Vector3 = run[1]
		box(pos, sz, stone_wall)
		_cast_shadow = false
		box(pos + Vector3(0.0, sz.y * 0.5 + 0.06, 0.0), Vector3(sz.x + 0.14, 0.14, sz.z + 0.14), moss_cap, false)
		_cast_shadow = true

	for pier: Vector3 in [
		Vector3(31.8, 0.0, -38.3), Vector3(31.8, 0.0, -30.7),
		Vector3(31.8, 0.0, -25.3), Vector3(31.8, 0.0, -18.2),
		Vector3(40.3, 0.0, 4.2), Vector3(47.6, 0.0, 4.2),
	]:
		_no_shadow_model("graveyard", "pillar-square", pier, 1.25)

	# Gravestones arranged along outer edges (keeping the ~26m center wide open for Cumulus!)
	var stones: Array[String] = ["gravestone-round", "gravestone-cross", "gravestone-wide", "gravestone-bevel", "gravestone-broken", "gravestone-roof"]
	for i: int in 6:
		var z := -46.0 + float(i) * 6.8
		_no_shadow_model("graveyard", stones[i % stones.size()], Vector3(34.6, 0.0, z), 1.4, float(i) * 4.0)
		_no_shadow_model("graveyard", stones[(i + 2) % stones.size()], Vector3(58.6, 0.0, z), 1.45, -float(i) * 5.0)
	for i: int in 4:
		_no_shadow_model("graveyard", stones[(i + 1) % stones.size()], Vector3(39.0 + float(i) * 5.2, 0.0, -49.2), 1.5, float(i - 2) * 6.0)

	_no_shadow_model("graveyard", "bench", Vector3(36.0, 0.0, -12.0), 2.8, 90.0)
	_no_shadow_model("graveyard", "bench", Vector3(55.5, 0.0, -18.0), 2.8, -90.0)
	_no_shadow_model("graveyard", "lightpost-single", Vector3(40.5, 0.0, -10.5), 1.6)
	for corner: Vector3 in [Vector3(34.5, 0.0, -49.5), Vector3(58.5, 0.0, -49.5), Vector3(58.5, 0.0, -1.0)]:
		model("graveyard", "pine-crooked", corner, 4.8, corner.x * 3.0, false)
		collider(corner + Vector3(0.0, 1.6, 0.0), Vector3(0.7, 3.2, 0.7))


func ranger_trailhead() -> void:
	section("RangerTrailhead")
	prop("ranger_station", Vector3(-14.0, 0.0, 45.0), 180.0)
	lamp(Vector3(-14.0, 3.1, 40.5), "#ffb86e")

	model("cars", "suv", Vector3(-24.5, 0.0, 41.5), 4.7, 16.0, true, "#6b8576")

	# Double-sided Wooden Trailhead Welcome Sign ("MAPLE HOLLOW / STATE FOREST")
	var timber := surface("#5f4c42", "wood", 0.35)
	for x: float in [2.2, 7.0]:
		box(Vector3(x, 1.55, 39.2), Vector3(0.24, 3.1, 0.24), timber)
	box(Vector3(4.6, 2.2, 39.2), Vector3(5.8, 1.95, 0.28), paint("#384a45"))
	box(Vector3(4.6, 3.25, 39.2), Vector3(6.2, 0.22, 0.56), surface("#6c584c", "wood"), false)
	# North face (facing trailhead & logging road)
	label("MAPLE HOLLOW", Vector3(4.6, 2.48, 39.02), 0.56, "#f5d7a6", 180.0)
	label("STATE FOREST", Vector3(4.6, 1.76, 39.02), 0.36, "#d4c39d", 180.0)
	# South face (readable from behind too!)
	label("MAPLE HOLLOW", Vector3(4.6, 2.48, 39.38), 0.56, "#f5d7a6", 0.0)
	label("STATE FOREST", Vector3(4.6, 1.76, 39.38), 0.36, "#d4c39d", 0.0)

	var rail_wood := surface("#775e4b", "wood", 0.36)
	_cast_shadow = false
	for i: int in 4:
		var x := -34.0 + float(i) * 3.6
		box(Vector3(x, 0.55, 36.8), Vector3(0.18, 1.1, 0.18), rail_wood, false)
	box(Vector3(-28.6, 0.85, 36.8), Vector3(11.0, 0.12, 0.12), rail_wood, false)
	box(Vector3(-28.6, 0.42, 36.8), Vector3(11.0, 0.12, 0.12), rail_wood, false)
	_cast_shadow = true
	collider(Vector3(-28.6, 0.55, 36.8), Vector3(11.2, 1.1, 0.28))

	for rx: float in [-62.0, 62.0]:
		var rz := 32.0 if rx < 0.0 else 15.0
		_no_shadow_model("roads", "construction-barrier", Vector3(rx, 0.05, rz - 1.5), 3.6, 88.0)
		_no_shadow_model("roads", "construction-barrier", Vector3(rx, 0.05, rz + 1.8), 3.6, 94.0)


func tower_clearing() -> void:
	section("FireTowerClearing")
	prop("fire_tower", Vector3(-12.0, 0.0, -4.0), 12.0)
	lamp(Vector3(-12.0, 3.1, -4.0), "#ffbc72")

	var post := paint("#5b493f")
	box(Vector3(-4.8, 1.25, 2.2), Vector3(0.18, 2.5, 0.18), post)
	box(Vector3(-4.2, 2.15, 2.2), Vector3(1.5, 0.28, 0.08), post, false, Vector3(0.0, -25.0, 0.0))
	box(Vector3(-5.4, 1.78, 2.2), Vector3(1.5, 0.28, 0.08), post, false, Vector3(0.0, 15.0, 0.0))

	prop("rock_outcrop", Vector3(-21.0, 0.0, -10.5), 25.0)
	prop("rock_outcrop", Vector3(-2.5, 0.0, -12.5), -40.0)
	prop("fallen_log", Vector3(-19.5, 0.0, 4.5), 28.0)
	prop("fallen_log", Vector3(-1.0, 0.0, 6.0), -22.0)


func campground_and_cabins() -> void:
	section("Campground")
	prop("camp_shelter", Vector3(-12.0, 0.0, -38.0), 0.0)
	lamp(Vector3(-12.0, 3.0, -38.0), "#ffbe76")

	prop("lean_to", Vector3(-28.0, 0.0, -46.0), 40.0)
	prop("lean_to", Vector3(-30.0, 0.0, 12.0), 95.0)

	prop("woodland_cabin", Vector3(2.0, 0.0, -51.0), 8.0)
	prop("woodland_cabin", Vector3(-28.0, 0.0, 21.0), 172.0)

	# Stone Campfire Ring with glowing embers & log benches at (-4, -30)
	var stone := surface("#777a80", "sidewalk", 0.35)
	var bark := surface("#5b463b", "wood", 0.42)
	_cast_shadow = false
	for i: int in 10:
		var a := float(i) * TAU / 10.0
		box(Vector3(-4.0 + cos(a) * 1.15, 0.18, -30.0 + sin(a) * 1.15), Vector3(0.42, 0.36, 0.38), stone, false, Vector3(0.0, rad_to_deg(-a), 0.0))
	tube(Vector3(-4.0, 0.12, -30.0), 0.72, 0.20, lit("#f0743d"))
	box(Vector3(-4.0, 0.22, -30.0), Vector3(0.95, 0.18, 0.18), paint("#332a28"), false, Vector3(0.0, 30.0, 0.0))
	box(Vector3(-4.0, 0.24, -30.0), Vector3(0.95, 0.18, 0.18), paint("#332a28"), false, Vector3(0.0, -40.0, 0.0))
	collider(Vector3(-4.0, 0.25, -30.0), Vector3(2.3, 0.5, 2.3), Vector3.ZERO, true)
	tube(Vector3(-4.0, 0.26, -26.8), 0.24, 2.8, bark, 1.0, false, Vector3(0.0, 0.0, 90.0))
	collider(Vector3(-4.0, 0.26, -26.8), Vector3(2.8, 0.52, 0.52))
	tube(Vector3(-0.8, 0.26, -30.0), 0.24, 2.6, bark, 1.0, false, Vector3(90.0, 0.0, 0.0))
	collider(Vector3(-0.8, 0.26, -30.0), Vector3(0.52, 0.52, 2.6))
	_cast_shadow = true


func logging_yard() -> void:
	section("LoggingYard")
	prop("logging_shed", Vector3(34.0, 0.0, 35.0), -18.0)
	lamp(Vector3(32.5, 3.0, 33.5), "#ffb86c")

	model("cars", "tractor", Vector3(45.5, 0.0, 31.0), 4.6, -42.0, true, "#c28658")
	var bark := surface("#5b463b", "wood", 0.42)
	for pile_pos: Vector3 in [Vector3(23.5, 0.0, 38.5), Vector3(41.5, 0.0, 23.0)]:
		for row: int in 3:
			var count := 4 - row
			for col: int in count:
				var off := (float(col) - float(count - 1) * 0.5) * 0.56
				tube(pile_pos + Vector3(0.0, 0.28 + float(row) * 0.46, off), 0.26, 4.2, bark, 0.96, false, Vector3(0.0, 0.0, 90.0))
		collider(pile_pos + Vector3(0.0, 0.68, 0.0), Vector3(4.2, 1.36, 2.3))

	# Scattered fallen logs & rocky outcrops in the woods (great tactical cover!)
	prop("fallen_log", Vector3(26.0, 0.0, 10.0), 34.0)
	prop("fallen_log", Vector3(10.0, 0.0, 17.0), -18.0)
	prop("fallen_log", Vector3(28.0, 0.0, -5.0), 75.0)
	prop("fallen_log", Vector3(5.0, 0.0, -28.0), 12.0)
	prop("fallen_log", Vector3(-22.0, 0.0, -26.0), -35.0)
	prop("fallen_log", Vector3(-36.0, 0.0, -14.0), 62.0)
	prop("fallen_log", Vector3(14.0, 0.0, 47.0), -8.0)
	prop("fallen_log", Vector3(-36.0, 0.0, 44.0), 40.0)

	prop("rock_outcrop", Vector3(12.0, 0.0, -4.0), 15.0)
	prop("rock_outcrop", Vector3(32.0, 0.0, 18.0), -30.0)
	prop("rock_outcrop", Vector3(-18.0, 0.0, 16.0), 50.0)
	prop("rock_outcrop", Vector3(-36.0, 0.0, -24.0), -15.0)
	prop("rock_outcrop", Vector3(4.0, 0.0, -42.0), 72.0)
	prop("rock_outcrop", Vector3(52.0, 0.0, 44.0), -55.0)


func _add_batched_pine(p: Vector3, h: float, bark: Material, crown: Material, with_collider: bool) -> void:
	tube(p + Vector3(0.0, h * 0.22, 0.0), 0.26, h * 0.44, bark, 0.65)
	tube(p + Vector3(0.0, h * 0.44, 0.0), h * 0.29, h * 0.42, crown, 0.16)
	tube(p + Vector3(0.0, h * 0.68, 0.0), h * 0.23, h * 0.38, crown, 0.14)
	tube(p + Vector3(0.0, h * 0.88, 0.0), h * 0.15, h * 0.30, crown, 0.03)
	if with_collider:
		collider(p + Vector3(0.0, 1.8, 0.0), Vector3(0.72, 3.6, 0.72), Vector3.ZERO, true)


func _add_batched_oak(p: Vector3, h: float, bark: Material, crown: Material, yaw_rad: float, with_collider: bool) -> void:
	tube(p + Vector3(0.0, h * 0.24, 0.0), 0.36, h * 0.48, bark, 0.68)
	tube(p + Vector3(0.0, h * 0.68, 0.0), h * 0.30, h * 0.36, crown, 0.55)
	for k: int in 3:
		var a := yaw_rad + float(k) * TAU / 3.0
		var off := Vector3(cos(a) * h * 0.17, h * (0.56 + 0.05 * float(k)), sin(a) * h * 0.17)
		tube(p + off, h * 0.20, h * 0.28, crown, 0.62)
	if with_collider:
		collider(p + Vector3(0.0, 1.8, 0.0), Vector3(0.84, 3.6, 0.84), Vector3.ZERO, true)


func _add_fern(p: Vector3, scale_f: float, mat: Material, yaw_deg: float) -> void:
	for k: int in 3:
		var yaw := yaw_deg + float(k) * 60.0
		var rad := deg_to_rad(yaw)
		var dir := Vector3(sin(rad), 0.0, cos(rad))
		box(p + Vector3(0.0, 0.28 * scale_f, 0.0) + dir * (0.26 * scale_f),
			Vector3(0.24 * scale_f, 0.04, 0.95 * scale_f), mat, false, Vector3(-28.0, yaw, 0.0))


func forest_trees_and_undergrowth() -> void:
	var bark := surface("#4c3e3a", "wood", 0.45)
	# 2 pine shades + 2 oak shades + 1 fern shade = only 6 merged draw calls per quadrant!
	var pine_mats: Array[Material] = [
		foliage("#263d41", 0.7),
		foliage("#2f4943", 0.7),
	]
	var oak_mats: Array[Material] = [
		foliage("#3f503f", 0.8),
		foliage("#524d3f", 0.8),
	]
	var fern_mat := foliage("#3e5f45", 4.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 19871031
	var placed: Array[Vector2] = []

	var quad_names: Array[String] = ["ForestNW", "ForestNE", "ForestSW", "ForestSE"]
	var quad_trees: Array[Array] = [[], [], [], []]
	var quad_ferns: Array[Array] = [[], [], [], []]

	for gx: int in range(-60, 61, 6):
		for gz: int in range(-60, 61, 6):
			var px := float(gx) + rng.randf_range(-2.3, 2.3)
			var pz := float(gz) + rng.randf_range(-2.3, 2.3)
			var p2 := Vector2(px, pz)
			if absf(px) > 61.5 or absf(pz) > 61.5:
				continue
			if not _is_clear_for_tree(p2, 1.4):
				continue
			var too_close := false
			for other: Vector2 in placed:
				if p2.distance_squared_to(other) < 17.5:
					too_close = true
					break
			if too_close:
				continue
			placed.append(p2)
			var qi := (1 if px >= 0.0 else 0) + (2 if pz >= 0.0 else 0)
			var roll := rng.randf()
			var h := rng.randf_range(7.2, 12.2)
			quad_trees[qi].append([p2, h, roll, rng.randf() * TAU])

	for i: int in 140:
		var fx := rng.randf_range(-60.0, 60.0)
		var fz := rng.randf_range(-60.0, 60.0)
		var fp := Vector2(fx, fz)
		if fx > -51.5 and fx < -41.5:
			continue
		if _is_clear_for_tree(fp, -1.2):
			var qi := (1 if fx >= 0.0 else 0) + (2 if fz >= 0.0 else 0)
			quad_ferns[qi].append([fp, rng.randf_range(0.75, 1.35), rng.randf_range(0.0, 180.0)])

	for qi: int in 4:
		section(quad_names[qi])
		var t_list: Array = quad_trees[qi]
		for idx: int in t_list.size():
			var item: Array = t_list[idx]
			var p2: Vector2 = item[0]
			var h: float = item[1]
			var roll: float = item[2]
			var yaw_r: float = item[3]
			var p3 := Vector3(p2.x, 0.0, p2.y)
			if roll < 0.72:
				_add_batched_pine(p3, h, bark, pine_mats[idx % pine_mats.size()], true)
			else:
				_add_batched_oak(p3, h * 0.78, bark, oak_mats[idx % oak_mats.size()], yaw_r, true)
		_cast_shadow = false
		var f_list: Array = quad_ferns[qi]
		for f_item: Array in f_list:
			var fp: Vector2 = f_item[0]
			var fscale: float = f_item[1]
			var fyaw: float = f_item[2]
			_add_fern(Vector3(fp.x, 0.02, fp.y), fscale, fern_mat, fyaw)
		_cast_shadow = true

	# Warm autumn October Maples as landmark accents ("Maple Hollow"!)
	section("AutumnMaples")
	var maple_spots: Array[Vector2] = [
		Vector2(8.0, -34.0),
		Vector2(31.0, -49.0),
		Vector2(10.0, -14.0),
		Vector2(-3.0, 23.0),
		Vector2(-22.0, -34.0),
		Vector2(-24.0, 2.0),
		Vector2(26.0, 24.0),
		Vector2(50.0, 12.0),
		Vector2(-56.0, 22.0),
		Vector2(-56.0, -24.0),
	]
	for mp: Vector2 in maple_spots:
		prop("october_maple", Vector3(mp.x, 0.0, mp.y), mp.x * 5.0 + mp.y * 3.0)


func fog_pockets() -> void:
	# Soft radial-feathered twilight ground mist pockets (zero hard rectangle edges!).
	# Single shared ShaderMaterial merged into 1 draw call!
	section("FogPockets")
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 mist_color : source_color = vec4(0.38, 0.52, 0.62, 0.19);

void fragment() {
	vec2 d = UV * 2.0 - vec2(1.0);
	float r = length(d);
	float soft = smoothstep(1.0, 0.15, r);
	ALBEDO = mist_color.rgb;
	ALPHA = mist_color.a * soft * soft;
}
"""
	var mist_mat := ShaderMaterial.new()
	mist_mat.shader = shader

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y

	var pockets: Array[Array] = [
		# Mill Creek mist blankets
		[Vector3(-46.75, -1.85, -48.0), Vector2(11.0, 24.0)],
		[Vector3(-46.75, -1.85, -16.0), Vector2(11.0, 24.0)],
		[Vector3(-46.75, -1.85, 16.0), Vector2(11.0, 24.0)],
		[Vector3(-46.75, -1.85, 48.0), Vector2(11.0, 24.0)],
		# Low forest hollow & churchyard mist patches
		[Vector3(46.0, 0.22, -26.0), Vector2(24.0, 26.0)],
		[Vector3(-12.0, 0.20, -38.0), Vector2(20.0, 16.0)],
		[Vector3(-12.0, 0.18, -4.0), Vector2(16.0, 16.0)],
		[Vector3(34.0, 0.20, 32.0), Vector2(18.0, 14.0)],
	]
	var st := SurfaceTool.new()
	for p: Array in pockets:
		var pos: Vector3 = p[0]
		var sz: Vector2 = p[1]
		st.append_from(quad, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(sz.x, 1.0, sz.y)), pos))
		st.append_from(quad, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(sz.x * 0.72, 1.0, sz.y * 0.72)), pos + Vector3(0.0, 0.28, 0.0)))
	var mi := add(part, MeshInstance3D.new(), "MistLayers") as MeshInstance3D
	mi.mesh = st.commit()
	mi.material_override = mist_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_pine_multimesh_asset(bark: Material, crown: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.radial_segments = 6
	trunk_cyl.rings = 0
	trunk_cyl.height = 4.2
	trunk_cyl.bottom_radius = 0.28
	trunk_cyl.top_radius = 0.16

	var st_bark := SurfaceTool.new()
	st_bark.append_from(trunk_cyl, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.1, 0.0)))
	st_bark.commit(mesh)
	mesh.surface_set_material(0, bark)

	var st_crown := SurfaceTool.new()
	var cone1 := CylinderMesh.new()
	cone1.radial_segments = 7
	cone1.rings = 0
	cone1.height = 4.5
	cone1.bottom_radius = 2.6
	cone1.top_radius = 0.38
	st_crown.append_from(cone1, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 4.6, 0.0)))

	var cone2 := CylinderMesh.new()
	cone2.radial_segments = 7
	cone2.rings = 0
	cone2.height = 4.0
	cone2.bottom_radius = 2.0
	cone2.top_radius = 0.08
	st_crown.append_from(cone2, 0, Transform3D(Basis.IDENTITY, Vector3(0.0, 7.6, 0.0)))
	st_crown.commit(mesh)
	mesh.surface_set_material(1, crown)
	return mesh


func _add_multimesh_trees(title: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = mesh
	var buf := PackedFloat32Array()
	buf.resize(transforms.size() * 12)
	for i: int in transforms.size():
		var xf: Transform3D = transforms[i]
		var o := i * 12
		buf[o + 0] = xf.basis.x.x
		buf[o + 1] = xf.basis.y.x
		buf[o + 2] = xf.basis.z.x
		buf[o + 3] = xf.origin.x
		buf[o + 4] = xf.basis.x.y
		buf[o + 5] = xf.basis.y.y
		buf[o + 6] = xf.basis.z.y
		buf[o + 7] = xf.origin.y
		buf[o + 8] = xf.basis.x.z
		buf[o + 9] = xf.basis.y.z
		buf[o + 10] = xf.basis.z.z
		buf[o + 11] = xf.origin.z
	mm.buffer = buf
	var mmi := add(part, MultiMeshInstance3D.new(), title) as MultiMeshInstance3D
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func outlying_forest() -> void:
	section("OutlyingWoodland")
	_cast_shadow = false
	var verge := surface("#7a8574", "forest_floor", 0.14)
	var gravel := surface("#a49b90", "dirt_trail", 0.20)
	for side: int in [-1, 1]:
		box(Vector3(float(side) * 124.0, -0.16, 0.0), Vector3(120.0, 0.3, 128.0), verge, false)
		for span: Vector2 in [Vector2(-184.0, -51.0), Vector2(-42.5, 184.0)]:
			box(Vector3((span.x + span.y) * 0.5, -0.16, float(side) * 125.0), Vector3(span.y - span.x, 0.3, 122.0), verge, false)
		box(Vector3(-46.75, -2.55, float(side) * 125.0), Vector3(8.5, 0.12, 122.0), surface("#5f9ca1", "water", 0.17), false)
	box(Vector3(-109.0, 0.02, 32.0), Vector3(90.0, 0.05, 6.4), gravel, false)
	box(Vector3(109.0, 0.02, 15.0), Vector3(90.0, 0.05, 6.0), gravel, false)
	_cast_shadow = true

	var bark := paint("#463936")
	var pine_a := _build_pine_multimesh_asset(bark, paint("#24393e"))
	var pine_b := _build_pine_multimesh_asset(bark, paint("#2f4742"))
	var transforms_a: Array[Transform3D] = []
	var transforms_b: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654

	for i: int in 260:
		var a := float(i) * 2.39996
		var direction := Vector3(cos(a), 0.0, sin(a))
		var dist := 68.0 + fmod(float(i) * 7.31, 46.0)
		var p := direction * dist / maxf(absf(direction.x), absf(direction.z))
		if p.x < -62.0 and absf(p.z - 32.0) < 5.5:
			continue
		if p.x > 62.0 and absf(p.z - 15.0) < 5.5:
			continue
		if absf(p.x + 46.75) < 5.2:
			continue
		var s := rng.randf_range(0.85, 1.55)
		var sy := s * rng.randf_range(0.95, 1.35)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, sy, s))
		var xf := Transform3D(b, p)
		if i % 2 == 0:
			transforms_a.append(xf)
		else:
			transforms_b.append(xf)

	_add_multimesh_trees("BackgroundPinesDark", pine_a, transforms_a)
	_add_multimesh_trees("BackgroundPinesSpruce", pine_b, transforms_b)


# ==============================================================================
# GAMEPLAY MARKERS & GROUP CONTRACT
# ==============================================================================

func markers() -> void:
	points("PlayerSpawns", "player_spawn", [
		Vector2(-5.2, 35.0),
		Vector2(-2.8, 35.0),
		Vector2(-5.2, 37.4),
		Vector2(-2.8, 37.4),
	])

	# 14 perimeter enemy spawns (all verified clear of obstacles & gravestones!)
	points("EnemySpawns", "enemy_spawn", [
		Vector2(-60.0, 52.0),
		Vector2(-60.0, 12.0),
		Vector2(-60.0, -22.0),
		Vector2(-59.0, -58.0),
		Vector2(-36.0, -59.0),
		Vector2(-10.0, -59.0),
		Vector2(14.0, -59.0),
		Vector2(46.0, -58.0),
		Vector2(56.0, -34.0),
		Vector2(58.5, 1.0),
		Vector2(59.0, 28.0),
		Vector2(55.0, 54.0),
		Vector2(18.0, 57.0),
		Vector2(-36.0, 56.0),
	])

	points("CrateSpawns", "crate_spawn", [
		Vector2(-56.0, 20.0),
		Vector2(-56.0, -16.0),
		Vector2(-30.0, -26.0),
		Vector2(-12.0, -24.0),
		Vector2(-2.0, -42.0),
		Vector2(21.0, -22.0),
		Vector2(46.0, -34.0),
		Vector2(46.0, -16.0),
		Vector2(34.0, 12.0),
		Vector2(20.0, 28.0),
		Vector2(-4.0, 14.0),
		Vector2(-22.0, -2.0),
	])

	_cast_shadow = false
	drain(Vector3(-39.0, 0.06, -34.0))
	drain(Vector3(-39.0, 0.06, -2.0))
	drain(Vector3(-39.0, 0.06, 30.0))
	drain(Vector3(-46.75, -2.76, -28.0))
	drain(Vector3(-46.75, -2.76, 5.5))
	drain(Vector3(18.5, 0.06, -15.5))
	drain(Vector3(4.5, 0.06, 28.0))
	drain(Vector3(38.0, 0.06, 17.5))
	_cast_shadow = true

	shower("RangerDecon", Vector3(-21.0, 0.0, 38.5))
	shower("CampgroundDecon", Vector3(-19.5, 0.0, -35.0))
	shower("ChapelDecon", Vector3(28.5, 0.0, -35.8))

	# 3 Crate Stations (Chapel Steps, Ranger Station, Campground)
	directories["CrateStations"] = add(scene, Node3D.new(), "CrateStations")
	marker("CrateStations", "crate_station", "ChapelSteps", Vector3(24.0, 0.08, -33.2))
	marker("CrateStations", "crate_station", "RangerStation", Vector3(-14.0, 0.08, 37.8))
	marker("CrateStations", "crate_station", "Campground", Vector3(-6.0, 0.08, -37.0))

	# 4 Street Supply Spawns at main woodland junctions
	directories["StreetSupplySpawns"] = add(scene, Node3D.new(), "StreetSupplySpawns")
	marker("StreetSupplySpawns", "street_supply_spawn", "TrailheadJunction", Vector3(6.0, 0.08, 31.5))
	marker("StreetSupplySpawns", "street_supply_spawn", "TowerClearing", Vector3(-5.0, 0.08, -4.0))
	marker("StreetSupplySpawns", "street_supply_spawn", "ChapelLot", Vector3(19.0, 0.08, -24.0))
	marker("StreetSupplySpawns", "street_supply_spawn", "CampgroundEdge", Vector3(-18.0, 0.08, -30.0))

	# Boss anchor over the open ~30m cemetery arena at hover height y = 18
	marker("", "boss_anchor", "BossAnchor", Vector3(46.0, 18.0, -26.0))

	puddles([
		Vector3(-37.0, 2.5, 32.0),
		Vector3(-24.0, 2.2, 33.0),
		Vector3(8.0, 2.4, 30.0),
		Vector3(28.0, 2.4, 24.0),
		Vector3(44.0, 2.2, 16.0),
		Vector3(-9.0, 2.2, 16.0),
		Vector3(-11.0, 2.0, -18.0),
		Vector3(-26.0, 2.2, -34.0),
		Vector3(-37.0, 2.4, -34.0),
		Vector3(-56.5, 2.0, -14.0),
		Vector3(-56.5, 2.0, 14.0),
		Vector3(-28.0, 2.2, -3.0),
		Vector3(19.0, 2.6, -20.0),
		Vector3(39.0, 2.8, -28.0),
		Vector3(53.0, 2.5, -36.0),
		Vector3(17.0, 2.2, 8.0),
	])
