extends Node3D
## Original chunky infected silhouettes with articulated limbs.
var limbs: Array[Node3D] = []
var _clock := 0.0
var _hurt := 0.0
var _attack := 0.0
var _body: Node3D
var _enemy: EnemyBase
var _head := Node3D.new()
var _head_kick := 0.0
var _anticipation := 0.0
var _mutation_root := Node3D.new()
var _spore_sacs: Array[MeshInstance3D] = []

func _ready() -> void:
	_enemy = get_parent() as EnemyBase
	var kind := _enemy.data.display_name.to_lower()
	var gutter := kind == "gutter"
	var mister := kind == "mister"
	var skin := Color("#b5df68") if not mister else Color("#d2b0db")
	var coat := Color("#d9613c") if gutter else (Color("#76599e") if mister else Color("#337c87"))
	_body = Node3D.new()
	add_child(_body)
	_piece(_body, Vector3(0, 1.05, 0), Vector3(.62, .7, .35), coat)
	_body.add_child(_head)
	_head.position.y = 1.63
	_piece(_head, Vector3(0, 0, -.04), Vector3(.43, .45, .4), skin)
	_piece(_head, Vector3(0, .25, .02), Vector3(.5, .12, .46), coat.darkened(.5))
	for side in [-1.0, 1.0]:
		_piece(_head, Vector3(side*.12, .05, -.25), Vector3(.09, .07, .05), Color("#ffed8a"), true)
		var arm := Node3D.new()
		arm.position = Vector3(side*.43, 1.32, 0)
		_body.add_child(arm)
		_piece(arm, Vector3(0, -.25, -.08), Vector3(.2, .55, .22), coat)
		_piece(arm, Vector3(0, -.53, -.15), Vector3(.23, .18, .24), skin)
		limbs.append(arm)
		var leg := Node3D.new()
		leg.position = Vector3(side*.19, .72, 0)
		_body.add_child(leg)
		_piece(leg, Vector3(0, -.3, 0), Vector3(.24, .6, .26), Color("#273143"))
		_piece(leg, Vector3(0, -.61, -.09), Vector3(.28, .17, .42), Color("#111b28"))
		limbs.append(leg)
	if mister:
		for side in [-1.0, 1.0]:
			_piece(_body, Vector3(side*.38, 1.18, .28), Vector3(.38, .6, .38), Color("#c6f075"), true)
		scale = Vector3(1.25, 1.15, 1.15)
	if gutter:
		scale = Vector3(1.05, .82, 1.0)
		_body.rotation.x = -.25
	_body.add_child(_mutation_root)
	_apply_mutations()
	if GameManager.mutations:
		GameManager.mutations.mutations_changed.connect(_on_mutations_changed)
	_enemy.winding_up.connect(func(): _anticipation = 1.0)
	_enemy.staggered.connect(func(): _hurt = 1.0)
	_enemy.attacked.connect(func(_target, _amount): _attack = 1.0)
	scale *= 0.1
	create_tween().tween_property(self, "scale", scale * 10.0, .3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_enemy.damaged.connect(func(_amount, _health):
		_hurt = 1.0
		if _enemy._bullet_critical:
			_head_kick = 1.0)


func _exit_tree() -> void:
	if GameManager.mutations and GameManager.mutations.mutations_changed.is_connected(_on_mutations_changed):
		GameManager.mutations.mutations_changed.disconnect(_on_mutations_changed)


func _on_mutations_changed(_active: Array) -> void:
	_apply_mutations()


func _apply_mutations() -> void:
	for child in _mutation_root.get_children():
		child.queue_free()
	_spore_sacs.clear()
	if GameManager.has_mutation("armor"):
		# Front metallic chest plate, visor brow and shoulder pauldrons matching the Armor shield card.
		var plate := Color("#7b90a3")
		var trim := Color("#c6d6e2")
		_piece(_mutation_root, Vector3(0, 1.06, -0.21), Vector3(0.68, 0.58, 0.12), plate, false, 0.65)
		_piece(_mutation_root, Vector3(0, 1.06, -0.28), Vector3(0.14, 0.48, 0.05), trim, true, 0.7)
		for side in [-1.0, 1.0]:
			_piece(_mutation_root, Vector3(side * 0.44, 1.36, -0.05), Vector3(0.28, 0.24, 0.34), plate, false, 0.65)
		_piece(_mutation_root, Vector3(0, 1.72, -0.26), Vector3(0.46, 0.12, 0.12), plate, false, 0.65)
	if GameManager.has_mutation("spores"):
		# Swollen glowing spore sacs clustered on shoulders and upper back.
		for spec in [
			[Vector3(-0.28, 1.44, 0.2), 0.19],
			[Vector3(0.26, 1.38, 0.22), 0.22],
			[Vector3(0.0, 1.24, 0.28), 0.25],
			[Vector3(0.0, 1.56, 0.16), 0.15],
		]:
			var sac := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = spec[1]
			sphere.height = spec[1] * 1.85
			sphere.radial_segments = 8
			sphere.rings = 5
			sac.mesh = sphere
			sac.position = spec[0]
			if _sac_material == null:
				_sac_material = StandardMaterial3D.new()
				_sac_material.albedo_color = Color("#b8f259")
				_sac_material.emission_enabled = true
				_sac_material.emission = Color("#9ee838")
				_sac_material.emission_energy_multiplier = 1.4
			sac.material_override = _sac_material
			_mutation_root.add_child(sac)
			_spore_sacs.append(sac)
	if GameManager.has_mutation("splitters") and not _enemy.is_small:
		# Glowing vertical split seam and twin side-buds matching the forked Splitters card.
		_piece(_mutation_root, Vector3(0, 1.05, 0.0), Vector3(0.1, 0.78, 0.42), Color("#ff5689"), true)
		_piece(_mutation_root, Vector3(0, 1.63, -0.04), Vector3(0.08, 0.5, 0.46), Color("#ff5689"), true)
		for side in [-1.0, 1.0]:
			_piece(_mutation_root, Vector3(side * 0.38, 1.52, 0.05), Vector3(0.22, 0.24, 0.22), Color("#ff8f5c"), true)


## One material per color/glow/metal combo, shared by every infected, so the
## RetroScreen material cache stays bounded over a long run.
static var _materials := {}
static var _sac_material: StandardMaterial3D


static func _shared_material(color: Color, glow: bool, metallic: float) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), glow, metallic]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.35 if metallic > 0.0 else 0.9
		material.metallic = metallic
		material.emission_enabled = glow
		material.emission = color
		material.emission_energy_multiplier = .7
		_materials[key] = material
	return _materials[key]


