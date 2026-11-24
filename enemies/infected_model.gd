extends Node3D
## Original chunky infected silhouettes with articulated limbs.
var limbs: Array[Node3D] = []
var _clock := 0.0
var _hurt := 0.0
var _hurt_side := 0.0
var _attack := 0.0
var _body: Node3D
var _enemy: EnemyBase
var _head := Node3D.new()
var _head_kick := 0.0
var _anticipation := 0.0
var _mutation_root := Node3D.new()
var _spore_sacs: Array[MeshInstance3D] = []
var _molt_plates: Array[Node3D] = []
var _miniboss_halo: MeshInstance3D
var _miniboss_ground_ring: MeshInstance3D
var _miniboss_nodes: Array[MeshInstance3D] = []

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
	_body = Node3D.new()
	add_child(_body)
	_build_model()
	if _enemy.miniboss_wave > 0:
		_build_miniboss_trappings(_enemy.miniboss_wave)
	scale *= randf_range(0.94, 1.06)
	# One mesh per bone instead of ~40 boxes per enemy.
	for bone in [_body, _head, _jaw] + limbs + _elbows + _knees:
		if bone:
			MeshMerge.merge_children(bone, not _web_model)
	if _enemy.miniboss_wave > 0:
		_build_miniboss_mantle()
	_body.add_child(_mutation_root)
	_apply_mutations()
	if GameManager.mutations:
		GameManager.mutations.mutations_changed.connect(_on_mutations_changed)
	_enemy.winding_up.connect(func(): _anticipation = 1.0)
	_enemy.staggered.connect(func(): _hurt = 1.0)
	_enemy.impact_reaction.connect(func(direction: Vector3, critical: bool):
		_hurt = 1.0
		_hurt_side = clampf(direction.dot(_enemy.global_basis.x), -1.0, 1.0)
		if critical:
			_head_kick = 1.0)
	_enemy.molted.connect(_on_molted)
	_enemy.attacked.connect(func(_target, _amount): _attack = 1.0)
	scale *= 0.1
	create_tween().tween_property(self, "scale", scale * 10.0, .3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_enemy.damaged.connect(func(_amount, _health):
		_hurt = 1.0
		if _enemy._bullet_critical:
			_head_kick = 1.0)


func _build_model() -> void:
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
	var web := OS.has_feature("web")
	# Torso: pelvis, belly, chest. The shirt is torn open over the ribs.
	_piece(_body, Vector3(0, 0.8, 0), Vector3(.5, .2, .3), pants)
	_piece(_body, Vector3(0, 1.0, 0), Vector3(.52, .24, .3), shirt)
	_piece(_body, Vector3(0, 1.27, 0.02), Vector3(.6, .34, .34), shirt)
	if not web:
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
	if not web:
		_piece(_head, Vector3(.12, .24, -.08), Vector3(.08, .08, .08), Color("#3b3026") if not mister else skin.darkened(.2))
	for side in [-1.0, 1.0]:
		if not web:
			_piece(_head, Vector3(side * .1, .07, -.2), Vector3(.1, .07, .03), Color("#1a1412"))  # socket
			_piece(_head, Vector3(side * .21, .03, 0), Vector3(.04, .1, .08), skin.darkened(.1))  # ear
		_piece(_head, Vector3(side * .1, .07, -.215), Vector3(.045 if web else .035, .045 if web else .035, .02), Color("#ffed8a"), true)  # eye glow
	if not web:
		_piece(_head, Vector3(0, -.01, -.215), Vector3(.06, .06, .04), skin.darkened(.2))  # nose
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, -.11, .02)
	_head.add_child(_jaw)
	_piece(_jaw, Vector3(0, -.05, -.1), Vector3(.32, .09, .28), skin.darkened(.08))
	if not web:
		_piece(_jaw, Vector3(0, .0, -.22), Vector3(.26, .03, .03), Color("#efe6c8"))  # teeth
		_piece(_head, Vector3(0, -.1, -.2), Vector3(.26, .03, .03), Color("#efe6c8"))
		_piece(_head, Vector3(0, -.13, -.16), Vector3(.24, .05, .1), Color("#3a0f14"))  # mouth
	if gutter:
		# Wide maw with extra teeth and slime down the front.
		if not web:
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
		if not web:
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
		if not web and randf() < 0.3:
			_piece(knee, Vector3(0, -.08, -.1), Vector3(.12, .08, .02), skin.darkened(.15))  # torn knee
		limbs.append(leg)
		_knees.append(knee)
	if mister:
		# Bloated gut, spore growths on the back, a breathing tube from the mouth.
		_piece(_body, Vector3(0, 1.05, -.06), Vector3(.62, .46, .46), shirt.lightened(.1))
		for side in [-1.0, 1.0]:
			_piece(_body, Vector3(side * .3, 1.22, .26), Vector3(.34, .5, .34), accent, true)
		_piece(_body, Vector3(0, 1.45, .3), Vector3(.28, .3, .26), accent, true)
		if not web:
			_piece(_head, Vector3(0, -.12, -.32), Vector3(.1, .1, .22), Color("#5b4a66"))
		_piece(_head, Vector3(0, -.12, -.45), Vector3(.16, .16, .06), accent, true)
		scale = Vector3(1.2, 1.12, 1.15)
	if gutter:
		scale = Vector3(1.05, .82, 1.0)
		_body.rotation.x = -.25


