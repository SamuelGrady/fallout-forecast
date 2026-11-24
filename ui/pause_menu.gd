extends CanvasLayer

const LOADOUT_HOLD := 0.4

var _panel := PanelContainer.new()
var _resume_button: Button
var _remote := Label.new()
var _remote_resume := Button.new()
var _remote_layer := CanvasLayer.new()
var _loadout_hint: Label
var _start_held := false
var _start_device := -1
var _start_time := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = BroadcastUI.theme()
	add_child(center)
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.add_theme_stylebox_override("panel", BroadcastUI.panel(BroadcastUI.OVERLAY, BroadcastUI.CYAN))
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(title, 34, BroadcastUI.CYAN)
	box.add_child(title)
	_resume_button = _button(box, "RESUME", _resume)
	var feats: Button
	feats = _button(box, "ACHIEVEMENTS", func():
		var screen := FeatsScreen.new()
		_panel.hide()
		screen.closed.connect(func():
			_panel.show()
			if is_instance_valid(feats):
				feats.grab_focus())
		add_child(screen))
	_button(box, "MAIN MENU", _main_menu)
	if not OS.has_feature("web"):
		_button(box, "QUIT", get_tree().quit)
	# Mutations moved to the loadout screen; point players at it.
	var rule := ColorRect.new()
	rule.color = Color(BroadcastUI.MUTED, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	_loadout_hint = Label.new()
	_loadout_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(_loadout_hint, 18, BroadcastUI.MUTED)
	box.add_child(_loadout_hint)
	visible = false
	BroadcastUI.text(_remote, 30, BroadcastUI.CYAN)
	BroadcastUI.back_label(_remote)
	_remote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_remote.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_remote.offset_left = -300
	_remote.offset_right = 300
	_remote.offset_top = -40
	_remote.offset_bottom = 40
	_remote.visible = false
	_remote_layer.layer = 19
	_remote_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_remote_layer)
	_remote_layer.add_child(_remote)
	_remote_resume.text = "RESUME"
	_remote_resume.theme = BroadcastUI.theme()
	BroadcastUI.button_role(_remote_resume, true)
	_remote_resume.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_remote_resume.offset_left = -96
	_remote_resume.offset_right = 96
	_remote_resume.offset_top = 44
	_remote_resume.pressed.connect(func(): GameManager.request_pause(false))
	_remote_resume.hide()
	_remote_layer.add_child(_remote_resume)
	TouchInput.layout_changed.connect(_layout_buttons)
	_layout_buttons()
	GameManager.global_pause_changed.connect(_on_global_pause)


func _layout_buttons() -> void:
	var target := maxf(48.0, 44.0 * TouchInput.units_per_css_pixel()) if TouchInput.enabled else 48.0
	for control in _resume_button.get_parent().get_children():
		if control is Button:
			control.custom_minimum_size.y = target
	_remote_resume.offset_bottom = _remote_resume.offset_top + target


func _on_global_pause(paused: bool, by: String) -> void:
	_remote.text = "PAUSED  -  %s" % by.to_upper()
	_remote.visible = paused and not visible
	_remote_resume.visible = _remote.visible and TouchInput.enabled
	if not paused and visible:
		MenuState.close(self)

func _button(box: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	BroadcastUI.animate_button(button)
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	box.add_child(button)
	BroadcastUI.button_role(button, text == "RESUME", text == "QUIT")
	return button

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.is_action("pause"):
		if _start_held and event.device == _start_device and event.is_released():
			get_viewport().set_input_as_handled()
			_start_held = false
			if not event.is_canceled() and _start_time < LOADOUT_HOLD and InventoryMenu.can_open():
				toggle_pause()
			return
		if event.is_pressed() and InventoryMenu.can_open() and not GameManager.global_paused:
			get_viewport().set_input_as_handled()
			Settings.using_gamepad = true
			_start_held = true
			_start_device = event.device
			_start_time = 0.0
			return
	var pause_pressed := event.is_action_pressed("pause")
	var cancel_open_menu := visible and event.is_action_pressed("ui_cancel")
	if not GameManager.awaiting_tape_choice and (pause_pressed or cancel_open_menu) and not event.is_echo():
		# ESC closes an open loadout screen instead of pausing.
		if InventoryMenu.blocks_gameplay_actions():
			return
		if not MenuState.stack.is_empty() and MenuState.stack.back() != self:
			return
		get_viewport().set_input_as_handled()
		toggle_pause()

func _process(delta: float) -> void:
	if visible:
		_loadout_hint.visible = not TouchInput.enabled
		_loadout_hint.text = "[%s]  LOADOUT & MUTATIONS" % BroadcastUI.input_hint("inventory")
	if not _start_held or _start_time >= LOADOUT_HOLD:
		return
	if not InventoryMenu.can_open() or GameManager.global_paused:
		_start_time = LOADOUT_HOLD
		return
	_start_time += delta
	if _start_time >= LOADOUT_HOLD:
		InventoryMenu.open_from_gamepad()

func toggle_pause() -> void:
	Sound.play("ui_click")
	if visible:
		_resume()
	elif GameManager.global_paused:
		# Someone else paused: ESC resumes for everyone.
		GameManager.request_pause(false)
	else:
		MenuState.open(self)
		BroadcastUI.reveal(_panel)
		GameManager.request_pause(true)
		_remote.visible = false
		_remote_resume.hide()

func focus_default() -> void:
	_resume_button.grab_focus()

func _resume() -> void:
	MenuState.close(self)
	GameManager.request_pause(false)

func _main_menu() -> void:
	# Don't leave the rest of the session frozen behind you.
	GameManager.request_pause(false)
	MenuState.reset()
	GameManager.run_active = false
	GameManager.mutations.clear()
	WeatherManager.stop()
	TouchInput.release_pointer()
	Net.leave()
	SceneLoader.cut_to("res://ui/title.tscn")

