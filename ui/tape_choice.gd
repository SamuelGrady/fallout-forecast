extends CanvasLayer
## The post-Cumulus choice stays on the live tape so the squad can carry on.

var _panel := PanelContainer.new()
var _prompt := Label.new()
var _continue := Button.new()
var _stop := Button.new()
var _can_choose := false


func _ready() -> void:
	layer = 25
	var shade := ColorRect.new()
	shade.color = Color(0.025, .035, .06, .82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel.theme = BroadcastUI.theme()
	_panel.add_theme_stylebox_override("panel", BroadcastUI.panel(BroadcastUI.OVERLAY, BroadcastUI.CYAN))
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 16)
	_panel.add_child(box)
	var heading := Label.new()
	heading.text = "CUMULUS DEFEATED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(heading, 48, BroadcastUI.CYAN)
	box.add_child(heading)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BroadcastUI.text(_prompt, 22, BroadcastUI.MUTED)
	box.add_child(_prompt)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_add_button(row, _continue, "CONTINUE", true)
	_add_button(row, _stop, "END TAPE", false)
	BroadcastUI.button_role(_continue, true)
	BroadcastUI.button_role(_stop, false, false)
	GameManager.tape_choice_changed.connect(_refresh)
	Net.roster_changed.connect(_refresh)
	hide()
	_refresh()


func _add_button(row: Control, button: Button, caption: String, keep_playing: bool) -> void:
	button.text = caption
	button.custom_minimum_size = Vector2(204, 48)
	BroadcastUI.animate_button(button)
	button.pressed.connect(GameManager.choose_tape.bind(keep_playing))
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

	if not was_open:
		BroadcastUI.reveal(_panel)
	var deciding_peer := GameManager.tape_decider()
	var can_choose := not Net.is_online() or multiplayer.get_unique_id() == deciding_peer
	_continue.disabled = not can_choose
	_stop.disabled = not can_choose
	if can_choose:
		_prompt.text = "CONTINUE INTO ENDLESS WAVES OR END THE TAPE."
		if not was_open or not _can_choose:
			_continue.grab_focus()
	else:
		var info: Dictionary = Net.roster.get(deciding_peer, {})
		_prompt.text = "WAITING FOR %s TO CHOOSE." % str(info.get("name", "THE SQUAD LEADER")).to_upper()
	_can_choose = can_choose
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