func _exit_tree() -> void:
	if GameManager.mutations and GameManager.mutations.mutations_changed.is_connected(_on_mutations_changed):
		GameManager.mutations.mutations_changed.disconnect(_on_mutations_changed)


func _on_mutations_changed(_active: Array) -> void:
	_apply_mutations()


func _on_molted() -> void:
	for plate in _molt_plates:
		if is_instance_valid(plate):
			plate.visible = false
	_molt_plates.clear()


func _apply_mutations() -> void:
	for child in _mutation_root.get_children():
		_mutation_root.remove_child(child)
		child.queue_free()
	_spore_sacs.clear()
	_molt_plates.clear()
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
	if GameManager.has_mutation("conductors"):
		# Twin glowing cyan lightning prongs rising off the shoulders.
		for side in [-1.0, 1.0]:
			_piece(_mutation_root, Vector3(side * 0.36, 1.72, 0.08), Vector3(0.06, 0.52, 0.06), Color("#5ce8ff"), true, 0.6)
			_piece(_mutation_root, Vector3(side * 0.36, 1.98, 0.08), Vector3(0.12, 0.08, 0.12), Color("#c6f8ff"), true)
	if GameManager.has_mutation("molting") and not _enemy._molted:
		# Amber chitin carapace plates that pop off on the first hit.
		var shell := Node3D.new()
		_mutation_root.add_child(shell)
		_piece(shell, Vector3(0, 1.24, 0.22), Vector3(0.64, 0.54, 0.14), Color("#e8a238"), false, 0.3)
		for side in [-1.0, 1.0]:
			_piece(shell, Vector3(side * 0.42, 1.42, 0.06), Vector3(0.24, 0.24, 0.28), Color("#d48628"), false, 0.3)
		_molt_plates.append(shell)
	if GameManager.has_mutation("pressure_front"):
		# Dense indigo pressure bands strapped around the torso.
		for y in [0.95, 1.15, 1.35]:
			_piece(_mutation_root, Vector3(0, y, 0.0), Vector3(0.66, 0.07, 0.4), Color("#6a73d9"), false, 0.7)
	if _enemy.is_elite:
		# Twin amber bars above the silhouette identify elites through the rain.
		for side in [-1.0, 1.0]:
			_piece(_mutation_root, Vector3(side * 0.19, elite_crest_height(), -0.02), Vector3(0.23, 0.085, 0.18), Color("#ffc76f"), true)
	_mesh_merge_mutation_trim()


func elite_crest_height() -> float:
	return 2.02


func _mesh_merge_mutation_trim() -> void:
	if _web_model:
		MeshMerge.merge_children(_mutation_root, false)


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


static var _unit_box: BoxMesh
static var _web_model := OS.has_feature("web")
static var _miniboss_halo_mesh: TorusMesh
static var _miniboss_ground_mesh: TorusMesh
static var _miniboss_node_mesh: SphereMesh
static var _miniboss_halo_material: StandardMaterial3D
static var _miniboss_ground_material: StandardMaterial3D
static var _miniboss_node_material: StandardMaterial3D


