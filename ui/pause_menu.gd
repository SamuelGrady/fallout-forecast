extends CanvasLayer

var _panel := PanelContainer.new()
var _mutations := PanelContainer.new()
var _mutation_text := RichTextLabel.new()
var _resume_button: Button
var _remote := Label.new()
var _remote_layer := CanvasLayer.new()

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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	center.add_child(row)
	_panel.custom_minimum_size = Vector2(326, 0)
	var centered := CenterContainer.new()
	centered.add_child(_panel)
	row.add_child(centered)
	_mutations.custom_minimum_size = Vector2(492, 440)
	row.add_child(_mutations)
	var list := VBoxContainer.new()
	_mutations.add_child(list)
	var mutation_title := Label.new()
	mutation_title.text = "MUTATION LOG"
	BroadcastUI.text(mutation_title, 34, BroadcastUI.CYAN)
	list.add_child(mutation_title)
	_mutation_text.bbcode_enabled = true
	_mutation_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mutation_text.focus_mode = Control.FOCUS_ALL
	_mutation_text.add_theme_font_override("normal_font", BroadcastUI.FONT)
	_mutation_text.add_theme_font_override("bold_font", BroadcastUI.FONT)
	_mutation_text.add_theme_font_size_override("normal_font_size", 21)
	_mutation_text.add_theme_font_size_override("bold_font_size", 22)
	var focus := BroadcastUI.panel(Color.TRANSPARENT)
	focus.set_border_width_all(1)
	focus.set_content_margin_all(0)
	_mutation_text.add_theme_stylebox_override("focus", focus)
	_mutation_text.gui_input.connect(_scroll_mutations)
	BroadcastUI.focus_sound(_mutation_text)
	list.add_child(_mutation_text)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "BROADCAST PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(title, 36, BroadcastUI.CYAN)
	box.add_child(title)
	_resume_button = _button(box, "RESUME", _resume)
	_button(box, "MAIN MENU", _main_menu)
	if not OS.has_feature("web"):
		_button(box, "QUIT", get_tree().quit)
	for item in box.get_children():
		if item is Button:
			item.focus_neighbor_right = item.get_path_to(_mutation_text)
	_mutation_text.focus_neighbor_left = _mutation_text.get_path_to(_resume_button)
	visible = false
	BroadcastUI.text(_remote, 30, BroadcastUI.CYAN)
	BroadcastUI.back_label(_remote)
	_remote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remote.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_remote.offset_left = -320
	_remote.offset_right = 320
	_remote.offset_top = -40
	_remote.offset_bottom = 40
	_remote.visible = false
	_remote_layer.layer = 19
	_remote_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_remote_layer)
	_remote_layer.add_child(_remote)
	GameManager.global_pause_changed.connect(_on_global_pause)


func _scroll_mutations(event: InputEvent) -> void:
	var scroll := _mutation_text.get_v_scroll_bar()
	if event.is_action_pressed("ui_down"):
		scroll.value += 34.0
		_mutation_text.accept_event()
	elif event.is_action_pressed("ui_up"):
		scroll.value -= 34.0
		_mutation_text.accept_event()


## Fill the right column: this wave's enemy mutation and the squad's run-long
## mutations, each with its description.
func _refresh_mutations() -> void:
	var roll := GameManager.mutations
	var lines := PackedStringArray()
	lines.append("[b][color=#%s]INFECTED  /  THIS WAVE[/color][/b]" % BroadcastUI.PINK.to_html(false))
	if roll == null or roll.active.is_empty():
		lines.append("[color=#9aa3ad]None right now.[/color]")
	else:
		for id in roll.active:
			var entry: MutationData = roll.table.get_entry(id)
			if entry:
				lines.append("[b]%s[/b]
[color=#e6d4d4]%s[/color]" % [entry.display_name.to_upper(), entry.description])
	lines.append("")
	lines.append("[b][color=#%s]SQUAD  /  THIS RUN[/color][/b]" % BroadcastUI.ACID.to_html(false))
	if roll == null or roll.player_mutations.is_empty():
		lines.append("[color=#9aa3ad]None yet. Draft one after each Calm.[/color]")
	else:
		for id in roll.player_mutations:
			if GameManager.PLAYER_MUTATIONS.has(id):
				var info: Dictionary = GameManager.PLAYER_MUTATIONS[id]
				lines.append("[b]%s[/b]
[color=#dcefd6]%s[/color]" % [str(info.name), str(info.desc)])
	_mutation_text.text = "
".join(lines)
	_mutation_text.get_v_scroll_bar().value = 0.0


func _on_global_pause(paused: bool, by: String) -> void:
	_remote.text = "PAUSED BY %s\n[%s] RESUME" % [by.to_upper(), BroadcastUI.input_hint("pause")]
	_remote.visible = paused and not visible
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
	var pause_pressed := event.is_action_pressed("pause")
	var cancel_open_menu := visible and event.is_action_pressed("ui_cancel")
	if not GameManager.awaiting_tape_choice and (pause_pressed or cancel_open_menu) and not event.is_echo():
		if not MenuState.stack.is_empty() and MenuState.stack.back() != self:
			return
		get_viewport().set_input_as_handled()
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

func focus_default() -> void:
	_refresh_mutations()
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	SceneLoader.cut_to("res://ui/title.tscn")

