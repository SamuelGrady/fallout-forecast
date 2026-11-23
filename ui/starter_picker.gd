extends Control
## Broadcast "Field Kit" spawn overlay: pick one of three starting weapons via
## mouse click, 1/2/3 quick keys, A/D or arrows + Enter/Space, or gamepad.
## Each card is a shared ItemStatCard (TALL layout) so the starter lineup reads
## exactly like the inventory inspector and the vending / pickup HUD card.

const KEYS := [KEY_1, KEY_2, KEY_3]
const KP_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3]
const PAD_HINTS := ["LEFT", "UP", "RIGHT"]
const SCRIM_COLOR := Color(0.03, 0.05, 0.09, 0.72)
const CARD_SIZE := Vector2(230, 326)
const SUBTITLE_DEFAULT := "CHOOSE YOUR SIDEARM BEFORE THE STORM HITS"
const SUBTITLE_FULL := "FREE A HOTBAR SLOT TO CLAIM YOUR FIELD KIT"

var loot: RunLoot

var _scrim: ColorRect
var _frame: PanelContainer
var _subtitle: Label
var _footer_hint: Label
var _cards: Array[ItemStatCard] = []
var _parts: Array[Dictionary] = []
var _card_tweens: Array = []

var _focused := 0
var _pad := false
var _stick_dir := 0
var _overlay_active := false
var _closing := false
var _clock := 0.0
var _pending_until := -1.0
var _fade_tween: Tween


func _ready() -> void:
	if _is_server_only():
		visible = false
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = BroadcastUI.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad = Settings.using_gamepad
	_build_ui()
	_refresh_hints()
	_apply_card_styles(-1)
	hide()


func _exit_tree() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	for t in _card_tweens:
		if t is Tween and t.is_valid():
			t.kill()


func _is_server_only() -> bool:
	return Net.dedicated or DisplayServer.get_name() == "headless"


# ------------------------------------------------------------------ layout
func _build_ui() -> void:
	_scrim = ColorRect.new()
	_scrim.color = SCRIM_COLOR
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_frame = PanelContainer.new()
	_frame.custom_minimum_size = Vector2(780, 0)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_theme_stylebox_override("panel", _frame_style())
	center.add_child(_frame)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
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
	tag_label.text = "CH 00 // FIELD ISSUE"
	BroadcastUI.text(tag_label, 18, BroadcastUI.CYAN)
	tag_pill.add_child(tag_label)

	var slate_right := Label.new()
	slate_right.text = "WAVE 01  //  LOADOUT LOCK"
	slate_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slate_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slate_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(slate_right, 17, BroadcastUI.MUTED)
	top_bar.add_child(slate_right)

	# Title + subtitle.
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(title_box)

	var title := Label.new()
	title.text = "SELECT STARTING WEAPON"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(title, 40, BroadcastUI.PAPER, 2)
	title_box.add_child(title)

	_subtitle = Label.new()
	_subtitle.text = SUBTITLE_DEFAULT
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(_subtitle, 20, BroadcastUI.MUTED)
	title_box.add_child(_subtitle)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(BroadcastUI.CYAN, 0.35)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(divider)

	# Normalize the bars across the starter lineup so the three kits contrast.
	var maxima := ItemStatCard.gun_maxima(RunLoot.STARTER_KITS, 0)

	# Three side-by-side weapon cards.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_box.add_child(row)

	for i in RunLoot.STARTER_KITS.size():
		row.add_child(_build_card(i, RunLoot.STARTER_KITS[i], maxima))

	# Footer controls hint.
	_footer_hint = Label.new()
	_footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(_footer_hint, 18, BroadcastUI.MUTED)
	root_box.add_child(_footer_hint)


