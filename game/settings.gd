extends Node
## Autoload "Settings": player options saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var master_volume := 0.8
var retro_enabled := true


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
		master_volume = cfg.get_value("audio", "master_volume", master_volume)
		retro_enabled = cfg.get_value("video", "retro_enabled", retro_enabled)
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("video", "retro_enabled", retro_enabled)
	cfg.save(PATH)
	apply()
