extends Control
## Cloud broadcast lobby: suit config, squad roster, live district vote cards,
## squad chat, and ready / force-start controls in a 4:3 VHS console layout.
##
## Net owns the roster; this screen only draws it and asks Net to change it.
## Everyone sits here until Net.run_started fires, then transitions together.

const TITLE_SCENE := "res://ui/title.tscn"
const QUICK := ["READY?", "ONE SEC", "LET'S GO", "GG"]

var _shell: MarginContainer
var _chat_panel: PanelContainer
var _roster_heading: Label
var _roster: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _ready_button: Button
var _force_button: Button
var _map_heading: Label
var _map_status: Label
var _map_button: Button
var _vote_row: HBoxContainer
var _vote_maps: Array[Dictionary] = []
var _vote_cards: Array[Button] = []
var _vote_picks: Array[Label] = []
var _map_picker: MapSelect
var _leave_button: Button
var _picker: SuitPicker
var _chat_log := RichTextLabel.new()
var _chat_edit := LineEdit.new()
var _leaving := false


func _ready() -> void:
	theme = BroadcastUI.theme()
	TouchInput.release_pointer()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	BroadcastUI.backdrop(self)

	_shell = MarginContainer.new()
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.add_theme_constant_override("margin_left", 24)
	_shell.add_theme_constant_override("margin_right", 24)
	_shell.add_theme_constant_override("margin_top", 14)
	_shell.add_theme_constant_override("margin_bottom", 14)
	add_child(_shell)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	_shell.add_child(root_box)
	BroadcastUI.reveal(root_box)

	_build_header(root_box)

	# The body takes only what the suit column needs; squad chat gets the rest.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	root_box.add_child(body)

	_build_suit_panel(body)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)

	_build_roster_panel(right)
	_build_vote_panel(right)
	_build_actions(right)

	_build_chat(root_box)
	TouchInput.layout_changed.connect(_layout_touch_actions)
	_layout_touch_actions()

	Net.chat_received.connect(_on_chat)
	Net.roster_changed.connect(_refresh)
	Net.run_started.connect(_on_run_started)
	Net.server_closed.connect(_on_server_closed)
	Net.connection_failed.connect(_on_connection_failed)
	SceneLoader.load_failed.connect(_on_load_failed)
	_refresh()
	var primary: Button = _ready_button if _ready_button.visible else _leave_button
	primary.grab_focus()


func _panel_style(accent := BroadcastUI.CYAN, pad_x := 14, pad_y := 10) -> StyleBoxFlat:
	var style := BroadcastUI.panel(BroadcastUI.OVERLAY, accent)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style


func _build_header(parent: Control) -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _panel_style(BroadcastUI.CYAN, 14, 7))
	parent.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	var title := Label.new()
	title.text = "LOBBY"
	BroadcastUI.text(title, 34, BroadcastUI.PAPER)
	row.add_child(title)

	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BroadcastUI.text(_status, 19, BroadcastUI.ACID)
	row.add_child(_status)


func _build_suit_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 296
	panel.add_theme_stylebox_override("panel", _panel_style(BroadcastUI.CYAN, 14, 10))
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var heading := Label.new()
	heading.text = "SUIT"
	BroadcastUI.text(heading, 20, BroadcastUI.CYAN)
	col.add_child(heading)

	_picker = SuitPicker.new(Vector2i(264, 180))
	_picker.changed.connect(_on_suit_changed)
	col.add_child(_picker)


func _build_roster_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(BroadcastUI.CYAN, 14, 9))
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)

	_roster_heading = Label.new()
	_roster_heading.text = "SQUAD"
	_roster_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(_roster_heading, 20, BroadcastUI.CYAN)
	top.add_child(_roster_heading)

	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name if Settings.player_name != "" else Net.local_name
	_name_edit.placeholder_text = "CALLSIGN"
	_name_edit.max_length = 18
	_name_edit.custom_minimum_size = Vector2(186, 32)
	_name_edit.text_submitted.connect(func(value: String):
		Sound.play("ui_click")
		_on_name_commit(value))
	BroadcastUI.focus_sound(_name_edit)
	_name_edit.focus_exited.connect(func(): _on_name_commit(_name_edit.text))
	top.add_child(_name_edit)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 4)
	# Room for a full squad up front, so a fourth join doesn't shift the layout.
	_roster.custom_minimum_size.y = Net.MAX_PLAYERS * 28 + (Net.MAX_PLAYERS - 1) * 4
	_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_roster)