func _build_miniboss_mantle() -> void:
	if _miniboss_halo_mesh == null:
		_miniboss_halo_mesh = TorusMesh.new()
		_miniboss_halo_mesh.inner_radius = 0.48
		_miniboss_halo_mesh.outer_radius = 0.62
		_miniboss_halo_mesh.rings = 24
		_miniboss_halo_mesh.ring_segments = 8
	if _miniboss_halo_material == null:
		_miniboss_halo_material = StandardMaterial3D.new()
		_miniboss_halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_miniboss_halo_material.albedo_color = Color(1.0, 0.36, 0.14)
		_miniboss_halo_material.emission_enabled = true
		_miniboss_halo_material.emission = Color(1.0, 0.24, 0.12)
		_miniboss_halo_material.emission_energy_multiplier = 2.6
	if _miniboss_node_mesh == null:
		_miniboss_node_mesh = SphereMesh.new()
		_miniboss_node_mesh.radius = 1.0
		_miniboss_node_mesh.height = 1.9
		_miniboss_node_mesh.radial_segments = 10
		_miniboss_node_mesh.rings = 6
	if _miniboss_node_material == null:
		_miniboss_node_material = StandardMaterial3D.new()
		_miniboss_node_material.albedo_color = Color(1.0, 0.48, 0.18)
		_miniboss_node_material.emission_enabled = true
		_miniboss_node_material.emission = Color(1.0, 0.28, 0.12)
		_miniboss_node_material.emission_energy_multiplier = 2.4
	if _miniboss_ground_mesh == null:
		_miniboss_ground_mesh = TorusMesh.new()
		_miniboss_ground_mesh.inner_radius = 0.92
		_miniboss_ground_mesh.outer_radius = 1.16
		_miniboss_ground_mesh.rings = 28
		_miniboss_ground_mesh.ring_segments = 6
	if _miniboss_ground_material == null:
		_miniboss_ground_material = StandardMaterial3D.new()
		_miniboss_ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_miniboss_ground_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_miniboss_ground_material.albedo_color = Color(1.0, 0.22, 0.12, 0.62)

	var crown := Node3D.new()
	crown.name = "MinibossMantle"
	_body.add_child(crown)

	_miniboss_halo = MeshInstance3D.new()
	_miniboss_halo.name = "MinibossHalo"
	_miniboss_halo.mesh = _miniboss_halo_mesh
	_miniboss_halo.material_override = _miniboss_halo_material
	_miniboss_halo.position = Vector3(0.0, 2.15, 0.0)
	_miniboss_halo.rotation = Vector3(0.28, 0.0, 0.14)
	if _web_model:
		_miniboss_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.add_child(_miniboss_halo)

	_miniboss_nodes.clear()
	for spec in [
		[Vector3(-0.34, 1.58, 0.28), 0.16],
		[Vector3(0.34, 1.58, 0.28), 0.16],
		[Vector3(0.0, 1.72, 0.32), 0.2],
		[Vector3(0.0, 1.32, 0.34), 0.18],
	]:
		var node_mesh := MeshInstance3D.new()
		node_mesh.mesh = _miniboss_node_mesh
		node_mesh.material_override = _miniboss_node_material
		node_mesh.position = spec[0]
		node_mesh.scale = Vector3.ONE * float(spec[1])
		node_mesh.set_meta("base_scale", float(spec[1]))
		if _web_model:
			node_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crown.add_child(node_mesh)
		_miniboss_nodes.append(node_mesh)

	_miniboss_ground_ring = MeshInstance3D.new()
	_miniboss_ground_ring.name = "MinibossGroundAura"
	_miniboss_ground_ring.mesh = _miniboss_ground_mesh
	_miniboss_ground_ring.material_override = _miniboss_ground_material
	_miniboss_ground_ring.position = Vector3(0.0, 0.06, 0.0)
	if _web_model:
		_miniboss_ground_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_miniboss_ground_ring)


