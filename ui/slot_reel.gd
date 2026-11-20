extends CanvasLayer
## Mutation Draft UI (the node is still called SlotReel in main.tscn).
## - Top: a slim red banner with this wave's ENEMY mutation (rolled, not picked).
## - Bottom: three PLAYER mutation cards; pick one with 1 / 2 / 3 (D-pad).
## Nothing covers the middle of the screen, so you keep your view.

const CARD_SIZE := Vector2(214, 132)
const ENEMY_RED := Color("#ff6a6a")

var _enemy_bar := PanelContainer.new()
var _enemy_icon := GameIcon.new()
var _enemy_text := Label.new()
var _strip := Control.new()
var _hint := Label.new()
var _timer := ProgressBar.new()
var _cards: Array[PanelContainer] = []
var _parts: Array = []  # per card: {badge, key, name, desc, pips}
var _table: MutationTable
var _hide_at := -1.0
var _clock := 0.0


func _ready() -> void:
	layer = 2
	_table = load("res://game/mutation_table.tres")
	_build_enemy_bar()
	_build_strip()
	_enemy_bar.visible = false
	_strip.visible = false
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


# ------------------------------------------------------------------ layout
func _build_enemy_bar() -> void:
	_enemy_bar.theme = BroadcastUI.theme()
	_enemy_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_enemy_bar.offset_left = -260
	_enemy_bar.offset_right = 260
	_enemy_bar.offset_top = 64
	_enemy_bar.offset_bottom = 104
	_enemy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.02, 0.04, 0.82)
	style.border_color = ENEMY_RED
	style.border_width_left = 4
	style.set_content_margin_all(8)
	_enemy_bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_enemy_bar.add_child(row)
	_enemy_icon.custom_minimum_size = Vector2(24, 24)
	row.add_child(_enemy_icon)
	_enemy_text.add_theme_font_size_override("font_size", 18)
	_enemy_text.add_theme_color_override("font_color", Color(1, 0.88, 0.88))
	_enemy_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_enemy_text)
	add_child(_enemy_bar)


func _build_strip() -> void:
	_strip.theme = BroadcastUI.theme()
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_strip.offset_left = -340
	_strip.offset_right = 340
	_strip.offset_top = -CARD_SIZE.y - 214
	_strip.offset_bottom = -178
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	_strip.add_child(box)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 6)
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in 3:
		row.add_child(_build_card(i))
	_timer.show_percentage = false
	_timer.custom_minimum_size = Vector2(0, 4)
	_timer.max_value = 1.0
	BroadcastUI.bar(_timer, BroadcastUI.CYAN)
	box.add_child(_timer)


## Player card: a coloured badge with the key to press, the name, one line of
## what it does, and vote pips in multiplayer.
func _build_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(34, 34)
	var key := Label.new()
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override("font_size", 20)
	key.add_theme_color_override("font_color", Color("#0c1422"))
	badge.add_child(key)
	top.add_child(badge)
	var name := Label.new()
	name.add_theme_font_size_override("font_size", 21)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(name)
	var pips := Label.new()
	pips.add_theme_font_size_override("font_size", 16)
	top.add_child(pips)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.9, 0.93, 0.88))
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 0)
	v.add_child(desc)
	_cards.append(card)
	_parts.append({"badge": badge, "key": key, "name": name, "desc": desc, "pips": pips})
	return card


func _card_style(color: Color, selected: bool, winner := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.84)
	style.border_color = Color("#ffd56a") if winner else (color if selected else Color(color, 0.35))
	style.set_border_width_all(3 if (selected or winner) else 1)
	style.border_width_top = 5
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	return style


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(17)
	return style


# ------------------------------------------------------------------ events
func _on_dealt(enemy: String, cards: Array) -> void:
	_hide_at = -1.0
	var entry := _table.get_entry(enemy)
	if entry:
		_enemy_icon.kind = entry.id
		_enemy_icon.color = entry.color
		_enemy_text.text = "THIS WAVE THE INFECTED MUTATE: %s  -  %s" % [entry.display_name.to_upper(), entry.description]
	_enemy_bar.visible = entry != null
	_enemy_bar.modulate.a = 1.0
	BroadcastUI.reveal(_enemy_bar)
	_strip.visible = not cards.is_empty()
	_strip.modulate.a = 1.0
	if not cards.is_empty():
		BroadcastUI.reveal(_strip)
	var keys := _key_hints()
	_hint.text = "PICK A SQUAD MUTATION   [%s] [%s] [%s]" % keys
	for i in _cards.size():
		_cards[i].visible = i < cards.size()
		_cards[i].modulate.a = 1.0
		_cards[i].scale = Vector2.ONE
		if i >= cards.size():
			continue
		var info: Dictionary = GameManager.PLAYER_MUTATIONS.get(cards[i], {})
		var color: Color = info.get("color", BroadcastUI.CYAN)
		var parts: Dictionary = _parts[i]
		parts.key.text = keys[i] if keys[i].length() <= 2 else str(i + 1)
		parts.badge.add_theme_stylebox_override("panel", _badge_style(color))
		parts.name.text = str(info.get("name", cards[i]))
		parts.name.add_theme_color_override("font_color", color)
		parts.desc.text = str(info.get("desc", ""))
	_on_votes(GameManager.mutations.vote_counts)
	_refresh_highlight()
	Sound.play("reel_land", -10.0, 1.2)


func _key_hints() -> Array:
	if Settings.using_gamepad:
		return ["LEFT", "UP", "RIGHT"]
	return ["1", "2", "3"]


func _on_votes(counts: Array) -> void:
	var multi := GameManager.player_count() > 1
	for i in _parts.size():
		var n: int = counts[i] if i < counts.size() else 0
		_parts[i].pips.text = "o".repeat(n) if multi else ""


func _card_color(i: int) -> Color:
	var cards: Array = GameManager.mutations.cards
	if i >= cards.size():
		return BroadcastUI.CYAN
	return GameManager.PLAYER_MUTATIONS.get(cards[i], {}).get("color", BroadcastUI.CYAN)


func _refresh_highlight() -> void:
	var pick: int = GameManager.mutations.local_pick
	for i in _cards.size():
		_cards[i].add_theme_stylebox_override("panel", _card_style(_card_color(i), i == pick))


func _on_resolved(index: int) -> void:
	_hint.text = "SQUAD MUTATED"
	for i in _cards.size():
		if i == index:
			_cards[i].add_theme_stylebox_override("panel", _card_style(_card_color(i), false, true))
			_cards[i].pivot_offset = CARD_SIZE * 0.5
			var tween := _cards[i].create_tween()
			tween.tween_property(_cards[i], "scale", Vector2.ONE * 1.07, 0.12)
			tween.tween_property(_cards[i], "scale", Vector2.ONE, 0.18)
		else:
			_cards[i].modulate.a = 0.25
	_hide_at = _clock + 2.0


func _on_mutations_changed(active: Array) -> void:
	if active.is_empty() and GameManager.mutations.stage == "":
		_enemy_bar.visible = false
		_strip.visible = false


func _process(delta: float) -> void:
	_clock += delta
	if not _strip.visible and not _enemy_bar.visible:
		return
	var roll := GameManager.mutations
	_timer.visible = roll.stage == "voting"
	_timer.value = roll.time_left / roll.DRAFT_TIME
	if _hide_at > 0.0 and _clock >= _hide_at:
		_hide_at = -1.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_strip, "modulate:a", 0.0, 0.3)
		tween.tween_property(_enemy_bar, "modulate:a", 0.0, 0.3)
		tween.chain().tween_callback(func():
			_strip.visible = false
			_enemy_bar.visible = false)