func _build_vote_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(BroadcastUI.CYAN, 14, 9))
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	col.add_child(header)

	_map_heading = Label.new()
	_map_heading.text = "DISTRICT"
	_map_heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(_map_heading, 20, BroadcastUI.CYAN)
	header.add_child(_map_heading)

	_map_status = Label.new()
	_map_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_map_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_map_status.clip_text = true
	_map_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BroadcastUI.text(_map_status, 18, BroadcastUI.MUTED)
	header.add_child(_map_status)

	_map_button = Button.new()
	_map_button.text = "FULL VIEW"
	_map_button.custom_minimum_size = Vector2(96, 28)
	BroadcastUI.button_role(_map_button, false, true)
	BroadcastUI.animate_button(_map_button)
	_map_button.add_theme_font_size_override("font_size", 18)
	_map_button.pressed.connect(_open_maps)
	header.add_child(_map_button)

	_vote_row = HBoxContainer.new()
	_vote_row.add_theme_constant_override("separation", 8)
	col.add_child(_vote_row)

	_vote_maps = Maps.available()
	_vote_maps.append(Maps.RANDOM)
	for map in _vote_maps:
		_build_vote_card(_vote_row, map)


func _build_vote_card(parent: Control, map: Dictionary) -> void:
	var card := Button.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 114)
	card.pressed.connect(func(): Net.vote_for_map(str(map.id)))
	BroadcastUI.animate_button(card)
	parent.add_child(card)
	_vote_cards.append(card)

	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 7)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inset)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(box)

	var ch := Label.new()
	ch.text = "CH " + str(map.channel)
	BroadcastUI.text(ch, 16, map.accent)
	box.add_child(ch)

	var monitor := ColorRect.new()
	monitor.clip_contents = true
	monitor.custom_minimum_size.y = 38
	monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(monitor)
	var preview_path := str(map.preview)
	if preview_path != "" and ResourceLoader.exists(preview_path, "Texture2D"):
		var preview := TextureRect.new()
		preview.texture = load(preview_path) as Texture2D
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		monitor.add_child(preview)
	else:
		var material := ShaderMaterial.new()
		material.shader = MapSelect._shared_monitor_shader()
		material.set_shader_parameter("tint", map.accent)
		monitor.material = material

	var title := Label.new()
	title.text = str(map.name)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BroadcastUI.text(title, 18, BroadcastUI.PAPER)
	box.add_child(title)

	var pick := Label.new()
	pick.text = "0 VOTES"
	pick.clip_text = true
	BroadcastUI.text(pick, 16, map.accent)
	box.add_child(pick)
	_vote_picks.append(pick)


func _vote_card_style(bg: Color, accent: Color, border_w: int) -> StyleBoxFlat:
	var style := BroadcastUI.panel(bg, accent)
	style.set_border_width_all(border_w)
	style.set_content_margin_all(0)
	return style


func _build_actions(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	_ready_button = _button(row, "READY", _on_ready)
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BroadcastUI.button_role(_ready_button, true)

	_force_button = _button(row, "START", _on_force)
	_force_button.custom_minimum_size = Vector2(158, 44)
	BroadcastUI.button_accent(_force_button, BroadcastUI.AMBER)

	_leave_button = _button(row, "LEAVE", _on_leave)
	_leave_button.custom_minimum_size = Vector2(142, 44)
	BroadcastUI.button_role(_leave_button, false, true)


func _layout_touch_actions() -> void:
	var height := maxf(44.0, 44.0 * TouchInput.units_per_css_pixel()) if TouchInput.enabled else 44.0
	for button in [_ready_button, _force_button, _leave_button]:
		button.custom_minimum_size.y = height


func _build_chat(parent: Control) -> void:
	var panel := PanelContainer.new()
	_chat_panel = panel
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(BroadcastUI.CYAN, 14, 8))
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var heading := Label.new()
	heading.text = "CHAT"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(heading, 19, BroadcastUI.CYAN)
	top.add_child(heading)
	for phrase: String in QUICK:
		var b := Button.new()
		b.text = phrase
		b.custom_minimum_size.y = 28
		BroadcastUI.button_role(b, false, true)
		b.add_theme_font_size_override("font_size", 18)
		BroadcastUI.animate_button(b)
		b.pressed.connect(func(): Net.send_chat(phrase))
		top.add_child(b)

	_chat_log.bbcode_enabled = false
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size.y = 72
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_override("normal_font", BroadcastUI.FONT)
	_chat_log.add_theme_font_size_override("normal_font_size", 19)
	_chat_log.add_theme_color_override("default_color", BroadcastUI.PAPER)
	v.add_child(_chat_log)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_chat_edit.placeholder_text = "SAY..."
	_chat_edit.custom_minimum_size.y = 34
	BroadcastUI.focus_sound(_chat_edit)
	_chat_edit.max_length = Net.CHAT_MAX
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_edit.text_submitted.connect(_send_chat)
	var send := Button.new()
	send.text = "SEND"
	send.custom_minimum_size = Vector2(88, 34)
	BroadcastUI.button_role(send, true, true)
	BroadcastUI.animate_button(send)
	send.pressed.connect(func(): _send_chat(_chat_edit.text, false))
	row.add_child(_chat_edit)
	row.add_child(send)

	for line in Net.chat_log:
		_on_chat(str(line[0]), str(line[1]))
	panel.visible = Net.is_online()


