extends Control
const RUN_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://ui/title.tscn"
const LOBBY_SCENE := "res://ui/lobby.tscn"


func _ready() -> void:
	MenuState.reset()
	theme = BroadcastUI.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Solid dark base guarantees we never flash Godot's default gray even if a
	# backdrop shader compiles late on WebGL2.
	var base := ColorRect.new()
	base.color = BroadcastUI.INK
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	BroadcastUI.backdrop(self)

	var result: Dictionary = GameManager.last_results if GameManager.last_results is Dictionary else {}
	var won: bool = bool(result.get("won", false))
	var endless := bool(result.get("endless", false))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 720
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	var title := "PINECREST IS SAFE" if won else "PINECREST IS LOST"
	var epilogue := _epilogue(won, int(result.get("wave_reached", result.get("waves", 0))))
	if endless:
		title = "ENDLESS TAPE COMPLETE"
		epilogue = "Cumulus fell. The squad stayed on the air until the signal cut out."
	_label(box, title, 52, BroadcastUI.CYAN if won or endless else BroadcastUI.PINK)
	_label(box, epilogue, 20, Color(0.85, 0.86, 0.8))
	var waves := HBoxContainer.new()
	waves.alignment = BoxContainer.ALIGNMENT_CENTER
	waves.add_theme_constant_override("separation", 12)
	box.add_child(waves)
	for i in 5:
		var segment := PanelContainer.new()
		segment.custom_minimum_size = Vector2(90, 45)
		segment.add_theme_stylebox_override("panel", BroadcastUI.panel(Color("#29545d") if i < int(result.get("waves", 0)) else Color("#14232d")))
		waves.add_child(segment)
		_label(segment, str(i + 1), 24, BroadcastUI.PAPER)

	# Run summary: time on tape, total eliminations, the squad's mutations.
	var total_kills := 0
	var pdata: Variant = result.get("players", {})
	if pdata is Dictionary:
		for st in (pdata as Dictionary).values():
			if st is Dictionary:
				total_kills += int(st.get("kills", 0))
	var secs := int(result.get("seconds", 0))
	var summary := HBoxContainer.new()
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	summary.add_theme_constant_override("separation", 40)
	box.add_child(summary)
	var survived := int(result.get("waves", 0))
	var measures := [["TIME ON TAPE", "%d:%02d" % [secs / 60, secs % 60]], ["WAVES SURVIVED", str(survived) if endless else "%d / 5" % survived], ["ELIMINATIONS", str(total_kills)]]
	if endless:
		measures.append(["TAPE SCORE", "%08d" % int(result.get("endless_score", 0))])
	for pair in measures:
		var col := VBoxContainer.new()
		summary.add_child(col)
		_label(col, pair[1], 34, BroadcastUI.PAPER)
		_label(col, pair[0], 15, BroadcastUI.CYAN)
	var squad: Array = result.get("squad_mutations", [])
	if not squad.is_empty():
		_label(box, "SQUAD MUTATIONS:  " + ", ".join(PackedStringArray(squad)), 18, Color("#8fe36a"))
	var players_data: Variant = result.get("players", {})
	var players: Dictionary = players_data if players_data is Dictionary else {}
	if players.size() <= 1:
		var stats: Dictionary = players.values()[0] if not players.is_empty() and players.values()[0] is Dictionary else {}
		var weapon := str(stats.get("weapon", stats.get("cursed", "")))
		if not weapon.is_empty():
			_label(box, "FINISHED WITH THE " + weapon.to_upper(), 22, BroadcastUI.PAPER)
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.add_theme_constant_override("h_separation", 24)
		box.add_child(grid)
		for heading in ["PLAYER", "KILLS", "REVIVES", "TURNED"]:
			_label(grid, heading, 18, BroadcastUI.CYAN)
		# MVP: most kills, revives count double.
		var mvp := ""
		var best := -1
		for st in players.values():
			if st is Dictionary:
				var score := int(st.get("kills", 0)) + 2 * int(st.get("revives", 0))
				if score > best:
					best = score
					mvp = str(st.get("name", "PLAYER"))
		if mvp != "":
			_label(box, "MVP: " + mvp.to_upper(), 24, Color("#ffd56a"))
		for stats in players.values():
			if not stats is Dictionary:
				continue
			for value in [stats.get("name", "PLAYER"), stats.get("kills", 0), stats.get("revives", 0), stats.get("turned", 0)]:
				_label(grid, str(value), 22, BroadcastUI.PAPER)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	box.add_child(actions)
	var play: Button
	# Online, another run has to start from the lobby: only the host can send
	# everyone into the run scene.
	if Net.is_online():
		play = _button(actions, "BACK TO LOBBY", func(): get_tree().change_scene_to_file(LOBBY_SCENE))
	else:
		play = _button(actions, "PLAY AGAIN", func(): SceneLoader.goto(RUN_SCENE))
	BroadcastUI.button_role(play, true)
	_button(actions, "MAIN MENU", _on_menu)
	play.grab_focus()
	# VHS sign-off.
	var corner := Label.new()
	corner.text = "STOP  []   END OF TAPE"
	corner.add_theme_font_size_override("font_size", 22)
	corner.position = Vector2(40, 28)
	add_child(corner)
	var credits := Label.new()
	credits.text = "FALLOUT FORECAST  -  A SAM & DREW PRODUCTION  -  OCT 31 1987"
	credits.add_theme_font_size_override("font_size", 16)
	credits.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	credits.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	credits.offset_left = -330
	credits.offset_right = 330
	credits.offset_top = -40
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(credits)


## One line of epilogue, by how the run went.
func _epilogue(won: bool, wave: int) -> String:
	if won:
		return "The acid storm broke over Pinecrest at dawn. Cumulus is gone, and the sirens finally stopped."
	match wave:
		0, 1:
			return "The first rain was enough. Nobody made it past the drizzle."
		2, 3:
			return "The squad held Main Street for a while. Then the downpour took the rest."
		4:
			return "So close. One more storm and the quarantine would have lifted."
		_:
			return "Cumulus swallowed the last of the signal. The tape runs out here."



func _on_menu() -> void:
	Net.leave()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_menu()
		get_viewport().set_input_as_handled()


func _label(parent: Node, text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 54)
	BroadcastUI.animate_button(button)
	button.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	parent.add_child(button)
	return button
