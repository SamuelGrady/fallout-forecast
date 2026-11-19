extends CanvasLayer

var _panel := PanelContainer.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel.theme = BroadcastUI.theme()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -190
	_panel.offset_right = 190
	_panel.offset_top = -180
	_panel.offset_bottom = 180
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "BROADCAST PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	_button(box, "RESUME", _resume)
	_button(box, "MAIN MENU", _main_menu)
	_button(box, "QUIT", get_tree().quit)
	visible = false

func _button(box: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 60
	button.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	box.add_child(button)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if visible:
			_resume()
		else:
			visible = true
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_panel.get_child(0).get_child(1).grab_focus()

func _resume() -> void:
	get_tree().paused = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _main_menu() -> void:
	get_tree().paused = false
	GameManager.run_active = false
	GameManager.mutations.clear()
	WeatherManager.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/title.tscn")
