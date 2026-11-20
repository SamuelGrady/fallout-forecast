class_name WebMaterials
## Shader-variant diet for the web build (Compatibility renderer on WebGL2 /
## ANGLE -> D3D11). Every distinct BaseMaterial3D feature combination is its
## own shader program there, and each program compiles (per lighting variant)
## the first time it draws, which stalls slow PCs for seconds. Colours, values
## and textures don't pick the shader; modes, features and flags do (see
## `shader_key`, which mirrors BaseMaterial3D's MaterialKey).
##
## `normalize` rewrites a material's flags IN PLACE so the common families
## share one program each, using only changes that leave the pixels alone:
## - emission is switched on everywhere it's off, with a black colour (adds 0)
## - opaque materials get vertex colour where the mesh has no colour channel
##   (the renderer then feeds white, so albedo * white = albedo)
## - lit opaque cull-back becomes cull-disabled (closed meshes hide their
##   back faces behind the depth buffer anyway; Kenney models are already
##   double-sided)
## - texture filter on untextured materials, diffuse/specular models (forced
##   to vertex Lambert on web), per-vertex shading and alpha modes are folded
##   into one each
## - world-triplanar map surfaces take the level's majority filter
##
## Web only; desktop is unchanged. Debug: FALLOUT_WEB_MATERIALS=1 (or
## `-- --web-materials`) applies the pass on desktop to compare captures.

const _DONE := &"_web_mat_done"
const _VC_ADDED := &"_web_vc_added"
const _VC_FREE := &"_web_vc_free"

static var _installed := false
static var _enabled := -1
## Majority filter of textured world-triplanar map surfaces (-1 = keep).
static var _triplanar_filter := -1


static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if OS.has_feature("web") or OS.get_environment("FALLOUT_WEB_MATERIALS") == "1" \
				or "--web-materials" in OS.get_cmdline_user_args() else 0
	return _enabled == 1


## Debug: render desktop with the web look path of RetroScreen (no PS1 swap,
## web VHS overlay, web 3D scale) so captures can be compared with the pass.
static func emulate_web_look() -> bool:
	return OS.has_feature("web") or OS.get_environment("FALLOUT_WEB_LOOK") == "1"


## Mirrors BaseMaterial3D's MaterialKey: the fields that pick the generated
## shader. Two materials with the same key share one shader program.
static func shader_key(material: Material) -> String:
	if material == null:
		return "none"
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null:
			return "shader:null"
		return "shader:" + (shader.resource_path if not shader.resource_path.is_empty() else "code#%d" % shader.code.hash())
	if not (material is BaseMaterial3D):
		return material.get_class()
	var m := material as BaseMaterial3D
	var features := 0
	for i in BaseMaterial3D.FEATURE_MAX:
		if m.get_feature(i):
			features |= 1 << i
	var flags := 0
	for i in BaseMaterial3D.FLAG_MAX:
		if m.get_flag(i):
			flags |= 1 << i
	return "%s t%d s%d b%d dd%d c%d d%d sp%d bb%d tf%d aa%d du%d db%d eo%d df%d g%d pf%d dp%d dt%d st%d/%d/%d/%d f%x fl%x" % [
		"orm" if m is ORMMaterial3D else "std", m.transparency, m.shading_mode, m.blend_mode,
		m.depth_draw_mode, m.cull_mode, m.diffuse_mode, m.specular_mode, m.billboard_mode,
		m.texture_filter, m.alpha_antialiasing_mode, m.detail_uv_layer, m.detail_blend_mode,
		m.emission_operator, m.distance_fade_mode, int(m.grow), int(m.proximity_fade_enabled),
		int(m.heightmap_deep_parallax), m.depth_test, m.stencil_mode, m.stencil_flags,
		m.stencil_compare, m.stencil_reference, features, flags]


