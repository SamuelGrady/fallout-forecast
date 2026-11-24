extends Area3D
## Damage cloud left by a Mister's spore, a Smog's acid glob, or the Spores
## mutation. Damages players standing in it, on the host only.
##
## Create clouds with SporeCloud.spawn(), not .new():
## - A cloud landing on top of a cloud of the same kind MERGES into it as a
##   compound multi-circle union (keeping each circle's exact radius and center,
##   refreshing lifetime) instead of expanding or stacking damage.
## - A cloud landing under an active Shield Dome fizzles, and existing clouds
##   inside a fresh dome dissipate: the dome keeps acid and spores out.
## - A player takes damage from at most one cloud per tick, and none
##   while under a dome.

const MAX_LOBES := 8
const CIRCLE_SEGMENTS := 36
const RIM_WIDTH := 0.09
const COINCIDENT_EPS := 0.12

var damage_per_second := 6.0
var radius := 2.5
var lifetime := 4.0
var source: Node = null
var acid := false
var hazard_id := 0

var _age := 0.0
var _damage_time := 0.0
var _lobes: Array[Dictionary] = []
var _shapes: Array[CollisionShape3D] = []
var _hazard_ids: Array[int] = []
var _mesh_material := StandardMaterial3D.new()
var _rim_material := StandardMaterial3D.new()
var _fill_mesh_instance: MeshInstance3D = null
var _rim_mesh_instance: MeshInstance3D = null
var _spore_meshes: Array[MeshInstance3D] = []

## body instance id -> msec it was last damaged by any cloud (one tick per 0.2 s).
static var _hit_frame := {}


## Spawn (or merge into) a cloud at `at`. Returns the cloud that now covers
## the spot, or null if a Shield Dome kept it out. Runs the same way on every
## peer, so all copies merge alike.
static func spawn(parent: Node, at: Vector3, is_acid: bool, cloud_radius: float, cloud_lifetime: float,
		dps: float, cloud_source: Variant = null, cloud_hazard_id := 0) -> Node:
	var tree := parent.get_tree()
	if _in_dome(at, tree, cloud_radius * 0.35):
		if not Net.dedicated:
			ShotFX.puff(parent, at + Vector3.UP * 0.3, Color(0.55, 0.95, 1.0, 0.7), 0.4, 0.5)
		return null
	var matches: Array[Area3D] = []
	for node in tree.get_nodes_in_group("spore_clouds"):
		var other := node as Area3D
		if other == null or other.is_queued_for_deletion() or bool(other.get("acid")) != is_acid:
			continue
		if other.call("overlaps_circle", at, cloud_radius):
			matches.append(other)
	if not matches.is_empty():
		var primary := matches[0]
		primary.call("_absorb", at, cloud_radius, cloud_lifetime, dps, cloud_hazard_id)
		for extra in matches.slice(1):
			primary.call("_absorb_cloud", extra)
			extra.queue_free()
		return primary
	var cloud := (load("res://enemies/mister/spore_cloud.gd") as GDScript).new() as Area3D
	cloud.set("acid", is_acid)
	cloud.set("radius", cloud_radius)
	cloud.set("lifetime", cloud_lifetime)
	cloud.set("damage_per_second", dps)
	cloud.set("source", cloud_source if is_instance_valid(cloud_source) else null)
	cloud.set("hazard_id", cloud_hazard_id)
	parent.add_child(cloud, true)
	cloud.global_position = at
	return cloud


static func _in_dome(point: Vector3, tree: SceneTree, margin := 0.0) -> bool:
	for dome in tree.get_nodes_in_group("active_flares"):
		if dome.is_queued_for_deletion() or str(dome.get("id")) != "shield_dome":
			continue
		var offset: Vector3 = point - dome.global_position
		offset.y = 0.0
		if offset.length() <= float(dome.data.effect_radius) + margin:
			return true
	return false


func overlaps_circle(point: Vector3, r: float) -> bool:
	if _lobes.is_empty():
		return Vector2(point.x - global_position.x, point.z - global_position.z).length() < radius + r * 0.96
	for l in _lobes:
		var off: Vector3 = l.offset
		var dist := Vector2(point.x - (global_position.x + off.x), point.z - (global_position.z + off.z)).length()
		if dist < float(l.radius) + r * 0.96:
			return true
	return false


