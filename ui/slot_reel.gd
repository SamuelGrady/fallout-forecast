extends CanvasLayer
## Broadcast "Mutation Draft" overlay (node is still named SlotReel in main.tscn).
## Matches the Broadcast "Field Kit" weapon select (ui/starter_picker.gd):
## centered VHS broadcast frame with incoming enemy mutation threat banner and
## three interactive player bio-mutation cards selectable via mouse, 1/2/3,
## A/D or arrows + Enter/Space, or gamepad.

const KEYS := [KEY_1, KEY_2, KEY_3]
const KP_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3]
const PAD_HINTS := ["LEFT", "UP", "RIGHT"]
const SCRIM_COLOR := Color(0.03, 0.05, 0.09, 0.72)
const CARD_SIZE := Vector2(230, 270)
const SUBTITLE_SOLO := "CHOOSE ONE SQUAD BIO-UPGRADE BEFORE THE NEXT STORM"
const SUBTITLE_MULTI := "SQUAD VOTE — MOST VOTES WINS"
const SUBTITLE_ALL_OWNED := "INCOMING STORM THREAT REPORT"
const SUBTITLE_LOCKED := "BIO-UPGRADE LOCKED IN — PREPARING NEXT STORM"

var _root: Control
var _scrim: ColorRect
var _frame: PanelContainer
var _slate_right: Label
var _countdown_label: Label
var _subtitle: Label
var _timer_bar: ProgressBar

var _threat_panel: PanelContainer
var _enemy_icon: GameIcon
var _threat_tag: Label
var _enemy_name: Label
var _enemy_desc: Label

var _cards_row: HBoxContainer
var _all_owned_panel: PanelContainer
var _footer_hint: Label

var _cards: Array[PanelContainer] = []
var _parts: Array[Dictionary] = []
var _card_tweens: Array = []

var _table: MutationTable
var _focused := 0
var _winner := -1
var _card_count := 0
var _pad := false
var _stick_dir := 0
var _interactive := false
var _closing := false
var _dismissed := true
var _claimed_cursor := false
var _clock := 0.0
var _hide_at := -1.0
var _fade_tween: Tween


func _ready() -> void:
	layer = 7
	if _is_server_only():
		visible = false
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("mutation_draft_ui")
	_table = load("res://game/mutation_table.tres")
	_pad = Settings.using_gamepad
	_build_ui()
	_refresh_hints()
	_root.hide()

	var roll := GameManager.mutations
	if roll:
		roll.cards_dealt.connect(_on_dealt)
		roll.votes_changed.connect(_on_votes)
		roll.vote_cast.connect(_on_vote_cast)
		roll.draft_resolved.connect(_on_resolved)
		roll.mutations_changed.connect(_on_mutations_changed)
		if roll.stage == "voting":
			_on_dealt(roll.enemy_pick, roll.cards)


func _exit_tree() -> void:
	_kill_fade_tween()
	_kill_card_tweens()
	var roll := GameManager.mutations
	if roll == null:
		return
	for pair in [
		[roll.cards_dealt, _on_dealt],
		[roll.votes_changed, _on_votes],
		[roll.vote_cast, _on_vote_cast],
		[roll.draft_resolved, _on_resolved],
		[roll.mutations_changed, _on_mutations_changed],
	]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _is_server_only() -> bool:
	return Net.dedicated or DisplayServer.get_name() == "headless"