func _piece(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := false, metallic := 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _shared_material(color, glow, metallic)
	parent.add_child(mesh)

var _gait := {}


## Distinct gaits per archetype, with a random start so a crowd doesn't march
## in lockstep.
func _setup_gait() -> void:
	_clock = randf() * TAU
	var kind := str(_enemy.data.display_name).to_lower() if _enemy and _enemy.data else "drip"
	match kind:
		"gutter":
			_gait = {"freq": 5.0, "freq_per_speed": 2.6, "arm": 0.7, "leg": 0.55, "bounce": 0.025, "sway": 0.02, "lean": -0.25}
		"mister":
			_gait = {"freq": 2.4, "freq_per_speed": 1.4, "arm": 0.2, "leg": 0.35, "bounce": 0.06, "sway": 0.07, "lean": 0.03}
		_:
			_gait = {"freq": 2.6, "freq_per_speed": 1.7, "arm": 0.55, "leg": 0.45, "bounce": 0.05, "sway": 0.06, "lean": -0.1}


func _process(delta: float) -> void:
	if _gait.is_empty():
		_setup_gait()
	_clock += delta * (_gait.freq + Vector2(_enemy.velocity.x, _enemy.velocity.z).length() * _gait.freq_per_speed)
	_hurt = move_toward(_hurt, 0.0, delta*5.0)
	_head_kick = move_toward(_head_kick, 0.0, delta * 4.0)
	_anticipation = move_toward(_anticipation, 0.0, delta * 2.0)
	_head.rotation.x = _head_kick * 0.7
	_attack = move_toward(_attack, 0.0, delta * 3.0)
	var speed := Vector2(_enemy.velocity.x, _enemy.velocity.z).length()
	# Arms counter-swing their own side's leg; amplitude follows speed.
	var amount := clampf(speed / 3.5, 0.0, 1.2)
	for i in limbs.size():
		var is_arm := i % 2 == 0
		var phase := (PI if i > 1 else 0.0) + (PI if not is_arm else 0.0)
		var reach: float = _gait.arm if is_arm else _gait.leg
		var swing := sin(_clock + phase) * reach * amount
		limbs[i].rotation.x = swing - ((_attack * 1.5 - _anticipation * 0.8) if is_arm else 0.0) + (_hurt * 0.6 if is_arm else 0.0)
	_body.position.y = absf(sin(_clock)) * _gait.bounce * maxf(amount, 0.2)
	# Hit reaction: snap back and twist away from the shot.
	_body.rotation.z = sin(_clock * .5) * _gait.sway + _hurt * .22
	_body.rotation.x = _gait.lean + _hurt * 0.35
	for i in _spore_sacs.size():
		var pulse := 1.0 + 0.14 * sin(_clock * 1.4 + i * 1.3)
		_spore_sacs[i].scale = Vector3.ONE * pulse
