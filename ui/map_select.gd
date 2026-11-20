class_name MapSelect
extends Control

signal dismissed

enum Mode { SOLO, HOST_PICK, VOTE }
const TITLE_SCENE := "res://ui/title.tscn"
const MONITOR_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color;
void fragment() {
	vec2 uv = UV;
	float bars = step(.5, fract(floor(uv.x * 7.0) * .43));
	float strip = step(.73, uv.y);
	float grid = step(.975, fract(uv.y * 13.0));
	float scan = step(.45, fract(uv.y * 56.0));
	float level = .18 + .19 * bars + .1 * strip + .06 * grid + .06 * scan;
	float vignette = 1.0 - .65 * distance(uv, vec2(.5));
	COLOR = vec4(tint.rgb * level * vignette + vec3(.025, .035, .06), 1.0);
}
"""

var mode := Mode.SOLO
var _maps: Array[Dictionary] = []
var _cards: Array[Button] = []
var _states: Array[Label] = []
var _selection := ""
var _back: Button
var _deploy: Button
var _error: Label
var _starting := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = BroadcastUI.theme()
	BroadcastUI.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 880
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	BroadcastUI.reveal(box)

	var heading := _label(box, "VOTE FOR A DISTRICT" if mode == Mode.VOTE else "SELECT A DISTRICT", 54, BroadcastUI.PAPER)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 14)
	box.add_child(cards)
	_maps = Maps.available()
	_maps.append(Maps.RANDOM)
	for map in _maps:
		_build_card(cards, map)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	box.add_child(actions)
	_back = _action(actions, "BACK" if mode == Mode.SOLO else "BACK TO LOBBY", _on_back)
	if mode != Mode.VOTE:
		_deploy = _action(actions, "PLAY" if mode == Mode.SOLO else "SET DISTRICT", _confirm)
		BroadcastUI.button_role(_deploy, true)
	if mode == Mode.SOLO:
		_error = _label(box, "", 20, BroadcastUI.PINK)
		_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_error.hide()
		SceneLoader.load_failed.connect(_on_load_failed)

	_selection = Maps.fallback(Settings.solo_map_id) if mode == Mode.SOLO else Net.lobby_map_id
	if mode == Mode.VOTE:
		Net.roster_changed.connect(_refresh)
	_refresh()
	_link_focus()
	var initial: Button = _cards[0]
	for i in _maps.size():
		if _maps[i].id == _selection:
			initial = _cards[i]
	initial.grab_focus()


func _build_card(parent: Control, map: Dictionary) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(205, 248)
	card.pressed.connect(_pick.bind(map.id))
	BroadcastUI.animate_button(card)
	parent.add_child(card)
	_cards.append(card)

	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 12)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inset)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(content)

	_label(content, "CHANNEL " + str(map.channel), 19, map.accent)
	var monitor := ColorRect.new()
	monitor.clip_contents = true
	monitor.custom_minimum_size.y = 94
	monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(monitor)
	if map.preview != "" and ResourceLoader.exists(map.preview, "Texture2D"):
		var preview := TextureRect.new()
		preview.texture = load(map.preview) as Texture2D
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		monitor.add_child(preview)
	else:
		var shader := Shader.new()
		shader.code = MONITOR_SHADER
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("tint", map.accent)
		monitor.material = material
	_label(content, map.name, 28, BroadcastUI.PAPER)
	var blurb := _label(content, map.blurb, 20, BroadcastUI.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_states.append(_label(content, "", 19, map.accent))


func _refresh() -> void:
	if mode == Mode.VOTE:
		_selection = Net.lobby_my_vote
	for i in _maps.size():
		var id: String = _maps[i].id
		var accent: Color = _maps[i].accent
		var selected := id == _selection
		var background := accent.darkened(0.80) if selected else Color("#14232d")
		var card := _cards[i]
		card.add_theme_stylebox_override("normal", _border(background, accent if selected else Color("#344957"), 2))
		card.add_theme_stylebox_override("hover", _border(background.lightened(0.12), accent, 2))
		card.add_theme_stylebox_override("pressed", _border(background, accent, 3))
		card.add_theme_stylebox_override("focus", _border(Color.TRANSPARENT, BroadcastUI.PAPER, 2))
		if mode == Mode.VOTE:
			var count := int(Net.lobby_vote_counts.get(id, 0))
			var tally := "%d VOTE" % count if count == 1 else "%d VOTES" % count
			_states[i].text = tally + ("  /  YOUR PICK" if selected else "")
		else:
			_states[i].text = "SELECTED" if selected else ""


func _pick(id: String) -> void:
	if _starting:
		return
	if mode == Mode.VOTE:
		Net.vote_for_map(id)
	else:
		_selection = id
		_refresh()


func _confirm() -> void:
	if _starting:
		return
	if mode == Mode.HOST_PICK:
		Net.set_lobby_map(_selection)
		dismissed.emit()
		return
	_starting = true
	_error.hide()
	Settings.solo_map_id = Maps.resolve(_selection)
	Settings.save()
	hide()
	SceneLoader.goto(Maps.RUN_SCENE)


func _on_load_failed(message: String) -> void:
	if _starting:
		_starting = false
		_error.text = message
		_error.show()
		show()
		_deploy.grab_focus()


func _on_back() -> void:
	if _starting:
		return
	if mode == Mode.SOLO:
		SceneLoader.cut_to(TITLE_SCENE)
	else:
		dismissed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		Sound.play("ui_click")
		_on_back()


func _link_focus() -> void:
	var last := _cards.size() - 1
	for i in _cards.size():
		var card := _cards[i]
		card.focus_neighbor_left = card.get_path_to(_cards[posmod(i - 1, _cards.size())])
		card.focus_neighbor_right = card.get_path_to(_cards[(i + 1) % _cards.size()])
		var action := _deploy if _deploy and i > last / 2.0 else _back
		card.focus_neighbor_bottom = card.get_path_to(action)
	_back.focus_neighbor_top = _back.get_path_to(_cards[0])
	if _deploy:
		_deploy.focus_neighbor_top = _deploy.get_path_to(_cards[last])


func _border(background: Color, accent: Color, width: int) -> StyleBoxFlat:
	var style := BroadcastUI.panel(background, accent)
	style.set_border_width_all(width)
	style.set_content_margin_all(0)
	return style


func _label(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _action(parent: Control, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(188, 52)
	BroadcastUI.button_role(button)
	BroadcastUI.animate_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
