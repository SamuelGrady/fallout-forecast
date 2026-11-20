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

## Outfits a Drip can spawn in: [shirt, pants, accent]. Picked per instance
## so a horde isn't a row of clones.
const OUTFITS := [
	[Color("#337c87"), Color("#273143"), Color("#c9d6df")],  # office: teal shirt, tie
	[Color("#c9a227"), Color("#3a3f4b"), Color("#f2e6c4")],  # yellow raincoat
	[Color("#a8434f"), Color("#2b2f3a"), Color("#f1f1f1")],  # jogger
	[Color("#5b6e3a"), Color("#3b3328"), Color("#d0c9a8")],  # parka
	[Color("#7d8a96"), Color("#22303c"), Color("#ff7aa8")],  # mall worker
]
const FLESH := [Color("#b5df68"), Color("#a6cf6a"), Color("#c3e07a"), Color("#9cc76a")]

var _elbows: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _jaw: Node3D
var _reach := 1.15  # resting shoulder angle: arms out in front
var _kind := "drip"


func _ready() -> void:
	_enemy = get_parent() as EnemyBase
	_kind = _enemy.data.display_name.to_lower()
	var gutter := _kind == "gutter"
	var mister := _kind == "mister"
	var outfit: Array = OUTFITS.pick_random()
	var skin: Color = FLESH.pick_random()
	var shirt: Color = outfit[0]
	var pants: Color = outfit[1]
	var accent: Color = outfit[2]
	if gutter:
		skin = Color("#8fb85a")
		shirt = Color("#d9613c").darkened(randf_range(0.0, 0.25))
		pants = Color("#2a2620")
		accent = Color("#4a5d2e")  # sewer slime
		_reach = 0.55
	elif mister:
		skin = Color("#d2b0db")
		shirt = Color("#76599e")
		pants = Color("#3a2d4a")
		accent = Color("#c6f075")
		_reach = 0.3
	_body = Node3D.new()
	add_child(_body)
	# Torso: pelvis, belly, chest. The shirt is torn open over the ribs.
	_piece(_body, Vector3(0, 0.8, 0), Vector3(.5, .2, .3), pants)
	_piece(_body, Vector3(0, 1.0, 0), Vector3(.52, .24, .3), shirt)
	_piece(_body, Vector3(0, 1.27, 0.02), Vector3(.6, .34, .34), shirt)
	_piece(_body, Vector3(.1, 1.2, -.17), Vector3(.2, .3, .02), skin.darkened(.15))  # torn gap
	for i in 3:
		_piece(_body, Vector3(.1, 1.12 + i * .08, -.18), Vector3(.18, .025, .02), Color("#e8e3cf"))  # ribs
	_piece(_body, Vector3(-.15, 1.0, -.16), Vector3(.12, .1, .02), Color("#6b1f2a"))  # wound
	if not gutter and not mister:
		_piece(_body, Vector3(-.06, 1.24, -.18), Vector3(.06, .22, .02), accent)  # tie or zip
	# Neck and head with a hanging jaw, sunken eyes and a little hair.
	_piece(_body, Vector3(0, 1.48, 0), Vector3(.16, .12, .16), skin.darkened(.1))
	_body.add_child(_head)
	_head.position.y = 1.63
	_piece(_head, Vector3(0, .04, -.02), Vector3(.4, .34, .38), skin)
	_piece(_head, Vector3(0, .2, .02), Vector3(.42, .08, .4), Color("#3b3026") if not mister else skin.darkened(.2))  # hair
	_piece(_head, Vector3(.12, .24, -.08), Vector3(.08, .08, .08), Color("#3b3026") if not mister else skin.darkened(.2))
	for side in [-1.0, 1.0]:
		_piece(_head, Vector3(side * .1, .07, -.2), Vector3(.1, .07, .03), Color("#1a1412"))  # socket
		_piece(_head, Vector3(side * .1, .07, -.215), Vector3(.035, .035, .02), Color("#ffed8a"), true)  # eye glow
		_piece(_head, Vector3(side * .21, .03, 0), Vector3(.04, .1, .08), skin.darkened(.1))  # ear
	_piece(_head, Vector3(0, -.01, -.215), Vector3(.06, .06, .04), skin.darkened(.2))  # nose
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -.11, .02)
	_head.add_child(_jaw)
	_piece(_jaw, Vector3(0, -.05, -.1), Vector3(.32, .09, .28), skin.darkened(.08))
	_piece(_jaw, Vector3(0, .0, -.22), Vector3(.26, .03, .03), Color("#efe6c8"))  # teeth
	_piece(_head, Vector3(0, -.1, -.2), Vector3(.26, .03, .03), Color("#efe6c8"))
	_piece(_head, Vector3(0, -.13, -.16), Vector3(.24, .05, .1), Color("#3a0f14"))  # mouth
	if gutter:
		# Wide maw with extra teeth and slime down the front.
		for i in 4:
			_piece(_jaw, Vector3(-.12 + i * .08, .03, -.23), Vector3(.03, .06, .02), Color("#efe6c8"))
		_piece(_body, Vector3(0, 1.12, -.18), Vector3(.3, .4, .02), accent, true)
	for side in [-1.0, 1.0]:
		# Shoulder -> upper arm -> elbow -> forearm -> hand with three fingers.
		var arm := Node3D.new()
		arm.position = Vector3(side * .37, 1.38, 0)
		_body.add_child(arm)
		var upper := (.36 if not gutter else .44)
		_piece(arm, Vector3(0, -upper * .5, 0), Vector3(.16, upper, .17), shirt)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -upper, 0)
		arm.add_child(elbow)
		var fore := (.32 if not gutter else .42)
		_piece(elbow, Vector3(0, -fore * .5, 0), Vector3(.13, fore, .14), skin if randf() < 0.5 else shirt)
		_piece(elbow, Vector3(0, -fore - .05, 0), Vector3(.15, .1, .1), skin)
		for f in 3:
			_piece(elbow, Vector3(-.045 + f * .045, -fore - .14, 0), Vector3(.03, .1 if not gutter else .16, .03), skin.darkened(.12))
		limbs.append(arm)
		_elbows.append(elbow)
		# Hip -> thigh -> knee -> shin -> shoe.
		var leg := Node3D.new()
		leg.position = Vector3(side * .15, .72, 0)
		_body.add_child(leg)
		_piece(leg, Vector3(0, -.17, 0), Vector3(.19, .34, .21), pants)
		var knee := Node3D.new()
		knee.position = Vector3(0, -.34, 0)
		leg.add_child(knee)
		_piece(knee, Vector3(0, -.15, 0), Vector3(.17, .3, .19), pants.darkened(.1))
		_piece(knee, Vector3(0, -.32, -.06), Vector3(.2, .1, .32), Color("#111b28"))
		if randf() < 0.3:
			_piece(knee, Vector3(0, -.08, -.1), Vector3(.12, .08, .02), skin.darkened(.15))  # torn knee
		limbs.append(leg)
		_knees.append(knee)
	if mister:
		# Bloated gut, spore growths on the back, a breathing tube from the mouth.
		_piece(_body, Vector3(0, 1.05, -.06), Vector3(.62, .46, .46), shirt.lightened(.1))
		for side in [-1.0, 1.0]:
			_piece(_body, Vector3(side * .3, 1.22, .26), Vector3(.34, .5, .34), accent, true)
		_piece(_body, Vector3(0, 1.45, .3), Vector3(.28, .3, .26), accent, true)
		_piece(_head, Vector3(0, -.12, -.32), Vector3(.1, .1, .22), Color("#5b4a66"))
		_piece(_head, Vector3(0, -.12, -.45), Vector3(.16, .16, .06), accent, true)
		scale = Vector3(1.2, 1.12, 1.15)
	if gutter:
		scale = Vector3(1.05, .82, 1.0)
		_body.rotation.x = -.25
	scale *= randf_range(0.94, 1.06)
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
	if _jaw:
		# Jaw hangs and chatters; gapes on the windup.
		_jaw.rotation.x = 0.18 + 0.1 * absf(sin(_clock * 3.1)) + _anticipation * 0.4 + _attack * 0.3
	_attack = move_toward(_attack, 0.0, delta * 3.0)
	var speed := Vector2(_enemy.velocity.x, _enemy.velocity.z).length()
	# Arms counter-swing their own side's leg; amplitude follows speed.
	var amount := clampf(speed / 3.5, 0.0, 1.2)
	for i in limbs.size():
		var is_arm := i % 2 == 0
		var phase := (PI if i > 1 else 0.0) + (PI if not is_arm else 0.0)
		var reach: float = _gait.arm if is_arm else _gait.leg
		var swing := sin(_clock + phase) * reach * amount
		if is_arm:
			# Arms hang out in front; windup lifts them overhead, the attack slams down.
			limbs[i].rotation.x = _reach + swing * 0.4 + _anticipation * 1.1 - _attack * 1.3 - _hurt * 0.7
			_elbows[i / 2].rotation.x = 0.25 + 0.2 * sin(_clock * 0.7 + i) + _attack * 0.6
		else:
			limbs[i].rotation.x = swing
			# Knees bend on the forward swing so the walk drags instead of stilting.
			_knees[i / 2].rotation.x = -maxf(0.0, -sin(_clock + phase)) * 0.7 * amount - 0.08
	_body.position.y = absf(sin(_clock)) * _gait.bounce * maxf(amount, 0.2)
	# Hit reaction: snap back and twist away from the shot.
	_body.rotation.z = sin(_clock * .5) * _gait.sway + _hurt * .22
	_body.rotation.x = _gait.lean + _hurt * 0.35
	for i in _spore_sacs.size():
		var pulse := 1.0 + 0.14 * sin(_clock * 1.4 + i * 1.3)
		_spore_sacs[i].scale = Vector3.ONE * pulse
