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
var _skip := Label.new()


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
	_label(box, "STOP  []   /   " + district, 20, BroadcastUI.MUTED)
	_label(box, title, 52, accent)
	var epilogue := "Cumulus fell. The squad stayed on the air until the signal cut out." if endless else _epilogue(won, int(result.get("wave_reached", _survived)))
	var signoff := _label(box, epilogue, 22, BroadcastUI.PAPER)
	signoff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not endless:
		_build_segments(box)
	_build_summary(box, result, players, endless)
	_build_players(box, players)
	var squad: Array = result.get("squad_mutations", [])
	if not squad.is_empty():
		var mutations := _label(box, "SQUAD MUTATIONS  /  " + ", ".join(PackedStringArray(squad)), 20, BroadcastUI.ACID)
		mutations.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := _row(box, 14)
	var back := _button(actions, "BACK TO LOBBY", func(): SceneLoader.cut_to(LOBBY_SCENE)) if Net.is_online() else _button(actions, "PLAY AGAIN", func(): SceneLoader.goto(Maps.RUN_SCENE, map_id))
	BroadcastUI.button_role(back, true)
	var menu := _button(actions, "MAIN MENU", _on_menu)
	BroadcastUI.button_role(menu, false, false)
	back.grab_focus()
	BroadcastUI.text(_skip, 19, BroadcastUI.MUTED)
	_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip.text = "PRESS ANY BUTTON TO SKIP TALLY" if Settings.using_gamepad else "PRESS ANY KEY TO SKIP TALLY"
	box.add_child(_skip)
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
	_metric(row, "TIME ON TAPE", int(result.get("seconds", 0)), Format.CLOCK)
	_metric(row, "WAVES SURVIVED", _survived, Format.NUMBER if endless else Format.CAMPAIGN_WAVES)
	_metric(row, "ELIMINATIONS", total_kills)
	if endless:
		_metric(row, "TAPE SCORE", int(result.get("endless_score", 0)), Format.TAPE_SCORE)


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
		var label := _label(grid, heading, 19, BroadcastUI.CYAN)
		label.custom_minimum_size.x = 218 if heading == "PLAYER" else 68
		if heading == "PLAYER":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var mvp := ""
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
			mvp = callsign
	if players.size() > 1 and not mvp.is_empty():
		_label(box, "MVP  /  " + mvp, 22, BroadcastUI.AMBER)
	elif players.size() == 1 and players.values()[0] is Dictionary:
		var stats: Dictionary = players.values()[0]
		var weapon := str(stats.get("weapon", stats.get("cursed", "")))
		if not weapon.is_empty():
			_label(box, "FINISHED WITH  /  " + weapon.to_upper(), 20, BroadcastUI.MUTED)


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
	_skip.modulate.a = 0.0
	set_process(false)


func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return
	if _counting and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton):
		_finish_tally()
		Sound.play("ui_tick", -18.0, 1.18)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Sound.play("ui_click")
		get_viewport().set_input_as_handled()
		_on_menu()


func _epilogue(won: bool, wave: int) -> String:
	if won:
		return "The acid storm broke at dawn. Cumulus is gone, and the sirens finally stopped."
	match wave:
		0, 1: return "The first rain was enough. Nobody made it past the drizzle."
		2, 3: return "The squad held the district for a while. Then the downpour took the rest."
		4: return "The quarantine still stands. The squad was one storm away."
		_: return "Cumulus swallowed the last of the signal. The tape runs out here."


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
	BroadcastUI.animate_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
