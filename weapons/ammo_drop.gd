extends Node3D
## Small reserve refill, collected automatically within reach and line of sight.
var _age := 0.0
var _mesh := MeshInstance3D.new()
var _taken := false
func _ready() -> void:
	add_to_group("ammo_drops")
	var box := BoxMesh.new()
	box.size = Vector3(.38, .24, .24)
	_mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#f6cf64")
	material.emission_enabled = true
	material.emission = Color("#e6a546")
	material.emission_energy_multiplier = .5
	_mesh.material_override = material
	add_child(_mesh)
	var stripe := MeshInstance3D.new()
	var band := BoxMesh.new()
	band.size = Vector3(.12, .25, .25)
	stripe.mesh = band
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#263444")
	stripe.material_override = dark
	_mesh.add_child(stripe)
func _physics_process(delta: float) -> void:
	_age += delta
	_mesh.position.y = .35 + sin(_age * 3.0) * .08
	_mesh.rotation.y += delta * 1.5
	if _age > 35:
		queue_free()
	if _taken or _age < .35:
		return
	for player in get_tree().get_nodes_in_group("local_player"):
		if player.state != "ok" or global_position.distance_to(player.global_position) > 1.8:
			continue
		var origin: Vector3 = player.global_position + Vector3.UP
		var query := PhysicsRayQueryParameters3D.create(origin, global_position + Vector3.UP * .3, 1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var holder := player.get_node("Head/Camera3D/WeaponHolder")
		if holder.collect_ammo():
			_taken = true
			Sound.play("pickup", -12.0)
			var tween := create_tween()
			tween.tween_property(self, "scale", Vector3.ZERO, .12)
			tween.tween_callback(queue_free)
			return