func _on_name_commit(new_text: String) -> void:
	var clean := new_text.strip_edges().left(18)
	if clean == "":
		return
	Settings.player_name = clean
	Settings.save()
	Net.set_display_name(clean)


func _refresh() -> void:
	if _leaving:
		return
	var online := Net.is_online()
	var all_ready := not Net.roster.is_empty()
	for peer_id in Net.roster:
		if not _is_ready(int(peer_id)):
			all_ready = false
	_ready_button.visible = online
	_force_button.visible = online and not all_ready
	var me_ready := _is_ready(Net.local_id())
	_ready_button.text = "UNREADY" if me_ready else "READY"
	if me_ready:
		BroadcastUI.button_accent(_ready_button, BroadcastUI.ACID)
	else:
		BroadcastUI.button_role(_ready_button, true)

	if Net.is_offline():
		_status.text = Net.last_error.to_upper() if Net.last_error != "" else "OFFLINE"
		_status.add_theme_color_override("font_color", BroadcastUI.PINK)
	else:
		_status.text = "%d/%d READY" % [_ready_count(), Net.roster.size()]
		_status.add_theme_color_override("font_color", BroadcastUI.ACID)

	var voting := online and Net.lobby_votes_enabled
	_vote_row.visible = voting
	_map_heading.text = "DISTRICT"
	_map_button.visible = voting
	_map_button.text = "FULL VIEW"
	if voting:
		var votes := 0
		for count in Net.lobby_vote_counts.values():
			votes += int(count)
		var pick := Maps.display_name(Net.lobby_my_vote) if not Net.lobby_my_vote.is_empty() else "-"
		_map_status.text = "%d VOTED  /  YOUR PICK: %s" % [votes, pick]
		_refresh_vote_cards()
	else:
		_map_status.text = Maps.display_name(Net.lobby_map_id) if online else "OFFLINE"

	_chat_panel.visible = online
	_roster_heading.text = "SQUAD  %d/%d" % [Net.roster.size(), Net.MAX_PLAYERS]

	# Out of the tree now, so the rebuilt list doesn't double up for a frame.
	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()
	var ids := Net.roster.keys()
	ids.sort()
	for peer_id in ids:
		_roster.add_child(_row(int(peer_id), Net.roster[peer_id]))
	_sync_picker()
	if ids.is_empty():
		var waiting := Label.new()
		waiting.text = "WAITING..."
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		BroadcastUI.text(waiting, 20, BroadcastUI.MUTED)
		_roster.add_child(waiting)


func _refresh_vote_cards() -> void:
	for i in _vote_maps.size():
		var id := str(_vote_maps[i].id)
		var accent: Color = _vote_maps[i].accent
		var selected := id == Net.lobby_my_vote
		var count := int(Net.lobby_vote_counts.get(id, 0))
		var bg := accent.darkened(0.78) if selected else BroadcastUI.PANEL
		var border := accent if selected else Color("#344957")
		var card := _vote_cards[i]
		card.add_theme_stylebox_override("normal", _vote_card_style(bg, border, 2))
		card.add_theme_stylebox_override("hover", _vote_card_style(bg.lightened(0.12), accent, 2))
		card.add_theme_stylebox_override("pressed", _vote_card_style(bg, accent, 3))
		card.add_theme_stylebox_override("focus", _vote_card_style(Color.TRANSPARENT, BroadcastUI.PAPER, 2))
		var tally := "%d VOTE" % count if count == 1 else "%d VOTES" % count
		_vote_picks[i].text = tally + "  /  YOURS" if selected else tally
		var tint := accent if selected else (BroadcastUI.ACID if count > 0 else BroadcastUI.MUTED)
		_vote_picks[i].add_theme_color_override("font_color", tint)


