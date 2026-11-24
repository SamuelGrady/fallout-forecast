extends Node3D
## Third-person survivor in a hazmat suit, built in code and animated from the
## Player's synced state: walk/sprint cycle from velocity, aim pitch from the
## head, idle breathing, a downed crawl. Other players see this; the owner's
## camera skips render layer 2, so you never see your own body.

const LAYER := 1 << 1

var player: CharacterBody3D
var suit_color := Color(1.0, 0.85, 0.2)
## Index into Cosmetics.SKINS: changes the head, back and trim parts.
var skin := 0

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var weapon_mount := Node3D.new()
var _clock := 0.0
var _down_blend := 0.0
var _speed_smooth := 0.0
var _materials := {}


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	if player and player.get("suit_color") != null:
		suit_color = player.suit_color
		skin = int(player.get("skin"))
	weapon_mount.name = "WeaponMount"
	add_child(weapon_mount)
	_build()
	_clock = randf() * TAU


## Rebuild with a new look (lobby preview, or a roster change mid-run).
func set_look(color: Color, new_skin: int) -> void:
	new_skin = Cosmetics.wrap_skin(new_skin)
	if color == suit_color and new_skin == skin and _hips != null:
		return
	suit_color = color
	skin = new_skin
	if _hips == null:
		return  # Not built yet: _ready builds with these.
	remove_child(_hips)
	_hips.queue_free()
	_arms.clear()
	_forearms.clear()
	_legs.clear()
	_shins.clear()
	_turned_shown = false
	_build()


func _build() -> void:
	skin = Cosmetics.wrap_skin(skin)
	var suit := suit_color
	var trim := suit.darkened(0.45)
	var rubber := Color("#1d2228")
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
	_head = Node3D.new()
	_head.position.y = 0.6
	_torso.add_child(_head)
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
	match skin:
		1: _dress_gas_mask(suit, trim, rubber)
		2: _dress_firefighter(suit, trim, rubber)
		3: _dress_biotech(suit, trim, rubber)
		4: _dress_ion_rig(suit, trim, rubber)
		_: _dress_standard(suit, trim, rubber)
	# Only the local owner's own body sits on Layer 2 (culled by the local
	# first-person camera). Remote players and lobby previews sit on Layer 1
	# so every teammate is visible.
	var render_layer := LAYER if (player and player.is_multiplayer_authority()) else 1
	for mesh in _hips.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = render_layer
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ------------------------------------------------------------------ skins
# Every skin hangs its parts off _torso, _head, the arms or the legs, so the
# walk, aim, downed and Turned poses move them with the body.

## The original hazmat suit: visor, respirator, backpack and air tank.
func _dress_standard(suit: Color, trim: Color, rubber: Color) -> void:
	_chest(suit)
	_part(_torso, Vector3(0, 0.3, 0.2), Vector3(0.34, 0.42, 0.14), trim)  # backpack
	_metal(_torso, Vector3(0, 0.3, 0.29), Vector3(0.16, 0.38, 0.12))  # tank
	_part(_torso, Vector3(0.14, 0.52, -0.15), Vector3(0.07, 0.07, 0.07), Color("#ffe9a8"), true)  # shoulder lamp
	_hood(suit)
	_glass(_head, Vector3(0, 0.15, -0.15), Vector3(0.24, 0.16, 0.04))
	_part(_head, Vector3(0, 0.03, -0.17), Vector3(0.14, 0.1, 0.06), rubber)  # respirator
	for side in [-1.0, 1.0]:
		_part(_head, Vector3(side * 0.1, 0.02, -0.2), Vector3(0.07, 0.07, 0.07), Color("#3d4650"))  # filters


## Rubber gas mask with twin eyepieces and one big snout canister, a
## shoulder strap and a mask bag instead of the air tank.
func _dress_gas_mask(suit: Color, trim: Color, rubber: Color) -> void:
	_chest(suit)
	var strap := _part(_torso, Vector3(0, 0.3, -0.18), Vector3(0.06, 0.62, 0.02), rubber)
	strap.rotation.z = 0.75
	_part(_hips, Vector3(-0.25, -0.02, 0.0), Vector3(0.08, 0.2, 0.22), trim)  # mask bag
	_part(_torso, Vector3(0, 0.32, 0.18), Vector3(0.3, 0.3, 0.08), trim)  # small pack
	_hood(suit)
	_part(_head, Vector3(0, 0.12, -0.165), Vector3(0.28, 0.26, 0.03), rubber)  # face plate
	for side in [-1.0, 1.0]:
		_part(_head, Vector3(side * 0.07, 0.19, -0.18), Vector3(0.1, 0.1, 0.02), Color("#6b737c"))  # lens rim
		_glass(_head, Vector3(side * 0.07, 0.19, -0.19), Vector3(0.07, 0.07, 0.02), Color("#ffb347"))
		_part(_head, Vector3(side * 0.165, 0.14, 0), Vector3(0.02, 0.05, 0.3), rubber)  # head strap
	_part(_head, Vector3(0, 0.03, -0.2), Vector3(0.1, 0.08, 0.06), rubber)  # snout
	_metal(_head, Vector3(0, 0.0, -0.27), Vector3(0.13, 0.13, 0.1), Color("#5f6b52"))  # canister
	_part(_head, Vector3(0, 0.0, -0.325), Vector3(0.09, 0.09, 0.02), Color("#2a2f26"))  # canister grille


