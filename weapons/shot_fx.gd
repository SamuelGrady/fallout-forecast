class_name ShotFX
## One-shot visual effects for weapons: tracer, muzzle flash, impact puff.
## All local and short-lived.


static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, life := 0.06) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, length)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_fog = true
	box.material = material
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.look_at_from_position((from + to) * 0.5, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	parent.get_tree().create_timer(life).timeout.connect(mesh.queue_free)


static func flash(parent: Node, at: Vector3, color := Color(1.0, 0.8, 0.4), energy := 4.0, life := 0.05) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 6.0
	parent.add_child(light)
	light.global_position = at
	parent.get_tree().create_timer(life).timeout.connect(light.queue_free)


static func puff(parent: Node, at: Vector3, color: Color, size := 0.18, life := 0.25) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	sphere.material = material
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	var tween := mesh.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE * 2.5, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(mesh.queue_free)
