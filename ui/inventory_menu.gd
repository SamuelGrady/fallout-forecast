class_name InventoryMenu
extends CanvasLayer
## Tab / I loadout screen: the survivor on the left, a drag-and-drop hotbar in
## the middle and the run's active mutations on the right.
##
## Like a co-op survival inventory it never pauses the tree. It frees the
## cursor while open, and Player / WeaponHolder ask is_open() to mute look,
## fire, the wheel, slot keys and quick-throws. Slot moves and drops go to the
## host through WeaponHolder.swap_slots / drop_slot; the screen just redraws
## from the holder's mirrored state.
##
## The survivor preview follows SuitPicker: a 3D SurvivorModel in its own
## SubViewport on desktop, the lightweight 2D portrait on Web.

const SurvivorModel := preload("res://player/player_model.gd")
const SCRIM := Color(0.015, 0.03, 0.055, 0.78)
const CARD_SIZE := Vector2(860, 556)
const COLUMN_BG := Color(0.03, 0.06, 0.09, 0.72)
const PREVIEW_SIZE := Vector2i(210, 178)
const SLOT_HEIGHT := 44.0
const AMMO_NAMES := {"shell": "SHELLS", "rifle": "RIFLE", "nail": "NAILS", "water": "WATER",
	"cell": "CELLS", "flare": "FLARES", "shaft": "SHAFTS", "fuel": "FUEL", "radio": "RADIO",
	"rocket": "ROCKETS", "revolver": ".38"}
const KIND_NAMES := ["WEAPON", "THROWABLE", "CONSUMABLE", "DEPLOYABLE"]
const ITEM_NOTES := {
	"umbrella": "Plants a rain canopy: everyone under it counts as sheltered.",
	"bleach_bomb": "Thrown burst that scours the infected caught in it.",
	"bait_radio": "Tossed lure. The infected chase the noise until it dies.",
	"sandbag": "Places a waist-high wall of cover in front of you.",
	"lightning_rod": "Spike that draws lightning strikes to itself.",
	"med_tin": "Restores health. Only usable while hurt.",
	"suit_patch": "Repairs suit integrity. Only usable while the suit is torn.",
	"frag": "Belt pouch grenade. Quick-throw it any time.",
	"shield_dome": "Belt pouch dome that shelters the squad from rain.",
}

static var _instance: InventoryMenu
static var _closed_frame := -1

## Set by main.gd; the inventory stays shut while the starter kit card is up.
var starter_picker: Control

var _card: PanelContainer
var _cards: Array = []
var _inspect := -1
var _hovered := -1
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

var _insp_name: Label
var _insp_sub: Label
var _insp_stats: RichTextLabel
var _equip_button: Button
var _drop_button: Button
var _ammo_flow: HFlowContainer
var _mutation_text: RichTextLabel


## True while the loadout screen is up on this machine.
static func is_open() -> bool:
	return is_instance_valid(_instance) and _instance.visible


## The pause menu skips an ESC that this screen used (open, or closed by it
## during this same frame), so one key press never closes and pauses at once.
static func blocks_pause() -> bool:
	return is_open() or _closed_frame == Engine.get_process_frames()


func _ready() -> void:
	_instance = self
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("inventory_menu")
	_build()
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
				close()
		return
	if event.is_action_pressed("inventory") and not event.is_echo() and _can_open():
		get_viewport().set_input_as_handled()
		open()