## Turnout coat with reflective bands, a broad-brimmed helmet with a crest
## and badge, and a big breathing-air cylinder.
func _dress_firefighter(suit: Color, _trim: Color, rubber: Color) -> void:
	var band := Color("#e9f2c4")
	_part(_torso, Vector3(0, 0.3, -0.16), Vector3(0.06, 0.4, 0.02), rubber)  # coat clasp line
	for side in [-1.0, 1.0]:
		_part(_torso, Vector3(side * 0.13, 0.3, -0.165), Vector3(0.05, 0.44, 0.02), Color("#3a3a3a"))  # harness
	_part(_torso, Vector3(0, 0.1, 0), Vector3(0.52, 0.05, 0.32), band, true)  # waist band
	_part(_torso, Vector3(0, 0.42, 0), Vector3(0.52, 0.04, 0.32), band, true)  # chest band
	for i in 2:
		_part(_forearms[i], Vector3(0, -0.12, 0), Vector3(0.13, 0.04, 0.14), band, true)
		_part(_shins[i], Vector3(0, -0.1, 0), Vector3(0.16, 0.04, 0.17), band, true)
	_metal(_torso, Vector3(0, 0.28, 0.24), Vector3(0.2, 0.46, 0.18), Color("#d9dde0"))  # air cylinder
	_part(_torso, Vector3(0, 0.05, 0.24), Vector3(0.22, 0.04, 0.2), rubber)  # cylinder strap
	_hood(suit.darkened(0.1))
	_glass(_head, Vector3(0, 0.12, -0.16), Vector3(0.26, 0.2, 0.03))  # face shield
	var helmet := suit.lightened(0.08)
	_part(_head, Vector3(0, 0.33, 0.0), Vector3(0.36, 0.12, 0.36), helmet)  # dome
	_part(_head, Vector3(0, 0.27, 0.05), Vector3(0.46, 0.03, 0.52), helmet)  # brim, longer at the back
	_part(_head, Vector3(0, 0.4, 0.0), Vector3(0.05, 0.05, 0.38), helmet.darkened(0.2))  # crest
	_part(_head, Vector3(0, 0.34, -0.19), Vector3(0.1, 0.11, 0.02), Color("#d8b23a"))  # badge
	_part(_head, Vector3(0, 0.31, 0.0), Vector3(0.37, 0.025, 0.37), band, true)  # helmet band


## Lab field tech: twin sample tanks, a lit antenna, shoulder pads and a wrist computer.
func _dress_biotech(suit: Color, trim: Color, rubber: Color) -> void:
	_chest(suit)
	for side in [-1.0, 1.0]:
		_metal(_torso, Vector3(side * 0.09, 0.3, 0.25), Vector3(0.13, 0.44, 0.13), Color("#b8e0d0"))  # tank
		_part(_torso, Vector3(side * 0.09, 0.54, 0.25), Vector3(0.07, 0.04, 0.07), rubber)  # valve
	_part(_torso, Vector3(0, 0.3, 0.17), Vector3(0.36, 0.06, 0.04), Color("#3d4650"))  # frame
	_part(_torso, Vector3(0, 0.08, 0.22), Vector3(0.36, 0.06, 0.14), Color("#3d4650"))
	_part(_torso, Vector3(0, 0.3, 0.33), Vector3(0.05, 0.14, 0.02), Color("#7dff6a"), true)  # level gauge
	_part(_torso, Vector3(-0.16, 0.82, 0.25), Vector3(0.02, 0.56, 0.02), Color("#2a2f36"))  # antenna
	_part(_torso, Vector3(-0.16, 1.11, 0.25), Vector3(0.05, 0.05, 0.05), Color("#ff3a3a"), true)  # tip
	for i in 2:
		_part(_arms[i], Vector3(0, 0.0, 0), Vector3(0.19, 0.07, 0.2), trim)  # shoulder pad
	_part(_forearms[0], Vector3(0, -0.17, -0.02), Vector3(0.14, 0.08, 0.12), Color("#2a2f36"))  # wrist computer
	_part(_forearms[0], Vector3(-0.071, -0.17, -0.02), Vector3(0.01, 0.06, 0.09), Color("#7dff6a"), true)
	_hood(suit)
	_glass(_head, Vector3(0, 0.13, -0.155), Vector3(0.28, 0.22, 0.04), Color("#8fe8ff"))  # full visor
	_part(_head, Vector3(0, 0.31, -0.08), Vector3(0.1, 0.05, 0.1), Color("#2a2f36"))  # head lamp
	_part(_head, Vector3(0, 0.31, -0.135), Vector3(0.07, 0.035, 0.01), Color("#ffe9a8"), true)


