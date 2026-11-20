extends Node
## Autoload "Settings": player options saved to user://settings.cfg.

signal video_changed
var using_gamepad := false

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var master_volume := 0.8
var retro_enabled := true
var unlocked_guns: Array = ["res://weapons/pump_shotgun.tres"]

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
		unlocked_guns = cfg.get_value("progress", "guns", unlocked_guns)
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func save() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "retro_enabled", retro_enabled)
	cfg.set_value("progress", "guns", unlocked_guns)
	cfg.save(PATH)
	apply()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_gamepad = false


func set_retro(value: bool) -> void:
	retro_enabled = value
	video_changed.emit()
