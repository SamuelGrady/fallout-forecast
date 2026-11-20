extends Node3D
## Small reserve refill, collected automatically within reach and line of sight.
@export_enum("ammo", "health", "suit", "supply") var kind := "ammo"
var expires_after := 35.0
var _age := 0.0
var _root := Node3D.new()
var _ring: MeshInstance3D
var _taken := false


func _ready() -> void:
	add_to_group("ammo_drops")
	add_child(_root)
	var colors := {"ammo": Color("#f6cf64"), "health": Color("#ff6e91"), "suit": Color("#66dfda"), "supply": Color("#b5ef82")}
	var accent: Color = colors.get(kind, Color("#f6cf64"))
	match kind:
		"health":
			_build_medkit(accent)
		"suit":
			_build_canister(accent)
		"supply":
			_build_supply_case(accent)
		_:
			_build_ammo(accent)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.34
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.45)
	_ring.material_override = ring_mat
	_ring.position.y = 0.04
	add_child(_ring)


func _build_ammo(accent: Color) -> void:
	# Brass/olive ammo tin with three standing cartridges on top.
	_add_box(_root, Vector3(0, 0, 0), Vector3(0.42, 0.22, 0.24), Color("#3c4b39"))
	_add_box(_root, Vector3(0, 0.02, 0), Vector3(0.44, 0.06, 0.26), accent, 0.45)
	for x in [-0.11, 0.0, 0.11]:
		_add_cyl(_root, Vector3(x, 0.18, 0), 0.035, 0.16, accent, 0.5)
		_add_cone(_root, Vector3(x, 0.29, 0), 0.034, 0.07, Color("#d6874a"), 0.35)


func _build_medkit(accent: Color) -> void:
	# White medical case with raised red/pink 3D cross on front, back and top + handle.
	_add_box(_root, Vector3.ZERO, Vector3(0.44, 0.3, 0.18), Color("#eff2ea"), 0.2)
	_add_box(_root, Vector3(0, 0.19, 0), Vector3(0.18, 0.06, 0.06), Color("#263444"))
	for z in [-0.095, 0.095]:
		_add_box(_root, Vector3(0, 0, z), Vector3(0.2, 0.065, 0.03), accent, 0.7)
		_add_box(_root, Vector3(0, 0, z), Vector3(0.065, 0.2, 0.03), accent, 0.7)
	_add_box(_root, Vector3(0, 0.155, 0), Vector3(0.16, 0.02, 0.055), accent, 0.6)
	_add_box(_root, Vector3(0, 0.155, 0), Vector3(0.055, 0.02, 0.14), accent, 0.6)


func _build_canister(accent: Color) -> void:
	# Pressurized cyan suit-repair canister with dark collar, valve cap and glowing level strip.
	_add_cyl(_root, Vector3(0, 0.04, 0), 0.14, 0.4, Color("#1f3542"))
	_add_cyl(_root, Vector3(0, 0.04, 0), 0.146, 0.22, accent, 0.65)
	_add_cyl(_root, Vector3(0, 0.26, 0), 0.11, 0.06, Color("#263444"))
	_add_cyl(_root, Vector3(0, 0.32, 0), 0.05, 0.08, Color("#d4dde0"))
	_add_box(_root, Vector3(0, 0.35, 0), Vector3(0.16, 0.03, 0.04), accent, 0.5)


func _build_supply_case(accent: Color) -> void:
	# Open field supply case with angled lid and visible ammo + med + canister inside.
	_add_box(_root, Vector3(0, -0.02, 0), Vector3(0.62, 0.24, 0.42), Color("#2b3a36"))
	_add_box(_root, Vector3(0, 0.09, 0), Vector3(0.64, 0.05, 0.44), accent, 0.4)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.1, -0.21)
	lid.rotation_degrees.x = -62.0
	_root.add_child(lid)
	_add_box(lid, Vector3(0, 0, 0.2), Vector3(0.62, 0.05, 0.42), Color("#364a42"))
	# Miniature contents peeking out of the open case.
	for x in [-0.19, -0.11]:
		_add_cyl(_root, Vector3(x, 0.17, 0.04), 0.03, 0.15, Color("#f6cf64"), 0.45)
	_add_box(_root, Vector3(0.02, 0.16, 0.02), Vector3(0.16, 0.14, 0.12), Color("#eff2ea"), 0.2)
	_add_box(_root, Vector3(0.02, 0.16, 0.085), Vector3(0.09, 0.03, 0.02), Color("#ff6e91"), 0.7)
	_add_box(_root, Vector3(0.02, 0.16, 0.085), Vector3(0.03, 0.09, 0.02), Color("#ff6e91"), 0.7)
	_add_cyl(_root, Vector3(0.2, 0.19, 0.02), 0.065, 0.22, Color("#66dfda"), 0.6)


func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _add_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)


func _add_cyl(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, glow := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)


func _add_cone(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, glow := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)


func _physics_process(delta: float) -> void:
	_age += delta
	_root.position.y = 0.36 + sin(_age * 3.0) * 0.07
	_root.rotation.y += delta * 1.4
	if _ring:
		var pulse := 1.0 + sin(_age * 4.0) * 0.08
		_ring.scale = Vector3(pulse, 1.0, pulse)
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
