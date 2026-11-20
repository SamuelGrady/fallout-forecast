extends Node3D
## Third-person survivor in a hazmat suit, built in code and animated from the
## Player's synced state: walk/sprint cycle from velocity, aim pitch from the
## head, idle breathing, a downed crawl. Other players see this; the owner's
## camera skips render layer 2, so you never see your own body.

const LAYER := 1 << 1
const SUIT_COLORS := [Color("#4fd1e0"), Color("#ff6fa8"), Color("#9be04a"), Color("#ff9a3c"), Color("#b48cff")]

var player: CharacterBody3D
var suit_color := Color(1.0, 0.85, 0.2)

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var _gun: Node3D
var _clock := 0.0
var _down_blend := 0.0
var _speed_smooth := 0.0
var _materials := {}


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	if player and player.get("suit_color") != null:
		suit_color = player.suit_color
		# Per-player suit colours so teammates are easy to tell apart. The
		# host keeps hazmat yellow; everyone else gets a colour by peer id.
		var peer := player.get_multiplayer_authority()
		if peer != 1 and suit_color == Color(1.0, 0.85, 0.2):
			suit_color = SUIT_COLORS[peer % SUIT_COLORS.size()]
	_build()
	_clock = randf() * TAU


func _build() -> void:
	var suit := suit_color
	var trim := suit.darkened(0.45)
	var rubber := Color("#1d2228")
	var visor := Color("#2fb7c4")
	_hips = Node3D.new()
	_hips.position.y = 0.92
	add_child(_hips)
	_part(_hips, Vector3(0, 0, 0), Vector3(0.42, 0.2, 0.26), suit)
	_part(_hips, Vector3(0, 0.08, 0), Vector3(0.44, 0.05, 0.28), rubber)  # belt
	_part(_hips, Vector3(0.18, 0.02, -0.12), Vector3(0.1, 0.12, 0.06), trim)  # pouch
	_torso = Node3D.new()
	_torso.position.y = 0.12
	_hips.add_child(_torso)
	_part(_torso, Vector3(0, 0.27, 0), Vector3(0.5, 0.48, 0.3), suit)
	_part(_torso, Vector3(0, 0.3, -0.16), Vector3(0.36, 0.32, 0.03), suit.lightened(0.12))  # chest panel
	_part(_torso, Vector3(-0.1, 0.38, -0.18), Vector3(0.1, 0.06, 0.02), Color("#e8ecef"))  # name tape
	_part(_torso, Vector3(0, 0.3, 0.2), Vector3(0.34, 0.42, 0.14), trim)  # backpack
	var tank := _part(_torso, Vector3(0, 0.3, 0.29), Vector3(0.16, 0.38, 0.12), Color("#c9d1d6"))
	tank.material_override = _mat(Color("#c9d1d6"), 0.6)
	_part(_torso, Vector3(0.14, 0.52, -0.15), Vector3(0.07, 0.07, 0.07), Color("#ffe9a8"), true)  # shoulder lamp
	_head = Node3D.new()
	_head.position.y = 0.6
	_torso.add_child(_head)
	_part(_head, Vector3(0, 0.14, 0), Vector3(0.32, 0.32, 0.32), suit)  # hood
	var glass := _part(_head, Vector3(0, 0.15, -0.15), Vector3(0.24, 0.16, 0.04), visor)
	glass.material_override = _mat(visor, 0.5, true)
	_part(_head, Vector3(0, 0.03, -0.17), Vector3(0.14, 0.1, 0.06), rubber)  # respirator
	for side in [-1.0, 1.0]:
		_part(_head, Vector3(side * 0.1, 0.02, -0.2), Vector3(0.07, 0.07, 0.07), Color("#3d4650"))  # filters
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.3, 0.46, 0)
		_torso.add_child(arm)
		_part(arm, Vector3(0, -0.14, 0), Vector3(0.14, 0.3, 0.15), suit)
		var fore := Node3D.new()
		fore.position = Vector3(0, -0.29, 0)
		arm.add_child(fore)
		_part(fore, Vector3(0, -0.13, 0), Vector3(0.12, 0.26, 0.13), suit)
		_part(fore, Vector3(0, -0.29, 0), Vector3(0.13, 0.09, 0.13), rubber)  # glove
		_arms.append(arm)
		_forearms.append(fore)
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.12, -0.06, 0)
		_hips.add_child(leg)
		_part(leg, Vector3(0, -0.2, 0), Vector3(0.17, 0.4, 0.18), suit)
		var shin := Node3D.new()
		shin.position = Vector3(0, -0.4, 0)
		leg.add_child(shin)
		_part(shin, Vector3(0, -0.17, 0), Vector3(0.15, 0.34, 0.16), suit)
		_part(shin, Vector3(0, -0.4, -0.04), Vector3(0.17, 0.12, 0.28), rubber)  # boot
		_part(shin, Vector3(0, -0.24, 0), Vector3(0.16, 0.04, 0.17), trim)  # boot cuff tape
		_legs.append(leg)
		_shins.append(shin)
	# Carried rifle, held across the body in the right hand.
	_gun = GunModels.build("rifle")
	_gun.scale = Vector3.ONE * 1.25
	_gun.position = Vector3(0.12, 0.2, -0.32)
	_torso.add_child(_gun)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.layers = LAYER
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _process(delta: float) -> void:
	if player == null:
		return
	var state := str(player.get("state"))
	var vel := player.velocity
	var speed := Vector2(vel.x, vel.z).length()
	_speed_smooth = lerpf(_speed_smooth, speed, 1.0 - exp(-10.0 * delta))
	var sprinting: bool = _speed_smooth > 6.5
	_clock += delta * (2.0 + _speed_smooth * 1.6)
	_down_blend = move_toward(_down_blend, 1.0 if state == "downed" else 0.0, delta * 3.0)
	var stride := clampf(_speed_smooth / 5.0, 0.0, 1.3)
	# Local move direction, so strafing and backpedalling read correctly.
	var local_vel := player.global_basis.inverse() * vel
	var backwards := -1.0 if local_vel.z > 0.4 else 1.0
	for i in 2:
		var phase := PI * i
		var swing := sin(_clock + phase) * 0.7 * stride * backwards
		_legs[i].rotation.x = swing
		_shins[i].rotation.x = -maxf(0.0, -sin(_clock + phase)) * 1.1 * stride - 0.05
	var bob := absf(sin(_clock)) * 0.05 * stride
	var breathe := sin(Time.get_ticks_msec() * 0.002) * 0.012
	_hips.position.y = 0.92 + bob - _down_blend * 0.62
	# Aim: the torso and arms follow the head's pitch; sprinting lowers the gun.
	var pitch := 0.0
	var head_node := player.get_node_or_null("Head") as Node3D
	if head_node:
		pitch = head_node.rotation.x
	_torso.rotation.x = -pitch * 0.35 + (0.25 if sprinting else 0.06) + breathe
	_head.rotation.x = -pitch * 0.55
	var aim_lift := -pitch * 0.65
	if sprinting:
		# Gun at port arms, arms pumping a little.
		_arms[0].rotation = Vector3(0.6 + sin(_clock) * 0.25, 0, 0.2)
		_arms[1].rotation = Vector3(0.9 - sin(_clock) * 0.25, 0, -0.25)
		_forearms[0].rotation.x = 1.2
		_forearms[1].rotation.x = 1.1
		_gun.rotation = Vector3(0.5, 0.9, 0.2)
	else:
		# Shouldered: both arms forward toward the gun.
		_arms[0].rotation = Vector3(1.25 + aim_lift, 0.15, 0.25)
		_arms[1].rotation = Vector3(1.35 + aim_lift, -0.3, -0.35)
		_forearms[0].rotation.x = 0.55
		_forearms[1].rotation.x = 0.25
		_gun.rotation = Vector3(aim_lift * 0.9, 0.0, 0.0)
	_gun.visible = state == "ok"
	_set_turned(state == "turned")
	if state == "turned":
		# Zombie lurch: arms out, head lolled, torso hunched.
		_arms[0].rotation = Vector3(1.4 + sin(_clock) * 0.15, 0, 0.1)
		_arms[1].rotation = Vector3(1.4 - sin(_clock) * 0.15, 0, -0.1)
		_forearms[0].rotation.x = 0.2
		_forearms[1].rotation.x = 0.3
		_torso.rotation.x = 0.35
		_head.rotation = Vector3(0.3, 0, 0.35)
	# Downed: roll onto the side, one arm reaching out, slow crawl.
	rotation.z = lerpf(0.0, 1.35, _down_blend)
	if _down_blend > 0.01:
		var crawl := sin(Time.get_ticks_msec() * 0.003)
		_arms[1].rotation = _arms[1].rotation.lerp(Vector3(2.6 + crawl * 0.3, 0, -0.2), _down_blend)
		_legs[0].rotation.x = lerpf(_legs[0].rotation.x, 0.3 + crawl * 0.2, _down_blend)


var _turned_shown := false
static var _turned_overlay: StandardMaterial3D


func _set_turned(value: bool) -> void:
	if value == _turned_shown:
		return
	_turned_shown = value
	if _turned_overlay == null:
		_turned_overlay = StandardMaterial3D.new()
		_turned_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_turned_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_turned_overlay.albedo_color = Color(0.55, 0.9, 0.3, 0.55)
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.material_overlay = _turned_overlay if value else null


func _part(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = _mat(color, 0.0, glow)
	parent.add_child(mesh)
	return mesh


func _mat(color: Color, metal := 0.0, glow := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), metal, glow]
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = metal
		material.roughness = 0.4 if metal > 0.0 else 0.75
		if glow:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 1.2
		_materials[key] = material
	return _materials[key]
