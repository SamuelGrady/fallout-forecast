class_name InventoryMenu
extends CanvasLayer
## Live loadout screen: the survivor on the left, a drag-and-drop hotbar in
## the middle and the run's active mutations on the right.
##
## Like a co-op survival inventory it never pauses the tree. It frees the
## cursor while open, and Player / WeaponHolder ask is_open() to mute look,
## fire, the wheel, slot keys and pouch shortcuts. Slot moves and drops go to the
## host through WeaponHolder.swap_slots / drop_slot; the screen just redraws
## from the holder's mirrored state.
##
## The survivor preview follows SuitPicker: a 3D SurvivorModel in its own
## SubViewport on desktop, the lightweight 2D portrait on Web.

const SurvivorModel := preload("res://player/player_model.gd")
const SCRIM := Color(0.015, 0.03, 0.055, 0.78)
const CARD_SIZE := Vector2(860, 430)
const COLUMN_BG := Color(0.03, 0.06, 0.09, 0.72)
const PREVIEW_SIZE := Vector2i(210, 178)
const SLOT_SIZE := Vector2(58, 72)
const AMMO_NAMES := {"shell": "SHELLS", "rifle": "RIFLE", "nail": "NAILS", "water": "WATER",
	"cell": "CELLS", "shaft": "SHAFTS", "fuel": "FUEL", "radio": "RADIO",
	"rocket": "ROCKETS", "revolver": ".38"}

static var _instance: InventoryMenu
static var _closed_frame := -1

## Set by main.gd; the inventory stays shut while the starter kit card is up.
var starter_picker: Control

var _card: PanelContainer
var _cards: Array = []
var _inspect := -1
var _swap_from := -1
var _swap_serial := -1
var _signature := ""

var _model: SurvivorModel
var _pivot: Node3D
var _viewport: SubViewport
var _preview_2d: Control
var _spin_hold := 0.0
var _look_key := ""

var _callsign: Label
var _suit_name: Label
var _hp_bar: ProgressBar
var _hp_value: Label
var _suit_bar: ProgressBar
var _suit_value: Label
var _scrap_value: Label
var _frag_value: Label
var _dome_value: Label
var _frag_key: Label
var _dome_key: Label

var _insp_card: ItemStatCard
var _equip_button: Button
var _drop_button: Button
var _ammo_flow: HFlowContainer
var _enemy_mutations: VBoxContainer
var _squad_mutations: VBoxContainer
var _close_hint: Label
var _touch_close: Button


## True while the loadout screen is up on this machine.
static func is_open() -> bool:
	return is_instance_valid(_instance) and _instance.visible


## Input polling still sees handled events, including ones that close the menu.
static func blocks_gameplay_actions() -> bool:
	return is_open() or _closed_frame == Engine.get_process_frames()

static func can_open() -> bool:
	return is_instance_valid(_instance) and not _instance.visible and not _instance._should_close() \
		and not (is_instance_valid(_instance.starter_picker) and _instance.starter_picker.is_visible_in_tree())

static func open_from_gamepad() -> void:
	if can_open():
		Settings.using_gamepad = true
		_instance.open()


func _ready() -> void:
	_instance = self
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("inventory_menu")
	_build()
	TouchInput.layout_changed.connect(_layout_touch_buttons)
	_layout_touch_buttons()
	visible = false
	_set_preview_active(false)
	if GameManager.mutations:
		GameManager.mutations.mutations_changed.connect(_on_mutations_changed)
		GameManager.mutations.player_mutations_changed.connect(_on_mutations_changed)
	GameManager.run_finished.connect(func(_won: bool, _results: Dictionary): close())


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