# ------------------------------------------------------------------ layout
func _build_ui() -> void:
	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.theme = BroadcastUI.theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_scrim = ColorRect.new()
	_scrim.color = SCRIM_COLOR
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_frame = PanelContainer.new()
	_frame.custom_minimum_size = Vector2(780, 0)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_theme_stylebox_override("panel", _frame_style())
	center.add_child(_frame)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 11)
	root_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(root_box)

	# Top VHS broadcast slate bar.
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(top_bar)

	var tag_pill := PanelContainer.new()
	tag_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_pill.add_theme_stylebox_override("panel", _tag_style())
	top_bar.add_child(tag_pill)

	var tag_label := Label.new()
	tag_label.text = "CH 01 // MUTATION DRAFT"
	BroadcastUI.text(tag_label, 18, BroadcastUI.CYAN)
	tag_pill.add_child(tag_label)

	_slate_right = Label.new()
	_slate_right.text = "WAVE 02  //  BIO-UPGRADE"
	_slate_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slate_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_slate_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(_slate_right, 17, BroadcastUI.MUTED)
	top_bar.add_child(_slate_right)

	_countdown_label = Label.new()
	_countdown_label.text = "14s"
	_countdown_label.custom_minimum_size = Vector2(44, 0)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(_countdown_label, 19, BroadcastUI.CYAN)
	top_bar.add_child(_countdown_label)

	# Title + subtitle.
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(title_box)

	var title := Label.new()
	title.text = "SELECT MUTATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(title, 40, BroadcastUI.PAPER, 2)
	title_box.add_child(title)

	_subtitle = Label.new()
	_subtitle.text = SUBTITLE_SOLO
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(_subtitle, 20, BroadcastUI.MUTED)
	title_box.add_child(_subtitle)

	# Thin cyan countdown ProgressBar right under the header.
	_timer_bar = ProgressBar.new()
	_timer_bar.max_value = 1.0
	_timer_bar.step = 0.001
	_timer_bar.value = 1.0
	_timer_bar.custom_minimum_size = Vector2(0, 4)
	_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BroadcastUI.thin_bar(_timer_bar, BroadcastUI.CYAN)
	root_box.add_child(_timer_bar)

	# Incoming Enemy Mutation Threat Banner.
	_build_threat_banner(root_box)

	# Three side-by-side Player Mutation cards.
	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", 16)
	_cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(_cards_row)

	for i in 3:
		_cards_row.add_child(_build_card(i))

	# Compact fallback notice when all squad mutations are already owned.
	_build_all_owned_panel(root_box)

	# Footer controls hint.
	_footer_hint = Label.new()
	_footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(_footer_hint, 18, BroadcastUI.MUTED)
	root_box.add_child(_footer_hint)


func _build_threat_banner(parent: Control) -> void:
	_threat_panel = PanelContainer.new()
	_threat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_panel.add_theme_stylebox_override("panel", _threat_panel_style())
	parent.add_child(_threat_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_panel.add_child(row)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(48, 48)
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", _threat_icon_style())
	row.add_child(icon_box)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(icon_center)

	_enemy_icon = GameIcon.new()
	_enemy_icon.custom_minimum_size = Vector2(32, 32)
	_enemy_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(_enemy_icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 1)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	_threat_tag = Label.new()
	_threat_tag.text = "INCOMING THREAT // STORM FORECAST"
	BroadcastUI.text(_threat_tag, 16, BroadcastUI.PINK)
	text_col.add_child(_threat_tag)

	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 12)
	detail_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(detail_row)

	_enemy_name = Label.new()
	_enemy_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(_enemy_name, 24, BroadcastUI.PAPER, 2)
	detail_row.add_child(_enemy_name)

	_enemy_desc = Label.new()
	_enemy_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enemy_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BroadcastUI.text(_enemy_desc, 19, BroadcastUI.PAPER)
	detail_row.add_child(_enemy_desc)


