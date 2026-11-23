extends CanvasLayer
## Developer toolbench (debug builds only). F10 opens it, Esc or F10 closes it.
## Five tabs: player cheats, weapons and loot, enemies, weather and waves, and
## maps/world overlays. Most actions are host-side (solo, or a debug host), so
## they quietly do nothing on a cloud client; view tools work everywhere.
## The Debug HUD reads `active_flags()` through the "dev_menu" group.

const PANEL_SIZE := Vector2(740, 600)
const TAB_NAMES := ["PLAYER", "WEAPONS", "ENEMIES", "WEATHER", "WORLD"]
const ENEMY_KINDS := ["drip", "gutter", "mister", "sleet", "hailstone", "undertow", "static", "smog", "thunderhead"]
const ENEMY_MUTATIONS := ["conductors", "molting", "undertow", "static_charge", "pressure_front", "false_clearing"]
const TIME_SCALES := [0.25, 0.5, 1.0, 2.0, 4.0]
const INTENSITY_LOCKS := [[-1.0, "AUTO"], [0.0, "0.0 CLEAR"], [0.3, "0.3 DRIZZLE"], [0.7, "0.7 DOWNPOUR"], [1.0, "1.0 ACID"]]
const SANDBOX_ID := "sandbox"
const SANDBOX_SCENE := "res://levels/sandbox/level_sandbox.tscn"
const SPEED_SCALE := 2.0
const JUMP_SCALE := 2.2
const MOVE_META := "dev_base_move"
const FREEZE_META := "dev_frozen"
const DRAW_MODES := [
	[Viewport.DEBUG_DRAW_DISABLED, "NORMAL"],
	[Viewport.DEBUG_DRAW_WIREFRAME, "WIREFRAME"],
	[Viewport.DEBUG_DRAW_OVERDRAW, "OVERDRAW"],
	[Viewport.DEBUG_DRAW_UNSHADED, "UNSHADED"],
]
## Marker overlay: group -> [label, color].
const OVERLAY_GROUPS := {
	"crate_station": ["VENDING", Color("#ffc365")],
	"decon_shower": ["DECON", Color("#66dfda")],
	"shelter": ["SHELTER", Color("#b8e56d")],
	"enemy_spawn": ["ENEMY SPAWN", Color("#ff5689")],
	"puddles": ["PUDDLE", Color("#83b8ff")],
}
const OVERLAY_RANGE := 140.0

# ------------------------------------------------------------------ state
var god_mode := false
var infinite_ammo := false
var super_speed := false
var high_jump := false
var spawn_at_crosshair := true
var spawn_count := 1
var ai_frozen := false
var spawner_paused := false
var hold_weather := false
var intensity_lock := -1.0
var selected_tier := ItemCatalog.STANDARD
var equip_direct := false
var marker_overlay := false
var draw_mode := 0

var _panel := PanelContainer.new()
var _first: Button
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _tab := 0
## [button, label, getter] rows refreshed in `_refresh()`.
var _toggles: Array = []
## [button, is_selected getter] rows highlighted in `_refresh()`.
var _choices: Array = []
var _flags_label := Label.new()
var _message_label := Label.new()
var _host_label := Label.new()
var _landmarks: GridContainer
var _overlay_layer: CanvasLayer
var _overlay: Control
var _freeze_scan := 0.0
var _message_left := 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	name = "DevMenu"
	add_to_group("dev_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_build()
	_build_overlay()
	visible = false


func _exit_tree() -> void:
	# Leaving a run must never strand the next scene in slow-mo or wireframe.
	Engine.time_scale = 1.0
	if is_inside_tree() and get_viewport():
		get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	if ai_frozen:
		_set_ai_frozen(false)
	if spawner_paused:
		_set_spawner_paused(false)
	if hold_weather:
		hold_weather = false
		WeatherManager.hold = false
	if intensity_lock >= 0.0 and Net.is_host():
		WeatherManager.set_intensity_override(-1.0)
	super_speed = false
	high_jump = false
	_apply_movement()
	if is_instance_valid(_overlay_layer):
		_overlay_layer.queue_free()


# ------------------------------------------------------------------ layout
func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	_panel.theme = BroadcastUI.theme()
	_panel.custom_minimum_size = PANEL_SIZE
	var style := BroadcastUI.panel(Color(BroadcastUI.INK, 0.96), BroadcastUI.CYAN)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)

	# Header: title, host status, close.
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "DEVELOPER TOOLS"
	BroadcastUI.text(title, 30, BroadcastUI.CYAN)
	header.add_child(title)
	_host_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.text(_host_label, BroadcastUI.T_META, BroadcastUI.MUTED)
	header.add_child(_host_label)
	var close := Button.new()
	close.text = "CLOSE  [F10]"
	BroadcastUI.button_role(close, false, true)
	BroadcastUI.animate_button(close)
	close.pressed.connect(_close)
	header.add_child(close)

	# Tab bar.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TAB_NAMES.size():
		var index := i
		var tab := Button.new()
		tab.text = TAB_NAMES[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BroadcastUI.animate_button(tab)
		tab.pressed.connect(func(): _show_tab(index))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	_first = _tab_buttons[0]

	# Pages share one slot; only the active one is visible.
	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.clip_contents = true
	column.add_child(pages)
	for builder: Callable in [_build_player, _build_weapons, _build_enemies, _build_weather, _build_world]:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		pages.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 6)
		scroll.add_child(box)
		builder.call(box)
		_pages.append(scroll)

	# Status strip: active toggles, then the last action.
	var strip := VBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	column.add_child(strip)
	var rule := ColorRect.new()
	rule.color = Color(BroadcastUI.CYAN, 0.35)
	rule.custom_minimum_size.y = 2
	strip.add_child(rule)
	BroadcastUI.text(_flags_label, 20, BroadcastUI.ACID)
	_flags_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strip.add_child(_flags_label)
	BroadcastUI.text(_message_label, BroadcastUI.T_META, BroadcastUI.MUTED)
	_message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	strip.add_child(_message_label)
	_show_tab(0)