func _open_maps() -> void:
	if _leaving or _map_picker:
		return
	Perf.mark("lobby open maps")
	var scene := load(Maps.SELECT_SCENE) as PackedScene
	_map_picker = scene.instantiate() as MapSelect
	_map_picker.mode = MapSelect.Mode.VOTE if Net.lobby_votes_enabled else MapSelect.Mode.HOST_PICK
	_map_picker.dismissed.connect(_close_maps)
	_shell.hide()
	add_child(_map_picker)
	SceneLoader.tracking_wipe()


func _close_maps() -> void:
	if _map_picker:
		_map_picker.hide()
		_map_picker.queue_free()
		_map_picker = null
	_shell.show()
	_chat_panel.visible = Net.is_online()
	if _map_button.visible:
		_map_button.grab_focus()
	SceneLoader.tracking_wipe()


func _row(peer_id: int, info: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 28
	row.add_theme_constant_override("separation", 10)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(18, 18)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Cosmetics.color(int(info.get("color", peer_id)))
	chip_style.border_color = BroadcastUI.INK
	chip_style.set_border_width_all(2)
	chip.add_theme_stylebox_override("panel", chip_style)
	var skin_label_text := Cosmetics.skin_name(int(info.get("skin", 0)))
	chip.tooltip_text = skin_label_text
	row.add_child(chip)

	var name_label := Label.new()
	var display := str(info.get("name", "PLAYER")).to_upper()
	if peer_id == Net.local_id():
		display += "  (YOU)"
	name_label.text = display
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(name_label, 22, BroadcastUI.CYAN if peer_id == Net.local_id() else BroadcastUI.PAPER)
	row.add_child(name_label)

	var skin_tag := Label.new()
	skin_tag.text = skin_label_text
	skin_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(skin_tag, 18, BroadcastUI.MUTED)
	row.add_child(skin_tag)

	var state := Label.new()
	var ready := bool(info.get("ready", false))
	state.text = "READY" if ready else "-"
	state.custom_minimum_size.x = 84
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(state, 19, BroadcastUI.ACID if ready else BroadcastUI.PINK)
	row.add_child(state)
	return row


## Grey out colours others wear, and show what the server actually gave us.
func _sync_picker() -> void:
	var me := Net.local_id()
	var taken: Array = []
	for peer_id in Net.roster:
		if int(peer_id) != me:
			taken.append(int(Net.roster[peer_id].get("color", -1)))
	var mine: Dictionary = Net.roster.get(me, {})
	_picker.set_value(int(mine.get("color", _picker.color)), int(mine.get("skin", _picker.skin)), taken)


func _on_suit_changed(color: int, skin: int) -> void:
	Settings.suit_color = color
	Settings.suit_skin = skin
	Settings.save()
	Net.set_cosmetic(color, skin)


func _is_ready(peer_id: int) -> bool:
	var info: Dictionary = Net.roster.get(peer_id, {})
	return bool(info.get("ready", false))


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	BroadcastUI.animate_button(b)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _send_chat(message: String, sound := true) -> void:
	if message.strip_edges().is_empty():
		return
	if sound:
		Sound.play("ui_click")
	Net.send_chat(message)
	_chat_edit.clear()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_map_picker) or not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	Sound.play("ui_click")
	_on_leave()


func _on_chat(sender: String, text: String) -> void:
	_chat_log.add_text("%s: %s\n" % [sender.to_upper(), text])


func _on_ready() -> void:
	Net.set_ready(not _is_ready(Net.local_id()))


func _on_force() -> void:
	Net.force_start()


func _on_leave() -> void:
	_leaving = true
	Net.leave()
	SceneLoader.cut_to(TITLE_SCENE)


func _on_run_started() -> void:
	if _leaving:
		return
	_leaving = true
	hide()
	SceneLoader.goto(Maps.RUN_SCENE)


func _on_server_closed() -> void:
	_leaving = true
	Net.leave()
	SceneLoader.cut_to(TITLE_SCENE)


func _on_connection_failed() -> void:
	if Net.last_error == "":
		_on_server_closed()
		return
	_leaving = false
	show()
	_close_maps()
	_refresh()
	_leave_button.grab_focus()


func _on_load_failed(message: String) -> void:
	if _leaving:
		Net.leave()
		Net.last_error = message
		_on_connection_failed()


func _ready_count() -> int:
	var count := 0
	for info: Variant in Net.roster.values():
		if info is Dictionary and bool(info.get("ready", false)):
			count += 1
	return count