func _build_all_owned_panel(parent: Control) -> void:
	_all_owned_panel = PanelContainer.new()
	_all_owned_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_all_owned_panel.add_theme_stylebox_override("panel", _all_owned_style())
	_all_owned_panel.visible = false
	parent.add_child(_all_owned_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_all_owned_panel.add_child(box)

	var heading := Label.new()
	heading.text = "ALL SQUAD MUTATIONS ACQUIRED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(heading, 24, BroadcastUI.ACID, 1)
	box.add_child(heading)

	var sub := Label.new()
	sub.text = "SQUAD BIO-DECK COMPLETE — STAND BY FOR NEXT STORM"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(sub, 18, BroadcastUI.MUTED)
	box.add_child(sub)


func _build_card(index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	card.mouse_entered.connect(_on_card_hover.bind(index))
	card.gui_input.connect(_on_card_gui_input.bind(index))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# Card header: colored key/D-pad badge + multiplayer vote pill.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(32, 24)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_label := Label.new()
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(key_label, 18, BroadcastUI.INK)
	badge.add_child(key_label)
	top.add_child(badge)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(header_spacer)

	var vote_pill := PanelContainer.new()
	vote_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vote_pill.add_theme_stylebox_override("panel", _vote_pill_style())
	vote_pill.visible = false
	var vote_label := Label.new()
	vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(vote_label, 16, BroadcastUI.CYAN)
	vote_pill.add_child(vote_label)
	top.add_child(vote_pill)

	# Framed icon well (~76px tall) with centered 48x48 GameIcon.
	var icon_well := PanelContainer.new()
	icon_well.custom_minimum_size = Vector2(0, 76)
	icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_theme_stylebox_override("panel", _icon_well_style(BroadcastUI.MUTED, false))
	box.add_child(icon_well)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_child(icon_center)

	var icon := GameIcon.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)

	# Bold uppercase mutation name.
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(name_label, 24, BroadcastUI.PAPER, 2)
	box.add_child(name_label)

	# Thin horizontal divider.
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(BroadcastUI.MUTED, 0.24)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sep)

	# Clear wrapped description.
	var desc_label := Label.new()
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(CARD_SIZE.x - 32.0, 44.0)
	BroadcastUI.text(desc_label, 19, BroadcastUI.PAPER)
	box.add_child(desc_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	var cta_label := Label.new()
	cta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(cta_label, 18, BroadcastUI.MUTED)
	box.add_child(cta_label)

	_cards.append(card)
	_card_tweens.append(null)
	_parts.append({
		"badge": badge,
		"key": key_label,
		"vote_pill": vote_pill,
		"vote_label": vote_label,
		"icon_well": icon_well,
		"icon": icon,
		"name": name_label,
		"sep": sep,
		"desc": desc_label,
		"cta": cta_label,
	})
	return card


# ------------------------------------------------------------------ styling
func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.11, 0.90)
	style.border_color = BroadcastUI.CYAN
	style.border_width_left = 4
	style.border_width_top = 2
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	return style


func _tag_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BroadcastUI.CYAN, 0.14)
	style.border_color = BroadcastUI.CYAN
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _threat_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.045, 0.075, 0.88)
	style.border_color = BroadcastUI.PINK
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _threat_icon_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.02, 0.04, 0.82)
	style.border_color = Color(BroadcastUI.PINK, 0.42)
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	return style


func _all_owned_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.12, 0.82)
	style.border_color = Color(BroadcastUI.ACID, 0.65)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	return style


func _vote_pill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BroadcastUI.CYAN, 0.16)
	style.border_color = BroadcastUI.CYAN
	style.set_border_width_all(1)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _icon_well_style(accent: Color, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.07, 0.78)
	style.border_color = Color(accent, 0.42) if highlighted else Color(BroadcastUI.MUTED, 0.18)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	return style