func _build_player(box: VBoxContainer) -> void:
	_heading(box, "CHEATS")
	var cheats := _grid(box)
	_toggle(cheats, "GOD MODE", func(): return god_mode, func(on: bool): god_mode = on)
	_toggle(cheats, "INFINITE AMMO", func(): return infinite_ammo, func(on: bool): infinite_ammo = on)
	_toggle(cheats, "SUPER SPEED (2x)", func(): return super_speed, func(on: bool):
		super_speed = on
		_apply_movement())
	_toggle(cheats, "HIGH JUMP", func(): return high_jump, func(on: bool):
		high_jump = on
		_apply_movement())
	_heading(box, "ACTIONS")
	var actions := _grid(box)
	_button(actions, "TELEPORT TO CROSSHAIR", _teleport_to_crosshair)
	_button(actions, "INSTANT REVIVE", _instant_revive)
	_button(actions, "HEAL + FULL SUIT", _heal)
	_button(actions, "REFILL ALL AMMO", _refill_ammo)
	_button(actions, "FILL GRENADES & DOMES", _fill_grenades)
	_button(actions, "RESET INVENTORY", _reset_inventory)
	_button(actions, "+100 SCRAP", func(): _add_scrap(100))
	_button(actions, "+500 SCRAP", func(): _add_scrap(500))
	_heading(box, "TIME SCALE")
	var times := _row(box)
	for value: float in TIME_SCALES:
		var factor := value
		_choice(times, "%sx" % _scale_text(factor), func(): return is_equal_approx(Engine.time_scale, factor), func():
			Engine.time_scale = factor
			_say("TIME SCALE %sx" % _scale_text(factor)))


func _build_weapons(box: VBoxContainer) -> void:
	_heading(box, "TIER (APPLIES TO SPAWNED GUNS)")
	var tiers := _row(box)
	for tier in ItemCatalog.TIER_NAMES.size():
		var chosen := tier
		_choice(tiers, ItemCatalog.TIER_NAMES[tier], func(): return selected_tier == chosen, _select_tier.bind(chosen), ItemCatalog.TIER_COLORS[tier])
	var delivery := _row(box)
	_choice(delivery, "DROP IN FRONT", func(): return not equip_direct, func(): equip_direct = false)
	_choice(delivery, "EQUIP DIRECTLY", func(): return equip_direct, func(): equip_direct = true)
	_heading(box, "GUNS")
	var guns := _grid(box)
	for id: String in ItemCatalog.GUNS:
		var gun := id
		_button(guns, _item_name(gun), func(): _give_item(gun), ItemCatalog.tier_color(gun, 0) if _is_special(gun) else Color())
	_heading(box, "THROWABLES / DEPLOYABLES / CONSUMABLES")
	var stacks := _grid(box)
	for id: String in ItemCatalog.STACKS:
		var stack := id
		_button(stacks, _item_name(stack), func(): _give_item(stack))
	_heading(box, "SUPPLY")
	var supply := _grid(box)
	_button(supply, "AIRDROP AT CROSSHAIR", _airdrop_at_crosshair)
	_button(supply, "RESTOCK VENDING MACHINES", _restock_vending)
	_button(supply, "CLEAR GROUND PICKUPS", _clear_pickups)


func _build_enemies(box: VBoxContainer) -> void:
	_heading(box, "SPAWN OPTIONS")
	var options := _grid(box)
	_toggle(options, "SPAWN AT CROSSHAIR", func(): return spawn_at_crosshair, func(on: bool): spawn_at_crosshair = on)
	var counts := _row(options)
	for n: int in [1, 5]:
		var count := n
		_choice(counts, "x%d" % count, func(): return spawn_count == count, func(): spawn_count = count)
	_heading(box, "SPAWN")
	var spawns := _grid(box)
	for kind: String in ENEMY_KINDS:
		var selected := kind
		if ResourceLoader.exists(_enemy_path(selected)):
			_button(spawns, "SPAWN " + selected.to_upper(), func(): _spawn_enemy(selected))
	_button(spawns, "SPAWN CUMULUS (BOSS)", _spawn_boss, BroadcastUI.ACID)
	_heading(box, "CONTROL")
	var control := _grid(box)
	_toggle(control, "FREEZE ENEMY AI", func(): return ai_frozen, _set_ai_frozen)
	_toggle(control, "PAUSE AUTO-SPAWNER", func(): return spawner_paused, _set_spawner_paused)
	_button(control, "KILL ALL ENEMIES", func(): _hurt_all(INF), BroadcastUI.PINK)
	_button(control, "DAMAGE ALL (-50)", func(): _hurt_all(50.0))
	_button(control, "REVEAL ALL (5s)", _reveal_all)


