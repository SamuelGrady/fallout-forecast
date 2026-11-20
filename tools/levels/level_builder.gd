extends SceneTree
## Shared, editor-independent authoring tools. Run either build_*.gd with
## Godot --headless --path . -s res://tools/levels/build_<district>.gd.

const FONT = preload("res://assets/fonts/VT323-Regular.ttf")
var scene: Node3D
var geometry: Node3D
var part: Node3D
var district: String
var materials := {}
var meshes := {}
var shapes := {}
var batches := {}
var bodies := {}
var directories := {}
var props := {}


func _initialize() -> void:
	build.call_deferred()


func build() -> void:
	pass


func add(parent: Node, child: Node, title: String) -> Node:
	child.name = title
	parent.add_child(child, true)
	child.owner = scene
	return child


func section(title: String, parent: Node3D = null) -> Node3D:
	part = add(parent if parent else geometry, Node3D.new(), title) as Node3D
	return part


func start_scene(title: String) -> void:
	scene = Node3D.new()
	scene.name = title
	part = scene
	batches.clear()
	bodies.clear()
	directories.clear()


func surface(tint: String, texture := "", tile := 0.25, glow := false) -> StandardMaterial3D:
	var key := "%s/%s/%s/%s" % [tint, texture, tile, glow]
	if materials.has(key):
		return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint)
	if texture:
		m.albedo_texture = load("res://assets/textures/%s.png" % texture)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * tile
	if glow:
		m.emission_enabled = true
		m.emission = Color(tint)
		m.emission_energy_multiplier = 0.65
	materials[key] = m
	return m


func paint(color: String) -> Material:
	return surface(color)


func lit(color: String) -> Material:
	return surface(color, "", 1, true)


func primitive(kind: String) -> PrimitiveMesh:
	if not meshes.has(kind):
		if kind == "Box":
			meshes[kind] = BoxMesh.new()
		else:
			var tube := CylinderMesh.new()
			tube.radial_segments = 12
			tube.rings = 0
			tube.height = 1
			tube.bottom_radius = 0.5
			tube.top_radius = float(kind)
			meshes[kind] = tube
	return meshes[kind]


func add_visual(kind: String, center: Vector3, size: Vector3, material: Material, rot: Vector3) -> void:
	# Batch repeated details locally. One crane's lattice or one block's pickets
	# share one draw call per finish and still cull with their own district.
	if not batches.has(part):
		batches[part] = {}
	var key := "%s_%s" % [kind, material.get_instance_id()]
	if not batches[part].has(key):
		batches[part][key] = [primitive(kind), material, []]
	var basis := Basis.from_euler(rot * PI / 180.0).scaled_local(size)
	batches[part][key][2].append(Transform3D(basis, center))


func collider(center: Vector3, size: Vector3, rot := Vector3.ZERO, round_base := false) -> void:
	if not bodies.has(part):
		bodies[part] = add(part, StaticBody3D.new(), "WorldCollision")
	var key := str(size) + str(round_base)
	if not shapes.has(key):
		if round_base:
			var cyl := CylinderShape3D.new()
			cyl.radius = size.x * 0.5
			cyl.height = size.y
			shapes[key] = cyl
		else:
			var shape := BoxShape3D.new()
			shape.size = size
			shapes[key] = shape
	var hit := add(bodies[part], CollisionShape3D.new(), "Hull") as CollisionShape3D
	hit.shape = shapes[key]
	hit.position = center
	hit.rotation_degrees = rot


func box(at: Vector3, size: Vector3, mat: Material, solid := true, rot := Vector3.ZERO) -> void:
	add_visual("Box", at, size, mat, rot)
	if solid:
		collider(at, size, rot)


func tube(at: Vector3, radius: float, height: float, mat: Material, top_ratio := 1.0, solid := false, rot := Vector3.ZERO) -> void:
	var size := Vector3(radius * 2, height, radius * 2)
	add_visual(str(top_ratio * 0.5), at, size, mat, rot)
	if solid:
		collider(at, size, rot, true)


func beam(a: Vector3, b: Vector3, width: float, mat: Material, solid := false) -> void:
	var rot := Basis(Quaternion(Vector3.UP, (b-a).normalized())).get_euler() * 180.0 / PI
	box((a+b)*0.5, Vector3(width, a.distance_to(b), width), mat, solid, rot)


