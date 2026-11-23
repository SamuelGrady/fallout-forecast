class_name Maps
extends RefCounted

const DEFAULT_ID := "pinecrest"
const RANDOM_ID := "random"
const RUN_SCENE := "res://main.tscn"
const SELECT_SCENE := "res://ui/map_select.tscn"
const ENTRIES: Array[Dictionary] = [
	{"id": DEFAULT_ID, "name": "PINECREST", "blurb": "Main Street and its shuttered storefronts.",
		"scene": "res://levels/pinecrest/level_pinecrest.tscn", "accent": Color("#66dfda"),
		"preview": "res://assets/ui/title_street.png", "channel": "01"},
	{"id": "harbor", "name": "HARBOR POINT", "blurb": "A tidal market, covered docks, and an elevated signal walk.",
		"scene": "res://levels/harbor/level_harbor.tscn", "accent": Color("#83b8ff"),
		"preview": "res://assets/ui/harbor.webp", "channel": "02"},
	{"id": "maple_hollow", "name": "MAPLE HOLLOW", "blurb": "Misty pine woods around an old chapel and cemetery.",
		"scene": "res://levels/maple_hollow/level_maple_hollow.tscn", "accent": Color("#ff9a75"),
		"preview": "res://assets/ui/maple_hollow.webp", "channel": "03"},
	{"id": "sandbox", "name": "TEST RANGE", "blurb": "Blank checkerboard floor for dev testing.",
		"scene": "res://levels/sandbox/level_sandbox.tscn", "accent": Color("#ffba42"),
		"preview": "", "channel": "DEV", "dev_only": true},
]
const RANDOM := {"id": RANDOM_ID, "name": "RANDOM", "blurb": "Tune to any available channel.",
	"accent": Color("#ff5689"), "preview": "", "channel": "??"}


static func available() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	for entry in ENTRIES:
		if _is_playable(entry):
			maps.append(entry)
	return maps


static func entry(id: String) -> Dictionary:
	for map in ENTRIES:
		if map.id == id:
			return map
	return {}


static func is_available(id: String) -> bool:
	return _is_playable(entry(id))


static func _is_playable(map: Dictionary) -> bool:
	return (not map.is_empty()
		and (OS.is_debug_build() or not map.get("dev_only", false))
		and ResourceLoader.exists(map.scene, "PackedScene"))


static func fallback(id: String) -> String:
	return id if is_available(id) else DEFAULT_ID


static func resolve(id: String) -> String:
	if id == RANDOM_ID:
		var maps := available().filter(func(map: Dictionary) -> bool: return not map.get("dev_only", false))
		if not maps.is_empty():
			var choice: Dictionary = maps.pick_random()
			return choice.id
	return fallback(id)


static func display_name(id: String) -> String:
	if id == RANDOM_ID:
		return RANDOM.name
	return str(entry(id).get("name", ENTRIES[0].name))
