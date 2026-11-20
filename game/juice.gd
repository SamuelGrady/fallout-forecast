extends Node
## Autoload "Juice": shared game-feel helpers, all local and cosmetic.
## - shake(strength, at): camera trauma with distance falloff
## - hit_stop(ms): a tiny freeze on big hits (solo only, so it never stalls
##   a session's host simulation for everyone)
## - duck_music(db, seconds): dip the soundtrack under big moments
## - popup(text, color): "+HEADSHOT"-style ticker lines (JuiceHud shows them)

signal popup_requested(text: String, color: Color)

var _trauma := 0.0
var _stop_left := 0.0
var _duck_left := 0.0
var _duck_db := 0.0
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Add camera shake. `at` (optional) attenuates by distance to the camera.
func shake(strength: float, at := Vector3.INF) -> void:
	if Settings.reduced_flash:
		return
	if at != Vector3.INF:
		var cam := get_viewport().get_camera_3d()
		if cam:
			strength *= clampf(1.0 - cam.global_position.distance_to(at) / 30.0, 0.0, 1.0)
	_trauma = minf(1.0, _trauma + strength)


func hit_stop(ms: float) -> void:
	if Settings.reduced_flash or Net.is_online() or get_tree().paused:
		return
	_stop_left = maxf(_stop_left, ms / 1000.0)
	Engine.time_scale = 0.05


func duck_music(db: float, seconds: float) -> void:
	_duck_db = minf(_duck_db, db)
	_duck_left = maxf(_duck_left, seconds)


func popup(text: String, color := Color.WHITE) -> void:
	popup_requested.emit(text, color)


func _process(delta: float) -> void:
	# Real (unscaled) time, so hit-stop always ends on schedule.
	var real := delta / maxf(Engine.time_scale, 0.0001)
	_clock += real
	if _stop_left > 0.0:
		_stop_left -= real
		if _stop_left <= 0.0:
			Engine.time_scale = 1.0
	_trauma = maxf(0.0, _trauma - real * 1.6)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var s := 0.0 if Settings.reduced_flash else _trauma * _trauma
		cam.h_offset = 0.18 * s * sin(_clock * 47.0)
		cam.v_offset = 0.14 * s * sin(_clock * 53.0 + 1.3)
	var music := AudioServer.get_bus_index(&"Music")
	if music >= 0:
		if _duck_left > 0.0:
			_duck_left -= real
			AudioServer.set_bus_volume_db(music, lerpf(AudioServer.get_bus_volume_db(music), _duck_db, 1.0 - exp(-18.0 * real)))
		else:
			_duck_db = 0.0
			AudioServer.set_bus_volume_db(music, lerpf(AudioServer.get_bus_volume_db(music), 0.0, 1.0 - exp(-5.0 * real)))
