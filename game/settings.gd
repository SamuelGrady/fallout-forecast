extends Node
## Autoload "Settings": player options saved to user://settings.cfg.

signal video_changed
var using_gamepad := false

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var master_volume := 0.8
var retro_enabled := true
## Comfort: dims lightning flashes and VHS tracking glitches.
var reduced_flash := false
var unlocked_guns: Array = ["res://weapons/pump_shotgun.tres"]
## Survivor look (indices into Cosmetics.COLORS / Cosmetics.SKINS).
var suit_color := 0
var suit_skin := 0
## Custom callsign shown in lobbies, teammate cards, and end-of-run results.
var player_name := ""
## Server JOIN GAME connects to. Empty = Net.CLOUD_URL (wss://fallout.drew.place/).
var server_url := ""
## Show the live performance overlay (Perf autoload). Recording is always on.
var perf_overlay := false

func unlock_gun(path: String) -> void:
	if path not in unlocked_guns:
		unlocked_guns.append(path)
		save()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		retro_enabled = cfg.get_value("video", "retro_enabled", retro_enabled)
		reduced_flash = cfg.get_value("video", "reduced_flash", reduced_flash)
		unlocked_guns = cfg.get_value("progress", "guns", unlocked_guns)
		suit_color = posmod(int(cfg.get_value("cosmetic", "color", suit_color)), Cosmetics.COLORS.size())
		suit_skin = Cosmetics.wrap_skin(int(cfg.get_value("cosmetic", "skin", suit_skin)))
		player_name = str(cfg.get_value("profile", "name", player_name)).strip_edges().left(18)
		server_url = str(cfg.get_value("network", "server_url", server_url)).strip_edges()
		perf_overlay = bool(cfg.get_value("debug", "perf_overlay", perf_overlay))
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func save() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "retro_enabled", retro_enabled)
	cfg.set_value("video", "reduced_flash", reduced_flash)
	cfg.set_value("progress", "guns", unlocked_guns)
	cfg.set_value("cosmetic", "color", suit_color)
	cfg.set_value("cosmetic", "skin", suit_skin)
	cfg.set_value("profile", "name", player_name.strip_edges().left(18))
	cfg.set_value("network", "server_url", server_url.strip_edges())
	cfg.set_value("debug", "perf_overlay", perf_overlay)
	cfg.save(PATH)
	apply()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_gamepad = false


## 1.0 normally, 0.25 with reduced flash on.
func flash_scale() -> float:
	return 0.25 if reduced_flash else 1.0


func set_reduced_flash(value: bool) -> void:
	reduced_flash = value
	save()


func set_retro(value: bool) -> void:
	retro_enabled = value
	video_changed.emit()
