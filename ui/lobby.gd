extends Control
## Lobby: who is in the session, a ready toggle, and the host's START.
##
## Net owns the roster; this screen only draws it and asks Net to change it.
## Both the host and every client sit here until Net.run_started fires, then
## all of them change to the run scene together.

const RUN_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://ui/title.tscn"

var _roster: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _ready_button: Button
var _force_button: Button
var _start_button: Button
var _picker: SuitPicker
var _leaving := false


func _ready() -> void:
	theme = BroadcastUI.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	BroadcastUI.backdrop(self)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.offset_left = -440
	box.offset_right = 440
	box.offset_top = -330
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	BroadcastUI.reveal(box)

	var title := Label.new()
	title.text = "BROADCAST LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color("8FD65A"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	# Your suit on the left, the roster and buttons on the right.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	box.add_child(columns)
	_picker = SuitPicker.new()
	_picker.changed.connect(_on_suit_changed)
	columns.add_child(_picker)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 14)
	columns.add_child(side)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	side.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "NAME"
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", BroadcastUI.CYAN)
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.text = Settings.player_name if Settings.player_name != "" else Net.local_name
	_name_edit.placeholder_text = "YOUR NAME..."
	_name_edit.max_length = 18
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size = Vector2(180, 40)
	_name_edit.text_submitted.connect(_on_name_commit)
	_name_edit.focus_exited.connect(func(): _on_name_commit(_name_edit.text))
	name_row.add_child(_name_edit)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	_roster.custom_minimum_size.y = 180
	side.add_child(_roster)

	_start_button = _button(side, "START RUN", _on_start)
	_ready_button = _button(side, "READY", _on_ready)
	_force_button = _button(side, "FORCE START", _on_force)
	_button(side, "LEAVE", _on_leave)

	Net.roster_changed.connect(_refresh)
	Net.run_started.connect(_on_run_started)
	Net.server_closed.connect(_on_server_closed)
	Net.connection_failed.connect(_on_server_closed)
	_refresh()
	var primary := _start_button if Net.is_host() else _ready_button
	primary.grab_focus()


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
	var hosting := Net.is_host()
	_start_button.visible = hosting
	_ready_button.visible = not hosting
	var all_ready := true
	for peer_id in Net.roster:
		if not _is_ready(peer_id):
			all_ready = false
	_start_button.text = "START RUN" if all_ready else "FORCE START"
	# Clients can force the start too (the cloud server has no host player).
	_force_button.visible = not hosting and Net.is_online() and not all_ready
	_ready_button.text = "READY" if _is_ready(Net.local_id()) else "NOT READY"
	if Net.is_offline():
		_status.text = "No session. Go back and pick HOST GAME or JOIN GAME."
	else:
		_status.text = _host_line()
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
		waiting.text = "waiting for players..."
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waiting.add_theme_font_size_override("font_size", 18)
		waiting.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		_roster.add_child(waiting)


func _host_line() -> String:
	if not Net.is_host():
		# A dedicated server is never in its own roster.
		if not Net.roster.is_empty() and not Net.roster.has(1):
			return "CONNECTED TO THE CLOUD SERVER   |   THE RUN STARTS WHEN EVERYONE IS READY"
		return "CONNECTED TO HOST"
	# Shown so the other player can type it in when discovery is blocked.
	var lan := "no LAN address"
	for address in IP.get_local_addresses():
		var text := str(address)
		if text.begins_with("127.") or text.contains(":"):
			continue
		lan = text
		break
	return "HOSTING ON PORT %d   |   LAN ADDRESS %s" % [Net.PORT, lan]


func _row(peer_id: int, info: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(22, 22)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Cosmetics.color(int(info.get("color", peer_id)))
	chip_style.border_color = Color("#0c1422")
	chip_style.set_border_width_all(2)
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.tooltip_text = Cosmetics.skin_name(int(info.get("skin", 0)))
	row.add_child(chip)
	var name_label := Label.new()
	var name := str(info.get("name", "PLAYER"))
	if peer_id == 1:
		name += "  (HOST)"
	if peer_id == Net.local_id():
		name += "  (YOU)"
	name_label.text = name
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var state := Label.new()
	var ready := bool(info.get("ready", false)) or peer_id == 1
	state.text = "READY" if ready else "NOT READY"
	state.add_theme_font_size_override("font_size", 18)
	state.add_theme_color_override("font_color", Color("8FD65A") if ready else Color("FF3EA5"))
	row.add_child(state)
	return row


## Grey out colours others wear, and show what the host actually gave us.
func _sync_picker() -> void:
	var me := Net.local_id()
	var taken := []
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
	return bool(info.get("ready", false)) or peer_id == 1


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 52)
	BroadcastUI.animate_button(b)
	b.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	parent.add_child(b)
	return b


func _on_ready() -> void:
	Net.set_ready(not _is_ready(Net.local_id()))


func _on_start() -> void:
	Net.request_start()


func _on_force() -> void:
	Net.force_start()


func _on_leave() -> void:
	_leaving = true
	Net.leave()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _on_run_started() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_server_closed() -> void:
	if _leaving:
		return
	_leaving = true
	Net.leave()
	get_tree().change_scene_to_file(TITLE_SCENE)