func _build_weather(box: VBoxContainer) -> void:
	_heading(box, "PHASE")
	var phases := _row(box)
	for spec: Array in [["CALM", WeatherManager.Phase.CALM], ["DRIZZLE", WeatherManager.Phase.DRIZZLE],
			["DOWNPOUR", WeatherManager.Phase.DOWNPOUR], ["CLEARING", WeatherManager.Phase.CLEARING]]:
		var target: int = spec[1]
		_button(phases, spec[0], func(): _set_phase(target, WeatherManager.wave))
	_button(phases, "NEXT", _next_phase, BroadcastUI.CYAN)
	_heading(box, "WAVE")
	var waves := _row(box)
	for n in range(1, WeatherManager.FINAL_WAVE + 2):
		var wave := n
		_button(waves, "W%d" % wave if wave <= WeatherManager.FINAL_WAVE else "W%d ENDLESS" % wave, func(): _jump_to_wave(wave))
	_heading(box, "STORM")
	var storm := _grid(box)
	_toggle(storm, "HOLD WEATHER TIMER", func(): return hold_weather, func(on: bool):
		hold_weather = on
		if not on:
			WeatherManager.hold = not get_tree().get_nodes_in_group("boss").is_empty() or GameManager.is_voting())
	_button(storm, "LIGHTNING AT CROSSHAIR", _lightning_at_crosshair, BroadcastUI.AMBER)
	var locks := _row(box)
	for spec: Array in INTENSITY_LOCKS:
		var value: float = spec[0]
		_choice(locks, spec[1], func(): return is_equal_approx(intensity_lock, value), func(): _lock_intensity(value))
	_heading(box, "MUTATIONS")
	var mutations := _grid(box)
	_button(mutations, "TRIGGER MUTATION DRAFT", _mutation_draft, BroadcastUI.ACID)
	_button(mutations, "GRANT PLAYER MUTATION", _grant_mutation, BroadcastUI.ACID)
	for id: String in _enemy_mutation_ids():
		_button(mutations, "FORCE " + id.replace("_", " ").to_upper(), _force_mutation.bind(id))


func _build_world(box: VBoxContainer) -> void:
	_heading(box, "QUICK MAP LAUNCHER (SOLO)")
	var maps := _grid(box)
	var sandbox_ready := ResourceLoader.exists(SANDBOX_SCENE) and Maps.is_available(SANDBOX_ID)
	var sandbox := _button(maps, "TEST RANGE (CHECKERBOARD)" if sandbox_ready else "TEST RANGE (NOT INSTALLED)",
			func(): _launch_map(SANDBOX_ID), BroadcastUI.ACID)
	sandbox.disabled = not sandbox_ready
	for entry: Dictionary in Maps.ENTRIES:
		var id: String = entry.id
		if id == SANDBOX_ID:
			continue
		var launch := _button(maps, str(entry.name), func(): _launch_map(id), entry.get("accent", Color()))
		launch.disabled = not Maps.is_available(id)
	_heading(box, "TELEPORT TO LANDMARK")
	_landmarks = _grid(box)
	_heading(box, "WORLD OVERLAYS")
	var overlays := _grid(box)
	_toggle(overlays, "3D MARKER OVERLAY", func(): return marker_overlay, func(on: bool):
		marker_overlay = on
		if is_instance_valid(_overlay_layer):
			_overlay_layer.visible = on)
	_toggle(overlays, "DEBUG HUD (F9)", _debug_hud_on, _set_debug_hud)
	_toggle(overlays, "RETRO SHADER (F8)", _retro_on, _set_retro)
	var draw := _button(overlays, "", _cycle_draw_mode)
	_toggles.append([draw, "", func(): return draw_mode != 0, func(): return "VIEW: " + DRAW_MODES[draw_mode][1]])


func _rebuild_landmarks() -> void:
	if _landmarks == null:
		return
	for child in _landmarks.get_children():
		child.queue_free()
	var count := 0
	for spec: Array in [["crate_station", "VENDING"], ["decon_shower", "DECON"], ["player_spawn", "SPAWN"], ["boss_anchor", "BOSS ANCHOR"]]:
		for node in get_tree().get_nodes_in_group(spec[0]):
			if node is Node3D:
				var target := node as Node3D
				_button(_landmarks, "%s  %s" % [spec[1], str(target.name).to_upper()], func(): _teleport_to_landmark(target))
				count += 1
	if count == 0:
		var none := Label.new()
		none.text = "NO LANDMARKS IN THIS LEVEL"
		BroadcastUI.text(none, BroadcastUI.T_META, BroadcastUI.MUTED)
		_landmarks.add_child(none)


func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "DevMarkerOverlay"
	_overlay_layer.layer = 29
	_overlay_layer.visible = false
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_overlay_layer.add_child(_overlay)
	# A sibling, so the overlay stays up while the menu panel is closed.
	if get_parent():
		get_parent().add_child.call_deferred(_overlay_layer)


