extends Control

const TITLE_SCENE := "res://ui/title.tscn"
const LOBBY_SCENE := "res://ui/lobby.tscn"
const COUNT_TIME := 1.55
const TICK_INTERVAL := 0.105

enum Format { NUMBER, CLOCK, CAMPAIGN_WAVES, TAPE_SCORE }

class Tally:
	var label: Label
	var total: int
	var format: Format

	func _init(target: Label, value: int, display: Format) -> void:
		label = target
		total = maxi(0, value)
		format = display

	func show_fraction(fraction: float) -> bool:
		var value := roundi(float(total) * fraction)
		var caption := str(value)
		match format:
			Format.CLOCK: caption = "%d:%02d" % [value / 60, value % 60]
			Format.CAMPAIGN_WAVES: caption = "%d / %d" % [value, WeatherManager.FINAL_WAVE]
			Format.TAPE_SCORE: caption = "%08d" % value
		if label.text == caption:
			return false
		label.text = caption
		return true

var _tallies: Array[Tally] = []
var _segments: Array[PanelContainer] = []
var _survived := 0
var _lit := -1
var _elapsed := 0.0
var _tick_left := 0.0
var _counting := true


func _ready() -> void:
	MenuState.reset()
	theme = BroadcastUI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	BroadcastUI.backdrop(self)
	var result := GameManager.last_results
	var won := bool(result.get("won", false))
	var endless := bool(result.get("endless", false))
	var map_id := str(result.get("map_id", Maps.DEFAULT_ID))
	var district := Maps.display_name(map_id)
	_survived = int(result.get("waves", 0))
	var players: Dictionary = result.get("players", {})
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var accent := BroadcastUI.CYAN if won or endless else BroadcastUI.PINK
	panel.add_theme_stylebox_override("panel", BroadcastUI.panel(BroadcastUI.OVERLAY, accent))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 704
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := "ENDLESS TAPE COMPLETE" if endless else district + (" IS SAFE" if won else " IS LOST")
	_label(box, "STOP", 20, BroadcastUI.MUTED)
	_label(box, title, 52, accent)
	if not endless:
		_build_segments(box)
	_build_summary(box, result, players, endless)
	_build_players(box, players)
	_build_feats(box)
	var squad: Array = result.get("squad_mutations", [])
	if not squad.is_empty():
		# Squad mutations as an icon row.
		var icons := _row(box, 6)
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		for id: String in GameManager.PLAYER_MUTATIONS:
			var info: Dictionary = GameManager.PLAYER_MUTATIONS[id]
			if str(info.name) in squad:
				var icon := GameIcon.new()
				icon.kind = id
				icon.color = info.color
				icon.custom_minimum_size = Vector2(26, 26)
				icons.add_child(icon)
	var actions := _row(box, 14)
	var back := _button(actions, "BACK TO LOBBY", func(): SceneLoader.cut_to(LOBBY_SCENE)) if Net.is_online() else _button(actions, "PLAY AGAIN", func(): SceneLoader.goto(Maps.RUN_SCENE, map_id))
	BroadcastUI.button_role(back, true)
	var menu := _button(actions, "MAIN MENU", _on_menu)
	BroadcastUI.button_role(menu, false, false)
	back.grab_focus()
	_render_tally(0.0)


func _build_segments(box: Control) -> void:
	var row := _row(box, 8)
	for i in WeatherManager.FINAL_WAVE:
		var segment := PanelContainer.new()
		segment.custom_minimum_size = Vector2(62, 32)
		row.add_child(segment)
		_segments.append(segment)
		_label(segment, str(i + 1), 20, BroadcastUI.PAPER)


func _build_summary(box: Control, result: Dictionary, players: Dictionary, endless: bool) -> void:
	var total_kills := 0
	for stats: Variant in players.values():
		if stats is Dictionary:
			total_kills += int(stats.get("kills", 0))
	var row := _row(box, 18)
	_metric(row, "TIME", int(result.get("seconds", 0)), Format.CLOCK)
	_metric(row, "WAVES", _survived, Format.NUMBER if endless else Format.CAMPAIGN_WAVES)
	_metric(row, "KILLS", total_kills)
	if endless:
		_metric(row, "SCORE", int(result.get("endless_score", 0)), Format.TAPE_SCORE)


func _metric(row: Control, caption: String, value: int, format := Format.NUMBER) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var label := _label(col, "", 37, BroadcastUI.PAPER)
	_tallies.append(Tally.new(label, value, format))
	_label(col, caption, 19, BroadcastUI.CYAN)


