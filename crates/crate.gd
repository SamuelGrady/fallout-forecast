extends StaticBody3D
## A mystery crate. CrateManager spawns these during Calm. Opening swings the
## lid open, illuminates the interior, and lifts the actual 3D reward out of
## the crate. Cooperative double crates display two illuminated hand pads.

const TIER_COLORS := {"common": Color(0.95, 0.92, 0.85), "rare": Color("2EE6E6"), "cursed": Color("FF3EA5")}

@export var double := false

var _result := ""
var _result_item := ""
var _result_color := Color.WHITE
var _reveal_left := 0.0
var _gone_in := -1.0
var _clock := 0.0
var _partner_waiting := 0.0

var _lid_hinge := Node3D.new()
var _reward_root := Node3D.new()
var _glow: OmniLight3D
var _hand_pads: Array[MeshInstance3D] = []

@onready var label: Label3D = $Spin
@onready var model: Node3D = $Model


func _ready() -> void:
	add_to_group("crates")
	label.visible = false
	label.font = preload("res://assets/fonts/VT323-Regular.ttf")
	label.pixel_size = 0.008
	label.font_size = 56
	_build_lid_and_pads()
	_reward_root.position = Vector3(0, 0.55, 0)
	add_child(_reward_root)


func _build_lid_and_pads() -> void:
	var length := 2.35 if double else 1.95
	var width := 1.08
	# Hinged metallic lid that swings open on reveal.
	_lid_hinge.position = Vector3(-width * 0.5, 0.74, 0.0)
	add_child(_lid_hinge)
	var lid := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.08, length)
	lid.mesh = box
	lid.position = Vector3(width * 0.5, 0.04, 0.0)
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color("#4a3f28") if double else Color("#2f3e48")
	lid_mat.roughness = 0.55
	lid.material_override = lid_mat
	_lid_hinge.add_child(lid)
	# Trim strip along lid edge.
	var trim := MeshInstance3D.new()
	var trim_box := BoxMesh.new()
	trim_box.size = Vector3(0.08, 0.09, length + 0.02)
	trim.mesh = trim_box
	trim.position = Vector3(width - 0.05, 0.045, 0.0)
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color("#FFE04A") if double else Color("#66dfda")
	trim_mat.emission_enabled = true
	trim_mat.emission = trim_mat.albedo_color
	trim_mat.emission_energy_multiplier = 0.9
	trim.material_override = trim_mat
	_lid_hinge.add_child(trim)
	if double:
		# Two illuminated hand-pad positions on opposite ends for cooperative opening.
		for z_pos in [-0.72, 0.72]:
			var pad := MeshInstance3D.new()
			var pad_box := BoxMesh.new()
			pad_box.size = Vector3(0.42, 0.03, 0.42)
			pad.mesh = pad_box
			pad.position = Vector3(width * 0.5, 0.095, z_pos)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color("#FFE04A")
			pad.material_override = mat
			_lid_hinge.add_child(pad)
			# Small hand/palm imprint silhouette on top of the pad.
			var palm := MeshInstance3D.new()
			var pbox := BoxMesh.new()
			pbox.size = Vector3(0.18, 0.015, 0.2)
			palm.mesh = pbox
			palm.position = Vector3(0, 0.02, 0.02)
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color("#18212b")
			palm.material_override = pmat
			pad.add_child(palm)
			for fx in [-0.07, -0.025, 0.025, 0.07]:
				var finger := MeshInstance3D.new()
				var fbox := BoxMesh.new()
				fbox.size = Vector3(0.032, 0.015, 0.12)
				finger.mesh = fbox
				finger.position = Vector3(fx, 0.02, -0.11)
				finger.material_override = pmat
				pad.add_child(finger)
			_hand_pads.append(pad)


func set_partner_waiting(duration: float) -> void:
	_partner_waiting = duration


func can_ping() -> bool:
	return _result == "" and not is_queued_for_deletion()