# ------------------------------------------------------------------ widgets
func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	BroadcastUI.text(label, 20, BroadcastUI.CYAN)
	parent.add_child(label)


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	return grid


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _button(parent: Control, text: String, action: Callable, accent := Color()) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if accent.a > 0.0:
		BroadcastUI.button_accent(button, accent, true)
	else:
		BroadcastUI.button_role(button, false, true)
	BroadcastUI.animate_button(button)
	button.pressed.connect(func():
		action.call()
		_refresh())
	parent.add_child(button)
	return button


func _toggle(parent: Control, label: String, getter: Callable, setter: Callable) -> Button:
	var button := _button(parent, label, func(): setter.call(not bool(getter.call())))
	_toggles.append([button, label, getter, Callable()])
	return button


func _choice(parent: Control, label: String, selected: Callable, action: Callable, accent := Color()) -> Button:
	var button := _button(parent, label, action)
	_choices.append([button, selected, accent if accent.a > 0.0 else BroadcastUI.ACID])
	return button


func _refresh() -> void:
	for row: Array in _toggles:
		var button: Button = row[0]
		var on := bool((row[2] as Callable).call())
		var text: String = (row[3] as Callable).call() if (row[3] as Callable).is_valid() else "%s: %s" % [row[1], "ON" if on else "OFF"]
		button.text = text
		_set_lit(button, on, BroadcastUI.ACID)
	for row: Array in _choices:
		_set_lit(row[0], bool((row[1] as Callable).call()), row[2])
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
		_set_lit(_tab_buttons[i], i == _tab, BroadcastUI.CYAN, false)
	var tags := PackedStringArray()
	for flag in active_flags():
		tags.append("[%s]" % flag)
	_flags_label.text = "  ".join(tags) if not tags.is_empty() else "[NO DEV FLAGS]"
	if Net.is_host():
		_host_label.text = "SOLO HOST" if not Net.is_online() else "DEBUG HOST"
	else:
		_host_label.text = "CLIENT: HOST TOOLS DISABLED"


## Only restyle on change so refreshes don't churn style boxes.
func _set_lit(button: Button, lit: bool, accent: Color, quiet := true) -> void:
	var key := "%s:%s" % [lit, accent.to_html()]
	if button.get_meta("dev_lit", "") == key:
		return
	button.set_meta("dev_lit", key)
	if lit:
		BroadcastUI.button_accent(button, accent, quiet)
	else:
		BroadcastUI.button_role(button, false, quiet)


func _show_tab(index: int) -> void:
	_tab = index
	for i in _pages.size():
		_pages[i].visible = i == index
	if index == 4:
		_rebuild_landmarks()
	_refresh()


func _say(text: String) -> void:
	_message_label.text = "> " + text
	_message_left = 4.0


## Short flag names for the status strip and the Debug HUD.
func active_flags() -> PackedStringArray:
	var flags := PackedStringArray()
	if god_mode:
		flags.append("GOD")
	if infinite_ammo:
		flags.append("INF AMMO")
	if super_speed:
		flags.append("SPEED 2x")
	if high_jump:
		flags.append("HIGH JUMP")
	if ai_frozen:
		flags.append("AI FROZEN")
	if spawner_paused:
		flags.append("SPAWNER PAUSED")
	if hold_weather:
		flags.append("WEATHER HELD")
	if intensity_lock >= 0.0:
		flags.append("STORM %.1f" % intensity_lock)
	if not is_equal_approx(Engine.time_scale, 1.0):
		flags.append("TIME %sx" % _scale_text(Engine.time_scale))
	if marker_overlay:
		flags.append("MARKERS")
	if draw_mode != 0:
		flags.append(DRAW_MODES[draw_mode][1])
	return flags


# ------------------------------------------------------------------ open / close
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		if visible:
			_close()
		else:
			_refresh()
			if _tab == 4:
				_rebuild_landmarks()
			MenuState.open(self)


func _close() -> void:
	MenuState.close(self)


func focus_default() -> void:
	_tab_buttons[_tab].grab_focus()


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_message_label.text = ""
	var player := _player()
	if player and Net.is_host():
		if god_mode:
			_apply_god(player)
		if infinite_ammo:
			_apply_infinite_ammo(player)
	if super_speed or high_jump:
		_apply_movement()
	if hold_weather and Net.is_host():
		WeatherManager.hold = true
	if intensity_lock >= 0.0 and Net.is_host() and not is_equal_approx(WeatherManager.intensity_override, intensity_lock):
		WeatherManager.set_intensity_override(intensity_lock)
	if ai_frozen:
		_freeze_scan -= delta
		if _freeze_scan <= 0.0:
			_freeze_scan = 0.2
			for enemy in _ai_nodes():
				_freeze(enemy)
	if marker_overlay and is_instance_valid(_overlay):
		_overlay.queue_redraw()


func _apply_god(player: Player) -> void:
	if player.state != "ok":
		_revive(player)
	player.health = player.max_health
	player.suit_integrity = 100.0
	# Hit grace keeps take_damage from landing at all (one-shots included).
	player.set("_grace_left", maxf(float(player.get("_grace_left")), 0.25))


