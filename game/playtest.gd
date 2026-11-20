extends Node
## Opt-in recording bridge. Normal launches do not create files or capture audio.

var session_dir := ""
var _events: FileAccess
var _record := AudioEffectRecord.new()
var _effect_index := -1
var _recording := false
var _ending := false
var _poll := 0.0
var _sample := 0.0
var _capture_start := 0.0
var _status: Label
var _scene_path := ""
var _marked_until := 0.0


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--playtest-session="):
			session_dir = argument.trim_prefix("--playtest-session=")
	if session_dir.is_empty():
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(session_dir)
	_events = FileAccess.open(session_dir.path_join("events.jsonl"), FileAccess.WRITE)
	if _events == null:
		push_error("Cannot create playtest event log")
		get_tree().quit(1)
		return
	get_tree().auto_accept_quit = false
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 720))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var title := "Fallout Forecast Playtest " + session_dir.get_file()
	get_tree().root.title = title
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(16, 16)
	_status.add_theme_font_override("font", BroadcastUI.FONT)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color("#ffcc66"))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 4)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.text = "CONNECTING RECORDER"
	layer.add_child(_status)
	WeatherManager.phase_changed.connect(func(phase, wave): _event("phase", {"phase": phase, "wave": wave}))
	GameManager.run_finished.connect(func(won, results): _event("run_finished", {"won": won, "results": results}))
	_write_json("ready.json", {"title": title, "unix": Time.get_unix_time_from_system()})
	_event("game_ready")


func active() -> bool:
	return not session_dir.is_empty()


func _process(delta: float) -> void:
	_poll += delta
	_sample += delta
	if _poll < 0.2 or _ending:
		return
	_poll = 0.0
	if FileAccess.file_exists(session_dir.path_join("stop.request")):
		finish()
		return
	if not _recording and FileAccess.file_exists(session_dir.path_join("capture.json")):
		var info = JSON.parse_string(FileAccess.get_file_as_string(session_dir.path_join("capture.json")))
		if info is Dictionary and info.has("started_unix"):
			_capture_start = info.started_unix
			_effect_index = AudioServer.get_bus_effect_count(0)
			_record.format = AudioStreamWAV.FORMAT_16_BITS
			AudioServer.add_bus_effect(0, _record)
			_record.set_recording_active(true)
			_recording = true
			_write_json("audio_start.json", {"unix": Time.get_unix_time_from_system()})
			_event("recording_started")
	if _recording:
		var elapsed := maxi(0, int(Time.get_unix_time_from_system() - _capture_start))
		_status.text = "CAPTURE %02d:%02d" % [elapsed / 60, elapsed % 60]
		_status.modulate = Color("#66dfda") if Time.get_unix_time_from_system() < _marked_until else Color.WHITE
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path != _scene_path:
		_scene_path = scene.scene_file_path
		_event("scene", {"path": _scene_path})
	var player := get_tree().get_first_node_in_group("local_player")
	if player and not player.has_meta("playtest_connected"):
		player.set_meta("playtest_connected", true)
		player.damaged.connect(func(amount): _event("health_damage", {"amount": amount}))
		player.state_changed.connect(func(state): _event("player_state", {"state": state}))
		var holder := player.get_node_or_null("Head/Camera3D/WeaponHolder")
		if holder:
			holder.fired.connect(func(weapon): _event("shot", {"weapon": weapon.display_name}))
	if player and _sample >= 1.0:
		_sample = 0.0
		var position: Vector3 = player.global_position
		_event("snapshot", {"position": [position.x, position.y, position.z], "health": player.health,
			"suit": player.suit_integrity, "ammo": player.ammo, "weapon": player.weapon_name,
			"sheltered": player.sheltered, "enemies": get_tree().get_nodes_in_group("enemies").size(),
			"fps": Engine.get_frames_per_second()})


func _input(event: InputEvent) -> void:
	if not active() or _ending or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F7 and _recording:
		get_viewport().set_input_as_handled()
		mark()
	elif event.keycode == KEY_F12:
		get_viewport().set_input_as_handled()
		finish()
	elif event.keycode == KEY_F11:
		# Keep the captured client area stable for this recording.
		get_viewport().set_input_as_handled()


func mark() -> void:
	var now := Time.get_unix_time_from_system()
	var filename := "mark-%d.png" % int(now * 1000.0)
	_event("marker", {"image": filename})
	_marked_until = now + 0.8
	_status.modulate = Color("#66dfda")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(session_dir.path_join(filename))


func finish() -> void:
	if _ending:
		return
	_save_session()
	get_tree().quit()


func _save_session() -> void:
	_ending = true
	_event("recording_stopped")
	if _recording:
		_record.set_recording_active(false)
		var audio := _record.get_recording()
		if audio:
			audio.save_to_wav(session_dir.path_join("game_audio.wav"))
		AudioServer.remove_bus_effect(0, _effect_index)
	if _events:
		_events.close()
	_write_json("finished.json", {"unix": Time.get_unix_time_from_system()})


func _exit_tree() -> void:
	if active() and not _ending:
		_save_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and active():
		finish()


func _event(kind: String, details := {}) -> void:
	if _events == null or not _events.is_open():
		return
	_events.store_line(JSON.stringify({"unix": Time.get_unix_time_from_system(), "type": kind, "data": details}))
	_events.flush()


func _write_json(filename: String, value: Dictionary) -> void:
	var temporary := session_dir.path_join(filename + ".tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(value))
		file.close()
		DirAccess.rename_absolute(temporary, session_dir.path_join(filename))