func _card_style(accent: Color, focused: bool, voted: bool, winner: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var active := focused or voted or winner
	var border_side := 2 if active else 1
	var border_top := 4 if active else 3
	if winner:
		style.bg_color = Color(0.14, 0.15, 0.10, 0.98)
		style.border_color = BroadcastUI.AMBER
	elif voted:
		style.bg_color = Color(0.08, 0.16, 0.22, 0.96).lerp(Color(accent.r, accent.g, accent.b, 0.96), 0.10)
		style.border_color = BroadcastUI.CYAN
	elif focused:
		style.bg_color = Color(0.08, 0.16, 0.22, 0.96)
		style.border_color = accent.lightened(0.12)
	else:
		style.bg_color = Color(0.05, 0.085, 0.135, 0.88)
		style.border_color = Color(accent, 0.36)
	style.set_border_width_all(border_side)
	style.border_width_top = border_top
	# Compensate padding so focus/vote border thickening never shifts layout.
	var pad_side := 14 - border_side
	style.content_margin_left = pad_side
	style.content_margin_right = pad_side
	style.content_margin_bottom = pad_side
	style.content_margin_top = 15 - border_top
	return style


func _badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _card_color(index: int) -> Color:
	var roll := GameManager.mutations
	if roll == null or index < 0 or index >= roll.cards.size():
		return BroadcastUI.CYAN
	return GameManager.PLAYER_MUTATIONS.get(roll.cards[index], {}).get("color", BroadcastUI.CYAN)


func _refresh_hints() -> void:
	for i in _parts.size():
		_parts[i].key.text = PAD_HINTS[i] if _pad else str(i + 1)
	if _footer_hint:
		_footer_hint.text = "[D-PAD] QUICK VOTE  ·  [STICK] BROWSE  ·  [A] DRAFT" if _pad else "CLICK CARD  ·  [1/2/3]  ·  [A/D] + ENTER"


func _apply_card_styles() -> void:
	var roll := GameManager.mutations
	var local_pick: int = roll.local_pick if roll else -1
	var resolved: bool = _winner >= 0 or (roll != null and str(roll.stage) == "result")
	var multi := GameManager.player_count() > 1

	for i in _cards.size():
		if i >= _card_count:
			continue
		var accent := _card_color(i)
		var is_winner := resolved and i == _winner
		var is_voted := not resolved and i == local_pick
		var is_focused := not resolved and i == _focused
		var parts: Dictionary = _parts[i]

		_cards[i].add_theme_stylebox_override("panel", _card_style(accent, is_focused, is_voted, is_winner))
		var badge_color := BroadcastUI.AMBER if is_winner else (accent if (is_voted or is_focused) else Color(accent, 0.78))
		parts.badge.add_theme_stylebox_override("panel", _badge_style(badge_color))
		parts.icon_well.add_theme_stylebox_override("panel", _icon_well_style(BroadcastUI.AMBER if is_winner else accent, is_focused or is_voted or is_winner))
		parts.name.add_theme_color_override("font_color", BroadcastUI.AMBER if is_winner else accent)
		parts.sep.color = Color(BroadcastUI.AMBER, 0.45) if is_winner else (Color(accent, 0.40) if (is_focused or is_voted) else Color(BroadcastUI.MUTED, 0.24))

		var key_text: String = str(PAD_HINTS[i]) if _pad else str(i + 1)
		if is_winner:
			parts.cta.text = "> LOCKED IN"
			parts.cta.add_theme_color_override("font_color", BroadcastUI.AMBER)
		elif resolved:
			parts.cta.text = "—"
			parts.cta.add_theme_color_override("font_color", Color(BroadcastUI.MUTED, 0.45))
		elif is_voted:
			parts.cta.text = "> VOTED" if multi else "> SELECTED"
			parts.cta.add_theme_color_override("font_color", BroadcastUI.CYAN)
		elif is_focused:
			parts.cta.text = "[%s] / [A] TO DRAFT" % key_text if _pad else "CLICK / [%s] TO DRAFT" % key_text
			parts.cta.add_theme_color_override("font_color", BroadcastUI.CYAN)
		else:
			parts.cta.text = "[%s] TO DRAFT" % key_text if _pad else "CLICK / [%s] TO DRAFT" % key_text
			parts.cta.add_theme_color_override("font_color", Color(BroadcastUI.MUTED, 0.72))


func _animate_card_focus() -> void:
	if Settings.reduced_flash:
		for i in _card_count:
			_cards[i].scale = Vector2.ONE
		return
	var local_pick: int = GameManager.mutations.local_pick if GameManager.mutations else -1
	for i in _card_count:
		if _card_tweens[i] is Tween and _card_tweens[i].is_valid():
			_card_tweens[i].kill()
		var card := _cards[i]
		card.pivot_offset = card.size * 0.5
		var lifted := i == _focused or i == local_pick
		var target := Vector2.ONE * (1.025 if lifted else 1.0)
		var tween := card.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_card_tweens[i] = tween
		tween.tween_property(card, "scale", target, 0.09)


func _kill_fade_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _kill_card_tweens() -> void:
	for i in _card_tweens.size():
		if _card_tweens[i] is Tween and _card_tweens[i].is_valid():
			_card_tweens[i].kill()
		_card_tweens[i] = null


func _set_interactive(enabled: bool) -> void:
	if _interactive == enabled:
		return
	_interactive = enabled
	var mode := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	_root.mouse_filter = mode
	if _scrim:
		_scrim.mouse_filter = mode
	if _frame:
		_frame.mouse_filter = mode
	for i in _cards.size():
		_cards[i].mouse_filter = mode if (enabled and i < _card_count) else Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------------ lifecycle & events
func _menu_on_top() -> bool:
	return not MenuState.stack.is_empty() or get_tree().paused \
		or GameManager.awaiting_tape_choice or GameManager.finished


func _reveal_root() -> void:
	_kill_fade_tween()
	_root.visible = true
	if Settings.reduced_flash:
		_root.modulate.a = 1.0
		return
	_root.modulate.a = 0.0
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_root, "modulate:a", 1.0, 0.2)