## Field "ion rig": a big boxy generator pack with vents and a glowing
## charge gauge, shoulder straps, a hose to the hip and a headset.
func _dress_ion_rig(suit: Color, _trim: Color, rubber: Color) -> void:
	var pack := Color("#3a4048")
	_part(_torso, Vector3(-0.1, 0.38, -0.18), Vector3(0.1, 0.06, 0.02), Color("#e8ecef"))  # name tape
	for side in [-1.0, 1.0]:
		_part(_torso, Vector3(side * 0.14, 0.32, -0.16), Vector3(0.06, 0.44, 0.02), rubber)  # strap
	_part(_torso, Vector3(0, 0.3, 0.27), Vector3(0.44, 0.52, 0.24), pack)  # generator box
	_metal(_torso, Vector3(0, 0.02, 0.27), Vector3(0.36, 0.1, 0.22), Color("#9aa3ab"))  # coil housing
	for i in 3:
		_part(_torso, Vector3(-0.08, 0.42 - i * 0.07, 0.395), Vector3(0.2, 0.025, 0.01), Color("#ff8a2a"), true)  # vents
	_part(_torso, Vector3(0.13, 0.3, 0.395), Vector3(0.07, 0.3, 0.01), Color("#2a2f36"))
	_part(_torso, Vector3(0.13, 0.25, 0.4), Vector3(0.04, 0.18, 0.01), Color("#66dfda"), true)  # charge gauge
	_part(_torso, Vector3(-0.18, 0.62, 0.32), Vector3(0.03, 0.12, 0.03), Color("#2a2f36"))  # stub antenna
	# Hose from the pack's base round the right side.
	_part(_torso, Vector3(0.24, 0.04, 0.18), Vector3(0.06, 0.06, 0.12), rubber)
	_part(_torso, Vector3(0.28, 0.02, 0.04), Vector3(0.06, 0.06, 0.2), rubber)
	_hood(suit)
	_glass(_head, Vector3(0, 0.15, -0.15), Vector3(0.26, 0.12, 0.04))
	_part(_head, Vector3(0.17, 0.14, 0), Vector3(0.04, 0.12, 0.12), Color("#2a2f36"))  # earpiece
	var mic := _part(_head, Vector3(0.13, 0.04, -0.13), Vector3(0.02, 0.02, 0.16), Color("#2a2f36"))
	mic.rotation.y = 0.5
	_part(_head, Vector3(0, 0.31, 0), Vector3(0.3, 0.03, 0.06), Color("#2a2f36"))  # headband


func _chest(suit: Color) -> void:
	_part(_torso, Vector3(0, 0.3, -0.16), Vector3(0.36, 0.32, 0.03), suit.lightened(0.12))  # chest panel
	_part(_torso, Vector3(-0.1, 0.38, -0.18), Vector3(0.1, 0.06, 0.02), Color("#e8ecef"))  # name tape


func _hood(color: Color) -> void:
	_part(_head, Vector3(0, 0.14, 0), Vector3(0.32, 0.32, 0.32), color)


func _glass(parent: Node3D, at: Vector3, size: Vector3, color := Color("#2fb7c4")) -> MeshInstance3D:
	var glass := _part(parent, at, size, color)
	glass.material_override = _mat(color, 0.5, true)
	return glass


func _metal(parent: Node3D, at: Vector3, size: Vector3, color := Color("#c9d1d6")) -> MeshInstance3D:
	var mesh := _part(parent, at, size, color)
	mesh.material_override = _mat(color, 0.6)
	return mesh


func _process(delta: float) -> void:
	if _hips == null:
		return
	# No Player parent (the lobby preview): idle, standing, aiming level.
	var state := str(player.get("state")) if player else "ok"
	var vel := player.velocity if player else Vector3.ZERO
	var speed := Vector2(vel.x, vel.z).length()
	_speed_smooth = lerpf(_speed_smooth, speed, 1.0 - exp(-10.0 * delta))
	var sprinting: bool = _speed_smooth > 6.5
	_clock += delta * (2.0 + _speed_smooth * 1.6)
	_down_blend = move_toward(_down_blend, 1.0 if state == "downed" else 0.0, delta * 3.0)
	var stride := clampf(_speed_smooth / 5.0, 0.0, 1.3)
	# Local move direction, so strafing and backpedalling read correctly.
	var local_vel := player.global_basis.inverse() * vel if player else Vector3.ZERO
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
	var head_node := (player.get_node_or_null("Head") as Node3D) if player else null
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
	else:
		# Shouldered: both arms forward toward the gun.
		_arms[0].rotation = Vector3(1.25 + aim_lift, 0.15, 0.25)
		_arms[1].rotation = Vector3(1.35 + aim_lift, -0.3, -0.35)
		_forearms[0].rotation.x = 0.55
		_forearms[1].rotation.x = 0.25
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
	# Sample the glove after animating the body. The mount survives suit rebuilds.
	weapon_mount.global_position = _forearms[1].to_global(Vector3(0, -0.29, 0))
	var aim := Vector3(0.3, 0.6, 0.2) if sprinting else Vector3(aim_lift * 0.9, 0, 0)
	weapon_mount.global_basis = _torso.global_basis * Basis.from_euler(aim)
	weapon_mount.visible = state == "ok"


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
	for mesh in _hips.find_children("*", "MeshInstance3D", true, false):
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
