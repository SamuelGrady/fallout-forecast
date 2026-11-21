extends RefCounted
## Canopies shelter the player without turning foliage into a solid wall.

static func install(level: Node3D) -> void:
	var shapes: Dictionary[float, CylinderShape3D] = {}
	for node in level.get_tree().get_nodes_in_group("tree_canopy_trunks"):
		if not level.is_ancestor_of(node):
			continue
		var body := node as StaticBody3D
		for trunk in body.get_children():
			if not trunk is CollisionShape3D:
				continue
			var height: float = trunk.shape.size.y if trunk.shape is BoxShape3D else trunk.shape.height
			var radius := float(body.get_meta("canopy_radius", clampf(height * 0.30, 1.35, 2.7)))
			if not shapes.has(radius):
				var canopy := CylinderShape3D.new()
				canopy.radius = radius
				canopy.height = 4.4
				shapes[radius] = canopy
			var area := Area3D.new()
			area.collision_layer = 1 << 3
			area.collision_mask = 0
			area.monitoring = false
			area.position = trunk.position - Vector3.UP * (height * 0.5 - 1.9)
			body.add_child(area)
			area.add_to_group("shelter")
			var collision := CollisionShape3D.new()
			collision.shape = shapes[radius]
			area.add_child(collision)
