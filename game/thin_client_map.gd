extends RefCounted
## Approximate static collision for renderers without access to exported maps.

const Feed := preload("res://game/thin_client_feed.gd")


static func describe(level: Node3D, id: String) -> Dictionary:
	var boxes := []
	var bounds := AABB()
	for node: CSGShape3D in level.find_children("*", "CSGShape3D", true, false):
		var root := node
		while root.get_parent() is CSGShape3D:
			root = root.get_parent() as CSGShape3D
		if not root.use_collision or not (root.collision_layer & 1):
			continue
		if node != root and node.operation != CSGShape3D.OPERATION_UNION:
			continue
		var size := Vector3.ZERO
		if node is CSGBox3D:
			size = node.size
		elif node is CSGCylinder3D:
			size = Vector3(node.radius * 2, node.height, node.radius * 2)
		elif node is CSGSphere3D:
			size = Vector3.ONE * node.radius * 2
		if size != Vector3.ZERO:
			bounds = _add(boxes, bounds, node.global_transform, AABB(-size * 0.5, size))
	for node: CollisionShape3D in level.find_children("*", "CollisionShape3D", true, false):
		var body := node.get_parent() as StaticBody3D
		if not body or not (body.collision_layer & 1) or node.disabled or not node.shape:
			continue
		var mesh := node.shape.get_debug_mesh()
		if mesh:
			bounds = _add(boxes, bounds, node.global_transform, mesh.get_aabb())
	return {"t": "map", "id": id, "boxes": boxes,
		"bounds": {"min": Feed.vec(bounds.position), "max": Feed.vec(bounds.end)}}


static func _add(boxes: Array, bounds: AABB, xf: Transform3D, local: AABB) -> AABB:
	var world := xf * local
	if not world.has_volume():
		return bounds
	var center := world.get_center()
	var size := world.size
	var yaw := 0.0
	if xf.basis.y.normalized().dot(Vector3.UP) > 0.999:
		center = xf * local.get_center()
		size = local.size * xf.basis.get_scale().abs()
		yaw = xf.basis.get_euler().y
	boxes.append(Feed.vec(center) + Feed.vec(size) + [Feed.angle(yaw)])
	return world if boxes.size() == 1 else bounds.merge(world)