# ------------------------------------------------------------------ open / close
func _input(event: InputEvent) -> void:
	if Net.dedicated:
		return
	if visible:
		if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			if not event.is_echo():
				Settings.using_gamepad = event is InputEventJoypadButton
				if _swap_from >= 0 and event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
					_clear_swap()
					_focus_slot()
				else:
					close()
		elif event is InputEventJoypadButton and event.is_pressed():
			Settings.using_gamepad = true
			if get_viewport().gui_get_focus_owner() == null:
				_focus_slot()
			if event.is_action_pressed("reload"):
				get_viewport().set_input_as_handled()
				_swap_with_gamepad()
			elif event.is_action_pressed("drop_item"):
				get_viewport().set_input_as_handled()
				if _swap_from < 0:
					request_drop(_inspect)
		return
	if event.is_action_pressed("inventory") and not event.is_echo() and can_open():
		get_viewport().set_input_as_handled()
		Settings.using_gamepad = false
		open()


func _should_close() -> bool:
	if get_tree().paused or not MenuState.stack.is_empty() or GameManager.awaiting_tape_choice \
			or GameManager.is_voting() or not GameManager.run_active:
		return true
	var player := _player()
	return player == null or not (player.state in ["ok", "downed"]) or _holder() == null


func open() -> void:
	if visible:
		return
	visible = true
	var holder := _holder()
	_inspect = holder.current if holder else 0
	_signature = ""
	_refresh_look()
	_refresh_vitals()
	_refresh_mutations()
	_refresh_state()
	_refresh_input_hints()
	_set_preview_active(true)
	TouchInput.release_pointer()
	if Settings.using_gamepad:
		_focus_slot()
	BroadcastUI.reveal(_card)
	Sound.play("ui_click")


func close() -> void:
	if not visible:
		return
	if get_viewport() and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	_clear_swap()
	visible = false
	_closed_frame = Engine.get_process_frames()
	_set_preview_active(false)
	Sound.play("ui_tick", -10.0)
	if MenuState.stack.is_empty() and not get_tree().paused and GameManager.run_active \
			and not GameManager.awaiting_tape_choice:
		TouchInput.capture_pointer()


func toggle() -> void:
	if visible:
		close()
	elif can_open():
		open()


func _process(delta: float) -> void:
	if not visible:
		return
	if _should_close():
		close()
		return
	_refresh_vitals()
	_refresh_state()
	_refresh_input_hints()
	if _pivot:
		_spin_hold = maxf(0.0, _spin_hold - delta)
		if _spin_hold <= 0.0 and not Settings.reduced_flash:
			_pivot.rotation.y += delta * 0.6


# ------------------------------------------------------------------ actions (slot cards call these)
func _focus_slot() -> void:
	_cards[_inspect].grab_focus()


func _clear_swap() -> void:
	if _swap_from < 0:
		return
	_swap_from = -1
	_swap_serial = -1
	_refresh_cards()
	_refresh_inspector()


func _swap_with_gamepad() -> void:
	var holder := _holder()
	if holder == null or not holder.can_act():
		return
	_focus_slot()
	if _swap_from >= 0:
		var source := _swap_from
		var item := holder.slots[source]
		var serial := _swap_serial
		_clear_swap()
		if item and item.serial == serial and source != _inspect:
			request_swap(source, _inspect)
	elif holder.slots[_inspect]:
		_swap_from = _inspect
		_swap_serial = holder.slots[_inspect].serial
		_refresh_cards()
		_refresh_inspector()
		Sound.ui_focus()


func request_swap(from_slot: int, to_slot: int) -> void:
	var holder := _holder()
	if holder == null or from_slot == to_slot:
		return
	holder.swap_slots(from_slot, to_slot)
	_inspect = to_slot
	_refresh_cards()
	_refresh_inspector()
	Sound.play("ui_tick", -6.0, 1.15)


func request_drop(slot: int) -> void:
	var holder := _holder()
	if holder == null or slot < 0 or slot >= WeaponHolder.SLOT_COUNT or holder.slots[slot] == null:
		return
	_clear_swap()
	holder.drop_slot(slot)
	_refresh_state()
	Sound.play("ui_tick", -6.0, 0.8)


func request_equip(slot: int) -> void:
	var holder := _holder()
	if holder == null or holder.slots[slot] == null or _swap_from >= 0:
		return
	_inspect = slot
	if holder.current != slot or not holder.active_pouch.is_empty():
		holder.select_slot(slot)
		Sound.play("ui_click")
	_refresh_cards()
	_refresh_inspector()