## Readable summary of the parts of a key that usually differ.
static func describe(material: Material) -> String:
	if not (material is BaseMaterial3D):
		return shader_key(material)
	var m := material as BaseMaterial3D
	var bits := PackedStringArray()
	bits.append(["opaque", "alpha", "scissor", "hash", "prepass"][m.transparency])
	bits.append(["unshaded", "lit", "vertexlit"][m.shading_mode])
	bits.append(["cull_back", "cull_front", "cull_off"][m.cull_mode])
	if m.blend_mode != BaseMaterial3D.BLEND_MODE_MIX: bits.append("blend%d" % m.blend_mode)
	if m.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY: bits.append("depthdraw%d" % m.depth_draw_mode)
	if m.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY: bits.append("diffuse%d" % m.diffuse_mode)
	if m.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX: bits.append("spec%d" % m.specular_mode)
	if m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: bits.append("billboard%d" % m.billboard_mode)
	if m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS: bits.append("filter%d" % m.texture_filter)
	if m.emission_enabled: bits.append("emission")
	if m.normal_enabled: bits.append("normalmap")
	if m.rim_enabled: bits.append("rim")
	if m.ao_enabled: bits.append("ao")
	if m.vertex_color_use_as_albedo: bits.append("vcolor")
	if m.vertex_color_is_srgb: bits.append("vcolor_srgb")
	if m.uv1_triplanar: bits.append("triplanar")
	if m.uv1_world_triplanar: bits.append("world_triplanar")
	if m.disable_fog: bits.append("nofog")
	if m.no_depth_test: bits.append("nodepth")
	if m.fixed_size: bits.append("fixedsize")
	if m.disable_receive_shadows: bits.append("noshadowrecv")
	if m.disable_ambient_light: bits.append("noambient")
	if not m.texture_repeat: bits.append("norepeat")
	if m.albedo_texture_force_srgb: bits.append("force_srgb")
	if m.grow: bits.append("grow")
	if m.billboard_keep_scale: bits.append("keepscale")
	if m.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED: bits.append("distfade")
	if m.disable_specular_occlusion: bits.append("nospecocc")
	if m is ORMMaterial3D: bits.append("orm")
	return " ".join(bits)


## Fold `material` into its family's common combination. `colorless` is true
## when every mesh surface drawing with it so far has no colour channel.
## Returns true if its shader changed. Each material is folded once.
static func normalize(material: Material, colorless := false) -> bool:
	if not (material is StandardMaterial3D) or material.has_meta(_DONE):
		return false
	var m := material as StandardMaterial3D
	m.set_meta(_DONE, true)
	var before := shader_key(m)
	# Web forces vertex shading and Lambert diffuse project-wide, so these
	# all compile to the same pixels.
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	if m.specular_mode == BaseMaterial3D.SPECULAR_TOON:
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH or m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if m.albedo_texture == null:
		# Filter and sRGB forcing only matter when something is sampled.
		m.albedo_texture_force_srgb = false
		if not m.uv1_triplanar:
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if m.uv1_triplanar and m.uv1_world_triplanar and _triplanar_filter >= 0:
		m.texture_filter = _triplanar_filter as BaseMaterial3D.TextureFilter
	elif m.albedo_texture != null and not m.uv1_triplanar and m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS \
			and _is_colormap(m.albedo_texture):
		# Kenney kits: flat palette cells, so nearest vs linear samples the
		# same colour. One filter for every kit.
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		# Lighting flags do nothing without lighting.
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.disable_receive_shadows = false
		m.disable_ambient_light = false
	else:
		# Black emission adds nothing; one program instead of two.
		if not m.emission_enabled:
			m.emission = Color.BLACK
			m.emission_energy_multiplier = 1.0
			m.emission_texture = null
			m.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
			m.emission_enabled = true
		# Closed opaque meshes hide back faces behind the depth buffer.
		if m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and m.cull_mode == BaseMaterial3D.CULL_BACK \
				and not m.uv1_triplanar and m.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and not m.grow:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Opaque only: that joins MeshMerge's vertex-coloured infected materials.
	# Transparent effects have no vertex-coloured twin to join.
	if colorless and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not m.vertex_color_use_as_albedo and not m.has_meta(_VC_FREE):
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.set_meta(_VC_ADDED, true)
	return shader_key(m) != before


static func _is_colormap(texture: Texture2D) -> bool:
	return texture.resource_path.get_file() == "colormap.png" or texture.resource_path.contains("/kenney/")


## Normalize every material a geometry node draws with.
static func normalize_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		var all_colorless := _colorless(mesh, -1)
		mi.material_override = _fold(mi.material_override, all_colorless)
		if mesh:
			for i in mesh.get_surface_count():
				var colorless := _colorless(mesh, i)
				var o := mi.get_surface_override_material(i)
				if o:
					mi.set_surface_override_material(i, _fold(o, colorless))
					continue
				var own := mesh.surface_get_material(i)
				if own:
					var folded := _fold(own, colorless)
					if folded != own:
						mi.set_surface_override_material(i, folded)
	elif node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		# Particles and multimeshes feed per-instance colour through COLOR.
		gi.material_override = _fold(gi.material_override, false)
		if node is CSGPrimitive3D:
			var csg := node as CSGPrimitive3D
			csg.material = _fold(csg.material, true)
		elif node is CPUParticles3D and (node as CPUParticles3D).mesh:
			var pm := (node as CPUParticles3D).mesh
			for i in pm.get_surface_count():
				_fold(pm.surface_get_material(i), false)
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh and (node as MultiMeshInstance3D).multimesh.mesh:
			var mm := (node as MultiMeshInstance3D).multimesh.mesh
			for i in mm.get_surface_count():
				_fold(mm.surface_get_material(i), false)


