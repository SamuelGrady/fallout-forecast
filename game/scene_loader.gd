extends CanvasLayer
## Autoload "SceneLoader": a VHS "loading tape" screen for heavy scene changes
## (entering a run builds the whole map). Call SceneLoader.goto(path).
##
## The card is shown first and drawn for a couple of frames, then the scene is
## loaded through ResourceLoader's threaded API only (never a plain load() of
## the same path at the same time, which deadlocked). Desktop loads in the
## background with a live progress bar; the single-threaded web build blocks
## during the load, but behind this card instead of a frozen frame.

var _target := ""
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


## Show the loading card and switch to `path` once it has loaded.
func goto(path: String) -> void:
	if _target != "":
		return
	_target = path
	_waited = 0
	_clock = 0.0
	_bar.value = 0.0
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_clock += delta
	var dots := int(_clock * 3.0) % 4
	_caption.text = "LOADING TAPE" + ".".repeat(dots)
	_counter.text = "%02d:%02d:%02d" % [0, int(_clock) / 60, int(_clock) % 60]
	# Let the card reach the screen before any blocking work.
	if _waited < 2:
		_waited += 1
		if _waited == 2:
			if ResourceLoader.load_threaded_request(_target, "PackedScene", false) != OK:
				_finish(load(_target) as PackedScene)
		return
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_target, progress)
	if not progress.is_empty():
		_bar.value = lerpf(_bar.value, float(progress[0]), 0.4)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_finish(ResourceLoader.load_threaded_get(_target) as PackedScene)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("SceneLoader: threaded load failed for %s; loading directly" % _target)
			_finish(load(_target) as PackedScene)


func _finish(scene: PackedScene) -> void:
	set_process(false)
	_bar.value = 1.0
	var path := _target
	_target = ""
	if scene == null:
		visible = false
		push_error("SceneLoader: could not load " + path)
		return
	get_tree().change_scene_to_packed(scene)
	# Keep the card up one more frame so the new scene's first draw (and the
	# run's TUNING IN warm-up) replaces it without a flash.
	await get_tree().process_frame
	await get_tree().process_frame
	visible = false
