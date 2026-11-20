extends CanvasLayer
## Mutation Draft UI (the node is still called SlotReel in main.tscn).
## A compact strip of three cards along the bottom of the screen, so the
## world stays visible and the player keeps moving and looking. Each card
## shows the ENEMY mutation for this wave and the PLAYER mutation the squad
## keeps for the run. Pick with 1 / 2 / 3 (D-pad on a controller).

const CARD_SIZE := Vector2(250, 172)
const ENEMY_RED := Color("#ff6a6a")
const SQUAD_GREEN := Color("#8fe36a")

var _root := Control.new()
var _title := Label.new()
var _timer := ProgressBar.new()
var _cards: Array[PanelContainer] = []
var _card_parts: Array = []  # per card: {key, e_icon, e_name, e_desc, p_name, p_desc, pips}
var _table: MutationTable
var _hide_at := -1.0
var _clock := 0.0


func _ready() -> void:
	layer = 2
	_table = load("res://game/mutation_table.tres")
	_root.theme = BroadcastUI.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_root.offset_left = -400
	_root.offset_right = 400
	_root.offset_top = -CARD_SIZE.y - 96
	_root.offset_bottom = -64
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 6)
	box.add_child(_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	for i in 3:
		row.add_child(_build_card(i))
	_timer.show_percentage = false
	_timer.custom_minimum_size = Vector2(0, 5)
	_timer.max_value = 1.0
	BroadcastUI.bar(_timer, BroadcastUI.CYAN)
	box.add_child(_timer)
	_root.visible = false
	var roll := GameManager.mutations
	roll.cards_dealt.connect(_on_dealt)
	roll.votes_changed.connect(_on_votes)
	roll.vote_cast.connect(func(_i): _refresh_highlight())
	roll.draft_resolved.connect(_on_resolved)
	roll.mutations_changed.connect(_on_mutations_changed)


func _exit_tree() -> void:
	var roll := GameManager.mutations
	if roll == null:
		return
	for pair in [[roll.cards_dealt, _on_dealt], [roll.votes_changed, _on_votes],
			[roll.draft_resolved, _on_resolved], [roll.mutations_changed, _on_mutations_changed]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _build_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _card_style(false))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	var key := Label.new()
	key.add_theme_font_size_override("font_size", 20)
	key.add_theme_color_override("font_color", BroadcastUI.CYAN)
	top.add_child(key)
	var e_icon := GameIcon.new()
	e_icon.custom_minimum_size = Vector2(26, 26)
	top.add_child(e_icon)
	var e_name := Label.new()
	e_name.add_theme_font_size_override("font_size", 20)
	e_name.add_theme_color_override("font_color", ENEMY_RED)
	e_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(e_name)
	var pips := Label.new()
	pips.add_theme_font_size_override("font_size", 16)
	pips.add_theme_color_override("font_color", BroadcastUI.PAPER)
	top.add_child(pips)
	var e_desc := _small(v, Color(1, 0.86, 0.86))
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)
	var p_name := Label.new()
	p_name.add_theme_font_size_override("font_size", 18)
	p_name.add_theme_color_override("font_color", SQUAD_GREEN)
	v.add_child(p_name)
	var p_desc := _small(v, Color(0.88, 1, 0.86))
	_cards.append(card)
	_card_parts.append({"key": key, "e_icon": e_icon, "e_name": e_name, "e_desc": e_desc,
		"p_name": p_name, "p_desc": p_desc, "pips": pips})
	return card


func _small(parent: Control, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 0)
	parent.add_child(label)
	return label


func _card_style(selected: bool, winner := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.78 if not winner else 0.9)
	style.border_color = Color("#ffd56a") if winner else (BroadcastUI.CYAN if selected else Color(1, 1, 1, 0.22))
	var w := 3 if (selected or winner) else 1
	style.set_border_width_all(w)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	return style


func _on_dealt(cards: Array) -> void:
	_hide_at = -1.0
	_root.visible = true
	_root.modulate.a = 1.0
	BroadcastUI.reveal(_root)
	_title.text = "MUTATION DRAFT  -  PICK A CARD  [%s] [%s] [%s]" % _key_hints()
	for i in _cards.size():
		var card: Dictionary = cards[i] if i < cards.size() else {}
		_cards[i].visible = not card.is_empty()
		_cards[i].modulate.a = 1.0
		if card.is_empty():
			continue
		var parts: Dictionary = _card_parts[i]
		parts.key.text = "[%s]" % _key_hints()[i]
		var entry := _table.get_entry(str(card.enemy))
		if entry:
			parts.e_icon.kind = entry.id
			parts.e_icon.color = entry.color
			parts.e_name.text = "ENEMIES: " + entry.display_name.to_upper()
			parts.e_desc.text = entry.description
		var pid := str(card.player)
		if pid != "" and GameManager.PLAYER_MUTATIONS.has(pid):
			var info: Dictionary = GameManager.PLAYER_MUTATIONS[pid]
			parts.p_name.text = "SQUAD: " + str(info.name)
			parts.p_desc.text = str(info.desc)
		else:
			parts.p_name.text = "SQUAD: -"
			parts.p_desc.text = "Every player mutation is already yours."
	_on_votes(GameManager.mutations.vote_counts)
	_refresh_highlight()
	Sound.play("reel_land", -10.0, 1.2)


func _key_hints() -> Array:
	if Settings.using_gamepad:
		return ["LEFT", "UP", "RIGHT"]
	return ["1", "2", "3"]


func _on_votes(counts: Array) -> void:
	var multi := GameManager.player_count() > 1
	for i in _card_parts.size():
		var n: int = counts[i] if i < counts.size() else 0
		_card_parts[i].pips.text = ("o".repeat(n)) if multi else ""


func _refresh_highlight() -> void:
	var pick: int = GameManager.mutations.local_pick
	for i in _cards.size():
		_cards[i].add_theme_stylebox_override("panel", _card_style(i == pick))


func _on_resolved(index: int) -> void:
	_title.text = "DRAFTED"
	for i in _cards.size():
		if i == index:
			_cards[i].add_theme_stylebox_override("panel", _card_style(false, true))
			var tween := _cards[i].create_tween()
			_cards[i].pivot_offset = CARD_SIZE * 0.5
			tween.tween_property(_cards[i], "scale", Vector2.ONE * 1.06, 0.12)
			tween.tween_property(_cards[i], "scale", Vector2.ONE, 0.18)
		else:
			_cards[i].modulate.a = 0.3
	_hide_at = _clock + 2.0


func _on_mutations_changed(active: Array) -> void:
	if active.is_empty() and GameManager.mutations.stage == "":
		_root.visible = false


func _process(delta: float) -> void:
	_clock += delta
	if not _root.visible:
		return
	var roll := GameManager.mutations
	_timer.visible = roll.stage == "voting"
	_timer.value = roll.time_left / roll.DRAFT_TIME
	if _hide_at > 0.0 and _clock >= _hide_at:
		_hide_at = -1.0
		var tween := _root.create_tween()
		tween.tween_property(_root, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): _root.visible = false)