func has_hazard_id(id: int) -> bool:
	if id <= 0:
		return false
	return hazard_id == id or _hazard_ids.has(id)


func lobe_world_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _lobes.is_empty():
		out.append(global_position)
		return out
	for l in _lobes:
		out.append(global_position + (l.offset as Vector3))
	return out


func nearest_lobe_world_position(to: Vector3) -> Vector3:
	if _lobes.is_empty():
		return global_position
	var best := global_position
	var best_d2 := INF
	for l in _lobes:
		var p := global_position + (l.offset as Vector3)
		var d2 := Vector2(p.x - to.x, p.z - to.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func get_lobe_count() -> int:
	return _lobes.size()


func _register_hazard_id(id: int) -> void:
	if id <= 0:
		return
	if hazard_id == 0:
		hazard_id = id
	if not _hazard_ids.has(id):
		_hazard_ids.append(id)


func _add_lobe(rel: Vector3, lobe_radius: float) -> void:
	var offset := Vector3(rel.x, 0.0, rel.z)
	_lobes.append({"offset": offset, "radius": lobe_radius})
	var shape := CollisionShape3D.new()
	if acid:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = lobe_radius
		cylinder.height = 0.36
		shape.shape = cylinder
	else:
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = lobe_radius
		shape.shape = sphere_shape
	shape.position = offset
	add_child(shape)
	_shapes.append(shape)


func _append_lobe_if_needed(rel: Vector3, other_radius: float) -> bool:
	for l in _lobes:
		var off: Vector3 = l.offset
		var dist := Vector2(rel.x - off.x, rel.z - off.z).length()
		if dist < COINCIDENT_EPS and other_radius <= float(l.radius) + 0.01:
			return false
	if _lobes.size() >= MAX_LOBES:
		return false
	_add_lobe(rel, other_radius)
	return true


## Merge another landing into this cloud without expanding radius or shifting
## global_position: appends a new lobe & collision shape and refreshes lifetime.
func _absorb(at: Vector3, other_radius: float, other_lifetime: float, dps: float, other_hazard_id := 0) -> void:
	var left := maxf(lifetime - _age, other_lifetime)
	_age = 0.0
	lifetime = left
	damage_per_second = maxf(damage_per_second, dps)
	_register_hazard_id(other_hazard_id)
	var rel := at - global_position
	rel.y = 0.0
	if _append_lobe_if_needed(rel, other_radius) and not Net.dedicated:
		_rebuild_visuals()


## Absorb every lobe and hazard_id from another bridged SporeCloud.
func _absorb_cloud(other: Area3D) -> void:
	var other_left := maxf(float(other.get("lifetime")) - float(other.get("_age")), 0.0)
	var left := maxf(lifetime - _age, other_left)
	_age = 0.0
	lifetime = left
	damage_per_second = maxf(damage_per_second, float(other.get("damage_per_second")))
	_register_hazard_id(int(other.get("hazard_id")))
	var other_ids: Variant = other.get("_hazard_ids")
	if other_ids is Array:
		for hid in other_ids:
			_register_hazard_id(int(hid))
	var changed := false
	var other_lobes: Variant = other.get("_lobes")
	if other_lobes is Array and not other_lobes.is_empty():
		for l in other_lobes:
			var world_pos := other.global_position + (l.offset as Vector3)
			var rel := world_pos - global_position
			rel.y = 0.0
			if _append_lobe_if_needed(rel, float(l.radius)):
				changed = true
	else:
		var rel := other.global_position - global_position
		rel.y = 0.0
		if _append_lobe_if_needed(rel, float(other.get("radius"))):
			changed = true
	if changed and not Net.dedicated:
		_rebuild_visuals()


static func _clip_polygon_half_plane(poly: Array[Vector2], origin: Vector2, normal: Vector2, rhs: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count := poly.size()
	if count < 3:
		return out
	for idx in count:
		var a: Vector2 = poly[idx]
		var b: Vector2 = poly[(idx + 1) % count]
		var da := (a - origin).dot(normal) - rhs
		var db := (b - origin).dot(normal) - rhs
		var a_in := da <= 0.0
		var b_in := db <= 0.0
		if a_in:
			out.append(a)
		if a_in != b_in:
			var denom := da - db
			if absf(denom) > 1e-8:
				var t := clampf(da / denom, 0.0, 1.0)
				out.append(a.lerp(b, t))
	return out


func _build_acid_fill_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_verts := false
	var lobe_count := _lobes.size()
	for i in lobe_count:
		var c_i := Vector2((_lobes[i].offset as Vector3).x, (_lobes[i].offset as Vector3).z)
		var r_i := float(_lobes[i].radius)
		var poly: Array[Vector2] = []
		poly.resize(CIRCLE_SEGMENTS)
		for k in CIRCLE_SEGMENTS:
			var angle := float(k) / float(CIRCLE_SEGMENTS) * TAU
			poly[k] = c_i + Vector2(cos(angle), sin(angle)) * r_i
		for j in lobe_count:
			if j == i:
				continue
			var c_j := Vector2((_lobes[j].offset as Vector3).x, (_lobes[j].offset as Vector3).z)
			var r_j := float(_lobes[j].radius)
			var d := c_j - c_i
			var d_sq := d.length_squared()
			if d_sq < 1e-6:
				if r_i < r_j or (is_equal_approx(r_i, r_j) and j < i):
					poly.clear()
					break
				continue
			var dist := sqrt(d_sq)
			if dist >= r_i + r_j:
				continue
			if dist + r_i <= r_j:
				poly.clear()
				break
			var rhs := 0.5 * (d_sq + r_i * r_i - r_j * r_j)
			poly = _clip_polygon_half_plane(poly, c_i, d, rhs)
			if poly.size() < 3:
				break
		if poly.size() < 3:
			continue
		var v0 := Vector3(poly[0].x, 0.0, poly[0].y)
		for k in range(1, poly.size() - 1):
			var v1 := Vector3(poly[k].x, 0.0, poly[k].y)
			var v2 := Vector3(poly[k + 1].x, 0.0, poly[k + 1].y)
			st.set_normal(Vector3.UP)
			st.add_vertex(v0)
			st.set_normal(Vector3.UP)
			st.add_vertex(v1)
			st.set_normal(Vector3.UP)
			st.add_vertex(v2)
			has_verts = true
	return st.commit() if has_verts else ArrayMesh.new()


func _build_rim_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_verts := false
	var lobe_count := _lobes.size()
	for i in lobe_count:
		var c_i := Vector2((_lobes[i].offset as Vector3).x, (_lobes[i].offset as Vector3).z)
		var r_i := float(_lobes[i].radius)
		var r_inner := maxf(r_i - RIM_WIDTH, 0.01)
		for k in CIRCLE_SEGMENTS:
			var a0 := float(k) / float(CIRCLE_SEGMENTS) * TAU
			var a1 := float((k + 1) % CIRCLE_SEGMENTS) / float(CIRCLE_SEGMENTS) * TAU
			var dir0 := Vector2(cos(a0), sin(a0))
			var dir1 := Vector2(cos(a1), sin(a1))
			var p0 := c_i + dir0 * r_i
			var p1 := c_i + dir1 * r_i
			var pm := (p0 + p1) * 0.5
			var inside_other := false
			for j in lobe_count:
				if j == i:
					continue
				var c_j := Vector2((_lobes[j].offset as Vector3).x, (_lobes[j].offset as Vector3).z)
				var r_j := float(_lobes[j].radius)
				if c_i.distance_to(c_j) < 0.015 and absf(r_i - r_j) < 0.015:
					if j < i:
						inside_other = true
						break
				elif pm.distance_to(c_j) < r_j - 0.015:
					inside_other = true
					break
			if inside_other:
				continue
			var q0 := c_i + dir0 * r_inner
			var q1 := c_i + dir1 * r_inner
			var vq0 := Vector3(q0.x, 0.0, q0.y)
			var vp0 := Vector3(p0.x, 0.0, p0.y)
			var vp1 := Vector3(p1.x, 0.0, p1.y)
			var vq1 := Vector3(q1.x, 0.0, q1.y)
			st.set_normal(Vector3.UP)
			st.add_vertex(vq0)
			st.set_normal(Vector3.UP)
			st.add_vertex(vp0)
			st.set_normal(Vector3.UP)
			st.add_vertex(vp1)
			st.set_normal(Vector3.UP)
			st.add_vertex(vq0)
			st.set_normal(Vector3.UP)
			st.add_vertex(vp1)
			st.set_normal(Vector3.UP)
			st.add_vertex(vq1)
			has_verts = true
	return st.commit() if has_verts else ArrayMesh.new()


func _rebuild_visuals() -> void:
	if acid:
		if _fill_mesh_instance == null:
			_fill_mesh_instance = MeshInstance3D.new()
			_fill_mesh_instance.position.y = 0.05
			_fill_mesh_instance.material_override = _mesh_material
			_fill_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_fill_mesh_instance)
		_fill_mesh_instance.mesh = _build_acid_fill_mesh()
	else:
		for old_mesh in _spore_meshes:
			if is_instance_valid(old_mesh):
				old_mesh.queue_free()
		_spore_meshes.clear()
		for l in _lobes:
			var r := float(l.radius)
			var mesh := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radial_segments = 12
			sphere.rings = 6
			sphere.radius = r
			sphere.height = r * 2.0
			mesh.mesh = sphere
			mesh.position = l.offset as Vector3
			mesh.material_override = _mesh_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mesh)
			_spore_meshes.append(mesh)
	if _rim_mesh_instance == null:
		_rim_mesh_instance = MeshInstance3D.new()
		_rim_mesh_instance.position.y = 0.075
		_rim_mesh_instance.material_override = _rim_material
		_rim_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rim_mesh_instance)
	_rim_mesh_instance.mesh = _build_rim_mesh()


