class_name ItemCatalog
extends RefCounted

const STANDARD := 0
const TUNED := 1
const OVERCLOCKED := 2
const TIER_NAMES := ["STANDARD", "TUNED", "OVERCLOCKED"]
const TIER_COLORS := [Color("#fff0d9"), Color("#66dfda"), Color("#ffc365")]
const DAMAGE_SCALE := [1.0, 1.08, 1.16]
const CAPS := {"shell": 36, "rifle": 200, "nail": 120, "water": 120, "cell": 80,
	"flare": 12, "shaft": 10, "fuel": 100, "radio": 12, "rocket": 10, "revolver": 36}
const MODELS := "res://weapons/item_models.gd"

const GUNS := {
	"service_revolver": ["revolver", "service_revolver"],
	"pump_shotgun": ["shell", "pump_shotgun"], "spray_rifle": ["rifle", "spray_rifle"],
	"nail_driver": ["nail", "nail_driver"], "hunting_rifle": ["rifle", "hunting_rifle"],
	"pressure_washer": ["water", "pressure_washer"], "rock_salt": ["shell", "rock_salt"],
	"battery_zapper": ["cell", "battery_zapper"], "flare_launcher": ["flare", "flare_launcher"],
	"harpoon": ["shaft", "harpoon"], "leaf_blower": ["fuel", "leaf_blower"],
	"disruptor": ["radio", "disruptor"], "leaky_nailgun": ["nail", "cursed/leaky_nailgun"],
	"boombox_launcher": ["rocket", "cursed/boombox_launcher"],
	"lucky_penny_revolver": ["revolver", "cursed/lucky_penny_revolver"],
}
const STACKS := {
	"frag": ["Frag Grenade", ItemDefinition.Kind.THROWABLE, 10, 2, "bug_bomb"],
	"shield_dome": ["Shield Dome", ItemDefinition.Kind.THROWABLE, 5, 2, "flare_gun"],
	"umbrella": ["Umbrella Stand", ItemDefinition.Kind.THROWABLE, 3, 2, "umbrella"],
	"bleach_bomb": ["Bleach Bomb", ItemDefinition.Kind.THROWABLE, 3, 2, "bleach_bomb"],
	"bait_radio": ["Bait Radio", ItemDefinition.Kind.THROWABLE, 3, 2, "bait_radio"],
	"sandbag": ["Sandbag", ItemDefinition.Kind.DEPLOYABLE, 6, 3, "sandbag"],
	"lightning_rod": ["Lightning Rod Spike", ItemDefinition.Kind.DEPLOYABLE, 3, 1, "lightning_rod"],
	"med_tin": ["Med Tin", ItemDefinition.Kind.CONSUMABLE, 3, 1, "med_tin"],
	"suit_patch": ["Suit Patch", ItemDefinition.Kind.CONSUMABLE, 3, 1, "suit_patch"],
}
## Frags and domes ride in dedicated belt pouches, never in the 5 hotbar slots.
const POUCH_CAPS := {"frag": 10, "shield_dome": 5}
## Equip or stow the pouch item with its dedicated input action.
const POUCH_ACTIONS := {"frag": "throw_grenade", "shield_dome": "throw_dome"}
static var _entries: Dictionary[String, ItemDefinition] = {}
static var _icons: Dictionary[String, Texture2D] = {}
static var _mesh: BoxMesh
static var _materials: Dictionary = {}

static func definition(id: String) -> ItemDefinition:
	if _entries.has(id):
		return _entries[id]
	if not GUNS.has(id) and not STACKS.has(id):
		return null
	var item := ItemDefinition.new()
	item.id = id
	var row: Array = GUNS.get(id, STACKS.get(id))
	if GUNS.has(id):
		item.ammo_type = row[0]
		item.weapon = load("res://weapons/%s.tres" % row[1]) as WeaponData
		item.display_name = item.weapon.display_name
		item.legendary = id == "disruptor"
	else:
		item.display_name = row[0]
		item.kind = row[1]
		item.stack_cap = row[2]
		item.spawn_count = row[3]
		item.weapon = load("res://weapons/%s.tres" % row[4]) as WeaponData
	var path := "res://assets/ui/items/%s.png" % ("lucky_penny_revolver" if id == "service_revolver" else id)
	if ResourceLoader.exists(path):
		item.icon = load(path) as Texture2D
	_entries[id] = item
	return item

static func is_pouch(id: String) -> bool:
	return POUCH_CAPS.has(id)