func _can_open() -> bool:
	if get_tree().paused or not MenuState.stack.is_empty() or GameManager.awaiting_tape_choice \
			or GameManager.is_voting() or not GameManager.run_active:
		return false
	if is_instance_valid(starter_picker) and starter_picker.is_visible_in_tree():
		return false
	var player := _player()
	return player != null and player.state in ["ok", "downed"] and _holder() != null


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
	_hovered = -1
	var holder := _holder()
	_inspect = holder.current if holder else 0
	_signature = ""
	_refresh_look()
	_refresh_mutations()
	_refresh_state()
	_set_preview_active(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	BroadcastUI.reveal(_card)
	Sound.play("ui_click")


func close() -> void:
	if not visible:
		return
	if get_viewport() and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	visible = false
	_closed_frame = Engine.get_process_frames()
	_hovered = -1
	_set_preview_active(false)
	Sound.play("ui_tick", -10.0)
	if MenuState.stack.is_empty() and not get_tree().paused and GameManager.run_active \
			and not GameManager.awaiting_tape_choice:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if visible:
		close()
	elif _can_open():
		open()


func _process(delta: float) -> void:
	if not visible:
		return
	if _should_close():
		close()
		return
	_refresh_vitals()
	_refresh_state()
	if _pivot:
		_spin_hold = maxf(0.0, _spin_hold - delta)
		if _spin_hold <= 0.0 and not Settings.reduced_flash:
			_pivot.rotation.y += delta * 0.6


# ------------------------------------------------------------------ actions (slot cards call these)
func request_swap(from_slot: int, to_slot: int) -> void:
	var holder := _holder()
	if holder == null or from_slot == to_slot:
		return
	holder.swap_slots(from_slot, to_slot)
	_inspect = to_slot
	Sound.play("ui_tick", -6.0, 1.15)


func request_drop(slot: int) -> void:
	var holder := _holder()
	if holder == null or slot < 0 or slot >= WeaponHolder.SLOT_COUNT or holder.slots[slot] == null:
		return
	holder.drop_slot(slot)
	Sound.play("ui_tick", -6.0, 0.8)


func request_equip(slot: int) -> void:
	var holder := _holder()
	if holder == null or holder.slots[slot] == null:
		return
	_inspect = slot
	if holder.current != slot:
		holder.select_slot(slot)
		Sound.play("ui_click")
	_refresh_inspector()


func inspect(slot: int) -> void:
	_inspect = slot
	Sound.ui_focus()
	_refresh_cards()
	_refresh_inspector()


func on_slot_hover(slot: int, inside: bool) -> void:
	if inside:
		_hovered = slot
	elif _hovered == slot:
		_hovered = -1
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
	var parts := PackedStringArray([str(holder.current), str(holder.scrap), str(holder.grenades), str(holder.domes)])
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
		card.reserve = -1
		if card.definition and card.definition.kind == ItemDefinition.Kind.GUN:
			card.reserve = int(holder.reserves.get(card.definition.ammo_type, 0))
		card.equipped = i == holder.current
		card.inspected = i == _inspect
		card.queue_redraw()


func _refresh_inspector() -> void:
	var holder := _holder()
	if holder == null or _insp_name == null:
		return
	var index := _hovered if _hovered >= 0 else _inspect
	index = clampi(index, 0, WeaponHolder.SLOT_COUNT - 1)
	var item := holder.slots[index]
	var muted := BroadcastUI.MUTED.to_html(false)
	_equip_button.disabled = item == null or index == holder.current or not holder.can_act()
	_drop_button.disabled = item == null or not holder.can_act()
	_equip_button.text = "IN HAND" if item and index == holder.current else "EQUIP"
	if item == null:
		_insp_name.text = "SLOT %d  /  EMPTY" % (index + 1)
		_insp_name.add_theme_color_override("font_color", BroadcastUI.MUTED)
		_insp_sub.text = "DRAG AN ITEM HERE TO MOVE IT"
		_insp_stats.text = "[color=#%s]Loot, crates and vending fill empty slots first.[/color]" % muted
		return
	var definition := ItemCatalog.definition(item.id)
	var tier_name := ItemCatalog.tier_name(item.id, item.tier)
	_insp_name.text = definition.display_name.to_upper()
	_insp_name.add_theme_color_override("font_color", ItemCatalog.tier_color(item.id, item.tier) if item.tier > 0 or definition.is_cursed() or definition.legendary else BroadcastUI.PAPER)
	var data := definition.weapon
	var cells: Array = []
	var notes := PackedStringArray()
	if definition.kind == ItemDefinition.Kind.GUN and data:
		var reserve := int(holder.reserves.get(definition.ammo_type, 0))
		var cap := int(ItemCatalog.CAPS.get(definition.ammo_type, 0))
		var damage := data.damage * float(ItemCatalog.DAMAGE_SCALE[clampi(item.tier, 0, 2)])
		_insp_sub.text = "SLOT %d  /  %s  /  %s AMMO%s" % [index + 1, tier_name, AMMO_NAMES.get(definition.ammo_type, definition.ammo_type.to_upper()), "  /  FULL AUTO" if data.automatic else ""]
		cells.append(["DMG", ("%d x%d" % [roundi(damage), data.pellets]) if data.pellets > 1 else str(roundi(damage))])
		if data.charge_time > 0.0:
			cells.append(["CHARGE", "%.1fs" % data.charge_time])
		else:
			cells.append(["RPM", str(roundi(60.0 / maxf(data.fire_interval * GameManager.fire_rate_scale(), 0.01)))])
		cells.append(["RANGE", "%dm" % roundi(data.max_range)])
		cells.append(["MAG", "%d/%d" % [item.count, data.mag_size]])
		cells.append(["RES", "%d/%d" % [reserve, cap]])
		cells.append(["RELOAD", "%.1fs" % (data.reload_time * GameManager.reload_scale())])
		if data.shell_reload:
			notes.append("Loads shell by shell.")
		if data.pierce > 0:
			notes.append("Pierces %d %s." % [data.pierce, "target" if data.pierce == 1 else "targets"])
		if data.held_suit_drain > 0.0:
			notes.append("Drains your suit while held.")
		if data.jam_chance > 0.0:
			notes.append("%d%% jam chance." % roundi(data.jam_chance * 100.0))
		if data.lucky_kill_chance > 0.0:
			notes.append("%d%% lucky instant kill." % roundi(data.lucky_kill_chance * 100.0))
		if definition.legendary:
			notes.append("Legendary: hold fire to charge.")
	else:
		_insp_sub.text = "SLOT %d  /  %s  /  %s" % [index + 1, tier_name, KIND_NAMES[definition.kind]]
		cells.append(["STACK", "%d/%d" % [item.count, definition.stack_cap]])
		if data and data.damage > 0.0 and definition.kind == ItemDefinition.Kind.THROWABLE:
			cells.append(["DMG", str(roundi(data.damage))])
		if data and data.effect_radius > 0.0:
			cells.append(["RADIUS", "%.1fm" % data.effect_radius])
		if data and data.effect_time > 0.0 and definition.kind != ItemDefinition.Kind.CONSUMABLE:
			cells.append(["LASTS", "%ds" % roundi(data.effect_time)])
		notes.append(str(ITEM_NOTES.get(item.id, "")))
	var text := "[table=3]"
	for cell: Array in cells:
		text += "[cell][color=#%s]%s[/color] %s   [/cell]" % [muted, cell[0], cell[1]]
	for _pad in (3 - cells.size() % 3) % 3:
		text += "[cell] [/cell]"
	text += "[/table]"
	var note := " ".join(notes).strip_edges()
	if not note.is_empty():
		var tint := Color("#ff8fc8") if definition.is_cursed() else BroadcastUI.MUTED
		text += "\n[color=#%s]%s[/color]" % [tint.to_html(false), note]
	_insp_stats.text = text


func _refresh_ammo() -> void:
	var holder := _holder()
	if holder == null:
		return
	for child in _ammo_flow.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = "AMMO"
	BroadcastUI.text(head, 16, BroadcastUI.MUTED)
	head.custom_minimum_size.y = 22
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ammo_flow.add_child(head)
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
	_frag_key.text = "FRAG [%s]" % BroadcastUI.input_hint("throw_grenade")
	_dome_key.text = "DOME [%s]" % BroadcastUI.input_hint("throw_dome")
	_frag_value.text = "%d/%d" % [holder.grenades, ItemCatalog.pouch_cap("frag")]
	_dome_value.text = "%d/%d" % [holder.domes, ItemCatalog.pouch_cap("shield_dome")]
	_frag_value.add_theme_color_override("font_color", BroadcastUI.PAPER if holder.grenades > 0 else Color(BroadcastUI.MUTED, 0.6))
	_dome_value.add_theme_color_override("font_color", BroadcastUI.PAPER if holder.domes > 0 else Color(BroadcastUI.MUTED, 0.6))


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
	if _mutation_text == null:
		return
	var roll := GameManager.mutations
	var muted := BroadcastUI.MUTED.to_html(false)
	var lines := PackedStringArray()
	lines.append("[b][color=#%s]INFECTED[/color][/b]" % BroadcastUI.PINK.to_html(false))
	if roll == null or roll.active.is_empty():
		lines.append("[color=#%s]No enemy mutation yet.[/color]" % muted)
	else:
		for id in roll.active:
			var entry: MutationData = roll.table.get_entry(id)
			if entry:
				lines.append("[b]%s[/b]\n[color=#%s]%s[/color]" % [entry.display_name.to_upper(), muted, entry.description])
	lines.append("")
	lines.append("[b][color=#%s]SQUAD[/color][/b]" % BroadcastUI.ACID.to_html(false))
	if roll == null or roll.player_mutations.is_empty():
		lines.append("[color=#%s]Draft bio-mutations between waves.[/color]" % muted)
	else:
		for id in roll.player_mutations:
			if GameManager.PLAYER_MUTATIONS.has(id):
				var info: Dictionary = GameManager.PLAYER_MUTATIONS[id]
				lines.append("[b]%s[/b]\n[color=#%s]%s[/color]" % [str(info.name).to_upper(), muted, str(info.desc)])
	_mutation_text.text = "\n".join(lines)
	_mutation_text.scroll_to_line(0)


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
	var dot := Label.new()
	dot.text = "REC"
	BroadcastUI.text(dot, 18, BroadcastUI.PINK)
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dot)
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	row.add_child(gap)
	var title := Label.new()
	title.text = "LOADOUT & MUTATIONS"
	BroadcastUI.text(title, 30, BroadcastUI.CYAN)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var hint := Label.new()
	hint.text = "[TAB / ESC] CLOSE"
	BroadcastUI.text(hint, 18, BroadcastUI.MUTED)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size_flags_vertical = Control.SIZE_FILL
	row.add_child(hint)
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
	box.add_child(_section("SURVIVOR"))
	if OS.has_feature("web") or SuitPicker.force_2d_preview:
		_build_preview_2d(box)
	else:
		_build_preview_3d(box)
	_callsign = _label(box, 26, BroadcastUI.PAPER)
	_callsign.clip_text = true
	_suit_name = _label(box, 16, BroadcastUI.MUTED)
	var vitals := _vital(box, "HP", BroadcastUI.PINK)
	_hp_bar = vitals[0]
	_hp_value = vitals[1]
	vitals = _vital(box, "SUIT", BroadcastUI.CYAN)
	_suit_bar = vitals[0]
	_suit_value = vitals[1]
	_suit_bar.max_value = 100.0
	var scrap := HBoxContainer.new()
	scrap.add_theme_constant_override("separation", 6)
	box.add_child(scrap)
	var nut := _ScrapIcon.new()
	nut.custom_minimum_size = Vector2(20, 22)
	scrap.add_child(nut)
	var scrap_label := _label(scrap, 20, BroadcastUI.AMBER)
	scrap_label.text = "SCRAP"
	scrap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrap_value = _label(scrap, 22, BroadcastUI.AMBER)
	box.add_child(_section("BELT POUCHES"))
	var frag := _pouch_row(box, "frag")
	_frag_key = frag[0]
	_frag_value = frag[1]
	var dome := _pouch_row(box, "shield_dome")
	_dome_key = dome[0]
	_dome_value = dome[1]
	return box.get_parent()


