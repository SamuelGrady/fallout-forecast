extends CanvasLayer
## Mutation Draft UI (the node is still called SlotReel in main.tscn).
## - Top: a slim red banner with this wave's ENEMY mutation (rolled, not picked).
## - Bottom: three PLAYER mutation cards; pick one with 1 / 2 / 3 (D-pad).
## Nothing covers the middle of the screen, so you keep your view.

const CARD_SIZE := Vector2(218, 124)
const ENEMY_RED := BroadcastUI.PINK

var _enemy_bar := PanelContainer.new()
var _enemy_icon := GameIcon.new()
var _enemy_text := Label.new()
var _strip := Control.new()
var _timer := ProgressBar.new()
var _cards: Array[PanelContainer] = []
var _parts: Array = []  # per card: {badge, key, name, desc, pips}
var _table: MutationTable
var _hide_at := -1.0
var _clock := 0.0
var _pad_hints := false
var _fade: Tween


func _ready() -> void:
	layer = 7
	_table = load("res://game/mutation_table.tres")
	_build_enemy_bar()
	_build_strip()
	_enemy_bar.visible = false
	_strip.visible = false
	var roll := GameManager.mutations
	roll.cards_dealt.connect(_on_dealt)
	roll.votes_changed.connect(_on_votes)
	roll.vote_cast.connect(_on_vote_cast)
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
	_enemy_bar.offset_left = -250
	_enemy_bar.offset_right = 250
	_enemy_bar.offset_top = 84
	_enemy_bar.offset_bottom = 84
	_enemy_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_enemy_bar.add_child(row)
	_enemy_icon.custom_minimum_size = Vector2(24, 24)
	row.add_child(_enemy_icon)
	BroadcastUI.hud_text(_enemy_text, BroadcastUI.T_BODY, ENEMY_RED)
	row.add_child(_enemy_text)
	add_child(_enemy_bar)