func _apply_infinite_ammo(player: Player) -> void:
	var holder := RunLoot.holder(player)
	if holder == null:
		return
	var changed := false
	for item: ItemInstance in holder.slots:
		if item == null:
			continue
		var definition := ItemCatalog.definition(item.id)
		if definition == null:
			continue
		if definition.kind == ItemDefinition.Kind.GUN:
			if item.count < definition.weapon.mag_size:
				item.count = definition.weapon.mag_size
				changed = true
			if not definition.ammo_type.is_empty():
				var cap := int(ItemCatalog.CAPS.get(definition.ammo_type, 0))
				if int(holder.reserves.get(definition.ammo_type, 0)) < cap:
					holder.reserves[definition.ammo_type] = cap
					changed = true
		elif item.count < definition.stack_cap:
			item.count = definition.stack_cap
			changed = true
	if changed:
		holder.send_state(false)


## Scale the local player's movement from the values it had before any boost,
## and put them back once both boosts are off.
func _apply_movement() -> void:
	var player := _player()
	if player == null:
		return
	if not super_speed and not high_jump:
		if player.has_meta(MOVE_META):
			var base: Dictionary = player.get_meta(MOVE_META)
			for key: String in base:
				player.set(key, base[key])
			player.remove_meta(MOVE_META)
		return
	if not player.has_meta(MOVE_META):
		player.set_meta(MOVE_META, {"walk_speed": player.walk_speed, "sprint_speed": player.sprint_speed,
			"crouch_speed": player.crouch_speed, "jump_velocity": player.jump_velocity})
	var stored: Dictionary = player.get_meta(MOVE_META)
	var speed := SPEED_SCALE if super_speed else 1.0
	player.walk_speed = float(stored.walk_speed) * speed
	player.sprint_speed = float(stored.sprint_speed) * speed
	player.crouch_speed = float(stored.crouch_speed) * speed
	player.jump_velocity = float(stored.jump_velocity) * (JUMP_SCALE if high_jump else 1.0)


# ------------------------------------------------------------------ small button actions
func _instant_revive() -> void:
	if _host_only():
		_with_player(func(p: Player): _revive(p))
		_say("REVIVED")


func _select_tier(tier: int) -> void:
	selected_tier = tier
	_say("TIER " + ItemCatalog.TIER_NAMES[tier])


func _spawn_boss() -> void:
	if _host_only():
		GameManager.spawn_boss()
		_say("CUMULUS REQUESTED" if get_tree().get_nodes_in_group("boss").is_empty() else "CUMULUS IS UP")


func _next_phase() -> void:
	if _host_only():
		WeatherManager.next_phase()
		_say("PHASE %s  WAVE %d" % [WeatherManager.phase_name().to_upper(), WeatherManager.wave])


func _mutation_draft() -> void:
	_set_phase(WeatherManager.Phase.MUTATION_ROLL, WeatherManager.wave)


func _grant_mutation() -> void:
	if _host_only():
		var granted: String = GameManager.mutations.grant_random_player_mutation()
		_say("GRANTED " + granted.to_upper() if not granted.is_empty() else "NO PLAYER MUTATIONS LEFT")


func _force_mutation(id: String) -> void:
	if _host_only():
		GameManager.mutations.force_enemy_mutation(id)
		_say("FORCED " + id.to_upper())


func _debug_hud_on() -> bool:
	var hud := _scene_node("DebugHUD")
	return hud != null and hud.visible


func _set_debug_hud(on: bool) -> void:
	var hud := _scene_node("DebugHUD")
	if hud:
		hud.visible = on


func _retro_on() -> bool:
	var retro := _scene_node("RetroScreen")
	return retro != null and bool(retro.get("enabled"))


func _set_retro(on: bool) -> void:
	var retro := _scene_node("RetroScreen")
	if retro and retro.has_method("_apply_enabled"):
		retro.set("enabled", on)
		retro.call("_apply_enabled")


# ------------------------------------------------------------------ player actions
func _player() -> Player:
	return get_tree().get_first_node_in_group("local_player") as Player


func _with_player(action: Callable) -> void:
	var player := _player()
	if player == null:
		_say("NO LOCAL PLAYER")
		return
	action.call(player)


func _host_only() -> bool:
	if Net.is_host():
		return true
	_say("HOST ONLY")
	return false


func _revive(player: Player) -> void:
	if not Net.is_host():
		return
	match player.state:
		"ok":
			return
		"downed":
			var revives := player.self_revives
			player.revive(player)
			player.self_revives = revives
		_:
			player.health = player.max_health
			player.suit_integrity = 100.0
			player.call("_set_state", "ok")


func _heal() -> void:
	if not _host_only():
		return
	_with_player(func(p: Player):
		_revive(p)
		p.health = p.max_health
		p.suit_integrity = 100.0
		_say("HEALED + SUIT 100%"))


func _refill_ammo() -> void:
	if not _host_only():
		return
	_with_player(func(p: Player):
		var holder := RunLoot.holder(p)
		for item: ItemInstance in holder.slots:
			var definition: ItemDefinition = ItemCatalog.definition(item.id) if item else null
			if definition and definition.kind == ItemDefinition.Kind.GUN:
				item.count = definition.weapon.mag_size
		for item: ItemInstance in holder.slots:
			var definition: ItemDefinition = ItemCatalog.definition(item.id) if item else null
			if definition and not definition.ammo_type.is_empty():
				holder.reserves[definition.ammo_type] = int(ItemCatalog.CAPS.get(definition.ammo_type, 0))
		holder.send_state(false)
		_say("AMMO REFILLED"))


