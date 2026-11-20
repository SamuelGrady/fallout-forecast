extends Node
## Autoload "Settings": player options saved to user://settings.cfg.

signal video_changed
var using_gamepad := false

const PATH := "user://settings.cfg"
const HUD_SCALE_LARGE := 1.15

var mouse_sensitivity := 0.0025
var master_volume := 0.8
var retro_enabled := true
## Comfort: reduces screen flashes, shake and tracking noise.
var reduced_flash := false
var hud_scale := 1.0
var unlocked_guns: Array = ["res://weapons/pump_shotgun.tres"]
## Feats and achievements (game/feats.gd): id -> count, and the finished ids.
## Only this machine writes them, from host-confirmed events.
var feat_progress: Dictionary = {}
var feats_done: Array = []
var _save_queued := false
## Survivor look (indices into Cosmetics.COLORS / Cosmetics.SKINS).
var suit_color := 0
var suit_skin := 0
## Custom callsign shown in lobbies, teammate cards, and end-of-run results.
var player_name := ""
## The last district played in solo.
var solo_map_id := Maps.DEFAULT_ID
## Server CLOUD PLAY connects to. Empty = Net.CLOUD_URL (wss://fallout.drew.place/).
var server_url := ""
## Show the live performance overlay (Perf autoload). Recording is always on.
var perf_overlay := false
## Send anonymous performance/run telemetry to the Fallout Forecast server.
var telemetry_enabled := true
## Random anonymous id for this install (no personal data), made on first launch.
var install_id := ""

func unlock_gun(path: String) -> void:
	if path not in unlocked_guns:
		unlocked_guns.append(path)
		save()


## Save once at the end of this frame (feat progress can tick several times).
func queue_save() -> void:
	if not _save_queued:
		_save_queued = true
		save.call_deferred()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		retro_enabled = cfg.get_value("video", "retro_enabled", retro_enabled)
		reduced_flash = cfg.get_value("video", "reduced_flash", reduced_flash)
		hud_scale = HUD_SCALE_LARGE if cfg.get_value("video", "large_hud", false) else 1.0
		unlocked_guns = cfg.get_value("progress", "guns", unlocked_guns)
		var saved_progress: Variant = cfg.get_value("progress", "feat_progress", {})
		if saved_progress is Dictionary:
			for id: Variant in saved_progress:
				if Feats.exists(str(id)):
					feat_progress[str(id)] = maxi(0, int(saved_progress[id]))
		var saved_done: Variant = cfg.get_value("progress", "feats", [])
		if saved_done is Array:
			for id: Variant in saved_done:
				if Feats.exists(str(id)) and str(id) not in feats_done:
					feats_done.append(str(id))
		suit_color = posmod(int(cfg.get_value("cosmetic", "color", suit_color)), Cosmetics.COLORS.size())
		suit_skin = Cosmetics.wrap_skin(int(cfg.get_value("cosmetic", "skin", suit_skin)))
		player_name = str(cfg.get_value("profile", "name", player_name)).strip_edges().left(18)
		solo_map_id = Maps.fallback(str(cfg.get_value("profile", "solo_map", solo_map_id)))
		server_url = str(cfg.get_value("network", "server_url", server_url)).strip_edges()
		perf_overlay = bool(cfg.get_value("debug", "perf_overlay", perf_overlay))
		telemetry_enabled = bool(cfg.get_value("debug", "telemetry", telemetry_enabled))
		install_id = str(cfg.get_value("debug", "install_id", install_id))
	# A look whose feat isn't earned on this machine falls back to a free one.
	if not Feats.color_unlocked(suit_color):
		suit_color = 0
	if not Feats.skin_unlocked(suit_skin):
		suit_skin = 0
	if install_id.length() != 32:
		var bytes := Crypto.new().generate_random_bytes(16)
		install_id = bytes.hex_encode()
		save()
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func save() -> void:
	_save_queued = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "retro_enabled", retro_enabled)
	cfg.set_value("video", "reduced_flash", reduced_flash)
	cfg.set_value("video", "large_hud", hud_scale > 1.0)
	cfg.set_value("progress", "guns", unlocked_guns)
	cfg.set_value("progress", "feat_progress", feat_progress)
	cfg.set_value("progress", "feats", feats_done)
	cfg.set_value("cosmetic", "color", suit_color)
	cfg.set_value("cosmetic", "skin", suit_skin)
	cfg.set_value("profile", "name", player_name.strip_edges().left(18))
	cfg.set_value("profile", "solo_map", solo_map_id)
	cfg.set_value("network", "server_url", server_url.strip_edges())
	cfg.set_value("debug", "perf_overlay", perf_overlay)
	cfg.set_value("debug", "telemetry", telemetry_enabled)
	cfg.set_value("debug", "install_id", install_id)
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


func set_large_hud(value: bool) -> void:
	hud_scale = HUD_SCALE_LARGE if value else 1.0
	save()


func set_retro(value: bool) -> void:
	retro_enabled = value
	video_changed.emit()