func _ready() -> void:
	add_to_group("spore_clouds")
	add_to_group("enemy_hazards")
	collision_layer = 0
	collision_mask = 1 << 1  # players
	monitorable = false
	_register_hazard_id(hazard_id)
	_add_lobe(Vector3.ZERO, radius)
	_mesh_material.albedo_color = Color(0.64, 0.84, 0.12, 0.65) if acid else Color(0.45, 0.9, 0.25, 0.35)
	_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_material.albedo_color = Color("#e7fc45") if acid else Color(0.7, 1.0, 0.3)
	_rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if Net.dedicated:
		return
	_rebuild_visuals()


func _physics_process(delta: float) -> void:
	_age += delta
	# A dome deployed over any lobe of this cloud burns it off quickly.
	var tree := get_tree()
	for pos in lobe_world_positions():
		if _in_dome(pos, tree):
			_age += delta * 6.0
			break
	_mesh_material.albedo_color.a = (0.65 if acid else 0.35) * clampf(1.0 - _age / lifetime, 0.0, 1.0)
	if _age >= lifetime or GameManager.victory_locked or GameManager.finished:
		queue_free()
		return
	if not Net.is_host() or damage_per_second <= 0.0:
		return
	_damage_time += delta
	if _damage_time < 0.2:
		return
	var amount := damage_per_second * _damage_time
	_damage_time = 0.0
	var now := Time.get_ticks_msec()
	for body in get_overlapping_bodies():
		if not body is Player:
			continue
		var id := body.get_instance_id()
		if now - int(_hit_frame.get(id, -100000)) < 190:
			continue  # An overlapping cloud already ticked on this player.
		if _in_dome(body.global_position, tree):
			continue
		if acid:
			var ray_from := nearest_lobe_world_position(body.global_position) + Vector3.UP * 0.35
			var ray := PhysicsRayQueryParameters3D.create(ray_from, body.global_position + Vector3.UP * 0.35, 1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
		_hit_frame[id] = now
		# The cloud outlives the enemy that spat it out.
		body.take_damage(amount, source if is_instance_valid(source) else null, true)
	if _hit_frame.size() > 64:
		_hit_frame.clear()
