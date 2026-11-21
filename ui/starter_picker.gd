extends VBoxContainer

const KEYS := [KEY_1, KEY_2, KEY_3]
const PAD := [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT]
const PAD_HINTS := ["LEFT", "UP", "RIGHT"]
const DESCRIPTIONS := ["Close-range burst", "Sustained fire", "Two portable shelters"]

var loot: RunLoot
var _heading: Label
var _labels: Array[Label] = []
var _pad := false

func _ready() -> void:
	theme = BroadcastUI.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -315
	offset_right = 315
	offset_top = -174
	offset_bottom = -103
	_heading = _label(self, 21, BroadcastUI.CYAN)
	var row := HBoxContainer.new()
	add_child(row)
	for i in DESCRIPTIONS.size():
		var card := VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		_labels.append(_label(card, 22, Color.WHITE))
		_label(card, 17, Color("#b8d6d9")).text = DESCRIPTIONS[i]
	_refresh_keys()
	hide()

func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("#0a1320"))
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label

func _refresh_keys() -> void:
	for i in _labels.size():
		var name_text := ItemCatalog.definition(RunLoot.STARTER_KITS[i]).display_name
		_labels[i].text = "[%s] %s" % [PAD_HINTS[i] if _pad else str(i + 1), name_text.to_upper()]

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	visible = loot.starter_available() and player != null and player.state == "ok" and not GameManager.is_voting()
	if visible:
		_heading.text = "CHOOSE STARTER KIT" if RunLoot.holder(player).slots.has(null) else "FREE A SLOT TO CLAIM A KIT"

func _input(event: InputEvent) -> void:
	var pad_event := event is InputEventJoypadButton
	if (pad_event or event is InputEventKey) and event.is_pressed() and not event.is_echo() and _pad != pad_event:
		_pad = pad_event
		_refresh_keys()
	if not visible or not loot.starter_available() or GameManager.is_voting() or not event.is_pressed() or event.is_echo():
		return
	var index := -1
	if event is InputEventJoypadButton:
		index = PAD.find(event.button_index)
	elif event is InputEventKey:
		index = KEYS.find(event.physical_keycode)
	if index >= 0:
		loot.choose_starter(index)
		get_viewport().set_input_as_handled()
