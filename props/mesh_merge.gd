class_name MeshMerge
## Folds a node's direct MeshInstance3D children (box/primitive pieces with a
## solid StandardMaterial3D colour) into ONE MeshInstance3D with vertex colours
## and at most two shared materials (lit, and glowing). Built for the infected:
## ~40 draw calls per enemy became ~10, which matters a lot on WebGL.
##
## Only direct children are merged, so animated bones (arms, knees, jaw) stay
## separate nodes and keep moving; their own pieces are merged per bone.

static var _lit: StandardMaterial3D
static var _glow: StandardMaterial3D


static func lit_material() -> StandardMaterial3D:
	if _lit == null:
		_lit = StandardMaterial3D.new()
		_lit.vertex_color_use_as_albedo = true
		_lit.vertex_color_is_srgb = true
		_lit.roughness = 0.85
	return _lit


static func glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.vertex_color_use_as_albedo = true
		_glow.vertex_color_is_srgb = true
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _glow


## Merge `parent`'s direct mesh children. Returns the new MeshInstance3D, or
## null if there was nothing to merge.
static func merge_children(parent: Node3D, cast_shadow := true) -> MeshInstance3D:
	var groups := {false: _new_group(), true: _new_group()}
	var merged: Array[MeshInstance3D] = []
	for child in parent.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var glow := mat.emission_enabled or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		_append(groups[glow], mi.mesh, mi.transform, mat.albedo_color)
		merged.append(mi)
	if merged.size() < 2:
		return null
	var mesh := ArrayMesh.new()
	for glow in [false, true]:
		var g: Dictionary = groups[glow]
		if (g.verts as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_NORMAL] = g.normals
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_INDEX] = g.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glow_material() if glow else lit_material())
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = mesh
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in merged:
		parent.remove_child(mi)
		mi.queue_free()
	parent.add_child(out)
	return out


static func _new_group() -> Dictionary:
	return {"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"colors": PackedColorArray(), "indices": PackedInt32Array()}


static func _append(g: Dictionary, mesh: Mesh, xform: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base: int = (g.verts as PackedVector3Array).size()
	var nbasis := xform.basis.inverse().transposed()
	var v_out: PackedVector3Array = g.verts
	var n_out: PackedVector3Array = g.normals
	var c_out: PackedColorArray = g.colors
	var i_out: PackedInt32Array = g.indices
	for i in verts.size():
		v_out.append(xform * verts[i])
		n_out.append((nbasis * normals[i]).normalized() if i < normals.size() else Vector3.UP)
		c_out.append(color)
	if indices.is_empty():
		for i in verts.size():
			i_out.append(base + i)
	else:
		for idx in indices:
			i_out.append(base + idx)
	g.verts = v_out
	g.normals = n_out
	g.colors = c_out
	g.indices = i_out