func _build_card(index: int, kit_id: String, maxima: Dictionary) -> ItemStatCard:
	var card := ItemStatCard.new(ItemStatCard.Layout.TALL)
	var opts := maxima.duplicate()
	opts["badge"] = str(index + 1)
	card.set_item(kit_id, 0, opts)
	card.custom_minimum_size = CARD_SIZE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	card.mouse_entered.connect(_on_card_hover.bind(index))
	card.gui_input.connect(_on_card_gui_input.bind(index))
	card.badge.custom_minimum_size = Vector2(32, 24)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.content.add_child(spacer)

	var cta := Label.new()
	cta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(cta, 18, BroadcastUI.MUTED)
	card.content.add_child(cta)

	_cards.append(card)
	_card_tweens.append(null)
	_parts.append({
		"badge": card.badge,
		"key": card.badge_label,
		"role": card.role_label,
		"name": card.name_label,
		"tagline": card.tagline_label,
		"cta": cta,
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


func _card_style(focused: bool, confirmed := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var border_side := 2 if (focused or confirmed) else 1
	var border_top := 4 if (focused or confirmed) else 3
	style.bg_color = Color(0.14, 0.15, 0.10, 0.98) if confirmed else (Color(0.08, 0.16, 0.22, 0.96) if focused else Color(0.05, 0.085, 0.135, 0.88))
	style.border_color = BroadcastUI.AMBER if confirmed else (BroadcastUI.CYAN if focused else Color(BroadcastUI.MUTED, 0.35))
	style.set_border_width_all(border_side)
	style.border_width_top = border_top
	# Compensate padding by 1 px so focus border thickening never shifts layout.
	var pad_side := 14 - border_side
	style.content_margin_left = pad_side
	style.content_margin_right = pad_side
	style.content_margin_bottom = pad_side
	style.content_margin_top = 15 - border_top
	return style


func _refresh_hints() -> void:
	for i in _parts.size():
		_parts[i].key.text = PAD_HINTS[i] if _pad else str(i + 1)
	if _footer_hint:
		_footer_hint.text = "[D-PAD / STICK] BROWSE   |   [A] EQUIP" if _pad else "[1-3] QUICK PICK   |   [A/D] BROWSE   |   [CLICK / ENTER] EQUIP"


func _apply_card_styles(confirmed_index: int) -> void:
	for i in _cards.size():
		var confirmed := i == confirmed_index
		var focused := i == _focused and confirmed_index < 0
		var parts := _parts[i]
		_cards[i].add_theme_stylebox_override("panel", _card_style(focused, confirmed))
		var badge_color := BroadcastUI.AMBER if confirmed else (BroadcastUI.CYAN if focused else Color(BroadcastUI.MUTED, 0.72))
		parts.badge.add_theme_stylebox_override("panel", ItemStatCard.badge_style(badge_color))
		parts.role.add_theme_color_override("font_color", BroadcastUI.AMBER if (focused or confirmed) else BroadcastUI.MUTED)
		parts.name.add_theme_color_override("font_color", BroadcastUI.AMBER if confirmed else BroadcastUI.PAPER)
		parts.tagline.add_theme_color_override("font_color", BroadcastUI.PAPER if (focused or confirmed) else BroadcastUI.MUTED)
		if confirmed:
			parts.cta.text = "> EQUIPPED"
			parts.cta.add_theme_color_override("font_color", BroadcastUI.AMBER)
		elif focused:
			parts.cta.text = "> EQUIP"
			parts.cta.add_theme_color_override("font_color", BroadcastUI.CYAN)
		else:
			parts.cta.text = "SELECT"
			parts.cta.add_theme_color_override("font_color", Color(BroadcastUI.MUTED, 0.55))


func _animate_card_focus() -> void:
	if Settings.reduced_flash:
		for card in _cards:
			card.scale = Vector2.ONE
		return
	for i in _cards.size():
		if _card_tweens[i] is Tween and _card_tweens[i].is_valid():
			_card_tweens[i].kill()
		var card := _cards[i]
		card.pivot_offset = card.size * 0.5
		var target := Vector2.ONE * (1.025 if i == _focused else 1.0)
		var tween := card.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_card_tweens[i] = tween
		tween.tween_property(card, "scale", target, 0.09)


func _set_interactive(enabled: bool) -> void:
	var mode := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	mouse_filter = mode
	if _scrim:
		_scrim.mouse_filter = mode
	if _frame:
		_frame.mouse_filter = mode
	for card in _cards:
		card.mouse_filter = mode


# ------------------------------------------------------------------ lifecycle
func _should_show() -> bool:
	if _is_server_only() or loot == null or _closing:
		return false
	if _pending_until > 0.0 and _clock < _pending_until:
		return false
	if not loot.starter_available():
		return false
	if not MenuState.stack.is_empty() or get_tree().paused:
		return false
	if GameManager.finished or GameManager.is_voting() or GameManager.awaiting_tape_choice:
		return false
	var player := get_tree().get_first_node_in_group("local_player")
	return player != null and player.state == "ok"


func _open_overlay() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_overlay_active = true
	_stick_dir = 0
	for card in _cards:
		card.modulate.a = 1.0
		card.scale = Vector2.ONE
	_apply_card_styles(-1)
	_set_interactive(true)
	visible = true
	if Settings.reduced_flash:
		modulate.a = 1.0
	else:
		BroadcastUI.reveal(self)
	if MenuState.stack.is_empty() and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_overlay_immediate(restore_mouse: bool) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_overlay_active = false
	_closing = false
	_set_interactive(false)
	hide()
	if restore_mouse:
		_restore_mouse_capture()


func _restore_mouse_capture() -> void:
	if _is_server_only():
		return
	if MenuState.stack.is_empty() and not get_tree().paused and not GameManager.finished:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_clock += delta
	if _pad != Settings.using_gamepad:
		_pad = Settings.using_gamepad
		_refresh_hints()

	if _closing:
		# If Pause or Dev menu opens mid-fade, yield immediately without touching mouse mode.
		if not MenuState.stack.is_empty() or get_tree().paused:
			_close_overlay_immediate(false)
		return

	var want := _should_show()
	if want:
		if not _overlay_active:
			_open_overlay()
		elif MenuState.stack.is_empty() and not get_tree().paused and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_update_slot_hint()
	elif _overlay_active:
		# Yield cleanly when Pause/Dev menu is on top; restore capture when closing back to gameplay.
		var menu_on_top := not MenuState.stack.is_empty() or get_tree().paused
		_close_overlay_immediate(not menu_on_top)


func _update_slot_hint() -> void:
	if _subtitle == null:
		return
	var can_claim := _can_claim_now()
	var target_text := SUBTITLE_DEFAULT if can_claim else SUBTITLE_FULL
	if _subtitle.text != target_text:
		_subtitle.text = target_text
		_subtitle.add_theme_color_override("font_color", BroadcastUI.MUTED if can_claim else BroadcastUI.AMBER)


func _can_claim_now() -> bool:
	if loot == null or not loot.starter_available():
		return false
	var player := get_tree().get_first_node_in_group("local_player")
	if player == null or player.state != "ok":
		return false
	var inventory := RunLoot.holder(player)
	if inventory == null or not inventory.can_act():
		return false
	var slot0 := inventory.slots[0]
	return slot0 == null or slot0.id == "service_revolver" or inventory.slots.has(null)


# ------------------------------------------------------------------ input
func _set_pad(is_pad: bool) -> void:
	if _pad != is_pad:
		_pad = is_pad
		_refresh_hints()


func _set_focus(index: int, play_sound: bool) -> void:
	var clamped := clampi(index, 0, _cards.size() - 1)
	var changed := clamped != _focused
	_focused = clamped
	_apply_card_styles(-1)
	_animate_card_focus()
	if play_sound and changed:
		Sound.ui_focus()


func _move_focus(step: int) -> void:
	_set_focus(posmod(_focused + step, _cards.size()), true)


func _on_card_hover(index: int) -> void:
	if not _overlay_active or _closing:
		return
	_set_pad(false)
	_set_focus(index, true)


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if not _overlay_active or _closing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cards[index].accept_event()
		_pick(index)


func _pick(index: int) -> void:
	if not _overlay_active or _closing or index < 0 or index >= RunLoot.STARTER_KITS.size():
		return
	if not _can_claim_now():
		_update_slot_hint()
		return
	_focused = index
	_closing = true
	_overlay_active = false
	_pending_until = _clock + 1.5
	_set_interactive(false)
	loot.choose_starter(index)
	Sound.play("vcr_insert")
	_restore_mouse_capture()
	_apply_card_styles(index)
	for i in _cards.size():
		if _card_tweens[i] is Tween and _card_tweens[i].is_valid():
			_card_tweens[i].kill()
		if i == index:
			if not Settings.reduced_flash:
				_cards[i].pivot_offset = _cards[i].size * 0.5
				var pop := _cards[i].create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				_card_tweens[i] = pop
				pop.tween_property(_cards[i], "scale", Vector2.ONE * 1.04, 0.08)
		else:
			_cards[i].modulate.a = 0.35
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if Settings.reduced_flash:
		_closing = false
		hide()
		return
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_interval(0.06)
	_fade_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	_fade_tween.tween_callback(func():
		_closing = false
		hide())


func _input(event: InputEvent) -> void:
	if not visible or not _overlay_active or _closing or loot == null or not loot.starter_available():
		return
	if not MenuState.stack.is_empty() or get_tree().paused or GameManager.is_voting() or GameManager.awaiting_tape_choice:
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
		_set_pad(false)
		var quick := KEYS.find(event.physical_keycode)
		if quick < 0:
			quick = KEYS.find(event.keycode)
		if quick < 0:
			quick = KP_KEYS.find(event.keycode)
		if quick >= 0:
			_pick(quick)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode in [KEY_A, KEY_LEFT] or event.keycode in [KEY_A, KEY_LEFT]:
			_move_focus(-1)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode in [KEY_D, KEY_RIGHT] or event.keycode in [KEY_D, KEY_RIGHT]:
			_move_focus(1)
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] \
				or event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] \
				or event.is_action_pressed("ui_accept"):
			_pick(_focused)
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventJoypadButton:
		_set_pad(true)
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			_move_focus(-1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == JOY_BUTTON_DPAD_RIGHT:
			_move_focus(1)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == JOY_BUTTON_DPAD_UP:
			_set_focus(1, true)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept") or event.button_index == JOY_BUTTON_A:
			_pick(_focused)
			get_viewport().set_input_as_handled()
			return