static func pouch_cap(id: String) -> int:
	return int(POUCH_CAPS.get(id, 0))

static func id_for_weapon_path(path: String) -> String:
	for id: String in GUNS:
		if path == "res://weapons/%s.tres" % GUNS[id][1]:
			return id
	for id: String in STACKS:
		if path == "res://weapons/%s.tres" % STACKS[id][4]:
			return id
	return ""

static func tier_name(id: String, tier: int) -> String:
	var item := definition(id)
	if item and item.is_cursed():
		return "CURSED"
	if item and item.legendary:
		return "LEGENDARY"
	return TIER_NAMES[tier]

static func tier_color(id: String, tier: int) -> Color:
	var item := definition(id)
	return Color("#ff55b4") if item and item.is_cursed() else TIER_COLORS[tier]

static var _models_checked := false
static var _models_script: Script = null

static func _item_models() -> Script:
	if not _models_checked:
		_models_checked = true
		if ResourceLoader.exists(MODELS):
			_models_script = load(MODELS) as Script
	return _models_script

static func model(id: String, pickup := false) -> Node3D:
	var key := "%s:%s" % [id, pickup]
	if not _scenes.has(key):
		var item := definition(id)
		var result: Node3D
		var models := _item_models()
		if models and models.call("has", id):
			result = models.call("pickup" if pickup else "build", id) as Node3D
			if result and not pickup:
				result.set_meta("muzzle", models.call("muzzle", id))
		if result == null and pickup and item and item.pickup_visual:
			result = item.pickup_visual.instantiate() as Node3D
		if result == null and item and item.weapon:
			result = _gun_pickup(item.weapon) if pickup else item.weapon.make_model()
		if result == null:
			result = placeholder(item.weapon.tracer_color if item else Color("#e5c65b"))
			result.scale = Vector3(0.34, 0.18, 0.6) if pickup else Vector3(0.15, 0.18, 0.58)
		# Pack the template so the node itself can be freed. Instances share
		# mesh/material resources, with independent animations and transforms.
		_cache_model(key, result)
	return _scenes[key].instantiate() as Node3D

static func _gun_pickup(data: WeaponData) -> Node3D:
	var model := data.make_model()
	if model == null:
		return null
	# Display the actual weapon at world scale. Flatten static mesh pivots
	# before merging, so a drop doesn't pay the first-person model's draw cost.
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var piece := child as MeshInstance3D
		var material := piece.material_override as StandardMaterial3D
		if material:
			var readable := material.duplicate() as StandardMaterial3D
			readable.albedo_color = material.albedo_color.lightened(0.13)
			piece.material_override = readable
		var at := piece.transform
		var pivot := piece.get_parent() as Node3D
		while pivot != model:
			at = pivot.transform * at
			pivot = pivot.get_parent() as Node3D
		if piece.get_parent() != model:
			piece.reparent(model, false)
			piece.transform = at
	var merged := MeshMerge.merge_children(model, false)
	if merged:
		merged.position = -merged.mesh.get_aabb().get_center()
	model.scale *= 1.95
	return model

static func projectile_model(id: String) -> Node3D:
	var custom := prop_model(id)
	return custom if custom != null else model(id, true)

static var _missing_props: Dictionary[String, bool] = {}

static func prop_model(id: String) -> Node3D:
	if _missing_props.has("prop:%s" % id):
		return null
	var models := _item_models()
	if models == null:
		return null
	var key := "prop:%s" % id
	if not _scenes.has(key):
		# Props such as crate_station/airdrop/sandbag_wall are not hotbar items,
		# so try projectile() for every id; an empty root means "no model".
		var result: Node3D = models.call("projectile", id) as Node3D
		if result != null and result.get_child_count() == 0:
			result.free()
			result = null
		if result == null and models.call("has", id):
			result = models.call("pickup", id) as Node3D
		if result == null:
			_missing_props[key] = true
			return null
		_cache_model(key, result)
	return _scenes[key].instantiate() as Node3D

static var _scenes: Dictionary[String, PackedScene] = {}

static func _cache_model(key: String, root: Node3D) -> void:
	for child in root.find_children("*", "", true, false):
		child.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	_scenes[key] = scene
	root.free()

static func placeholder(color: Color) -> MeshInstance3D:
	if _mesh == null:
		_mesh = BoxMesh.new()
	var key := color.to_rgba32()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.75
		_materials[key] = material
	var box := MeshInstance3D.new()
	box.mesh = _mesh
	box.material_override = _materials[key]
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return box