func _fill_grenades() -> void:
	if not _host_only():
		return
	_with_player(func(p: Player):
		var holder := RunLoot.holder(p)
		for id: String in ["frag", "shield_dome"]:
			var cap := int(ItemCatalog.STACKS[id][2])
			if not _add_pouch(holder, id, cap):
				var item := holder.loot.make_item(id, selected_tier)
				item.count = cap
				_place(holder, item, p)
		holder.send_state()
		_say("GRENADES + DOMES FILLED"))


## Feed WeaponHolder.add_pouch() whatever shape its signature has, if it exists.
func _add_pouch(holder: WeaponHolder, id: String, count: int) -> bool:
	if not holder.has_method("add_pouch"):
		return false
	var args := _method_args(holder, "add_pouch")
	var first_type := int(args[0].get("type", TYPE_NIL)) if not args.is_empty() else TYPE_NIL
	if first_type == TYPE_OBJECT:
		var item := holder.loot.make_item(id, selected_tier)
		item.count = count
		if args.size() >= 2:
			holder.call("add_pouch", item, count)
		else:
			holder.call("add_pouch", item)
	elif args.size() >= 2:
		holder.call("add_pouch", id, count)
	elif args.size() == 1:
		for i in count:
			holder.call("add_pouch", id)
	else:
		return false
	return true


func _method_args(target: Object, method: String) -> Array:
	for info: Dictionary in target.get_method_list():
		if info.name == method:
			return info.get("args", [])
	return []


func _add_scrap(amount: int) -> void:
	if not _host_only():
		return
	_with_player(func(p: Player):
		RunLoot.holder(p).earn_scrap(amount)
		_say("+%d SCRAP" % amount))


func _reset_inventory() -> void:
	if not _host_only():
		return
	_with_player(func(p: Player):
		var holder := RunLoot.holder(p)
		if holder.loot == null:
			return
		holder.call("_cancel_actions")
		for i in holder.slots.size():
			holder.slots[i] = null
		holder.slots[0] = holder.loot.make_item("service_revolver")
		holder.reserves = {"revolver": 24}
		holder.set("_seeded_ammo", {"revolver": true})
		holder.current = 0
		if "pouches" in holder and holder.get("pouches") is Dictionary:
			(holder.get("pouches") as Dictionary).clear()
		holder.send_state()
		_say("INVENTORY RESET"))


func _teleport_to_crosshair() -> void:
	_with_player(func(p: Player):
		var hit := _crosshair_hit(Player.WORLD_LAYER)
		if hit.is_empty():
			_say("NOTHING UNDER CROSSHAIR")
			return
		var at: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		# Floors put you on top; walls put you a body width out from them.
		at += Vector3.UP * 0.1 if normal.y > 0.55 else normal * 0.6
		p.teleport(Transform3D(p.global_basis, at))
		_say("TELEPORTED %s" % _vec_text(at)))


func _teleport_to_landmark(target: Node3D) -> void:
	if not is_instance_valid(target):
		_rebuild_landmarks()
		return
	_with_player(func(p: Player):
		var focus := target.global_position
		var at := focus - target.global_basis.z * 2.2
		at.y = focus.y
		# Land on the floor under the spot, never inside a counter or roof.
		var space := p.get_world_3d().direct_space_state
		var probe := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.5, at - Vector3.UP * 6.0, Player.WORLD_LAYER)
		probe.exclude = [p.get_rid()]
		var floor_hit := space.intersect_ray(probe)
		at.y = (floor_hit.position as Vector3).y + 0.1 if not floor_hit.is_empty() else focus.y + 0.2
		var look := focus - at
		look.y = 0.0
		var basis := Basis.looking_at(look.normalized(), Vector3.UP) if look.length_squared() > 0.01 else p.global_basis
		p.teleport(Transform3D(basis, at))
		p.set("_pitch", 0.0)
		p.head.rotation.x = 0.0
		_close()
		_say("AT " + str(target.name).to_upper()))


# ------------------------------------------------------------------ weapons / loot
func _give_item(id: String) -> void:
	if not _host_only():
		return
	_with_player(func(p: Player):
		var holder := RunLoot.holder(p)
		var loot := RunLoot.find(get_tree())
		if loot == null:
			return
		var item := loot.make_item(id, selected_tier)
		if item == null:
			_say("UNKNOWN ITEM " + id)
			return
		var definition := ItemCatalog.definition(id)
		if definition.kind != ItemDefinition.Kind.GUN:
			item.count = definition.stack_cap
		var label := "%s %s" % [ItemCatalog.tier_name(id, item.tier), _item_name(id)]
		if equip_direct:
			_place(holder, item, p)
			var slot := holder.slots.find(item)
			if slot >= 0 and slot != holder.current:
				holder.call("_cancel_actions")
				holder.current = slot
			holder.send_state()
			_say("EQUIPPED " + label)
		else:
			loot.spawn_pickup(item, _front_of(p, loot))
			_say("DROPPED " + label))


## Put an item into the inventory; anything it displaces lands at your feet.
func _place(holder: WeaponHolder, item: ItemInstance, player: Player) -> void:
	var displaced := holder.accept_pickup(item)
	if displaced != null and displaced != item:
		holder.loot.spawn_pickup(displaced, _front_of(player, holder.loot))


