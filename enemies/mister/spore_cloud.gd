extends Area3D
## Short-lived damage cloud left by a Mister's spore (and later the Spores
## mutation). Damages players standing in it, on the host only.

var damage_per_second := 6.0
var radius := 2.5
var lifetime := 4.0
var source: Node = null

var _age := 0.0
var _mesh_material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("spore_clouds")
	collision_layer = 0
	collision_mask = 1 << 1  # players
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = radius
	shape.shape = sphere_shape
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 1.2
	_mesh_material.albedo_color = Color(0.45, 0.9, 0.25, 0.35)
	_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere.material = _mesh_material
	mesh.mesh = sphere
	mesh.position.y = radius * 0.3
	add_child(mesh)


func _physics_process(delta: float) -> void:
	_age += delta
	_mesh_material.albedo_color.a = 0.35 * (1.0 - _age / lifetime)
	if _age >= lifetime:
		queue_free()
		return
	if not Net.is_host():
		return
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			# The cloud outlives the enemy that spat it out.
			body.take_damage(damage_per_second * delta, source if is_instance_valid(source) else null)