func _center_column() -> Control:
	var box := _column(344)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _section("HOTBAR")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var help := _label(head, 15, Color(BroadcastUI.MUTED, 0.75))
	help.text = "DRAG TO MOVE  /  RMB DROP"
	var slots := VBoxContainer.new()
	slots.add_theme_constant_override("separation", 4)
	box.add_child(slots)
	for i in WeaponHolder.SLOT_COUNT:
		var card := _SlotCard.new()
		card.menu = self
		card.index = i
		slots.add_child(card)
		_cards.append(card)
	var zone := _DropZone.new()
	zone.menu = self
	box.add_child(zone)
	box.add_child(_inspector())
	_ammo_flow = HFlowContainer.new()
	_ammo_flow.add_theme_constant_override("h_separation", 6)
	_ammo_flow.add_theme_constant_override("v_separation", 4)
	box.add_child(_ammo_flow)
	return box.get_parent()


func _inspector() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BroadcastUI.INK, 0.75)
	style.border_color = Color(BroadcastUI.CYAN, 0.35)
	style.border_width_left = 2
	style.border_width_top = 1
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	_insp_name = _label(top, 24, BroadcastUI.PAPER)
	_insp_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insp_name.clip_text = true
	_equip_button = _small_button(top, "EQUIP", BroadcastUI.CYAN, func():
		request_equip(_hovered if _hovered >= 0 else _inspect))
	_drop_button = _small_button(top, "DROP", BroadcastUI.PINK, func():
		request_drop(_hovered if _hovered >= 0 else _inspect))
	_insp_sub = _label(box, 16, BroadcastUI.MUTED)
	_insp_sub.clip_text = true
	_insp_stats = RichTextLabel.new()
	_insp_stats.bbcode_enabled = true
	_insp_stats.scroll_active = false
	_insp_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_insp_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_insp_stats.add_theme_font_override("normal_font", BroadcastUI.FONT)
	_insp_stats.add_theme_font_size_override("normal_font_size", 18)
	_insp_stats.add_theme_constant_override("line_separation", -2)
	box.add_child(_insp_stats)
	return panel


