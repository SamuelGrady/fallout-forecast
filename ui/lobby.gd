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
var _ready_button: Button
var _start_button: Button
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
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -220
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

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	_roster.custom_minimum_size.y = 200
	box.add_child(_roster)

	_start_button = _button(box, "START RUN", _on_start)
	_ready_button = _button(box, "READY", _on_ready)
	_button(box, "LEAVE", _on_leave)

	Net.roster_changed.connect(_refresh)
	Net.run_started.connect(_on_run_started)
	Net.server_closed.connect(_on_server_closed)
	Net.connection_failed.connect(_on_server_closed)
	_refresh()
	_start_button.grab_focus()


func _refresh() -> void:
	if _leaving:
		return
	var hosting := Net.is_host()
	_start_button.visible = hosting
	_ready_button.visible = not hosting
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
			return "CONNECTED TO THE CLOUD SERVER   ·   THE RUN STARTS WHEN EVERYONE IS READY"
		return "CONNECTED TO HOST"
	# Shown so the other player can type it in when discovery is blocked.
	var lan := "no LAN address"
	for address in IP.get_local_addresses():
		var text := str(address)
		if text.begins_with("127.") or text.contains(":"):
			continue
		lan = text
		break
	return "HOSTING ON PORT %d   ·   LAN ADDRESS %s" % [Net.PORT, lan]


func _row(peer_id: int, info: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
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
