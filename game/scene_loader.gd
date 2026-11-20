extends CanvasLayer
## Autoload "SceneLoader": a VHS "loading tape" screen for heavy scene changes
## (entering a run builds the whole map). Call SceneLoader.goto(path).
##
## The card is shown first and drawn for a couple of frames, then the scene is
## loaded through ResourceLoader's threaded API only (never a plain load() of
## the same path at the same time, which deadlocked). Desktop loads in the
## background with a live progress bar; the single-threaded web build blocks
## during the load, but behind this card instead of a frozen frame.

signal load_failed(message: String)

const MAP_REVEAL_SECONDS := 1.35

var _target := ""
var _loading_path := ""
var _map_id := ""
var _map_scene: PackedScene
var _online_run := false
var _announcement := ""
var _entering := false
## Desktop background prefetch (title/lobby): path -> true while in flight.
var _prefetching := {}
var _prefetched := {}
var _waited := 0
var _bar := ProgressBar.new()
var _caption := Label.new()
var _counter := Label.new()
var _clock := 0.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back := ColorRect.new()
	back.color = Color(0.03, 0.06, 0.14)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = -60
	box.offset_bottom = 60
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	_caption.text = "LOADING TAPE"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_color_override("font_color", BroadcastUI.PAPER)
	box.add_child(_caption)
	_bar.custom_minimum_size = Vector2(440, 10)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	BroadcastUI.bar(_bar, BroadcastUI.CYAN)
	box.add_child(_bar)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.add_theme_font_size_override("font_size", 22)
	_counter.add_theme_color_override("font_color", BroadcastUI.CYAN)
	box.add_child(_counter)
	var corner := Label.new()
	corner.text = "PLAY  >"
	corner.add_theme_font_size_override("font_size", 24)
	corner.position = Vector2(40, 30)
	add_child(corner)
	visible = false
	set_process(false)
	set_process_input(false)


## Start loading `path` in the background (desktop only: the web build has no
## worker threads, so a "background" load would freeze the menu). goto() on
## the same path then reuses this request, or switches at once if it's done.
## NOTE: not called anywhere. A threaded prefetch of main.tscn from the title
## deadlocked (the run never started), so entering a run always goes through
## goto() and the loading card. Kept for a future retry.
func prefetch(path: String) -> void:
	if OS.has_feature("web") or Net.dedicated or _prefetching.has(path) or _prefetched.has(path):
		return
	if ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK:
		_prefetching[path] = true
		set_process(true)


## True while a background prefetch is loading (Preload holds off meanwhile).
func busy() -> bool:
	return not _prefetching.is_empty() or _target != "" or _entering


func _poll_prefetch() -> void:
	for path in _prefetching.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_prefetched[path] = ResourceLoader.load_threaded_get(path)
			_prefetching.erase(path)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_prefetching.erase(path)


## Show the loading card and switch to `path` once it has loaded.
func goto(path: String, map_id := "") -> void:
	if _target != "" or _entering:
		return
	Perf.mark("load start " + path.get_file())
	_target = path
	_loading_path = path
	_map_id = ""
	_map_scene = null
	_online_run = path == Maps.RUN_SCENE and Net.is_online()
	_announcement = ""
	if path == Maps.RUN_SCENE:
		_map_id = Net.run_map_id if _online_run else Maps.fallback(map_id if map_id != "" else Settings.solo_map_id)
		_loading_path = Maps.entry(_map_id).scene
		if _online_run and Net.lobby_votes_enabled:
			_announcement = "VOTED: " + Maps.display_name(_map_id)
	_waited = 0
	_clock = 0.0
	_bar.value = 0.0
	_caption.text = _announcement if _announcement != "" else "LOADING TAPE"
	_counter.text = ""
	visible = true
	set_process(true)
	set_process_input(true)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_poll_prefetch()
	if _target == "":
		if _prefetching.is_empty():
			set_process(false)
		return
	_clock += delta
	if _announcement != "" and _clock < MAP_REVEAL_SECONDS:
		return
	var dots := int(_clock * 3.0) % 4
	_caption.text = "LOADING TAPE" + ".".repeat(dots)
	_counter.text = "%02d:%02d:%02d" % [0, int(_clock) / 60, int(_clock) % 60]
	if _prefetched.has(_loading_path):
		var scene: PackedScene = _prefetched[_loading_path]
		_prefetched.erase(_loading_path)
		_on_loaded(scene)
		return
	# Let the card reach the screen before any blocking work.
	if _waited < 2:
		_waited += 1
		if _waited == 2 and not _prefetching.has(_loading_path):
			if ResourceLoader.load_threaded_request(_loading_path, "PackedScene", false) != OK:
				_on_loaded(load(_loading_path) as PackedScene)
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
	if not progress.is_empty():
		var stage := float(progress[0])
		if not _map_id.is_empty():
			# Reserve 0.45..1.0 for post-load map batching and shader warm-up.
			stage = 0.34 + stage * 0.11 if _map_scene else stage * 0.34
		_bar.value = lerpf(_bar.value, stage, 0.4)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_on_loaded(ResourceLoader.load_threaded_get(_loading_path) as PackedScene)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("SceneLoader: threaded load failed for %s; loading directly" % _loading_path)
			_on_loaded(load(_loading_path) as PackedScene)


func _on_loaded(scene: PackedScene) -> void:
	if scene == null or (_online_run and not Net.is_online()):
		_abort("COULD NOT LOAD " + _loading_path.get_file() if scene == null else "")
		return
	if _map_id != "" and _map_scene == null:
		_map_scene = scene
		_loading_path = _target
		_waited = 0
		return
	_finish(scene)


## Update the visible loading card during post-load stages (batching, warm-up).
func set_stage(caption: String, progress: float, detail := "") -> void:
	if not visible:
		return
	_caption.text = caption
	_bar.value = maxf(_bar.value, clampf(progress, 0.0, 1.0))
	if not detail.is_empty():
		_counter.text = detail


func _finish(scene: PackedScene) -> void:
	Perf.mark("load done, entering scene")
	_entering = true
	if _map_scene == null:
		_bar.value = 1.0
	else:
		_bar.value = maxf(_bar.value, 0.45)
	_target = ""
	var run: Node
	var error: Error
	if _map_scene:
		run = scene.instantiate()
		run.set("map_id", _map_id)
		run.set("map_scene", _map_scene)
		_map_scene = null
		error = get_tree().change_scene_to_node(run)
	else:
		error = get_tree().change_scene_to_packed(scene)
	if error != OK:
		if is_instance_valid(run):
			run.free()
		_abort("COULD NOT ENTER " + _loading_path.get_file())
		return
	# Keep the card up one more frame so the new scene's first draw (and the
	# run's TUNING IN warm-up) replaces it without a flash.
	await get_tree().process_frame
	await get_tree().process_frame
	while is_instance_valid(run) and bool(run.get("loading_map")):
		await get_tree().process_frame
	_entering = false
	visible = false
	set_process_input(false)


func _abort(message: String) -> void:
	_target = ""
	_map_scene = null
	_entering = false
	visible = false
	set_process_input(false)
	if not message.is_empty():
		push_error("SceneLoader: " + message)
		load_failed.emit(message)