func _build_strip() -> void:
	# Below the center reticle, above the vitals/armory panels and the reserved ~360x64 bottom-center hotbar.
	_strip.theme = BroadcastUI.theme()
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_strip.offset_left = -342
	_strip.offset_right = 342
	_strip.offset_top = -352
	_strip.offset_bottom = -170
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 6)
	_strip.add_child(box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in 3:
		row.add_child(_build_card(i))
	_timer.show_percentage = false
	_timer.custom_minimum_size = Vector2(0, 3)
	_timer.max_value = 1.0
	BroadcastUI.thin_bar(_timer, BroadcastUI.CYAN)
	box.add_child(_timer)


## Player card: a coloured badge with the key to press, the name, one line of
## what it does, and vote pips in multiplayer.
func _build_card(_index: int) -> PanelContainer:
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
	badge.custom_minimum_size = Vector2(30, 24)
	var key := Label.new()
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(key, 18, BroadcastUI.INK)
	badge.add_child(key)
	top.add_child(badge)
	var name := Label.new()
	BroadcastUI.text(name, 23, BroadcastUI.PAPER)
	v.add_child(name)
	var pips := Label.new()
	BroadcastUI.text(pips, 17, BroadcastUI.CYAN)
	pips.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(pips)
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BroadcastUI.text(desc, 19, BroadcastUI.PAPER)
	desc.custom_minimum_size = Vector2(CARD_SIZE.x - 24, 0)
	v.add_child(desc)
	_cards.append(card)
	_parts.append({"badge": badge, "key": key, "name": name, "desc": desc, "pips": pips})
	return card


func _card_style(color: Color, selected: bool, winner := false) -> StyleBoxFlat:
	var style := BroadcastUI.panel(Color(BroadcastUI.INK, 0.6), BroadcastUI.AMBER if winner else (color if selected else Color(color, 0.4)))
	style.set_border_width_all(2 if (selected or winner) else 1)
	style.border_width_top = 3
	style.set_content_margin_all(10)
	return style


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_content_margin_all(1)
	return style


# ------------------------------------------------------------------ events
func _on_dealt(enemy: String, cards: Array) -> void:
	_hide_at = -1.0
	if _fade and _fade.is_valid():
		_fade.kill()
	var entry := _table.get_entry(enemy)
	if entry:
		_enemy_icon.kind = entry.id
		_enemy_icon.color = entry.color
	_enemy_text.text = str(WeatherManager.WavePlan.FORECAST.get(WeatherManager.wave_modifier(), "STORM FORECAST"))
	_enemy_icon.visible = entry != null
	_enemy_bar.visible = true
	_enemy_bar.modulate.a = 1.0
	BroadcastUI.reveal(_enemy_bar)
	_strip.visible = not cards.is_empty()
	_strip.modulate.a = 1.0
	if not cards.is_empty():
		BroadcastUI.reveal(_strip)
	_update_input_hints()
	for i in _cards.size():
		_cards[i].visible = i < cards.size()
		_cards[i].modulate.a = 1.0
		_cards[i].scale = Vector2.ONE
		if i >= cards.size():
			continue
		var info: Dictionary = GameManager.PLAYER_MUTATIONS.get(cards[i], {})
		var color: Color = info.get("color", BroadcastUI.CYAN)
		var parts: Dictionary = _parts[i]
		parts.badge.add_theme_stylebox_override("panel", _badge_style(color))
		parts.name.text = str(info.get("name", cards[i])).to_upper()
		parts.name.add_theme_color_override("font_color", color)
		parts.desc.text = str(info.get("desc", ""))
	_on_votes(GameManager.mutations.vote_counts)
	_refresh_highlight()
	Sound.play("reel_land", -10.0, 1.2)


func _update_input_hints() -> void:
	_pad_hints = Settings.using_gamepad
	var keys := ["LEFT", "UP", "RIGHT"] if _pad_hints else ["1", "2", "3"]
	for i in _parts.size():
		_parts[i].key.text = keys[i]


func _on_votes(counts: Array) -> void:
	var multi := GameManager.player_count() > 1
	for i in _parts.size():
		var n: int = counts[i] if i < counts.size() else 0
		_parts[i].pips.text = str(n) if multi and n > 0 else ""


func _card_color(i: int) -> Color:
	var cards: Array = GameManager.mutations.cards
	if i >= cards.size():
		return BroadcastUI.CYAN
	return GameManager.PLAYER_MUTATIONS.get(cards[i], {}).get("color", BroadcastUI.CYAN)


func _refresh_highlight() -> void:
	var pick: int = GameManager.mutations.local_pick
	for i in _cards.size():
		_cards[i].add_theme_stylebox_override("panel", _card_style(_card_color(i), i == pick))


func _on_vote_cast(index: int) -> void:
	_refresh_highlight()
	Sound.play("ui_click")
	if not Settings.reduced_flash:
		var card := _cards[index]
		card.pivot_offset = card.size * .5
		card.create_tween().tween_property(card, "scale", Vector2.ONE * 1.025, 0.10)
		for i in _cards.size():
			if i != index:
				_cards[i].scale = Vector2.ONE


func _on_resolved(index: int) -> void:
	for i in _cards.size():
		if i == index:
			_cards[i].add_theme_stylebox_override("panel", _card_style(_card_color(i), false, true))
			if not Settings.reduced_flash:
				_cards[i].pivot_offset = _cards[i].size * 0.5
				var tween := _cards[i].create_tween()
				tween.tween_property(_cards[i], "scale", Vector2.ONE * 1.05, 0.12)
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
	if roll.stage == "voting" and _pad_hints != Settings.using_gamepad:
		_update_input_hints()
	_timer.visible = roll.stage == "voting"
	_timer.value = roll.time_left / roll.DRAFT_TIME
	if _hide_at > 0.0 and _clock >= _hide_at:
		_hide_at = -1.0
		_fade = create_tween().set_parallel(true)
		_fade.tween_property(_strip, "modulate:a", 0.0, 0.3)
		_fade.tween_property(_enemy_bar, "modulate:a", 0.0, 0.3)
		_fade.chain().tween_callback(func():
			_strip.visible = false
			_enemy_bar.visible = false)
