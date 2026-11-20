class_name StaticBatcher
## Merges the level's static prop meshes (Kenney trees, cars, fences, crates,
## the generated buildings, ...) into one mesh per material, cutting hundreds
## of draw calls to a few dozen. That matters most on WebGL, where draw calls
## are expensive. (MeshInstance3D.merge_meshes isn't exposed in 4.7, so the
## merge is done here; vertex transforms use native packed-array math.)
##
## Skipped: anything under a node that runs its own script (flicker lights,
## traffic lights, police lights, signs with meta), transparent or unshaded
## materials, and meshes that aren't ArrayMeshes. Collision and navigation
## are separate nodes and are untouched.

const ALLOWED_SCRIPTS := ["model_style.gd"]


static func batch(root: Node3D) -> int:
	var groups := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not _eligible(mi, root):
			continue
		var key := _key(mi)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	var merged_count := 0
	var holder := Node3D.new()
	holder.name = "StaticBatches"
	root.add_child(holder)
	holder.global_transform = Transform3D.IDENTITY
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var typed: Array[MeshInstance3D] = []
		typed.assign(list)
		var mesh := _merge(typed)
		if mesh == null:
			continue
		var batch_mi := MeshInstance3D.new()
		batch_mi.mesh = mesh
		holder.add_child(batch_mi)
		batch_mi.global_transform = Transform3D.IDENTITY
		batch_mi.layers = typed[0].layers
		batch_mi.cast_shadow = typed[0].cast_shadow
		for mi in typed:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
		merged_count += typed.size()
	return merged_count


static func _eligible(mi: MeshInstance3D, root: Node) -> bool:
	if mi.mesh == null or not (mi.mesh is ArrayMesh) or not mi.is_visible_in_tree():
		return false
	if mi.material_overlay != null:
		return false
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat == null:
			return false
		if mat is BaseMaterial3D:
			var base := mat as BaseMaterial3D
			if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return false
		elif not (mat is ShaderMaterial and (mat as ShaderMaterial).shader and (mat as ShaderMaterial).shader.resource_path.ends_with("ps1.gdshader")):
			# Only the RetroScreen PS1 swap is known to be opaque and static.
			return false
	# Nothing that animates or is driven by a script, and nothing with meta
	# other systems look up (neon lettering, flicker targets).
	var node: Node = mi
	while node and node != root:
		var script: Script = node.get_script()
		if script and script.resource_path.get_file() not in ALLOWED_SCRIPTS:
			return false
		if node.has_meta("lettering") or node.has_meta("tubes") or node is Label3D:
			return false
		for child in node.get_children():
			if child.get_script() and (child.get_script() as Script).resource_path.get_file() == "flicker.gd":
				return false
		node = node.get_parent()
	return true


static func _key(mi: MeshInstance3D) -> String:
	var parts := PackedStringArray([str(mi.layers), str(mi.cast_shadow), str(mi.mesh.get_surface_count())])
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		parts.append(str(mat.get_instance_id()))
		parts.append(str(mi.mesh.surface_get_format(s)))
	return "|".join(parts)


## One ArrayMesh holding every instance's surfaces, in world space. Surface i
## of each mesh goes into output surface i with the first mesh's material.
static func _merge(list: Array[MeshInstance3D]) -> ArrayMesh:
	var first := list[0]
	var surfaces := first.mesh.get_surface_count()
	var out := ArrayMesh.new()
	for s in surfaces:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		var has_uv := true
		var has_color := true
		for mi in list:
			var arrays := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var xf := mi.global_transform
			var base := verts.size()
			verts.append_array(xf * v)
			var n = arrays[Mesh.ARRAY_NORMAL]
			if n != null and (n as PackedVector3Array).size() == v.size():
				normals.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (n as PackedVector3Array))
			else:
				var up := PackedVector3Array()
				up.resize(v.size())
				up.fill(Vector3.UP)
				normals.append_array(up)
			var uv = arrays[Mesh.ARRAY_TEX_UV]
			if uv != null and (uv as PackedVector2Array).size() == v.size():
				uvs.append_array(uv)
			else:
				has_uv = false
			var c = arrays[Mesh.ARRAY_COLOR]
			if c != null and (c as PackedColorArray).size() == v.size():
				colors.append_array(c)
			else:
				has_color = false
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx == null or (idx as PackedInt32Array).is_empty():
				for i in v.size():
					indices.append(base + i)
			else:
				var src: PackedInt32Array = idx
				var start := indices.size()
				indices.resize(start + src.size())
				for i in src.size():
					indices[start + i] = src[i] + base
		if verts.is_empty():
			continue
		var arrays_out := []
		arrays_out.resize(Mesh.ARRAY_MAX)
		arrays_out[Mesh.ARRAY_VERTEX] = verts
		arrays_out[Mesh.ARRAY_NORMAL] = normals
		if has_uv and uvs.size() == verts.size():
			arrays_out[Mesh.ARRAY_TEX_UV] = uvs
		if has_color and colors.size() == verts.size():
			arrays_out[Mesh.ARRAY_COLOR] = colors
		arrays_out[Mesh.ARRAY_INDEX] = indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_out)
		out.surface_set_material(out.get_surface_count() - 1, first.get_active_material(s))
	return out if out.get_surface_count() > 0 else null