func flush() -> void:
	for parent: Node3D in batches:
		for data: Array in batches[parent].values():
			var transforms: Array = data[2]
			if transforms.size() == 1:
				var single := add(parent, MeshInstance3D.new(), "Finish") as MeshInstance3D
				single.mesh = data[0]
				single.material_override = data[1]
				single.transform = transforms[0]
			else:
				# Write the vertex data itself: the dummy headless renderer
				# does not persist a MultiMesh's per-instance transforms.
				var batch := SurfaceTool.new()
				for xf: Transform3D in transforms:
					batch.append_from(data[0],0,xf)
				var merged := add(parent,MeshInstance3D.new(),"Finish") as MeshInstance3D
				merged.mesh = batch.commit()
				merged.material_override = data[1]
	batches.clear()


func label(words: String, at: Vector3, height: float, color: String, yaw := 0.0, wind := false) -> void:
	var sign := add(part, Label3D.new(), "Lettering") as Label3D
	sign.font = FONT
	sign.font_size = 80
	sign.pixel_size = height / 52.0
	sign.outline_size = 0
	sign.modulate = Color(color)
	sign.text = words
	sign.position = at
	sign.rotation_degrees.y = yaw
	sign.double_sided = false
	if wind:
		sign.add_to_group("wind_sway", true)


func shelter(title: String, center: Vector3, size: Vector3) -> void:
	var area := add(part, Area3D.new(), title) as Area3D
	area.add_to_group("shelter", true)
	area.position = center
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	var shape := BoxShape3D.new()
	shape.size = size
	var hit := add(area, CollisionShape3D.new(), "CollisionShape3D") as CollisionShape3D
	hit.shape = shape


func lamp(at: Vector3, tint: String) -> void:
	var light := add(part, OmniLight3D.new(), "Lamp") as OmniLight3D
	light.position = at
	light.light_color = Color(tint)
	light.light_energy = 2.2
	light.omni_range = 13
	light.distance_fade_enabled = true
	light.distance_fade_begin = 28
	light.distance_fade_length = 12


func save(path: String) -> PackedScene:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	if packed.pack(scene) != OK or ResourceSaver.save(packed, path) != OK:
		push_error("Could not save " + path)
		quit(1)
		return null
	return load(path) as PackedScene


func finish_prop(id: String, wind := false) -> void:
	flush()
	if wind:
		var visual := add(scene, Node3D.new(), "WindVisuals")
		visual.add_to_group("wind_sway", true)
		for child in scene.get_children():
			if child is MeshInstance3D:
				child.reparent(visual, false)
	props[id] = save("res://props/%s/%s.tscn" % [district, id])
	scene.free()


func prop(id: String, at: Vector3, yaw := 0.0) -> Node3D:
	var item := (props[id] as PackedScene).instantiate() as Node3D
	add(part, item, id.to_pascal_case())
	item.position = at
	item.rotation_degrees.y = yaw
	return item


func model(kit: String, id: String, at: Vector3, length: float, yaw := 0.0, block := true, tint := "") -> Node3D:
	# Fit against actual imported mesh bounds, including off-centre origins.
	var asset := load("res://assets/kenney/%s/%s.glb" % [kit, id]) as PackedScene
	var holder := add(part, Node3D.new(), id.to_pascal_case()) as Node3D
	var item := asset.instantiate() as Node3D
	if tint:
		item.set_script(load("res://props/model_style.gd"))
		item.set("texture",load("res://assets/kenney/%s/Textures/colormap.png" % kit))
		item.set("tint",Color(tint))
	add(holder, item, "Model")
	if id.begins_with("pine-") or id == "construction-barrier":
		item.add_to_group("wind_sway", true)
	var instances := item.find_children("*", "MeshInstance3D", true, false)
	if item is MeshInstance3D:
		instances.append(item)
	var bounds := AABB()
	for mi: MeshInstance3D in instances:
		var xf := Transform3D.IDENTITY
		var node: Node3D = mi
		while node != holder:
			xf = node.transform * xf
			node = node.get_parent_node_3d()
		var mesh_bounds: AABB = xf * mi.get_aabb()
		bounds = bounds.merge(mesh_bounds) if bounds.has_volume() else mesh_bounds
	var factor := length / maxf(bounds.size.x, bounds.size.z)
	var size := bounds.size * factor
	item.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	item.scale *= factor
	holder.position = at
	holder.rotation_degrees.y = yaw
	if block:
		collider(at + Vector3.UP * size.y * 0.5, size, Vector3(0,yaw,0))
	return holder