func _yield_for_menu() -> void:
	_kill_fade_tween()
	_set_interactive(false)
	_root.hide()


func _close_immediate(restore_mouse: bool) -> void:
	_kill_fade_tween()
	_kill_card_tweens()
	_closing = false
	_dismissed = true
	_hide_at = -1.0
	_set_interactive(false)
	_root.hide()
	if restore_mouse:
		_restore_mouse_capture()
	else:
		_claimed_cursor = false


func _begin_fade_out() -> void:
	_dismissed = true
	if _closing or not _root.visible:
		_restore_mouse_capture()
		return
	_closing = true
	_hide_at = -1.0
	_set_interactive(false)
	_restore_mouse_capture()
	_kill_fade_tween()
	if Settings.reduced_flash:
		_closing = false
		_root.hide()
		return
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_root, "modulate:a", 0.0, 0.24)
	_fade_tween.tween_callback(func():
		_closing = false
		_root.hide())


func _restore_mouse_capture() -> void:
	if _is_server_only() or not _claimed_cursor:
		return
	_claimed_cursor = false
	if MenuState.stack.is_empty() and not get_tree().paused \
			and not InventoryMenu.is_open() and GameManager.run_active \
			and not GameManager.finished and not GameManager.awaiting_tape_choice:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _populate_threat_banner(enemy: String) -> void:
	var entry: MutationData = _table.get_entry(enemy) if _table else null
	var modifier: String = WeatherManager.wave_modifier()
	var forecast: String = str(WeatherManager.WavePlan.FORECAST.get(modifier, "STORM FORECAST"))

	if entry != null:
		_threat_panel.visible = true
		_enemy_icon.kind = entry.id
		_enemy_icon.color = entry.color
		_enemy_icon.visible = true
		_threat_tag.text = "INCOMING THREAT // %s" % forecast
		_enemy_name.text = entry.display_name.to_upper()
		_enemy_name.add_theme_color_override("font_color", entry.color)
		_enemy_desc.text = entry.description
		_enemy_desc.visible = not entry.description.is_empty()
	elif not modifier.is_empty():
		_threat_panel.visible = true
		_enemy_icon.kind = "weather"
		_enemy_icon.color = BroadcastUI.PINK
		_enemy_icon.visible = true
		_threat_tag.text = "INCOMING THREAT // %s" % modifier
		_enemy_name.text = forecast
		_enemy_name.add_theme_color_override("font_color", BroadcastUI.PINK)
		_enemy_desc.text = ""
		_enemy_desc.visible = false
	else:
		_threat_panel.visible = false


func _on_dealt(enemy: String, cards: Array) -> void:
	if _is_server_only():
		return
	_kill_fade_tween()
	_kill_card_tweens()
	_set_interactive(false)
	_closing = false
	_dismissed = false
	_hide_at = -1.0
	_winner = -1
	_stick_dir = 0
	_card_count = mini(cards.size(), _cards.size())
	_focused = 0

	_slate_right.text = "WAVE %02d  //  BIO-UPGRADE" % maxi(1, WeatherManager.wave)
	if _card_count == 0:
		_subtitle.text = SUBTITLE_ALL_OWNED
	elif GameManager.player_count() > 1:
		_subtitle.text = SUBTITLE_MULTI
	else:
		_subtitle.text = SUBTITLE_SOLO
	_subtitle.add_theme_color_override("font_color", BroadcastUI.MUTED)

	_populate_threat_banner(enemy)

	_cards_row.visible = _card_count > 0
	_all_owned_panel.visible = _card_count == 0
	_footer_hint.visible = _card_count > 0
	_countdown_label.visible = _card_count > 0
	_countdown_label.add_theme_color_override("font_color", BroadcastUI.CYAN)
	_timer_bar.visible = true
	_timer_bar.value = 1.0
	BroadcastUI.thin_bar(_timer_bar, BroadcastUI.CYAN)

	for i in _cards.size():
		var shown := i < _card_count
		_cards[i].visible = shown
		_cards[i].modulate.a = 1.0
		_cards[i].scale = Vector2.ONE
		if not shown:
			continue
		var card_id: String = str(cards[i])
		var info: Dictionary = GameManager.PLAYER_MUTATIONS.get(card_id, {})
		var color: Color = info.get("color", BroadcastUI.CYAN)
		var parts: Dictionary = _parts[i]
		parts.icon.kind = card_id
		parts.icon.color = color
		parts.name.text = str(info.get("name", card_id)).to_upper()
		parts.desc.text = str(info.get("desc", ""))
		parts.vote_pill.visible = false

	_pad = Settings.using_gamepad
	_refresh_hints()
	_on_votes(GameManager.mutations.vote_counts)
	_apply_card_styles()
	_update_countdown(GameManager.mutations)

	if not _menu_on_top():
		_reveal_root()
		if _card_count > 0:
			_set_interactive(true)
			if not InventoryMenu.is_open():
				_claimed_cursor = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_set_interactive(false)
	else:
		_yield_for_menu()

	Sound.play("reel_land", -10.0, 1.2)


