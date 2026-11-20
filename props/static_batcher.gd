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


class Job extends RefCounted:
	var merged_count := 0
	var unique_reads := 0
	var slices := 0
	var _total_us := 0
	var _root: Node3D
	var _holder: Node3D
	var _groups: Array = []  # Array of Array[MeshInstance3D]
	var _mesh_cache := {}  # "mesh_id|s" -> Array from surface_get_arrays
	var _scanned := false
	var _done := false
	var _total_steps := 0
	var _done_steps := 0

	var _group_idx := 0
	var _surface_idx := 0
	var _mesh_idx := 0
	var _out_mesh: ArrayMesh
	var _verts := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _uvs := PackedVector2Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()
	var _has_uv := true
	var _has_color := true


	func _init(root: Node3D) -> void:
		_root = root


	func is_done() -> bool:
		return _done


	func progress() -> float:
		if _done:
			return 1.0
		if not _scanned or _total_steps <= 0:
			return 0.0
		return clampf(float(_done_steps) / float(_total_steps), 0.0, 1.0)


	func total_ms() -> float:
		return _total_us / 1000.0


	## Do up to `budget_ms` of work and return true once all groups are merged.
	func step(budget_ms := 8.0) -> bool:
		if _done:
			return true
		if not is_instance_valid(_root):
			_done = true
			_mesh_cache.clear()
			return true
		var slice_start := Time.get_ticks_usec()
		var budget_us := int(budget_ms * 1000.0) if budget_ms < 1e9 else 0x7fffffff
		slices += 1
		if not _scanned:
			_scan()
			if _groups.is_empty():
				_done = true
				_mesh_cache.clear()
				_total_us += Time.get_ticks_usec() - slice_start
				return true
			if Time.get_ticks_usec() - slice_start >= budget_us:
				_total_us += Time.get_ticks_usec() - slice_start
				return false
		while _group_idx < _groups.size():
			var list: Array[MeshInstance3D] = _groups[_group_idx]
			if _out_mesh == null:
				_out_mesh = ArrayMesh.new()
				_surface_idx = 0
				_reset_surface()
			var first := list[0]
			var surfaces := first.mesh.get_surface_count() if is_instance_valid(first) and first.mesh else 0
			while _surface_idx < surfaces:
				while _mesh_idx < list.size():
					var mi := list[_mesh_idx]
					_mesh_idx += 1
					_done_steps += 1
					if is_instance_valid(mi) and mi.mesh and _surface_idx < mi.mesh.get_surface_count():
						_append_mesh_surface(mi, _surface_idx)
					if Time.get_ticks_usec() - slice_start >= budget_us:
						_total_us += Time.get_ticks_usec() - slice_start
						return false
				_commit_surface(first, _surface_idx)
				_surface_idx += 1
				_reset_surface()
			_finish_group(list, first)
			_group_idx += 1
			_out_mesh = null
			if Time.get_ticks_usec() - slice_start >= budget_us:
				_total_us += Time.get_ticks_usec() - slice_start
				return false
		_done = true
		_mesh_cache.clear()
		_total_us += Time.get_ticks_usec() - slice_start
		return true


	func _scan() -> void:
		_scanned = true
		var by_key := {}
		for node in _root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi == null or not StaticBatcher._eligible(mi, _root):
				continue
			var key := StaticBatcher._key(mi)
			if not by_key.has(key):
				by_key[key] = []
			(by_key[key] as Array).append(mi)
		_holder = Node3D.new()
		_holder.name = "StaticBatches"
		_root.add_child(_holder)
		_holder.global_transform = Transform3D.IDENTITY
		for key in by_key:
			var raw: Array = by_key[key]
			if raw.size() < 2:
				continue
			var typed: Array[MeshInstance3D] = []
			typed.assign(raw)
			_groups.append(typed)
			_total_steps += typed.size() * typed[0].mesh.get_surface_count()


	func _reset_surface() -> void:
		_mesh_idx = 0
		_verts = PackedVector3Array()
		_normals = PackedVector3Array()
		_uvs = PackedVector2Array()
		_colors = PackedColorArray()
		_indices = PackedInt32Array()
		_has_uv = true
		_has_color = true


	func _cached_arrays(mesh: Mesh, s: int) -> Array:
		# In WebGL2 / GL Compatibility, surface_get_arrays() reads vertex/index
		# buffers back from GL. Caching per unique (mesh, surface) avoids
		# repeating that GPU->CPU stall for dozens of instanced props.
		var cache_key := "%d|%d" % [mesh.get_instance_id(), s]
		if not _mesh_cache.has(cache_key):
			unique_reads += 1
			_mesh_cache[cache_key] = mesh.surface_get_arrays(s)
		return _mesh_cache[cache_key]


	func _append_mesh_surface(mi: MeshInstance3D, s: int) -> void:
		var arrays := _cached_arrays(mi.mesh, s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			return
		var xf := mi.global_transform
		var base := _verts.size()
		_verts.append_array(xf * v)
		var n: Variant = arrays[Mesh.ARRAY_NORMAL]
		if n != null and (n as PackedVector3Array).size() == v.size():
			_normals.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (n as PackedVector3Array))
		else:
			var up := PackedVector3Array()
			up.resize(v.size())
			up.fill(Vector3.UP)
			_normals.append_array(up)
		var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if uv != null and (uv as PackedVector2Array).size() == v.size():
			_uvs.append_array(uv as PackedVector2Array)
		else:
			_has_uv = false
		var c: Variant = arrays[Mesh.ARRAY_COLOR]
		if c != null and (c as PackedColorArray).size() == v.size():
			_colors.append_array(c as PackedColorArray)
		else:
			_has_color = false
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var chunk := PackedInt32Array()
		if idx == null or (idx as PackedInt32Array).is_empty():
			chunk.resize(v.size())
			for i in v.size():
				chunk[i] = base + i
		else:
			var src: PackedInt32Array = idx
			chunk.resize(src.size())
			for i in src.size():
				chunk[i] = src[i] + base
		_indices.append_array(chunk)


	func _commit_surface(first: MeshInstance3D, s: int) -> void:
		if _verts.is_empty() or not is_instance_valid(first):
			return
		var arrays_out := []
		arrays_out.resize(Mesh.ARRAY_MAX)
		arrays_out[Mesh.ARRAY_VERTEX] = _verts
		arrays_out[Mesh.ARRAY_NORMAL] = _normals
		if _has_uv and _uvs.size() == _verts.size():
			arrays_out[Mesh.ARRAY_TEX_UV] = _uvs
		if _has_color and _colors.size() == _verts.size():
			arrays_out[Mesh.ARRAY_COLOR] = _colors
		arrays_out[Mesh.ARRAY_INDEX] = _indices
		_out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_out)
		_out_mesh.surface_set_material(_out_mesh.get_surface_count() - 1, first.get_active_material(s))


	func _finish_group(list: Array[MeshInstance3D], first: MeshInstance3D) -> void:
		if _out_mesh == null or _out_mesh.get_surface_count() == 0 or not is_instance_valid(_holder):
			return
		var batch_mi := MeshInstance3D.new()
		batch_mi.mesh = _out_mesh
		_holder.add_child(batch_mi)
		batch_mi.global_transform = Transform3D.IDENTITY
		if is_instance_valid(first):
			batch_mi.layers = first.layers
			batch_mi.cast_shadow = first.cast_shadow
		for mi in list:
			if is_instance_valid(mi):
				if mi.get_parent():
					mi.get_parent().remove_child(mi)
				mi.queue_free()
				merged_count += 1


static func begin(root: Node3D) -> Job:
	return Job.new(root)


static func batch(root: Node3D) -> int:
	var job := begin(root)
	while not job.step(INF):
		pass
	return job.merged_count


static func _eligible(mi: MeshInstance3D, root: Node) -> bool:
	if mi.mesh == null or not (mi.mesh is ArrayMesh) or not mi.is_visible_in_tree():
		return false
	# An imported mesh can also be the parent of another mesh. Removing it
	# would strand the child (possibly in a different batch) outside the tree.
	if mi.get_child_count() > 0 or mi.global_basis.determinant() <= 0.0:
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