func _build_miniboss_trappings(wave: int) -> void:
	match wave:
		1:
			# THE DREDGE: hazard bulldozer pauldrons + glowing toxic furnace core.
			var armor := Color("#c89328")
			var core := Color("#a8ff3e")
			_piece(_body, Vector3(0, 1.18, -0.22), Vector3(0.76, 0.56, 0.16), armor, false, 0.7)
			_piece(_body, Vector3(0, 1.18, -0.32), Vector3(0.24, 0.24, 0.08), core, true)
			for side in [-1.0, 1.0]:
				_piece(_body, Vector3(side * 0.54, 1.46, -0.02), Vector3(0.38, 0.32, 0.44), armor, false, 0.75)
			_piece(_head, Vector3(0, 0.28, -0.06), Vector3(0.48, 0.16, 0.46), armor, false, 0.7)
		2:
			# SEWER MATRIARCH: crimson dorsal spines + glowing brood sacs.
			var spine := Color("#ff3e7a")
			var sac := Color("#d4ff4a")
			for i in 3:
				_piece(_body, Vector3(0, 1.05 + i * 0.22, 0.26 + i * 0.03), Vector3(0.14, 0.22, 0.28), spine, true)
			for side in [-1.0, 1.0]:
				_piece(_body, Vector3(side * 0.34, 1.18, 0.24), Vector3(0.28, 0.34, 0.28), sac, true)
			_piece(_head, Vector3(0, 0.24, -0.1), Vector3(0.46, 0.12, 0.12), spine, true)
		3:
			# CLOUDBURST: oversized twin toxic canisters + neon respirator visor.
			var glow := Color("#88ff3c")
			var metal := Color("#463864")
			for side in [-1.0, 1.0]:
				_piece(_body, Vector3(side * 0.46, 1.38, 0.32), Vector3(0.36, 0.68, 0.36), metal, false, 0.6)
				_piece(_body, Vector3(side * 0.46, 1.76, 0.32), Vector3(0.26, 0.22, 0.26), glow, true)
			_piece(_head, Vector3(0, 0.06, -0.26), Vector3(0.42, 0.18, 0.1), glow, true)
		_:
			# VOLT GOLIATH: twin Tesla spires + crackling cyan chest reactor.
			var volt := Color("#66f2ff")
			var plate := Color("#23334c")
			_piece(_body, Vector3(0, 1.2, -0.22), Vector3(0.78, 0.6, 0.16), plate, false, 0.75)
			_piece(_body, Vector3(0, 1.2, -0.32), Vector3(0.26, 0.34, 0.08), volt, true)
			for side in [-1.0, 1.0]:
				_piece(_body, Vector3(side * 0.48, 1.76, 0.04), Vector3(0.12, 0.72, 0.12), plate, false, 0.8)
				_piece(_body, Vector3(side * 0.48, 2.16, 0.04), Vector3(0.24, 0.24, 0.24), volt, true)
			_piece(_head, Vector3(0, 0.26, 0), Vector3(0.5, 0.12, 0.46), volt, true)


func _piece(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := false, metallic := 0.0) -> MeshInstance3D:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	return _shape(parent, _unit_box, at, size, color, glow, metallic)


func _shape(parent: Node3D, shape: Mesh, at: Vector3, size: Vector3, color: Color, glow := false, metallic := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = at
	mesh.scale = size
	if _web_model:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = _shared_material(color, glow, metallic)
	parent.add_child(mesh)
	return mesh

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
	_body.rotation.z = sin(_clock * .5) * _gait.sway + _hurt * .22 * _hurt_side
	_body.rotation.x = _gait.lean + _hurt * 0.35
	for i in _spore_sacs.size():
		var pulse := 1.0 + 0.14 * sin(_clock * 1.4 + i * 1.3)
		_spore_sacs[i].scale = Vector3.ONE * pulse
	if is_instance_valid(_miniboss_halo):
		_miniboss_halo.rotation.y += delta * 2.4
		_miniboss_halo.rotation.z = 0.14 + sin(_clock * 1.1) * 0.15
		_miniboss_halo.scale = Vector3.ONE * (1.0 + 0.1 * sin(_clock * 1.8))
	for i in _miniboss_nodes.size():
		var node_mesh := _miniboss_nodes[i]
		if is_instance_valid(node_mesh):
			var base_s := float(node_mesh.get_meta("base_scale", 0.16))
			node_mesh.scale = Vector3.ONE * (base_s * (1.0 + 0.18 * sin(_clock * 2.0 + i * 1.4)))
	if is_instance_valid(_miniboss_ground_ring):
		_miniboss_ground_ring.rotation.y -= delta * 0.9
		var aura_p := 1.0 + 0.08 * sin(_clock * 1.5)
		_miniboss_ground_ring.scale = Vector3(aura_p, 1.0, aura_p)