## Every peer: open the lid and lift the actual reward hovering out of the crate.
func play_spin(result: String, tier: String, _pool: Array, item_id := "") -> void:
	Perf.mark("crate open " + (item_id if not item_id.is_empty() else tier))
	Sound.play_at("crate_open", global_position)
	_result = result
	_result_item = item_id
	_result_color = TIER_COLORS.get(tier, Color.WHITE)
	_reveal_left = 0.65
	_partner_waiting = 0.0
	label.visible = false
	if not OS.has_feature("web") and not Net.dedicated:
		_glow = OmniLight3D.new()
		_glow.light_color = _result_color
		_glow.light_energy = 0.2
		_glow.omni_range = 4.5
		_glow.position = Vector3(0, 0.9, 0)
		add_child(_glow)
	# Swing lid open smoothly and brighten the interior glow.
	var t := create_tween().set_parallel(true)
	t.tween_property(_lid_hinge, "rotation_degrees:z", 108.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow:
		t.tween_property(_glow, "light_energy", 3.2, 0.55)
	_build_reward_mesh(item_id, _result_color)
	_reward_root.position = Vector3(0, 0.5, 0)
	_reward_root.scale = Vector3.ONE * 0.1
	t.tween_property(_reward_root, "position:y", 1.35, 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_reward_root, "scale", Vector3.ONE, 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_reward_mesh(item_id: String, accent: Color) -> void:
	for child in _reward_root.get_children():
		child.queue_free()
	if item_id.begins_with("weapon:"):
		var data := load(item_id.trim_prefix("weapon:")) as WeaponData
		var gun := data.make_model() if data else null
		if gun:
			gun.scale = Vector3.ONE * (2.4 if data.gun_model != "" else 1.45)
			_reward_root.add_child(gun)
			return
	match item_id:
		"medkit":
			_box(_reward_root, Vector3.ZERO, Vector3(0.46, 0.32, 0.2), Color("#eff2ea"), 0.25)
			for z in [-0.105, 0.105]:
				_box(_reward_root, Vector3(0, 0, z), Vector3(0.22, 0.07, 0.03), Color("#ff6e91"), 0.8)
				_box(_reward_root, Vector3(0, 0, z), Vector3(0.07, 0.22, 0.03), Color("#ff6e91"), 0.8)
		"suit_patch":
			_cyl(_reward_root, Vector3.ZERO, 0.16, 0.42, Color("#1f3542"))
			_cyl(_reward_root, Vector3.ZERO, 0.166, 0.24, Color("#66dfda"), 0.8)
		"flares":
			for x in [-0.1, 0.0, 0.1]:
				_cyl(_reward_root, Vector3(x, 0, 0), 0.04, 0.36, Color("#ff4d4d"), 0.8)
		"tarp":
			var roll := _cyl(_reward_root, Vector3.ZERO, 0.13, 0.56, Color("#56b8e8"), 0.6)
			roll.rotation_degrees.z = 90.0
		"decon":
			_cyl(_reward_root, Vector3.ZERO, 0.14, 0.46, Color("#2EE6E6"), 0.9)
			_cyl(_reward_root, Vector3(0, 0.24, 0), 0.19, 0.06, Color("#eff2ea"), 0.3)
		_:
			# Ammo / base_ammo / default supply box with brass shells.
			_box(_reward_root, Vector3(0, -0.04, 0), Vector3(0.44, 0.24, 0.26), Color("#3c4b39"))
			_box(_reward_root, Vector3(0, -0.02, 0), Vector3(0.46, 0.06, 0.28), accent, 0.6)
			for x in [-0.12, 0.0, 0.12]:
				_cyl(_reward_root, Vector3(x, 0.16, 0), 0.038, 0.18, Color("#f6cf64"), 0.6)


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _mat(color, glow)
	parent.add_child(mi)
	return mi


func _mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _process(delta: float) -> void:
	_clock += delta
	if not _hand_pads.is_empty():
		if _partner_waiting > 0.0:
			_partner_waiting = maxf(0.0, _partner_waiting - delta)
			(_hand_pads[0].material_override as StandardMaterial3D).albedo_color = Color("#2EE6E6")
			var blink := 0.55 + 0.45 * sin(_clock * 16.0)
			(_hand_pads[1].material_override as StandardMaterial3D).albedo_color = Color("#FFE04A").lerp(Color.WHITE, blink)
		else:
			var pulse := 0.75 + 0.25 * sin(_clock * 3.5)
			for pad in _hand_pads:
				(pad.material_override as StandardMaterial3D).albedo_color = Color("#FFE04A") * pulse
	if _reward_root.get_child_count() > 0:
		_reward_root.rotation.y += delta * 2.2
		_reward_root.position.y += sin(_clock * 4.0) * delta * 0.12
	if _reveal_left > 0.0:
		_reveal_left -= delta
		if _reveal_left <= 0.0:
			Sound.play_at("pickup", global_position)
			label.text = _result
			label.modulate = _result_color
			label.position.y = 1.9
			label.visible = true
			_gone_in = 1.9
			var t := create_tween().set_parallel(true)
			t.tween_property(_reward_root, "position:y", 1.75, 1.1).set_delay(0.5)
			t.tween_property(_reward_root, "scale", Vector3.ZERO, 0.35).set_delay(1.3)
			t.tween_property(self, "scale", Vector3.ONE * 0.02, 0.35).set_delay(1.55)
	if _gone_in > 0.0:
		_gone_in -= delta
		label.position.y += delta * 0.22
		if _gone_in <= 0.0 and is_inside_tree():
			queue_free()
