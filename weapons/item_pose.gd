extends RefCounted
## Each row identifies the action, moving part and support-hand grip in model space.
const PROFILES := {
	"service_revolver": ["swing", "Cylinder", -0.018],
	"lucky_penny_revolver": ["swing", "Cylinder", -0.018],
	"pump_shotgun": ["tube", "Pump", -0.18],
	"spray_rifle": ["mag", "Magazine", -0.15],
	"nail_driver": ["mag", "Magazine", -0.075],
	"leaky_nailgun": ["mag", "Magazine", -0.12],
	"hunting_rifle": ["bolt", "Bolt", -0.14],
	"pressure_washer": ["hose", "Wand", -0.095],
	"rock_salt": ["break", "Barrel", -0.08],
	"battery_zapper": ["charge", "Clamps", -0.10],
	"flare_launcher": ["flare", "Barrel", -0.055],
	"harpoon": ["reel", "Spool", -0.095],
	"leaf_blower": ["fan", "Fan", -0.085],
	"disruptor": ["tune", "Dish", -0.10],
	"boombox_launcher": ["tube", "", -0.055],
	"frag": ["lob", "", -0.015],
	"shield_dome": ["toss", "", -0.016],
	"umbrella": ["lob", "Canopy", -0.07],
	"bleach_bomb": ["lob", "Cap", -0.035],
	"bait_radio": ["toss", "Antenna", -0.04],
	"sandbag": ["place", "Sack", -0.06],
	"lightning_rod": ["plant", "Spike", -0.07],
	"med_tin": ["open", "Lid", -0.045],
	"suit_patch": ["press", "Patch", -0.035],
}
const G := preload("res://weapons/gun_models.gd")
var support: Node3D
var part: Node3D
var rest := Transform3D.IDENTITY
var grip := Vector3.ZERO
var rounds: Array[Node3D] = []
var action: String

func bind(model: Node3D, id: String) -> void:
	var row: Array = PROFILES[id]
	action = row[0]
	part = model.get_node_or_null(NodePath(row[1])) if row[1] != "" else null
	if part:
		rest = part.transform
	rounds.clear()
	if action == "flare":
		for index in 3:
			rounds.append(G._box(model, Vector3(0.009, 0.009, 0.014), Vector3(-0.023, 0.013, -0.02 - index * 0.02), Color("#ffe893")))
	for side in [-1, 1]:
		var hand := Node3D.new()
		model.add_child(hand)
		hand.position = Vector3(side * 0.026, -0.045, row[2] if side < 0 else 0.033)
		if side < 0:
			support = hand
			grip = hand.position
		var rubber := Color("#333f3d")
		G._box(hand, Vector3(0.042, 0.043, 0.062), Vector3.ZERO, rubber)
		G._box(hand, Vector3(0.056, 0.055, 0.1), Vector3(side * 0.009, -0.018, 0.073), Color("#c8a245"), 0, Vector3(16, side * 10, 0))
		for finger in 3:
			G._box(hand, Vector3(0.031, 0.016, 0.014), Vector3(-side * 0.017, 0.012, -0.022 + finger * 0.017), rubber.lightened(0.1))

func show_rounds(count: int) -> void:
	for index in rounds.size():
		rounds[index].visible = index < count

func pose(model: Node3D, reload_phase: float, pulse: float, charge: float, delta: float) -> void:
	var reach := sin(PI * reload_phase)
	var target := Vector3(-0.045, -0.10, 0.005)
	match action:
		"swing": target = Vector3(-0.064, 0.010, 0.012)
		"tube", "reel": target = Vector3(-0.015, -0.042, -0.045)
		"bolt", "break": target = Vector3(0.032, 0.015, 0.036)
		"charge", "tune": target = Vector3(-0.046, 0.049, -0.087)
	support.position = grip.lerp(target, reach)
	model.rotation_degrees += gesture_angles(action) * pulse + Vector3(-4, 0, -8) * charge
	match action:
		"open", "press":
			model.position += Vector3(-0.09, 0.04, 0.05) * pulse
			support.position += Vector3(0.015, 0.05, -0.01) * pulse
		"plant", "place":
			model.position += Vector3(-0.025, -0.055, -0.11) * pulse
		"lob", "toss":
			model.position += Vector3(-0.045, 0.06, -0.095) * pulse
	if not part:
		return
	if action == "fan":
		part.rotate_x(delta * (pulse * 42 + reach * 5))
		return
	if action in ["tube", "reel"]:
		return # Existing pump and reel motion follows their firing cycles.
	part.transform = rest
	match action:
		"swing":
			part.position.x -= reach * 0.048
			part.rotate_object_local(Vector3.UP, pulse * PI / 3 + reach * PI)
		"mag": part.position.y -= reach * 0.095
		"bolt": part.position.z += 0.045 * maxf(reach, pulse)
		"break": part.rotation.x -= reach * 0.72
		"hose": part.rotation.x += pulse * 0.09 - reach * 0.16
		"flare": part.rotation.x += pulse * 0.09
		"charge": part.rotation.z += pulse * 0.32 + reach * 0.4
		"tune": part.rotation.y += pulse * 0.5 + reach * PI + charge * 0.65
		"open": part.rotation.x -= pulse * 1.4
		"lob", "toss", "plant", "press": part.position.y += pulse * 0.022

func equip_angles() -> Vector3:
	match action:
		"lob", "toss": return Vector3(-15, 16, 22)
		"open", "press": return Vector3(16, -24, -15)
		"plant", "place": return Vector3(-26, -8, 5)
		"swing", "flare": return Vector3(-30, 12, 14)
		_: return Vector3(-16, 9, -12)

static func gesture_angles(style: String) -> Vector3:
	match style:
		"lob": return Vector3(38, -12, 20)
		"toss": return Vector3(-25, 15, -18)
		"plant": return Vector3(-48, 0, 8)
		"place": return Vector3(-22, 3, 9)
		"open": return Vector3(22, -32, -18)
		"press": return Vector3(-8, -30, 30)
		"flare": return Vector3(18, 0, -9)
		"tube", "reel": return Vector3(9, 0, -3)
		"hose", "fan": return Vector3(2, 1, -2)
		_: return Vector3(5, 0, -3)
