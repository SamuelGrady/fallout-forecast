extends Node3D
## Small reserve refill, collected automatically within reach and line of sight.
@export_enum("ammo", "health", "suit", "supply") var kind := "ammo"
var expires_after := 35.0
var _age := 0.0
var _mesh := MeshInstance3D.new()
var _taken := false
func _ready() -> void:
	add_to_group("ammo_drops")
	var box := BoxMesh.new()
	box.size = Vector3(.38, .24, .24)
	_mesh.mesh = box
	var material := StandardMaterial3D.new()
	var colors := {"ammo": Color("#f6cf64"), "health": Color("#ff6e91"), "suit": Color("#66dfda"), "supply": Color("#b5ef82")}
	material.albedo_color = colors[kind]
	material.emission_enabled = true
	material.emission = material.albedo_color
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
	var label := Label3D.new()
	label.text = {"ammo": "AMMO", "health": "+ HEALTH", "suit": "+ SUIT", "supply": "STREET SUPPLIES"}[kind]
	label.font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	label.font_size = 36
	label.pixel_size = 0.006
	label.position.y = 0.8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
func _physics_process(delta: float) -> void:
	_age += delta
	_mesh.position.y = .35 + sin(_age * 3.0) * .08
	_mesh.rotation.y += delta * 1.5
	if _age > expires_after:
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
		if _collect(player, holder):
			_taken = true
			Sound.play("pickup", -12.0)
			var tween := create_tween()
			tween.tween_property(self, "scale", Vector3.ZERO, .12)
			tween.tween_callback(queue_free)
			return


func _collect(player: Node, holder: Node) -> bool:
	var collected := false
	if kind in ["ammo", "supply"]:
		collected = holder.collect_ammo()
	if kind in ["health", "supply"] and player.health < player.max_health:
		player.heal(20.0)
		collected = true
	if kind in ["suit", "supply"] and player.suit_integrity < 100.0:
		player.suit_integrity = minf(100.0, player.suit_integrity + 25.0)
		collected = true
	return collected
