extends Interactable
## A rotating district objective. GameManager activates one per storm,
## and completing it pays out a decon charge and a supply pack.
##
## Every peer builds the same objectives (main.gd); the host chooses
## the active one and syncs it through GameManager.

const PINECREST_SITES := {
	"pharmacy": {"label": "RESTART GENERATOR", "at": Vector3(9, 0, 20)},
	"water_tower": {"label": "SWAP WATER FILTER", "at": Vector3(-52, 0, -43)},
	"gas_pumps": {"label": "SEAL GAS PUMPS", "at": Vector3(45, 0, 16)},
}

var site := ""
var site_label := ""
var active := false
var _beacon: MeshInstance3D
var _clock := 0.0


func _init() -> void:
	hold_time = 4.0
	radius = 2.6


func _ready() -> void:
	super._ready()
	add_to_group("district_objectives")
	prompt = site_label.capitalize()
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.12
	cylinder.bottom_radius = 0.18
	cylinder.height = 1.4
	pole.mesh = cylinder
	pole.position.y = -0.3
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color("#3a4652")
	pole.material_override = pole_material
	add_child(pole)
	_beacon = MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.25
	beam.bottom_radius = 0.25
	beam.height = 30.0
	_beacon.mesh = beam
	_beacon.position.y = 14.0
	var beam_material := StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.albedo_color = Color(1.0, 0.85, 0.3, 0.35)
	beam_material.disable_fog = true
	_beacon.material_override = beam_material
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)
	set_active(false)


func set_active(value: bool) -> void:
	if value and not active:
		Perf.mark("objective active " + site)
	active = value
	if _beacon:
		_beacon.visible = value


func _process(delta: float) -> void:
	if active and _beacon:
		_clock += delta
		_beacon.scale = Vector3(1.0 + 0.25 * sin(_clock * 4.0), 1.0, 1.0 + 0.25 * sin(_clock * 4.0))


func can_interact(player: Node) -> bool:
	return active and player.get("state") == "ok"


func interact(player: Node) -> void:
	GameManager.complete_objective(self, player)
