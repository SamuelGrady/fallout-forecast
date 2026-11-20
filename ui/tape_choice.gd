extends CanvasLayer
## The post-Cumulus choice stays on the live tape so the squad can carry on.

var _prompt := Label.new()
var _continue := Button.new()
var _stop := Button.new()
var _can_choose := false


func _ready() -> void:
	layer = 25
	var shade := ColorRect.new()
	shade.color = Color(0.025, .035, .06, .80)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme = BroadcastUI.theme()
	panel.add_theme_stylebox_override("panel", BroadcastUI.panel(BroadcastUI.INK))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "CUMULUS DEFEATED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 50)
	heading.add_theme_color_override("font_color", BroadcastUI.CYAN)
	box.add_child(heading)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 23)
	box.add_child(_prompt)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_add_button(row, _continue, "CONTINUE", true)
	_add_button(row, _stop, "END TAPE", false)
	BroadcastUI.button_role(_continue, true)
	GameManager.tape_choice_changed.connect(_refresh)
	Net.roster_changed.connect(_refresh)
	hide()
	_refresh()


func _add_button(row: Control, button: Button, caption: String, keep_playing: bool) -> void:
	button.text = caption
	button.custom_minimum_size = Vector2(195, 54)
	BroadcastUI.animate_button(button)
	button.pressed.connect(func():
		Sound.play("ui_click")
		GameManager.choose_tape(keep_playing))
	row.add_child(button)


func _refresh() -> void:
	var open := GameManager.awaiting_tape_choice
	var was_open := visible
	visible = open
	if not open:
		_can_choose = false
		if was_open and MenuState.stack.is_empty() and not Net.dedicated:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	var deciding_peer := GameManager.tape_decider()
	var can_choose := not Net.is_online() or multiplayer.get_unique_id() == deciding_peer
	_continue.disabled = not can_choose
	_stop.disabled = not can_choose
	if can_choose:
		_prompt.text = "Continue into endless waves or end the tape."
		if not was_open or not _can_choose:
			_continue.grab_focus()
	else:
		var info: Dictionary = Net.roster.get(deciding_peer, {})
		_prompt.text = "Waiting for %s to choose." % str(info.get("name", "the squad leader"))
	_can_choose = can_choose
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