func begin_map(title: String, harbor: bool) -> void:
	start_scene(title)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#132f45" if harbor else "#29213c")
	sky_mat.sky_horizon_color = Color("#dd9467" if harbor else "#be779d")
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.darkened(0.25)
	sky_mat.ground_bottom_color = sky_mat.sky_top_color
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 15
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8faeb7" if harbor else "#a599b2")
	env.ambient_light_energy = 0.76
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	var world := add(scene, WorldEnvironment.new(), "WorldEnvironment") as WorldEnvironment
	world.environment = env
	var sun := add(scene, DirectionalLight3D.new(), "Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-19,-48,0)
	sun.light_color = Color("#ffb47c" if harbor else "#ffd1b8")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	geometry = add(scene, Node3D.new(), "Geometry") as Node3D
	geometry.add_to_group("navigation_geometry", true)
	part = geometry
	for title_key in ["PlayerSpawns","EnemySpawns","StormDrains","CrateSpawns","DeconShowers","Puddles","StreetSupplySpawns"]:
		directories[title_key] = add(scene, Node3D.new(), title_key)


func boundary() -> void:
	section("Bounds")
	for side: float in [-64,64]:
		collider(Vector3(side,8,0), Vector3(0.5,26,128))
		collider(Vector3(0,8,side), Vector3(128,26,0.5))


func marker(folder: String, group: String, title: String, at: Vector3) -> Marker3D:
	var parent: Node = directories[folder] if folder else scene
	var m := add(parent, Marker3D.new(), title) as Marker3D
	m.add_to_group(group,true)
	m.position = at
	return m


func points(folder: String, group: String, locations: Array, height := 0.08) -> void:
	for p: Vector2 in locations:
		marker(folder, group, group.to_pascal_case(), Vector3(p.x,height,p.y))


func drain(at: Vector3) -> void:
	var m := marker("StormDrains","drain_spawn","Grate",at)
	var old := part
	part = m
	box(Vector3(0,0.01,0),Vector3(1.5,0.035,0.85),paint("#27313b"),false)
	for n in 8:
		box(Vector3(n*0.17-0.595,0.036,0),Vector3(0.065,0.025,0.74),paint("#849390"),false)
	part = old


func shower(title: String, at: Vector3) -> void:
	var m := marker("DeconShowers","decon_shower",title,at)
	var metal := paint("#92b7ac")
	for spec: Array in [["Pipe",1.3,0.08,2.6,6],["Head",2.6,0.35,0.1,10],["Pad",0.025,0.7,0.05,12]]:
		var piece := add(m,CSGCylinder3D.new(),spec[0]) as CSGCylinder3D
		piece.position.y = spec[1]
		piece.radius = spec[2]
		piece.height = spec[3]
		piece.sides = spec[4]
		piece.material = metal
	var tag := add(m,Label3D.new(),"Label") as Label3D
	tag.position.y = 2.95
	tag.pixel_size = 0.01
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.2,1,0.9)
	tag.text = "DECON"
	tag.font_size = 64


func puddles(locations: Array) -> void:
	for p: Vector3 in locations: # x, maximum radius, z
		var area := add(directories.Puddles, Area3D.new(), "Pool") as Area3D
		area.position = Vector3(p.x,0.04,p.z)
		area.collision_layer = 16
		area.collision_mask = 0
		area.monitoring = false
		area.set_script(load("res://weather/puddle.gd"))
		area.set("max_radius",p.y)


func bake_map() -> void:
	flush()
	var region := add(scene,NavigationRegion3D.new(),"NavigationRegion3D") as NavigationRegion3D
	var nav := NavigationMesh.new()
	nav.agent_height = 1.75
	nav.agent_radius = 0.5
	nav.agent_max_slope = 30
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav.geometry_source_group_name = &"navigation_geometry"
	nav.geometry_collision_mask = 1
	nav.filter_baking_aabb = AABB(Vector3(-64,-4,-64),Vector3(128,32,128))
	region.navigation_mesh = nav
	root.add_child(scene)
	region.bake_navigation_mesh(false)
	if nav.get_polygon_count() == 0:
		push_error("Navigation bake produced no polygons")
		quit(1)
		return
	print(district, ": baked ", nav.get_polygon_count(), " polygons")
	save("res://levels/%s/level_%s.tscn" % [district,district])
	scene.free()
	quit()