func inspect(slot: int) -> void:
	if _inspect == slot:
		return
	_inspect = slot
	Sound.ui_focus()
	_refresh_cards()
	_refresh_inspector()


func make_drag_preview(slot: int) -> Control:
	var holder := _holder()
	var item: ItemInstance = holder.slots[slot] if holder else null
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item == null:
		return root
	var definition := ItemCatalog.definition(item.id)
	var chip := PanelContainer.new()
	var style := BroadcastUI.panel(Color(BroadcastUI.INK, 0.92), ItemCatalog.tier_color(item.id, item.tier))
	style.set_content_margin_all(5)
	style.content_margin_left = 8
	style.set_border_width_all(1)
	style.border_width_left = 3
	chip.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	if definition and definition.icon:
		var icon := TextureRect.new()
		icon.texture = definition.icon
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var label := Label.new()
	label.text = (definition.display_name if definition else item.id).to_upper()
	BroadcastUI.text(label, 22, BroadcastUI.PAPER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	chip.modulate = Color(1, 1, 1, 0.9)
	chip.position = Vector2(-30, -22)
	root.add_child(chip)
	return root


# ------------------------------------------------------------------ data
func _player() -> Player:
	var player := get_tree().get_first_node_in_group("local_player") as Player
	return player if is_instance_valid(player) and player.is_inside_tree() else null


func _holder() -> WeaponHolder:
	var player := _player()
	return RunLoot.holder(player) if player else null


func _refresh_state() -> void:
	var holder := _holder()
	if holder == null:
		return
	var parts := PackedStringArray([str(holder.current), holder.active_pouch, str(holder.scrap),
		str(holder.grenades), str(holder.domes), str(holder.can_act())])
	for item in holder.slots:
		parts.append("%d:%s:%d:%d" % [item.serial, item.id, item.tier, item.count] if item else "-")
	var types := holder.reserves.keys()
	types.sort()
	for type in types:
		parts.append("%s=%d" % [type, int(holder.reserves[type])])
	var signature := "|".join(parts)
	if signature == _signature:
		return
	_signature = signature
	if _inspect < 0 or _inspect >= WeaponHolder.SLOT_COUNT:
		_inspect = holder.current
	if _swap_from >= 0:
		var source := holder.slots[_swap_from]
		if source == null or source.serial != _swap_serial or not holder.can_act():
			_clear_swap()
	_refresh_cards()
	_refresh_inspector()
	_refresh_ammo()
	_refresh_belt()


func _refresh_cards() -> void:
	var holder := _holder()
	if holder == null:
		return
	for i in _cards.size():
		var card: _SlotCard = _cards[i]
		var item := holder.slots[i]
		card.item = item
		card.definition = ItemCatalog.definition(item.id) if item else null
		card.tooltip_text = card.definition.display_name if card.definition else "Empty slot"
		card.mouse_default_cursor_shape = Control.CURSOR_DRAG if item else Control.CURSOR_POINTING_HAND
		card.equipped = i == holder.current and holder.active_pouch.is_empty()
		card.inspected = i == _inspect
		card.swap_source = i == _swap_from
		card.queue_redraw()


func _refresh_inspector() -> void:
	var holder := _holder()
	if holder == null or _insp_card == null:
		return
	var index := clampi(_inspect, 0, WeaponHolder.SLOT_COUNT - 1)
	var item := holder.slots[index]
	var focused := get_viewport().gui_get_focus_owner()
	var in_hand := index == holder.current and holder.active_pouch.is_empty()
	var can_change := item != null and holder.can_act() and _swap_from < 0
	_equip_button.disabled = not can_change or in_hand
	_drop_button.disabled = not can_change
	_equip_button.text = "IN HAND" if item and in_hand else "EQUIP"
	for card: Control in _cards:
		var target: Control = card
		if not _equip_button.disabled:
			target = _equip_button
		elif not _drop_button.disabled:
			target = _drop_button
		card.focus_neighbor_bottom = card.get_path_to(target)
	for button in [_equip_button, _drop_button]:
		button.focus_neighbor_top = button.get_path_to(_cards[index])
	if (focused == _equip_button and _equip_button.disabled) or (focused == _drop_button and _drop_button.disabled):
		_focus_slot()
	var definition := ItemCatalog.definition(item.id) if item else null
	if definition == null:
		_insp_card.clear("EMPTY SLOT")
		return
	var opts := {"source": "inventory", "count": item.count}
	if not definition.ammo_type.is_empty():
		opts["reserve"] = int(holder.reserves.get(definition.ammo_type, 0))
		opts["reserve_cap"] = int(ItemCatalog.CAPS.get(definition.ammo_type, 0))
	_insp_card.set_item(item.id, item.tier, opts)


func _refresh_ammo() -> void:
	var holder := _holder()
	if holder == null:
		return
	for child in _ammo_flow.get_children():
		_ammo_flow.remove_child(child)
		child.queue_free()
	var carried := {}
	for item in holder.slots:
		if item:
			var definition := ItemCatalog.definition(item.id)
			if definition and definition.kind == ItemDefinition.Kind.GUN and not definition.ammo_type.is_empty():
				carried[definition.ammo_type] = definition.weapon.mag_size
	var types := carried.keys()
	for type in holder.reserves:
		if int(holder.reserves[type]) > 0 and not types.has(type):
			types.append(type)
	types.sort()
	if types.is_empty():
		var none := Label.new()
		none.text = "NONE"
		BroadcastUI.text(none, 16, Color(BroadcastUI.MUTED, 0.6))
		_ammo_flow.add_child(none)
		return
	for type: String in types:
		var amount := int(holder.reserves.get(type, 0))
		var tint := BroadcastUI.PAPER
		if amount <= 0:
			tint = BroadcastUI.PINK
		elif carried.has(type) and amount <= int(carried[type]):
			tint = BroadcastUI.AMBER
		if not carried.has(type):
			tint = Color(BroadcastUI.MUTED, 0.75)
		var chip := Label.new()
		chip.text = "%s %d" % [AMMO_NAMES.get(type, type.to_upper()), amount]
		BroadcastUI.text(chip, 17, tint)
		BroadcastUI.back_label(chip, tint.darkened(0.25), 1)
		_ammo_flow.add_child(chip)


func _refresh_belt() -> void:
	var holder := _holder()
	if holder == null:
		return
	_scrap_value.text = str(holder.scrap)
	_frag_value.text = "%d/%d" % [holder.grenades, ItemCatalog.pouch_cap("frag")]
	_dome_value.text = "%d/%d" % [holder.domes, ItemCatalog.pouch_cap("shield_dome")]
	_frag_value.add_theme_color_override("font_color", BroadcastUI.PAPER if holder.grenades > 0 else Color(BroadcastUI.MUTED, 0.6))
	_dome_value.add_theme_color_override("font_color", BroadcastUI.PAPER if holder.domes > 0 else Color(BroadcastUI.MUTED, 0.6))


func _refresh_input_hints() -> void:
	_close_hint.visible = not TouchInput.enabled or Settings.using_gamepad
	_close_hint.text = "[%s] CLOSE" % BroadcastUI.input_hint("cancel")
	if Settings.using_gamepad:
		if _swap_from >= 0:
			_close_hint.text = "CHOOSE SLOT   [X] PLACE   [B] CANCEL"
		else:
			_close_hint.text = "[D-PAD] INSPECT   [A] EQUIP   [X] MOVE   [R3] DROP   [B] CLOSE"
	_frag_key.text = BroadcastUI.input_hint("throw_grenade")
	_dome_key.text = BroadcastUI.input_hint("throw_dome")


func _layout_touch_buttons() -> void:
	var height := 44.0 * TouchInput.units_per_css_pixel() if TouchInput.enabled else 0.0
	_touch_close.visible = TouchInput.enabled
	_touch_close.custom_minimum_size.y = height
	_equip_button.custom_minimum_size.y = height
	_drop_button.custom_minimum_size.y = height


func _refresh_vitals() -> void:
	var player := _player()
	if player == null:
		return
	_hp_bar.max_value = maxf(player.max_health, 1.0)
	_hp_bar.value = player.health
	_hp_value.text = "%d/%d" % [ceili(player.health), roundi(player.max_health)]
	_suit_bar.value = player.suit_integrity
	_suit_value.text = "%d%%" % ceili(player.suit_integrity)


func _refresh_look() -> void:
	var player := _player()
	if player == null:
		return
	var callsign := str(player.display_name)
	if callsign.is_empty() or callsign == "You":
		callsign = Settings.player_name if not Settings.player_name.is_empty() else "SURVIVOR"
	_callsign.text = callsign.to_upper()
	_suit_name.text = "%s SUIT" % Cosmetics.skin_name(player.skin)
	var key := "%s:%d" % [player.suit_color.to_html(), player.skin]
	if key == _look_key:
		return
	_look_key = key
	if _model:
		_model.set_look(player.suit_color, player.skin)
		_no_shadows(_model)
	if _preview_2d:
		_preview_2d.call("set_look", player.suit_color, player.skin)


func _on_mutations_changed(_active: Array = []) -> void:
	_refresh_mutations()


## This wave's enemy mutation and the squad's run-long bio-mutations.
func _refresh_mutations() -> void:
	for list in [_enemy_mutations, _squad_mutations]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var roll := GameManager.mutations
	if roll:
		for id in roll.active:
			var entry: MutationData = roll.table.get_entry(id)
			if entry:
				_add_mutation(_enemy_mutations, id, entry.display_name, entry.description, entry.color)
		for id in roll.player_mutations:
			if GameManager.PLAYER_MUTATIONS.has(id):
				var info: Dictionary = GameManager.PLAYER_MUTATIONS[id]
				_add_mutation(_squad_mutations, id, info.name, info.desc, info.color)
	for list in [_enemy_mutations, _squad_mutations]:
		if list.get_child_count() == 0:
			_label(list, 17, BroadcastUI.MUTED).text = "—"


func _add_mutation(parent: Control, id: String, title: String, description: String, tint: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var glyph := GameIcon.new()
	glyph.kind = id
	glyph.color = tint
	glyph.custom_minimum_size = Vector2(25, 25)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(glyph)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var title_label := _label(copy, 19, tint)
	title_label.text = title.to_upper()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var effect := _label(copy, 16, BroadcastUI.MUTED)
	effect.text = description
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# ------------------------------------------------------------------ layout
func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = BroadcastUI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks on the world so they never reach the player.
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = CARD_SIZE
	var card_style := BroadcastUI.panel(BroadcastUI.OVERLAY, BroadcastUI.CYAN)
	card_style.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", card_style)
	center.add_child(_card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	_card.add_child(stack)
	stack.add_child(_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	body.add_child(_left_column())
	body.add_child(_center_column())
	body.add_child(_right_column())


func _header() -> Control:
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0e1d29")
	style.border_color = Color(BroadcastUI.CYAN, 0.55)
	style.border_width_bottom = 1
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var title := _label(row, 30, BroadcastUI.CYAN)
	title.text = "LOADOUT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close_hint = _label(row, 18, BroadcastUI.MUTED)
	_touch_close = _small_button(row, "CLOSE", BroadcastUI.CYAN, close)
	_touch_close.custom_minimum_size.x = 130
	_touch_close.focus_mode = Control.FOCUS_NONE
	return bar


func _column(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	var style := StyleBoxFlat.new()
	style.bg_color = COLUMN_BG
	style.border_color = Color(BroadcastUI.MUTED, 0.18)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _left_column() -> Control:
	var box := _column(232)
	if OS.has_feature("web") or SuitPicker.force_2d_preview:
		_build_preview_2d(box)
	else:
		_build_preview_3d(box)
	_callsign = _label(box, 26, BroadcastUI.PAPER)
	_callsign.clip_text = true
	_suit_name = _label(box, 16, BroadcastUI.MUTED)
	var vitals := _vital(box, "health", BroadcastUI.PINK)
	_hp_bar = vitals[0]
	_hp_value = vitals[1]
	vitals = _vital(box, "suit", BroadcastUI.CYAN)
	_suit_bar = vitals[0]
	_suit_value = vitals[1]
	_suit_bar.max_value = 100.0
	var scrap := HBoxContainer.new()
	scrap.add_theme_constant_override("separation", 6)
	box.add_child(scrap)
	var gear := GameIcon.new()
	gear.kind = "scrap"
	gear.color = BroadcastUI.AMBER
	gear.custom_minimum_size = Vector2(22, 22)
	scrap.add_child(gear)
	_scrap_value = _label(scrap, 22, BroadcastUI.AMBER)
	var frag := _pouch_row(box, "frag")
	_frag_key = frag[0]
	_frag_value = frag[1]
	var dome := _pouch_row(box, "shield_dome")
	_dome_key = dome[0]
	_dome_value = dome[1]
	return box.get_parent()


func _center_column() -> Control:
	var box := _column(344)
	box.add_theme_constant_override("separation", 4)
	box.add_child(_section("HOTBAR"))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 5)
	box.add_child(slots)
	for i in WeaponHolder.SLOT_COUNT:
		var card := _SlotCard.new()
		card.menu = self
		card.index = i
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(card)
		_cards.append(card)
	var zone := _DropZone.new()
	zone.menu = self
	zone.hide()
	box.add_child(zone)
	box.add_child(_inspector())
	for i in _cards.size():
		var card: Control = _cards[i]
		card.focus_neighbor_left = card.get_path_to(_cards[posmod(i - 1, _cards.size())])
		card.focus_neighbor_right = card.get_path_to(_cards[(i + 1) % _cards.size()])
	return box.get_parent()


func _inspector() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_insp_card = ItemStatCard.new(ItemStatCard.Layout.ROW)
	_insp_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_insp_card)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	_equip_button = _small_button(actions, "EQUIP", BroadcastUI.CYAN, func(): request_equip(_inspect))
	_equip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_button = _small_button(actions, "DROP", BroadcastUI.PINK, func(): request_drop(_inspect))
	_drop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


func _right_column() -> Control:
	var box := _column(232)
	box.add_child(_section("RESERVE AMMO"))
	_ammo_flow = HFlowContainer.new()
	_ammo_flow.add_theme_constant_override("h_separation", 6)
	_ammo_flow.add_theme_constant_override("v_separation", 4)
	box.add_child(_ammo_flow)
	box.add_child(_section("MUTATIONS"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var mutations := VBoxContainer.new()
	mutations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mutations.add_theme_constant_override("separation", 4)
	scroll.add_child(mutations)
	_label(mutations, 17, BroadcastUI.PINK).text = "INFECTED"
	_enemy_mutations = VBoxContainer.new()
	mutations.add_child(_enemy_mutations)
	_label(mutations, 17, BroadcastUI.ACID).text = "SQUAD"
	_squad_mutations = VBoxContainer.new()
	mutations.add_child(_squad_mutations)
	return box.get_parent()


func _section(text: String) -> Label:
	var label := Label.new()
	label.text = text
	BroadcastUI.text(label, 16, Color(BroadcastUI.MUTED, 0.85))
	return label


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	BroadcastUI.text(label, font_size, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _vital(parent: Control, kind: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var icon := GameIcon.new()
	icon.kind = kind
	icon.color = color
	icon.custom_minimum_size = Vector2(22, 22)
	row.add_child(icon)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 8
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BroadcastUI.bar(bar, color)
	row.add_child(bar)
	var count := _label(row, 18, BroadcastUI.PAPER)
	count.custom_minimum_size.x = 57
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return [bar, count]


func _pouch_row(parent: Control, id: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var icon := TextureRect.new()
	var definition := ItemCatalog.definition(id)
	icon.texture = definition.icon if definition else null
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var key := _label(row, 17, BroadcastUI.MUTED)
	key.tooltip_text = definition.display_name if definition else id
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, 22, BroadcastUI.PAPER)
	return [key, value]


func _small_button(parent: Control, text: String, accent: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	BroadcastUI.button_accent(button, accent, true)
	button.add_theme_font_size_override("font_size", 17)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as StyleBoxFlat
		if box:
			box.content_margin_top = 1
			box.content_margin_bottom = 1
			box.content_margin_left = 8
			box.content_margin_right = 8
	button.pressed.connect(action)
	button.pressed.connect(func(): Sound.play("ui_click"))
	parent.add_child(button)
	return button


# ------------------------------------------------------------------ survivor preview
func _preview_frame(parent: Control) -> PanelContainer:
	var frame := PanelContainer.new()
	var style := BroadcastUI.panel(Color("#09111d"), Color(BroadcastUI.CYAN, 0.75))
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_content_margin_all(1)
	style.content_margin_left = 3
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(frame)
	return frame


func _build_preview_2d(parent: Control) -> void:
	var frame := _preview_frame(parent)
	var portrait := SuitPicker._SuitPreview2D.new()
	portrait.custom_minimum_size = PREVIEW_SIZE
	frame.add_child(portrait)
	_preview_2d = portrait


func _build_preview_3d(parent: Control) -> void:
	var frame := _preview_frame(parent)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = PREVIEW_SIZE
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	container.mouse_default_cursor_shape = Control.CURSOR_DRAG
	container.tooltip_text = "Drag to turn the survivor"
	container.gui_input.connect(_on_preview_input)
	frame.add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6a7f99")
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	_viewport.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.2, 2.2, 1.5)
	rim.light_color = Color("#ff5689")
	rim.light_energy = 1.5
	rim.omni_range = 5.0
	_viewport.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 34
	# The model faces -Z, so the camera sits in front of it on -Z.
	camera.transform = Transform3D(Basis(), Vector3(0, 1.05, -4.4)).looking_at(Vector3(0, 0.98, 0))
	_viewport.add_child(camera)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_pivot.rotation.y = 0.5
	_model = SurvivorModel.new()
	_pivot.add_child(_model)
	_no_shadows(_model)


func _on_preview_input(event: InputEvent) -> void:
	if _pivot == null:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pivot.rotation.y += event.relative.x * 0.014
		_spin_hold = 2.0
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_spin_hold = 2.0


func _set_preview_active(active: bool) -> void:
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if _model:
		_model.set_process(active)
	if _preview_2d:
		_preview_2d.set_process(active)


func _no_shadows(root: Node) -> void:
	for mesh in root.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ widgets
## One hotbar slot: drag it onto another slot to move/swap, onto the drop zone
## (or right-click it) to drop, click to inspect, double-click to equip.
class _SlotCard extends Control:
	var menu: InventoryMenu
	var index := 0
	var item: ItemInstance
	var definition: ItemDefinition
	var equipped := false
	var inspected := false
	var swap_source := false
	var _hover := false
	var _drop_hover := false
	var _dragging := false

	func _init() -> void:
		custom_minimum_size = InventoryMenu.SLOT_SIZE
		focus_mode = Control.FOCUS_ALL
		focus_entered.connect(func(): menu.inspect(index))
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _get_drag_data(_at: Vector2) -> Variant:
		if item == null:
			return null
		menu._clear_swap()
		set_drag_preview(menu.make_drag_preview(index))
		Sound.play("ui_tick", -10.0, 1.3)
		return {"inventory_slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and data.has("inventory_slot") and int(data.inventory_slot) != index
		if ok != _drop_hover:
			_drop_hover = ok
			queue_redraw()
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_drop_hover = false
		queue_redraw()
		menu.request_swap(int(data.inventory_slot), index)

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_accept"):
			menu.request_equip(index)
			accept_event()
			return
		var button := event as InputEventMouseButton
		if button == null or not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.double_click:
				menu.request_equip(index)
			else:
				menu.inspect(index)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			menu.request_drop(index)
			accept_event()

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_ENTER:
				_hover = true
				queue_redraw()
			NOTIFICATION_MOUSE_EXIT:
				_hover = false
				_drop_hover = false
				queue_redraw()
			NOTIFICATION_DRAG_BEGIN:
				_dragging = true
				queue_redraw()
			NOTIFICATION_DRAG_END:
				_dragging = false
				_drop_hover = false
				queue_redraw()

	func _draw() -> void:
		var font := BroadcastUI.FONT
		var bg := Color("#10202b") if item else Color(BroadcastUI.INK, 0.55)
		if equipped:
			bg = Color("#173943")
		if _hover or _drop_hover:
			bg = bg.lightened(0.07)
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		draw_string(font, Vector2(6, 16), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				BroadcastUI.CYAN if equipped else BroadcastUI.MUTED)
		if equipped:
			var x := size.x - 13.0
			draw_polyline(PackedVector2Array([Vector2(x - 2, 11), Vector2(x + 2, 15), Vector2(x + 8, 7)]), BroadcastUI.CYAN, 2.0, true)
		if item and definition:
			var tier_color := ItemCatalog.tier_color(item.id, item.tier)
			if definition.legendary:
				tier_color = BroadcastUI.AMBER
			if definition.icon:
				var icon_size := Vector2(38, 38)
				draw_texture_rect(definition.icon, Rect2(Vector2((size.x - icon_size.x) * 0.5, 13), icon_size), false)
			var count := "x%d" % item.count
			var tint := BroadcastUI.PAPER
			if definition.kind == ItemDefinition.Kind.GUN and definition.weapon:
				count = "%d/%d" % [item.count, definition.weapon.mag_size]
				if item.count <= 0:
					tint = BroadcastUI.PINK
			draw_string(font, Vector2(0, size.y - 7), count, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, tint)
			draw_rect(Rect2(0, size.y - 2, size.x, 2), tier_color)
		else:
			draw_line(size * 0.5 - Vector2(4, 0), size * 0.5 + Vector2(4, 0), Color(BroadcastUI.MUTED, 0.5), 2)
		var border := Color(BroadcastUI.MUTED, 0.3)
		var width := 1.0
		if swap_source:
			border = BroadcastUI.AMBER
			width = 2.0
		elif _drop_hover:
			border = BroadcastUI.CYAN
			width = 2.0
		elif inspected:
			border = BroadcastUI.PAPER
			width = 2.0
		elif equipped or _dragging:
			border = Color(BroadcastUI.CYAN, 0.65)
		elif _hover:
			border = Color(BroadcastUI.PAPER, 0.45)
		draw_rect(Rect2(Vector2.ONE * width * 0.5, size - Vector2.ONE * width), border, false, width)


## Drag a slot here to drop it on the ground in front of you.
class _DropZone extends Control:
	var menu: InventoryMenu
	var _armed := false
	var _dragging := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and data.has("inventory_slot")
		if ok != _armed:
			_armed = ok
			queue_redraw()
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_armed = false
		queue_redraw()
		menu.request_drop(int(data.inventory_slot))

	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_MOUSE_EXIT:
				_armed = false
				queue_redraw()
			NOTIFICATION_DRAG_BEGIN:
				_dragging = true
				mouse_filter = Control.MOUSE_FILTER_STOP
				show()
				queue_redraw()
			NOTIFICATION_DRAG_END:
				_dragging = false
				mouse_filter = Control.MOUSE_FILTER_IGNORE
				_armed = false
				hide()

	func _draw() -> void:
		if not _dragging:
			return
		var rect := Rect2(Vector2.ONE, size - Vector2.ONE * 2.0)
		var tint := BroadcastUI.PINK
		draw_rect(rect, Color(BroadcastUI.PINK, 0.22 if _armed else 0.07))
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], tint, 1.5 if _armed else 1.0, 6.0)
		var label := "RELEASE TO DROP" if _armed else "DROP ON GROUND"
		draw_string(BroadcastUI.FONT, Vector2(0, size.y * 0.5 + 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20,
				tint)