func _right_column() -> Control:
	var box := _column(232)
	var title := _label(box, 26, BroadcastUI.CYAN)
	title.text = "MUTATIONS"
	_mutation_text = RichTextLabel.new()
	_mutation_text.bbcode_enabled = true
	_mutation_text.scroll_active = true
	_mutation_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mutation_text.add_theme_font_override("normal_font", BroadcastUI.FONT)
	_mutation_text.add_theme_font_override("bold_font", BroadcastUI.FONT)
	_mutation_text.add_theme_font_size_override("normal_font_size", 19)
	_mutation_text.add_theme_font_size_override("bold_font_size", 21)
	box.add_child(_mutation_text)
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


func _vital(parent: Control, title: String, color: Color) -> Array:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 1)
	parent.add_child(block)
	var row := HBoxContainer.new()
	block.add_child(row)
	var name_label := _label(row, 18, color)
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, 18, BroadcastUI.PAPER)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BroadcastUI.bar(bar, color)
	block.add_child(bar)
	return [bar, value]


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
	var key := _label(row, 20, BroadcastUI.PAPER)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, 22, BroadcastUI.PAPER)
	return [key, value]


func _small_button(parent: Control, text: String, accent: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
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
	var reserve := -1
	var equipped := false
	var inspected := false
	var _hover := false
	var _drop_hover := false
	var _dragging := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, InventoryMenu.SLOT_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _get_drag_data(_at: Vector2) -> Variant:
		if item == null:
			return null
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
				menu.on_slot_hover(index, true)
			NOTIFICATION_MOUSE_EXIT:
				_hover = false
				_drop_hover = false
				queue_redraw()
				menu.on_slot_hover(index, false)
			NOTIFICATION_DRAG_BEGIN:
				_dragging = true
				queue_redraw()
			NOTIFICATION_DRAG_END:
				_dragging = false
				_drop_hover = false
				queue_redraw()

	func _draw() -> void:
		var font := BroadcastUI.FONT
		var w := size.x
		var h := size.y
		var bg := Color("#10202b") if item else Color(BroadcastUI.INK, 0.55)
		if equipped:
			bg = Color("#173943")
		if _hover or _drop_hover:
			bg = bg.lightened(0.07)
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		# Number tab.
		var tab_w := 30.0
		draw_rect(Rect2(0, 0, tab_w, h), Color(BroadcastUI.CYAN, 0.24) if equipped else Color(BroadcastUI.INK, 0.85))
		draw_string(font, Vector2(0, h * 0.5 + 9.0), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, tab_w, 28,
				BroadcastUI.CYAN if equipped else BroadcastUI.MUTED)
		if item and definition:
			var tier_color := ItemCatalog.tier_color(item.id, item.tier)
			if definition.legendary:
				tier_color = BroadcastUI.AMBER
			var icon_rect := Rect2(tab_w + 6.0, 4.0, h - 8.0, h - 8.0)
			draw_rect(icon_rect, Color(0, 0, 0, 0.35))
			if definition.icon:
				draw_texture_rect(definition.icon, icon_rect, false)
			var text_x := icon_rect.end.x + 8.0
			var count_w := 74.0
			draw_string(font, Vector2(text_x, 20.0), definition.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
					w - text_x - count_w, 21, BroadcastUI.PAPER)
			var tier_text := ItemCatalog.tier_name(item.id, item.tier)
			draw_string(font, Vector2(text_x, 37.0), tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tier_color)
			var tier_w := font.get_string_size(tier_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_rect(Rect2(text_x, 39.0, tier_w, 1.5), Color(tier_color, 0.8))
			# Tier strip along the bottom edge.
			draw_rect(Rect2(tab_w, h - 2.0, w - tab_w, 2.0), Color(tier_color, 0.55 if item.tier > 0 or definition.is_cursed() or definition.legendary else 0.18))
			var count_text := ""
			var count_sub := ""
			if definition.kind == ItemDefinition.Kind.GUN and definition.weapon:
				count_text = "%d/%d" % [item.count, definition.weapon.mag_size]
				count_sub = "+%d %s" % [maxi(reserve, 0), "RES"]
			else:
				count_text = "x%d" % item.count
				count_sub = "OF %d" % definition.stack_cap
			var count_color := BroadcastUI.PAPER
			if definition.kind == ItemDefinition.Kind.GUN and item.count <= 0:
				count_color = BroadcastUI.PINK
			draw_string(font, Vector2(w - count_w - 6.0, 21.0), count_text, HORIZONTAL_ALIGNMENT_RIGHT, count_w, 22, count_color)
			draw_string(font, Vector2(w - count_w - 6.0, 37.0), count_sub, HORIZONTAL_ALIGNMENT_RIGHT, count_w, 14, BroadcastUI.MUTED)
			if equipped:
				draw_string(font, Vector2(text_x + tier_w + 10.0, 37.0), "IN HAND", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, BroadcastUI.CYAN)
		else:
			draw_string(font, Vector2(tab_w + 12.0, h * 0.5 + 7.0), "EMPTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
					Color(BroadcastUI.MUTED, 0.45))
		var border := Color(BroadcastUI.MUTED, 0.3)
		var width := 1.0
		if _drop_hover:
			border = BroadcastUI.CYAN
			width = 2.0
		elif equipped:
			border = Color(BroadcastUI.CYAN, 0.85)
			width = 2.0
		elif inspected:
			border = Color(BroadcastUI.PAPER, 0.7)
		elif _hover:
			border = Color(BroadcastUI.PAPER, 0.45)
		elif _dragging:
			border = Color(BroadcastUI.CYAN, 0.35)
		draw_rect(Rect2(Vector2.ONE * width * 0.5, size - Vector2.ONE * width), border, false, width)
		if inspected:
			draw_rect(Rect2(tab_w - 3.0, 0, 3.0, h), BroadcastUI.PAPER)


## Drag a slot here to drop it on the ground in front of you.
class _DropZone extends Control:
	var menu: InventoryMenu
	var _armed := false
	var _dragging := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 32)
		mouse_filter = Control.MOUSE_FILTER_STOP

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
				queue_redraw()
			NOTIFICATION_DRAG_END:
				_dragging = false
				_armed = false
				queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ONE, size - Vector2.ONE * 2.0)
		var tint := BroadcastUI.PINK if _armed or _dragging else Color(BroadcastUI.MUTED, 0.45)
		draw_rect(rect, Color(BroadcastUI.PINK, 0.22 if _armed else (0.07 if _dragging else 0.0)))
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], tint, 1.5 if _armed else 1.0, 6.0)
		var label := "RELEASE TO DROP" if _armed else "DROP ON GROUND"
		draw_string(BroadcastUI.FONT, Vector2(0, size.y * 0.5 + 7.0), label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20,
				BroadcastUI.PINK if _armed or _dragging else Color(BroadcastUI.MUTED, 0.7))


## Small amber hex nut for the scrap counter.
class _ScrapIcon extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		var points := PackedVector2Array()
		for i in 6:
			points.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r)
		draw_colored_polygon(points, BroadcastUI.AMBER)
		points.append(points[0])
		draw_polyline(points, BroadcastUI.INK, 1.5)
		draw_circle(c, r * 0.38, BroadcastUI.INK)