## Normalize a material (and its next passes). If it was already given
## vertex colour but this mesh has colours of its own, hand back a copy
## without it so the mesh keeps its look.
static func _fold(material: Material, colorless: bool) -> Material:
	if material == null:
		return null
	var m := material
	if not colorless and m is StandardMaterial3D:
		if m.has_meta(_VC_ADDED):
			if not m.has_meta(&"_web_vc_copy"):
				var copy := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				copy.vertex_color_use_as_albedo = false
				copy.vertex_color_is_srgb = false
				copy.remove_meta(_VC_ADDED)
				copy.set_meta(_VC_FREE, true)
				m.set_meta(&"_web_vc_copy", copy)
			return m.get_meta(&"_web_vc_copy")
		if not m.has_meta(_DONE):
			m.set_meta(_VC_FREE, true)
	normalize(m, colorless)
	var pass_material := m.next_pass
	var guard := 0
	while pass_material and guard < 4:
		normalize(pass_material, colorless)
		pass_material = pass_material.next_pass
		guard += 1
	return m


## True if `surface` (or every surface for -1) of `mesh` has no colour.
static func _colorless(mesh: Mesh, surface: int) -> bool:
	if mesh == null:
		return true
	if mesh is PrimitiveMesh:
		return true
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		if surface >= 0:
			return surface < am.get_surface_count() and not (am.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR)
		for i in am.get_surface_count():
			if am.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR:
				return false
		return true
	return false


## Fold a level (in or out of the tree). Picks the triplanar filter first.
static func apply_tree(root: Node) -> void:
	if not enabled() or root == null:
		return
	var nodes := root.find_children("*", "GeometryInstance3D", true, false)
	if _triplanar_filter < 0:
		var votes := {}
		for node in nodes:
			var used: Array[Material] = []
			if node is CSGPrimitive3D and _shown(node, root):
				used.append((node as CSGPrimitive3D).material)
			elif node is MeshInstance3D and (node as MeshInstance3D).mesh:
				var mi := node as MeshInstance3D
				for i in mi.mesh.get_surface_count():
					used.append(mi.get_active_material(i))
			for material in used:
				var m := material as BaseMaterial3D
				if m and m.uv1_triplanar and m.uv1_world_triplanar and m.albedo_texture:
					votes[m.texture_filter] = int(votes.get(m.texture_filter, 0)) + 1
		var best := -1
		for f in votes:
			if best < 0 or int(votes[f]) > int(votes[best]):
				best = f
		_triplanar_filter = best
	for node in nodes:
		normalize_node(node)
	for node in root.find_children("*", "Label3D", true, false):
		normalize_label(node as Label3D)


## Visible up to `root` (works before the level enters the tree).
static func _shown(node: Node, root: Node) -> bool:
	var n := node
	while n and n != root:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## Label3D builds its own material from these flags. Wall lettering defaults
## to double-sided (Godot's default); the back side faces into the wall.
static func normalize_label(label: Label3D) -> void:
	if label and label.billboard == BaseMaterial3D.BILLBOARD_DISABLED and not label.no_depth_test and not label.double_sided:
		label.double_sided = true


## Forget the level's triplanar choice (a new run picks again).
static func reset_level() -> void:
	_triplanar_filter = -1


## Normalize everything that enters the tree from now on (once per process).
static func install(tree: SceneTree) -> void:
	if _installed or not enabled() or tree == null:
		return
	_installed = true
	tree.node_added.connect(_on_node_added)


static func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		# Materials are often assigned right after add_child: fold now (for a
		# same-frame draw) and again at the end of the frame.
		normalize_node(node)
		if node is Label3D:
			normalize_label(node as Label3D)
		_late.call_deferred(node.get_instance_id())


static func _late(id: int) -> void:
	var node := instance_from_id(id) as Node
	if is_instance_valid(node):
		normalize_node(node)
		if node is Label3D:
			normalize_label(node as Label3D)