func _front_of(player: Player, loot: RunLoot) -> Vector3:
	var forward := -player.global_basis.z * 2.0
	var at := loot.ground_at(player, forward)
	if at == Vector3.INF:
		at = loot.ground_at(player, Vector3.ZERO)
	return at if at != Vector3.INF else player.global_position + forward


func _airdrop_at_crosshair() -> void:
	if not _host_only():
		return
	var crates: Node = GameManager.crates
	var hit := _crosshair_hit(Player.WORLD_LAYER)
	var player := _player()
	var at: Vector3
	if not hit.is_empty():
		at = hit.position
	elif player:
		at = _front_of(player, RunLoot.find(get_tree()))
	else:
		_say("NO DROP POINT")
		return
	if crates.has_method("spawn_airdrop_at"):
		crates.call("spawn_airdrop_at", at)
	elif crates.has_method("_make_airdrop"):
		crates.call("_make_airdrop", at, SupplyStation.DESCENT)
		crates.set("last_drop_position", at)
		if Net.is_online() and crates.has_method("_airdrop_spawn"):
			Net.rpc_to_run(Callable(crates, "_airdrop_spawn"), [int(crates.get("_run")), at, SupplyStation.DESCENT])
	else:
		_say("NO AIRDROP HELPER")
		return
	_say("AIRDROP %s" % _vec_text(at))


func _restock_vending() -> void:
	if not _host_only():
		return
	var crates: Node = GameManager.crates
	if crates.has_method("restock_all"):
		crates.call("restock_all")
	elif crates.has_method("_restock"):
		var stations: Dictionary = crates.get("stations")
		for key: String in stations:
			var station: Variant = stations[key]
			if is_instance_valid(station):
				crates.call("_restock", station)
	else:
		_say("NO RESTOCK HELPER")
		return
	_say("VENDING RESTOCKED")


func _clear_pickups() -> void:
	if not _host_only():
		return
	var loot := RunLoot.find(get_tree())
	if loot == null:
		return
	var ids: Array = loot.pickups.keys()
	for id: int in ids:
		loot.remove_pickup(id)
	_say("CLEARED %d PICKUPS" % ids.size())


# ------------------------------------------------------------------ enemies
func _spawner() -> Node:
	return _scene_node("Enemies")


func _enemy_path(kind: String) -> String:
	return "res://enemies/%s/%s.tscn" % [kind, kind]


func _spawn_enemy(kind: String) -> void:
	if not _host_only():
		return
	var spawner := _spawner()
	var scene := load(_enemy_path(kind)) as PackedScene
	if spawner == null or scene == null:
		_say("NO SPAWNER")
		return
	var hit := _crosshair_hit(Player.WORLD_LAYER) if spawn_at_crosshair else {}
	var spawned := 0
	for i in spawn_count:
		var enemy: Node = null
		if not hit.is_empty() and spawner.has_method("_spawn_near"):
			enemy = spawner.call("_spawn_near", scene, hit.position as Vector3, 0.0 if spawn_count == 1 else 2.5)
		else:
			enemy = spawner.spawn(scene)
		if enemy:
			spawned += 1
			if ai_frozen:
				_freeze(enemy)
	_say("SPAWNED %dx %s%s" % [spawned, kind.to_upper(), " AT CROSSHAIR" if not hit.is_empty() else ""])


func _ai_nodes() -> Array:
	var nodes := get_tree().get_nodes_in_group("enemies")
	for boss in get_tree().get_nodes_in_group("boss"):
		if not nodes.has(boss):
			nodes.append(boss)
	return nodes


func _set_ai_frozen(on: bool) -> void:
	ai_frozen = on
	for enemy in _ai_nodes():
		if on:
			_freeze(enemy)
		else:
			_thaw(enemy)
	_say("ENEMY AI FROZEN" if on else "ENEMY AI RESUMED")


func _freeze(enemy: Node) -> void:
	if enemy.has_meta(FREEZE_META) or enemy.is_queued_for_deletion():
		return
	enemy.set_meta(FREEZE_META, [enemy.is_physics_processing(), enemy.is_processing()])
	enemy.set_physics_process(false)
	enemy.set_process(false)


func _thaw(enemy: Node) -> void:
	if not enemy.has_meta(FREEZE_META):
		return
	var was: Array = enemy.get_meta(FREEZE_META)
	enemy.remove_meta(FREEZE_META)
	enemy.set_physics_process(bool(was[0]))
	enemy.set_process(bool(was[1]))


func _set_spawner_paused(on: bool) -> void:
	var spawner := _spawner()
	spawner_paused = on
	if spawner:
		spawner.set_physics_process(not on)
	_say("AUTO-SPAWNER PAUSED" if on else "AUTO-SPAWNER RESUMED")


func _hurt_all(amount: float) -> void:
	if not _host_only():
		return
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy and enemy.health > 0.0:
			enemy.take_damage(enemy.health + 1.0 if amount == INF else amount)
			count += 1
	_say(("KILLED %d" if amount == INF else "DAMAGED %d") % count)


func _reveal_all() -> void:
	var count := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_method("reveal"):
			node.reveal(5.0)
			count += 1
	_say("REVEALED %d" % count)