func _on_votes(counts: Array) -> void:
	var multi := GameManager.player_count() > 1
	for i in _parts.size():
		var n: int = int(counts[i]) if i < counts.size() else 0
		var show_pill := multi and n > 0 and i < _card_count
		_parts[i].vote_pill.visible = show_pill
		if show_pill:
			_parts[i].vote_label.text = "1 VOTE" if n == 1 else "%d VOTES" % n


func _on_vote_cast(index: int) -> void:
	if index < 0 or index >= _card_count:
		return
	_focused = index
	_apply_card_styles()
	Sound.play("ui_click")
	_animate_card_focus()


func _on_resolved(index: int) -> void:
	_winner = index
	_set_interactive(false)
	_apply_card_styles()

	if _card_count > 0:
		_subtitle.text = SUBTITLE_LOCKED
		_subtitle.add_theme_color_override("font_color", BroadcastUI.AMBER)
		_countdown_label.text = "LOCKED"
		_countdown_label.add_theme_color_override("font_color", BroadcastUI.AMBER)
		BroadcastUI.thin_bar(_timer_bar, BroadcastUI.AMBER)
		_timer_bar.value = 1.0

	_kill_card_tweens()
	for i in _card_count:
		if i == index:
			_cards[i].modulate.a = 1.0
			if not Settings.reduced_flash:
				_cards[i].pivot_offset = _cards[i].size * 0.5
				var tween := _cards[i].create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				_card_tweens[i] = tween
				tween.tween_property(_cards[i], "scale", Vector2.ONE * 1.05, 0.12)
				tween.tween_property(_cards[i], "scale", Vector2.ONE * 1.02, 0.16)
		else:
			_cards[i].modulate.a = 0.28
			_cards[i].scale = Vector2.ONE

	Sound.play("reel_land")
	var beat := maxf(GameManager.mutations.RESULT_TIME - 0.35, 1.4) if _card_count > 0 else 1.25
	_hide_at = _clock + beat


func _on_mutations_changed(active: Array) -> void:
	if active.is_empty() and GameManager.mutations != null and GameManager.mutations.stage == "":
		_close_immediate(_claimed_cursor)


func _update_countdown(roll: Node) -> void:
	if roll == null:
		return
	if roll.stage == "voting":
		var total: float = roll.DRAFT_TIME if _card_count > 0 else 1.5
		_timer_bar.value = clampf(roll.time_left / maxf(total, 0.01), 0.0, 1.0)
		if _card_count > 0:
			var secs := ceili(roll.time_left)
			_countdown_label.text = "%ds" % secs
			var urgent := secs <= 4
			_countdown_label.add_theme_color_override("font_color", BroadcastUI.AMBER if urgent else BroadcastUI.CYAN)


func _process(delta: float) -> void:
	if not get_tree().paused:
		_clock += delta
	if _pad != Settings.using_gamepad:
		_pad = Settings.using_gamepad
		_refresh_hints()
		if _card_count > 0:
			_apply_card_styles()

	var roll := GameManager.mutations
	if roll == null:
		return

	var menu_up := _menu_on_top()

	if _closing:
		# Yield immediately if Pause or Dev menu opens mid-fade without touching mouse mode.
		if menu_up:
			_close_immediate(false)
		return

	if roll.stage == "":
		if _root.visible:
			if menu_up:
				_close_immediate(false)
			else:
				_begin_fade_out()
		elif _claimed_cursor:
			if not menu_up:
				_restore_mouse_capture()
			else:
				_claimed_cursor = false
		return

	if _dismissed:
		return

	# Draft is active ("voting" or "result").
	if menu_up:
		if _root.visible or _interactive:
			_yield_for_menu()
		return

	if not _root.visible:
		_reveal_root()
		_refresh_hints()
		_apply_card_styles()

	if roll.stage == "voting":
		_update_countdown(roll)
		if _card_count > 0:
			_set_interactive(true)
			if not InventoryMenu.is_open():
				_claimed_cursor = true
				if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			_set_interactive(false)
	elif roll.stage == "result":
		_set_interactive(false)
		if _hide_at > 0.0 and _clock >= _hide_at:
			_begin_fade_out()


