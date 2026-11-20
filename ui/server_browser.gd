extends Control
## Join screen: lists hosted games found on the LAN, with a manual address box
## for when discovery is blocked (different subnet, firewall, VPN).
##
## Net scans while this screen is open: it broadcasts a UDP probe twice a
## second and lists every host that answers. Clicking one connects; a manual
## address goes through the same Net.join() path.

const TITLE_SCENE := "res://ui/title.tscn"
const LOBBY_SCENE := "res://ui/lobby.tscn"

var _list: VBoxContainer
var _status: Label
var _address: LineEdit
var _connect_button: Button
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
	box.offset_left = -340
	box.offset_right = 340
	box.offset_top = -240
	box.offset_bottom = -240
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	BroadcastUI.reveal(box)

	var title := Label.new()
	title.text = "FIND A BROADCAST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)

	_status = Label.new()
	_status.text = "SCANNING THE LAN..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color("8FD65A"))
	box.add_child(_status)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size.y = 190
	box.add_child(_list)

	var manual := HBoxContainer.new()
	manual.add_theme_constant_override("separation", 10)
	box.add_child(manual)
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.1.20"
	_address.custom_minimum_size = Vector2(280, 46)
	_address.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_address.text_submitted.connect(func(text): _connect_to(text))
	manual.add_child(_address)
	_connect_button = Button.new()
	_connect_button.text = "CONNECT"
	_connect_button.custom_minimum_size = Vector2(160, 46)
	BroadcastUI.animate_button(_connect_button)
	_connect_button.pressed.connect(func():
		Sound.play("ui_click")
		_connect_to(_address.text))
	manual.add_child(_connect_button)

	_button(box, "BACK", _on_back)

	Net.servers_changed.connect(_refresh)
	Net.joined_server.connect(_on_joined)
	Net.connection_failed.connect(_on_failed)
	Net.start_scanning()
	_refresh()
	_connect_button.grab_focus()


func _exit_tree() -> void:
	Net.stop_scanning()


func _refresh() -> void:
	if _leaving:
		return
	for child in _list.get_children():
		child.queue_free()
	if Net.servers.is_empty():
		var none := Label.new()
		none.text = "no games found yet"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
		_list.add_child(none)
		return
	var ips := Net.servers.keys()
	ips.sort()
	for ip in ips:
		var info: Dictionary = Net.servers[ip]
		# A fresh local per row: the button closure captures this one, not the
		# loop variable.
		var address := str(ip)
		var row := Button.new()
		row.text = "%s   ·   %d / %d   ·   %s" % [
			str(info.get("name", "HOST")), int(info.get("players", 0)),
			int(info.get("max", 4)), address]
		row.custom_minimum_size = Vector2(0, 48)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		BroadcastUI.animate_button(row)
		row.pressed.connect(func():
			Sound.play("ui_click")
			_connect_to(address))
		_list.add_child(row)


func _connect_to(address: String) -> void:
	var target := address.strip_edges()
	if target == "" or _leaving:
		return
	_status.text = "CONNECTING TO %s ..." % target
	_status.add_theme_color_override("font_color", Color("FFE04A"))
	var err := Net.join(target)
	if err != OK:
		_on_failed()


func _on_joined() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_failed() -> void:
	if _leaving:
		return
	_status.text = "NO ANSWER. Check the address, or that the host is on your network."
	_status.add_theme_color_override("font_color", Color("FF3EA5"))
	Net.start_scanning()


func _on_back() -> void:
	_leaving = true
	Net.leave()
	get_tree().change_scene_to_file(TITLE_SCENE)


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