# ------------------------------------------------------------------ weather / waves
func _set_phase(phase: int, wave: int) -> void:
	if not _host_only():
		return
	WeatherManager.set_phase(phase as WeatherManager.Phase, wave)
	_say("PHASE %s  WAVE %d" % [WeatherManager.phase_name().to_upper(), wave])


func _jump_to_wave(wave: int) -> void:
	if not _host_only():
		return
	var endless := wave > WeatherManager.FINAL_WAVE
	if GameManager.endless != endless and GameManager.has_method("_set_tape_state"):
		GameManager.call("_set_tape_state", false, endless, false)
	if endless:
		WeatherManager.hold = hold_weather
		if intensity_lock < 0.0:
			WeatherManager.set_intensity_override(-1.0)
	WeatherManager.set_phase(WeatherManager.Phase.CALM, wave)
	_say("WAVE %d%s" % [wave, " (ENDLESS)" if endless else ""])


func _lock_intensity(value: float) -> void:
	if not _host_only():
		return
	intensity_lock = value
	WeatherManager.set_intensity_override(value)
	_say("STORM AUTO" if value < 0.0 else "STORM LOCKED %.1f" % value)


func _lightning_at_crosshair() -> void:
	if not _host_only():
		return
	var hit := _crosshair_hit(Player.WORLD_LAYER)
	if hit.is_empty():
		WeatherManager.strike_lightning()
		_say("LIGHTNING (RANDOM)")
		return
	var at: Vector3 = hit.position
	if WeatherManager.has_method("strike_at"):
		WeatherManager.call("strike_at", at)
	else:
		WeatherManager.strike_lightning(at)
	_say("LIGHTNING %s" % _vec_text(at))


func _enemy_mutation_ids() -> Array:
	var table: Variant = GameManager.mutations.get("table") if GameManager.mutations else null
	var ids: Array = []
	if table and "entries" in table:
		for entry in table.entries:
			if entry and "id" in entry:
				ids.append(str(entry.id))
	return ids if not ids.is_empty() else ENEMY_MUTATIONS


# ------------------------------------------------------------------ maps / world
func _launch_map(id: String) -> void:
	if Net.is_online():
		_say("MAP LAUNCHER IS SOLO ONLY")
		return
	if not Maps.is_available(id):
		_say("MAP %s NOT AVAILABLE" % id.to_upper())
		return
	Engine.time_scale = 1.0
	_close()
	# Same teardown as the pause menu's exit, minus leaving the session.
	GameManager.request_pause(false)
	MenuState.reset()
	GameManager.run_active = false
	GameManager.mutations.clear()
	WeatherManager.stop()
	Settings.solo_map_id = id
	SceneLoader.goto(Maps.RUN_SCENE, id)


func _cycle_draw_mode() -> void:
	draw_mode = (draw_mode + 1) % DRAW_MODES.size()
	if DRAW_MODES[draw_mode][0] == Viewport.DEBUG_DRAW_WIREFRAME:
		RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = DRAW_MODES[draw_mode][0]
	_say("VIEW " + DRAW_MODES[draw_mode][1])


func _draw_overlay() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var font := BroadcastUI.FONT
	var eye := camera.global_position
	var view := _overlay.get_viewport_rect().size
	for group: String in OVERLAY_GROUPS:
		var spec: Array = OVERLAY_GROUPS[group]
		var color: Color = spec[1]
		for node in get_tree().get_nodes_in_group(group):
			if not node is Node3D:
				continue
			var at := (node as Node3D).global_position
			var distance := eye.distance_to(at)
			if distance > OVERLAY_RANGE or camera.is_position_behind(at):
				continue
			var screen := camera.unproject_position(at)
			if screen.x < -40.0 or screen.y < -40.0 or screen.x > view.x + 40.0 or screen.y > view.y + 40.0:
				continue
			var fade := clampf(1.25 - distance / OVERLAY_RANGE, 0.35, 1.0)
			var tint := Color(color, fade)
			_overlay.draw_rect(Rect2(screen - Vector2(4, 4), Vector2(8, 8)), tint)
			var text := "%s %s  %dm" % [spec[0], str(node.name).to_upper(), roundi(distance)]
			_overlay.draw_string_outline(font, screen + Vector2(8, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, fade))
			_overlay.draw_string(font, screen + Vector2(8, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, tint)


# ------------------------------------------------------------------ helpers
func _scene_node(path: String) -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(path) if scene else null


## Physics ray from the center of the screen (the crosshair), skipping yourself.
func _crosshair_hit(mask: int, reach := 250.0) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(center)
	var query := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(center) * reach, mask)
	var player := _player()
	if player:
		query.exclude = [player.get_rid()]
	return camera.get_world_3d().direct_space_state.intersect_ray(query)


func _item_name(id: String) -> String:
	var definition := ItemCatalog.definition(id)
	return (definition.display_name if definition and not definition.display_name.is_empty() else id.replace("_", " ")).to_upper()


func _is_special(id: String) -> bool:
	var definition := ItemCatalog.definition(id)
	return definition != null and (definition.legendary or definition.is_cursed())


func _scale_text(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0") if not is_equal_approx(value, roundf(value)) else "%.1f" % value


func _vec_text(at: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [at.x, at.y, at.z]