# ------------------------------------------------------------------ input
func _set_pad(is_pad: bool) -> void:
	if _pad != is_pad:
		_pad = is_pad
		_refresh_hints()
		if _card_count > 0:
			_apply_card_styles()


func _set_focus(index: int, play_sound: bool) -> void:
	if _card_count <= 0:
		return
	var clamped := clampi(index, 0, _card_count - 1)
	var changed := clamped != _focused
	_focused = clamped
	_apply_card_styles()
	_animate_card_focus()
	if play_sound and changed:
		Sound.ui_focus()


func _move_focus(step: int) -> void:
	if _card_count <= 1:
		return
	_set_focus(posmod(_focused + step, _card_count), true)


func _vote_card(index: int) -> void:
	if not _interactive or _closing or index < 0 or index >= _card_count:
		return
	var roll := GameManager.mutations
	if roll == null or roll.stage != "voting":
		return
	_focused = index
	roll.vote(index)


func _on_card_hover(index: int) -> void:
	if not _interactive or _closing or index < 0 or index >= _card_count:
		return
	_set_pad(false)
	_set_focus(index, true)


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if not _interactive or _closing or index < 0 or index >= _card_count:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cards[index].accept_event()
		_vote_card(index)


func _input(event: InputEvent) -> void:
	if not _root.visible or not _interactive or _closing or _card_count <= 0:
		return
	var roll := GameManager.mutations
	if roll == null or roll.stage != "voting":
		return
	if _menu_on_top() or InventoryMenu.is_open():
		return

	if event is InputEventJoypadMotion:
		if event.axis == JOY_AXIS_LEFT_X:
			if absf(event.axis_value) < 0.30:
				_stick_dir = 0
			elif event.axis_value < -0.55 and _stick_dir != -1:
				_stick_dir = -1
				_set_pad(true)
				_move_focus(-1)
				get_viewport().set_input_as_handled()
			elif event.axis_value > 0.55 and _stick_dir != 1:
				_stick_dir = 1
				_set_pad(true)
				_move_focus(1)
				get_viewport().set_input_as_handled()
		return

	if not event.is_pressed() or event.is_echo():
		return

	if event is InputEventKey:
		# Never intercept ESC (pause/ui_cancel) or F10 (Dev Menu).
		if event.keycode in [KEY_ESCAPE, KEY_F10] or event.physical_keycode in [KEY_ESCAPE, KEY_F10] \
				or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			return
		var quick := KEYS.find(event.physical_keycode)
		if quick < 0:
			quick = KEYS.find(event.keycode)
		if quick < 0:
			quick = KP_KEYS.find(event.keycode)
		if quick >= 0:
			_set_pad(false)
			if quick < _card_count:
				_vote_card(quick)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode in [KEY_A, KEY_LEFT] or event.keycode in [KEY_A, KEY_LEFT]:
			_set_pad(false)
			_move_focus(-1)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode in [KEY_D, KEY_RIGHT] or event.keycode in [KEY_D, KEY_RIGHT]:
			_set_pad(false)
			_move_focus(1)
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] \
				or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] \
				or event.is_action_pressed("ui_accept"):
			_set_pad(false)
			_vote_card(_focused)
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventJoypadButton:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			return
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			_set_pad(true)
			_vote_card(0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == JOY_BUTTON_DPAD_UP:
			_set_pad(true)
			_vote_card(1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_set_pad(true)
			_vote_card(2)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept") or event.button_index == JOY_BUTTON_A:
			_set_pad(true)
			_vote_card(_focused)
			get_viewport().set_input_as_handled()
			return