func _build_players(box: Control, players: Dictionary) -> void:
	if players.is_empty():
		return
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	for heading: String in ["PLAYER", "KILLS", "REVIVES", "TURNED"]:
		var label := _label(grid, "" if heading == "PLAYER" else heading, 19, BroadcastUI.CYAN)
		label.custom_minimum_size.x = 218 if heading == "PLAYER" else 68
		if heading == "PLAYER":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var mvp: Label
	var best := -1
	for stats: Variant in players.values():
		if not stats is Dictionary:
			continue
		var callsign := str(stats.get("name", "PLAYER")).to_upper()
		var name_label := _label(grid, callsign, 23, BroadcastUI.PAPER)
		name_label.custom_minimum_size.x = 218
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var kills := int(stats.get("kills", 0))
		var revives := int(stats.get("revives", 0))
		var turned := int(stats.get("turned", 0))
		for value: int in [kills, revives, turned]:
			_tallies.append(Tally.new(_label(grid, "", 23, BroadcastUI.PAPER), value, Format.NUMBER))
		var contribution := kills + 2 * revives
		if contribution > best:
			best = contribution
			mvp = name_label
	# MVP: their name in amber, no extra line.
	if players.size() > 1 and mvp:
		mvp.add_theme_color_override("font_color", BroadcastUI.AMBER)


## This machine's feats from the run: a "SUIT UNLOCKED" card per new look,
## then one line naming the new achievements.
func _build_feats(box: Control) -> void:
	var earned: Array = GameManager.feats.earned_this_run if GameManager.feats else []
	if earned.is_empty():
		return
	var suits: Array[String] = []
	var others: Array[String] = []
	for id: String in earned:
		if Feats.is_suit_unlock(id):
			suits.append(id)
		else:
			others.append(id)
	if not suits.is_empty():
		var row := _row(box, 10)
		for i in mini(suits.size(), 3):
			row.add_child(_unlock_card(suits[i], suits.size()))
		if suits.size() > 3:
			_label(row, "+%d" % (suits.size() - 3), 26, BroadcastUI.ACID)
	if not others.is_empty():
		var names := PackedStringArray()
		for i in mini(others.size(), 3):
			names.append(str(Feats.entry(others[i]).name))
		var line := "NEW ACHIEVEMENTS  /  " + ", ".join(names)
		if others.size() > 3:
			line += "  +%d MORE" % (others.size() - 3)
		var label := _label(box, line, 20, BroadcastUI.AMBER)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Sound.play("ui_achievement", -9.0)


func _unlock_card(id: String, count: int) -> Control:
	var feat := Feats.entry(id)
	var card := PanelContainer.new()
	var style := BroadcastUI.panel(Color("#13202b"), BroadcastUI.ACID)
	style.set_content_margin_all(7)
	style.content_margin_left = 10
	style.content_margin_right = 12
	card.add_theme_stylebox_override("panel", style)
	var width := 704.0 if count == 1 else (347.0 if count == 2 else (228.0 if count == 3 else 214.0))
	card.custom_minimum_size.x = width
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(30, 30)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.color = Cosmetics.color(int(feat.color)) if feat.has("color") else BroadcastUI.AMBER
	row.add_child(chip)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	row.add_child(col)
	var look: String = Cosmetics.COLOR_NAMES[int(feat.color)] if feat.has("color") else Cosmetics.SKINS[int(feat.skin)]
	var head := Label.new()
	head.text = "SUIT UNLOCKED: " + look
	head.clip_text = true
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BroadcastUI.text(head, 22 if count == 1 else 19, BroadcastUI.ACID)
	col.add_child(head)
	var sub := Label.new()
	sub.text = str(feat.name) + (("  /  " + str(feat.desc)) if count == 1 else "")
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BroadcastUI.text(sub, 17, BroadcastUI.MUTED)
	col.add_child(sub)
	if count > 1:
		head.custom_minimum_size.x = width - 60.0
		sub.custom_minimum_size.x = width - 60.0
	return card


func _render_tally(fraction: float) -> bool:
	var changed := false
	for tally in _tallies:
		if tally.show_fraction(fraction):
			changed = true
	var lit := roundi(_survived * fraction)
	if lit != _lit:
		_lit = lit
		for i in _segments.size():
			var style := BroadcastUI.panel(Color("#29545d") if i < lit else BroadcastUI.PANEL,
				BroadcastUI.CYAN if i < lit else BroadcastUI.MUTED.darkened(.55))
			style.set_content_margin_all(4)
			_segments[i].add_theme_stylebox_override("panel", style)
	return changed


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= COUNT_TIME:
		_finish_tally()
		return
	var fraction := _elapsed / COUNT_TIME
	var changed := _render_tally(1.0 - pow(1.0 - fraction, 2.0))
	_tick_left = maxf(0.0, _tick_left - delta)
	if changed and _tick_left <= 0.0:
		Sound.play("ui_tick", -18.0, lerpf(0.94, 1.14, fraction))
		_tick_left = TICK_INTERVAL


func _finish_tally() -> void:
	_counting = false
	_render_tally(1.0)
	set_process(false)


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if _counting and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch):
		_finish_tally()
		Sound.play("ui_tick", -18.0, 1.18)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Sound.play("ui_click")
		get_viewport().set_input_as_handled()
		_on_menu()


func _on_menu() -> void:
	Net.leave()
	SceneLoader.cut_to(TITLE_SCENE)


func _row(parent: Control, spacing: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", spacing)
	parent.add_child(row)
	return row


func _label(parent: Control, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(label, font_size, color)
	parent.add_child(label)
	return label


func _button(parent: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(216, 48)
	if TouchInput.enabled:
		button.custom_minimum_size.y = maxf(48.0, 44.0 * TouchInput.units_per_css_pixel())
	BroadcastUI.animate_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
