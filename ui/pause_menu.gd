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
	_panel.offset_left = -410
	_panel.offset_right = -30
	_panel.offset_top = -180
	_panel.offset_bottom = 180
	add_child(_panel)
	# Right column: what is mutated right now, with descriptions.
	_mutations.theme = BroadcastUI.theme()
	_mutations.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_mutations.offset_left = 10
	_mutations.offset_right = 430
	_mutations.offset_top = -240
	_mutations.offset_bottom = 240
	add_child(_mutations)
	_mutation_text.bbcode_enabled = true
	_mutation_text.fit_content = false
	_mutation_text.scroll_active = true
	_mutation_text.add_theme_font_size_override("normal_font_size", 17)
	_mutation_text.add_theme_font_size_override("bold_font_size", 19)
	_mutations.add_child(_mutation_text)
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
	_button(box, "EXPORT PERF REPORT", _export_perf)
	if not OS.has_feature("web"):
		_button(box, "QUIT", get_tree().quit)
	visible = false
	_remote.theme = BroadcastUI.theme()
	_remote.add_theme_font_size_override("font_size", 30)
	_remote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remote.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_remote.offset_left = -400
	_remote.offset_right = 400
	_remote.offset_top = -40
	_remote.offset_bottom = 40
	_remote.visible = false
	_remote_layer.layer = 19
	_remote_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_sibling.call_deferred(_remote_layer)
	_remote_layer.add_child(_remote)
	GameManager.global_pause_changed.connect(_on_global_pause)


var _mutations := PanelContainer.new()
var _mutation_text := RichTextLabel.new()


## Fill the right column: this wave's enemy mutation and the squad's run-long
## mutations, each with its description.
func _refresh_mutations() -> void:
	var roll := GameManager.mutations
	var lines := PackedStringArray()
	lines.append("[b][color=#ff6a6a]ENEMY MUTATIONS (THIS WAVE)[/color][/b]")
	if roll == null or roll.active.is_empty():
		lines.append("[color=#9aa3ad]None right now.[/color]")
	else:
		for id in roll.active:
			var entry: MutationData = roll.table.get_entry(id)
			if entry:
				lines.append("[b]%s[/b]
[color=#e6d4d4]%s[/color]" % [entry.display_name.to_upper(), entry.description])
	lines.append("")
	lines.append("[b][color=#8fe36a]SQUAD MUTATIONS (THIS RUN)[/color][/b]")
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


## Shown on everyone else's screen while someone has the game paused.
var _remote := Label.new()
var _remote_layer := CanvasLayer.new()


func _exit_tree() -> void:
	if GameManager.global_pause_changed.is_connected(_on_global_pause):
		GameManager.global_pause_changed.disconnect(_on_global_pause)


func _on_global_pause(paused: bool, by: String) -> void:
	_remote.text = "PAUSED BY %s  -  ESC TO RESUME" % by.to_upper()
	_remote.visible = paused and not visible
	if not paused and visible:
		MenuState.close(self)

func _button(box: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	BroadcastUI.animate_button(button)
	button.custom_minimum_size.y = 60
	button.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	box.add_child(button)
	BroadcastUI.button_role(button, text == "RESUME", text == "QUIT")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if not MenuState.stack.is_empty() and MenuState.stack.back() != self:
			return
		get_viewport().set_input_as_handled()
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
	_panel.get_child(0).get_child(1).grab_focus()

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
	get_tree().change_scene_to_file("res://ui/title.tscn")


func _export_perf() -> void:
	var where := Perf.export_report()
	for child in _panel.get_child(0).get_children():
		if child is Button and child.text.begins_with("EXPORT"):
			child.text = "EXPORTED - " + ("DOWNLOADED" if OS.has_feature("web") else "SAVED")
	print(where)
