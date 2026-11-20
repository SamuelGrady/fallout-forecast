extends Area3D
## Short-lived damage cloud left by a Mister's spore (and later the Spores
## mutation). Damages players standing in it, on the host only.

var damage_per_second := 6.0
var radius := 2.5
var lifetime := 4.0
var source: Node = null
var acid := false

var _age := 0.0
var _mesh_material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("spore_clouds")
	add_to_group("enemy_hazards")
	collision_layer = 0
	collision_mask = 1 << 1  # players
	monitorable = false
	var shape := CollisionShape3D.new()
	if acid:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = .36
		shape.shape = cylinder
	else:
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = radius
		shape.shape = sphere_shape
	add_child(shape)
	if Net.dedicated:
		return

	var mesh := MeshInstance3D.new()
	if acid:
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = .024
		disc.radial_segments = 20
		mesh.mesh = disc
		mesh.position.y = .05
	else:
		var sphere := SphereMesh.new()
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
	_mesh_material.albedo_color = Color(.64, .84, .12, .65) if acid else Color(0.45, 0.9, 0.25, 0.35)
	_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = _mesh_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.08
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.position.y = 0.075
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color("#e7fc45") if acid else Color(0.7, 1.0, 0.3)
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _physics_process(delta: float) -> void:
	_age += delta
	_mesh_material.albedo_color.a = (.65 if acid else .35) * (1.0 - _age / lifetime)
	if _age >= lifetime or GameManager.victory_locked or GameManager.finished:
		queue_free()
		return
	if not Net.is_host():
		return
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			if acid:
				var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .35, body.global_position + Vector3.UP * .35, 1)
				if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
					continue
			# The cloud outlives the enemy that spat it out.
			body.take_damage(damage_per_second * delta, source if is_instance_valid(source) else null)
