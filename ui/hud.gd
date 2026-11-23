extends CanvasLayer
## Local vitals, ammunition, team status and the current forecast.
## No backing boxes: outlined text, thin bars and icons. Groups sit dim when
## idle and come up to full opacity only while they matter (ammo while firing,
## vitals while exposed or hurt, the forecast chip on a phase change).

const TeammateCard := preload("res://ui/teammate_card.tscn")
const WEATHER_COLORS := [BroadcastUI.CYAN, Color("#9fd8ff"), Color("#adbaff"), BroadcastUI.ACID]
const PHASE_NAMES := ["CALM", "DRAFT", "DRIZZLE", "DOWNPOUR", "CLEARING"]
const BAR_W := 168.0
const FADE_SPEED := 3.0


## A key cap followed by one or two words, centred in its rect.
class KeyPrompt extends Control:
	var key := ""
	var words := ""
	var color := BroadcastUI.PAPER
	var font_size := BroadcastUI.T_BODY

	func show_prompt(new_key: String, new_words: String, new_color := BroadcastUI.PAPER) -> void:
		if new_key != key or new_words != words or new_color != color:
			key = new_key
			words = new_words
			color = new_color
			queue_redraw()

	func _draw() -> void:
		var font := BroadcastUI.FONT
		var cap := font_size - 4
		var cap_w := 0.0
		if not key.is_empty():
			cap_w = maxf(font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, cap).x + 10.0, cap + 2.0) + 8.0
		var text_w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var x := (size.x - cap_w - text_w) * 0.5
		var baseline := font_size * 0.9
		if not key.is_empty():
			BroadcastUI.draw_key_cap(self, Vector2(x, baseline - cap - 1.0), key, cap, color)
		draw_string_outline(font, Vector2(x + cap_w, baseline), words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(BroadcastUI.INK, 0.9))
		draw_string(font, Vector2(x + cap_w, baseline), words, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Campaign progress as five small diamonds: cleared, current, to come.
class WavePips extends Control:
	var wave := 0
	var total := 5
	var clock := 0.0

	func _draw() -> void:
		var step := 14.0
		var x0 := (size.x - (total - 1) * step) * 0.5
		for i in total:
			var at := Vector2(x0 + i * step, size.y * 0.5)
			var points := PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5), at + Vector2(-5, 0)])
			var n := i + 1
			if n < wave:
				draw_colored_polygon(points, BroadcastUI.CYAN)
			elif n == wave:
				var pulse := 1.0 if Settings.reduced_flash else 0.65 + 0.35 * sin(clock * 4.0)
				draw_colored_polygon(points, Color(BroadcastUI.PAPER, pulse))
			else:
				points.append(points[0])
				draw_polyline(points, Color(BroadcastUI.MUTED, 0.6), 1.0, true)


var _layout := Control.new()
# Top centre.
var _chip := HBoxContainer.new()
var _weather := GameIcon.new()
var _forecast := Label.new()
var _pips_waves := WavePips.new()
var _wave := Label.new()
var _countdown := Label.new()
var _combat := HBoxContainer.new()
var _wave_progress := ProgressBar.new()
var _combat_status := Label.new()
var _ready_hint := KeyPrompt.new()
var _phase_flash := 0.0
var _last_phase := -1
var _boss_box := VBoxContainer.new()
var _boss_label := Label.new()
var _boss_bar := ProgressBar.new()
var _sacs: Array[ProgressBar] = []
var _tape_counter := Label.new()
var _banner := Label.new()
var _banner_left := 0.0
var _last_countdown := -1
# Left.
var _teammates := VBoxContainer.new()
var _cards := {}
# Vitals (bottom left).
var _vitals := VBoxContainer.new()
var _mutation_row := HBoxContainer.new()
var _enemy_icons := HBoxContainer.new()
var _squad_icons := HBoxContainer.new()
var _mutation_divider := ColorRect.new()
var _enemy_ids: Array = []
var _squad_ids: Array = []
var _mutation_flash := 0.0
var _suit := ProgressBar.new()
var _health := ProgressBar.new()
var _suit_icon := GameIcon.new()
var _health_icon := GameIcon.new()
var _status_icon := GameIcon.new()
var _hazard_text := Label.new()
var _health_text := Label.new()
var _decon_icon := GameIcon.new()
var _decon_text := Label.new()
var _tarp_icon := GameIcon.new()
var _tarp_key := KeyPrompt.new()
var _static_icon := GameIcon.new()
var _static_text := Label.new()
var _vitals_hot := 0.0
# Ammo (bottom right) and the hotbar.
var _armory := VBoxContainer.new()
var _weapon := Label.new()
var _ammo := Label.new()
var _reserve := Label.new()
var _pips := preload("res://ui/ammo_pips.gd").new()
var _slots := ItemHotbar.new()
var _armory_hot := 0.0
var _name_left := 0.0
var _hotbar_hot := 0.0
var _last_pouch_state := ""
var _last_slot_state := ""
var _holder: WeaponHolder
var _unlock_name := ""
# Centre.
var _reticle := preload("res://ui/reticle.gd").new()
var _prompt := KeyPrompt.new()
# Stat card for the vending bay / ground pickup under the crosshair.
var _item_card := ItemStatCard.new(ItemStatCard.Layout.ROW, true)
var _item_card_key := ""
var _downed := Label.new()
var _state_flash := 0.0
var _last_state := ""
# Damage feedback.
var _last_health := -1.0
var _last_suit := -1.0
var _damage_left := 0.0
var _suit_flash := 0.0
var _damage_cue_left := 0.0
var _hurt := ShaderMaterial.new()
var _acid := ShaderMaterial.new()
var _clock := 0.0


func _ready() -> void:
	layer = 6
	_layout.theme = BroadcastUI.theme()
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layout)
	var compass := preload("res://ui/compass.gd").new()
	compass.name = "Compass"
	_layout.add_child(compass)
	_build_damage()
	_build_forecast()
	_build_vitals()
	_build_armory()
	_build_messages()
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.add_child(_reticle)
	_layout.move_child(_reticle, 0)
	GameManager.combat_hit.connect(_reticle.hit)
	GameManager.banner.connect(_show_banner)
	GameManager.weapon_unlocked.connect(_show_unlock)


# ------------------------------------------------------------------ building
func _ignore(control: Control) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


func _anchor(control: Control, preset: Control.LayoutPreset, rect: Rect2, pivot: Vector2) -> void:
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y
	control.pivot_offset = rect.size * pivot
	control.scale = Vector2.ONE * Settings.hud_scale
	if pivot.y >= 1.0:
		control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ignore(control)
	_layout.add_child(control)


func _icon(kind: String, color: Color, side := 16.0) -> GameIcon:
	var icon := GameIcon.new()
	icon.kind = kind
	icon.color = color
	icon.custom_minimum_size = Vector2(side, side)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _bar(parent: Control, bar: ProgressBar, size: Vector2, color: Color, max_value: float = 1.0) -> void:
	_ignore(bar)
	bar.max_value = max_value
	bar.step = 0.001
	bar.custom_minimum_size = size
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.thin_bar(bar, color)
	parent.add_child(bar)


func _build_forecast() -> void:
	# Chip under the compass: weather icon, phase word (briefly), wave pips, timer.
	_anchor(_chip, Control.PRESET_CENTER_TOP, Rect2(-180, 40, 360, 22), Vector2(0.5, 0))
	_chip.alignment = BoxContainer.ALIGNMENT_CENTER
	_chip.add_theme_constant_override("separation", 8)
	_weather.kind = "weather"
	_weather.custom_minimum_size = Vector2(20, 20)
	_chip.add_child(_ignore(_weather))
	BroadcastUI.hud_text(_forecast, BroadcastUI.T_BODY - 2, BroadcastUI.CYAN)
	_chip.add_child(_forecast)
	_pips_waves.custom_minimum_size = Vector2(70, 20)
	_chip.add_child(_ignore(_pips_waves))
	BroadcastUI.hud_text(_wave, BroadcastUI.T_BODY - 2)
	_chip.add_child(_wave)
	_chip.add_child(_ignore(_ready_hint))
	_ready_hint.custom_minimum_size = Vector2(150, 22)
	_ready_hint.font_size = BroadcastUI.T_BODY - 2

	_anchor(_combat, Control.PRESET_CENTER_TOP, Rect2(-100, 64, 200, 14), Vector2(0.5, 0))
	_combat.alignment = BoxContainer.ALIGNMENT_CENTER
	_combat.add_theme_constant_override("separation", 6)
	_bar(_combat, _wave_progress, Vector2(160, 3), BroadcastUI.PINK)
	BroadcastUI.hud_text(_combat_status, BroadcastUI.T_META, BroadcastUI.PINK)
	_combat.add_child(_combat_status)

	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.hud_text(_countdown, BroadcastUI.T_HEAD, BroadcastUI.AMBER)
	_anchor(_countdown, Control.PRESET_CENTER_TOP, Rect2(-60, 70, 120, 60), Vector2(0.5, 0))
	_countdown.hide()

	_anchor(_boss_box, Control.PRESET_CENTER_TOP, Rect2(-200, 82, 400, 30), Vector2(0.5, 0))
	_boss_box.add_theme_constant_override("separation", 2)
	BroadcastUI.hud_text(_boss_label, BroadcastUI.T_META, BroadcastUI.ACID)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_label)
	_bar(_boss_box, _boss_bar, Vector2(400, 4), BroadcastUI.ACID)
	var sac_row := HBoxContainer.new()
	sac_row.add_theme_constant_override("separation", 6)
	_boss_box.add_child(_ignore(sac_row))
	for i in 3:
		var sac := ProgressBar.new()
		sac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar(sac_row, sac, Vector2(0, 4), BroadcastUI.ACID)
		_sacs.append(sac)
	_boss_box.hide()

	_tape_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BroadcastUI.hud_text(_tape_counter, BroadcastUI.T_BODY, BroadcastUI.AMBER)
	_anchor(_tape_counter, Control.PRESET_TOP_RIGHT, Rect2(-220, 12, 200, 26), Vector2(1, 0))

	_teammates.add_theme_constant_override("separation", 8)
	_anchor(_teammates, Control.PRESET_CENTER_LEFT, Rect2(20, -110, 120, 0), Vector2(0, 0))


func _build_vitals() -> void:
	# Bottom left, clear of the 360x64 bottom-centre hotbar even at Large HUD.
	_vitals.alignment = BoxContainer.ALIGNMENT_END
	_vitals.add_theme_constant_override("separation", 5)
	_anchor(_vitals, Control.PRESET_BOTTOM_LEFT, Rect2(20, -110, 220, 86), Vector2(0, 1))
	_mutation_row.add_theme_constant_override("separation", 4)
	_vitals.add_child(_ignore(_mutation_row))
	_mutation_row.add_child(_ignore(_enemy_icons))
	_mutation_divider.custom_minimum_size = Vector2(1, 14)
	_mutation_divider.color = Color(BroadcastUI.MUTED, 0.5)
	_mutation_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mutation_row.add_child(_ignore(_mutation_divider))
	_mutation_row.add_child(_ignore(_squad_icons))
	for row in [_enemy_icons, _squad_icons]:
		row.add_theme_constant_override("separation", 3)
	_mutation_row.hide()

	var suit_row := _vital_row(_suit_icon, "suit", BroadcastUI.CYAN, _suit, "SuitBar")
	_status_icon.custom_minimum_size = Vector2(16, 16)
	_status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	suit_row.add_child(_ignore(_status_icon))
	_status_icon.hide()
	BroadcastUI.hud_text(_hazard_text, 16, BroadcastUI.CYAN)
	suit_row.add_child(_ignore(_hazard_text))
	_hazard_text.hide()
	var health_row := _vital_row(_health_icon, "health", BroadcastUI.PINK, _health, "HealthBar")
	BroadcastUI.hud_text(_health_text, BroadcastUI.T_META, BroadcastUI.PINK)
	health_row.add_child(_health_text)

	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", 5)
	_vitals.add_child(_ignore(utility))
	for spec in [[_decon_icon, "shower", BroadcastUI.CYAN], [_tarp_icon, "tarp", BroadcastUI.AMBER], [_static_icon, "static_charge", BroadcastUI.CYAN]]:
		var icon: GameIcon = spec[0]
		icon.kind = spec[1]
		icon.color = spec[2]
		icon.custom_minimum_size = Vector2(16, 16)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		utility.add_child(_ignore(icon))
		if icon == _decon_icon:
			BroadcastUI.hud_text(_decon_text, BroadcastUI.T_META, BroadcastUI.CYAN)
			utility.add_child(_decon_text)
		elif icon == _tarp_icon:
			_tarp_key.custom_minimum_size = Vector2(24, 18)
			_tarp_key.font_size = BroadcastUI.T_META + 2
			utility.add_child(_ignore(_tarp_key))
		else:
			BroadcastUI.hud_text(_static_text, BroadcastUI.T_META, BroadcastUI.CYAN)
			utility.add_child(_static_text)
	_tarp_icon.value = 1.0


func _vital_row(icon: GameIcon, kind: String, color: Color, bar: ProgressBar, bar_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_vitals.add_child(_ignore(row))
	icon.kind = kind
	icon.color = color
	icon.custom_minimum_size = Vector2(16, 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ignore(icon))
	# JuiceHud finds these bars by name for the white damage trail.
	bar.name = bar_name
	_bar(row, bar, Vector2(BAR_W, 5), color, 100.0)
	bar.value = 100.0
	return row


func _build_armory() -> void:
	_armory.alignment = BoxContainer.ALIGNMENT_END
	_armory.add_theme_constant_override("separation", 0)
	_anchor(_armory, Control.PRESET_BOTTOM_RIGHT, Rect2(-190, -110, 170, 86), Vector2(1, 1))
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BroadcastUI.hud_text(_weapon, BroadcastUI.T_BODY - 2)
	_weapon.clip_text = true
	_weapon.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_armory.add_child(_weapon)
	var count := HBoxContainer.new()
	count.alignment = BoxContainer.ALIGNMENT_END
	count.add_theme_constant_override("separation", 4)
	_armory.add_child(_ignore(count))
	BroadcastUI.hud_text(_ammo, BroadcastUI.T_NUM)
	count.add_child(_ammo)
	BroadcastUI.hud_text(_reserve, BroadcastUI.T_META + 2, BroadcastUI.MUTED)
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	count.add_child(_reserve)
	_pips.custom_minimum_size.y = 14
	_armory.add_child(_ignore(_pips))
	# The 5-slot hotbar sits bottom centre, between the vitals and the ammo.
	_slots.name = "Hotbar"
	_slots.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_slots.offset_left = -ItemHotbar.SIZE.x * 0.5
	_slots.offset_right = ItemHotbar.SIZE.x * 0.5
	_slots.offset_top = -24 - ItemHotbar.SIZE.y
	_slots.offset_bottom = -24
	_slots.pivot_offset = Vector2(ItemHotbar.SIZE.x * 0.5, ItemHotbar.SIZE.y)
	_slots.scale = Vector2.ONE * minf(Settings.hud_scale, 1.0)
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.add_child(_slots)


func _build_messages() -> void:
	# Headline under the forecast/boss strip. No box: outline only.
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BroadcastUI.hud_text(_banner, 30)
	_anchor(_banner, Control.PRESET_CENTER_TOP, Rect2(-300, 124, 600, 36), Vector2(0.5, 0))
	_banner.hide()
	# Interact / attack prompt just under the reticle.
	_anchor(_prompt, Control.PRESET_CENTER, Rect2(-240, 44, 480, 28), Vector2(0.5, 0))
	_prompt.hide()
	# Item card right of the reticle, bottom edge above the prompt, growing up
	# so it never covers the crosshair, the prompt, vitals or the hotbar.
	_item_card.name = "ItemCard"
	_anchor(_item_card, Control.PRESET_CENTER, Rect2(58, -104, ItemStatCard.COMPACT_WIDTH, 136), Vector2(0, 1))
	_item_card.resized.connect(func(): _item_card.pivot_offset = Vector2(0, _item_card.size.y))
	_item_card.hide()
	_downed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	BroadcastUI.hud_text(_downed, BroadcastUI.T_NUM, BroadcastUI.PINK)
	_anchor(_downed, Control.PRESET_CENTER, Rect2(-200, -96, 400, 40), Vector2(0.5, 0))
	_downed.hide()


func _build_damage() -> void:
	var effects := CanvasLayer.new()
	effects.layer = 1
	add_child(effects)
	var materials: Array[ShaderMaterial] = [_hurt, _acid]
	for material in materials:
		material.shader = preload("res://ui/damage.gdshader")
		var rect := ColorRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.material = material
		effects.add_child(rect)
	_acid.set_shader_parameter("tint", Vector3(0.65, 1.0, 0.08))


# ------------------------------------------------------------------ events
func _show_banner(message: String, color: Color, seconds: float) -> void:
	if message.is_empty():
		return
	_banner.text = message
	_banner.add_theme_color_override("font_color", color)
	_banner_left = seconds
	_banner.modulate.a = 0.0


func _show_unlock(weapon_name: String) -> void:
	_slots.flash()
	_hotbar_hot = 3.0
	_unlock_name = weapon_name.to_upper()
	_name_left = 2.5
	_armory_hot = 3.0


func _fade(control: CanvasItem, hot: bool, idle: float, delta: float) -> void:
	control.modulate.a = move_toward(control.modulate.a, 1.0 if hot else idle, delta * FADE_SPEED)


func _process(delta: float) -> void:
	_clock += delta
	_banner_left = maxf(0.0, _banner_left - delta)
	_banner.visible = _banner_left > 0.0
	if _banner.visible:
		_banner.modulate.a = minf(minf(1.0, _banner.modulate.a + delta * 6.0), _banner_left * 2.5)
	_update_forecast(delta)
	_update_mutations(delta)
	_update_boss()
	var player := get_tree().get_first_node_in_group("local_player") as Player
	if player == null:
		return
	_update_vitals(player, delta)
	_update_weapon(player, delta)
	_update_item_card(player)
	_update_teammates(player)


func _update_forecast(delta: float) -> void:
	var phase := WeatherManager.phase
	var state := WeatherManager.storm_state
	var seconds := maxi(0, ceili(WeatherManager.phase_time_left))
	var countdown := phase == WeatherManager.Phase.CALM and WeatherManager.running and seconds in [1, 2, 3, 4, 5]
	if phase != _last_phase:
		_last_phase = phase
		_phase_flash = 2.5
	_phase_flash = maxf(0.0, _phase_flash - delta)
	var acid := state == WeatherManager.StormState.ACID_STORM and phase == WeatherManager.Phase.DOWNPOUR
	_forecast.text = "ACID STORM" if acid else PHASE_NAMES[phase]
	_forecast.visible = _phase_flash > 0.0 or acid
	var accent: Color = BroadcastUI.AMBER if countdown else WEATHER_COLORS[state]
	if _weather.color != accent:
		_weather.color = accent
		_forecast.add_theme_color_override("font_color", accent)
	_weather.value = WeatherManager.storm_intensity
	_countdown.visible = countdown
	if countdown:
		_countdown.text = str(seconds)
	if countdown and seconds != _last_countdown:
		Sound.play("storm_countdown", -15.0, lerpf(0.88, 1.16, (5.0 - seconds) / 4.0))
	_last_countdown = seconds if countdown else -1
	var wave := WeatherManager.wave
	_pips_waves.visible = not GameManager.endless
	_pips_waves.wave = wave
	_pips_waves.total = WeatherManager.FINAL_WAVE
	_pips_waves.clock = _clock
	_pips_waves.queue_redraw()
	var between := phase in [WeatherManager.Phase.CALM, WeatherManager.Phase.MUTATION_ROLL]
	var timer := "%d:%02d" % [seconds / 60, seconds % 60] if between else ""
	_wave.text = ("ENDLESS %d  %s" % [wave - WeatherManager.FINAL_WAVE, timer]).strip_edges() if GameManager.endless else timer
	_wave.visible = not _wave.text.is_empty()
	_tape_counter.visible = GameManager.endless
	if _tape_counter.visible:
		_tape_counter.text = "CNT  %08d" % GameManager.endless_score
	_ready_hint.visible = GameManager.can_ready_up()
	if _ready_hint.visible:
		var count := "  %d/%d" % [GameManager.ready_count, GameManager.player_count()] if GameManager.player_count() > 1 else ""
		_ready_hint.show_prompt(BroadcastUI.input_hint("ready_up"), "READY" + count, BroadcastUI.CYAN)
	_fade(_chip, _phase_flash > 0.0 or countdown or _ready_hint.visible, 0.55, delta)
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	var fighting := phase in [WeatherManager.Phase.DRIZZLE, WeatherManager.Phase.DOWNPOUR] and not GameManager.victory_locked
	var total: int = spawner.wave_total() if spawner and fighting else 0
	_combat.visible = total > 0 and not _countdown.visible
	if _combat.visible:
		var left: int = spawner.remaining()
		_combat_status.text = str(left) if left <= 5 else ""
		_wave_progress.value = clampf(1.0 - float(left) / total, 0.0, 1.0)


func _update_mutations(delta: float) -> void:
	var roll := GameManager.mutations
	var changed := false
	if roll.active != _enemy_ids:
		_enemy_ids = roll.active.duplicate()
		_clear(_enemy_icons)
		for id in _enemy_ids:
			var entry: MutationData = roll.table.get_entry(id)
			if entry:
				_enemy_icons.add_child(_ignore(_icon(id, entry.color)))
		changed = true
	if roll.player_mutations != _squad_ids:
		_squad_ids = roll.player_mutations.duplicate()
		_clear(_squad_icons)
		for id in _squad_ids:
			if GameManager.PLAYER_MUTATIONS.has(id):
				_squad_icons.add_child(_ignore(_icon(id, GameManager.PLAYER_MUTATIONS[id].color)))
		changed = true
	if changed:
		_mutation_flash = 2.0
		_mutation_row.visible = not _enemy_ids.is_empty() or not _squad_ids.is_empty()
		_mutation_divider.visible = not _enemy_ids.is_empty() and not _squad_ids.is_empty()
	_mutation_flash = maxf(0.0, _mutation_flash - delta)
	_fade(_mutation_row, _mutation_flash > 0.0, 0.5, delta)


func _clear(row: Control) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


func _update_boss() -> void:
	var boss := get_tree().get_first_node_in_group("boss")
	var miniboss := get_tree().get_first_node_in_group("miniboss") if boss == null else null
	_boss_box.visible = boss != null or miniboss != null
	if not _boss_box.visible:
		return
	var sacs: bool = boss != null and not boss.core_exposed()
	_boss_bar.visible = not sacs
	for i in _sacs.size():
		_sacs[i].get_parent().visible = sacs
		if sacs:
			_sacs[i].value = boss.part_health[i] / maxf(1.0, boss.part_max[i])
	if boss:
		_boss_label.text = "CUMULUS"
		_boss_bar.value = boss.part_health[3] / maxf(1.0, boss.part_max[3])
		var burning: bool = boss.is_burning()
		_boss_bar.modulate = Color(1.0, 0.6 + 0.2 * sin(_clock * 18.0), 0.35) if burning else Color.WHITE
	else:
		_boss_label.text = str(miniboss.get("miniboss_name")).to_upper()
		_boss_bar.value = float(miniboss.get("health")) / maxf(1.0, float(miniboss.get("max_health")))
		_boss_bar.modulate = Color.WHITE


func _update_vitals(player: Player, delta: float) -> void:
	_health.max_value = player.max_health
	_health.value = lerpf(_health.value, player.health, 1.0 - exp(-12.0 * delta))
	_suit.value = player.suit_integrity
	_health.modulate = BroadcastUI.CYAN.lightened(.35) if player.invulnerable else Color.WHITE
	var low_health := player.health <= player.max_health * 0.3
	_health_text.visible = low_health and player.state == "ok"
	_health_text.text = str(roundi(player.health))
	_update_damage(player, delta)
	var hazard: String = player.acid_hazard() if player.state in ["ok", "downed"] else ""
	var protected := hazard == "shelter"
	var breach := hazard in ["rain", "puddle"] and _suit.value < 25.0
	_status_icon.visible = not hazard.is_empty()
	_status_icon.kind = "shelter" if protected else "rain"
	var pulse := 1.0 if Settings.reduced_flash else 0.65 + 0.35 * sin(_clock * 6.0)
	_status_icon.color = BroadcastUI.CYAN if protected else (BroadcastUI.PINK if hazard == "puddle" or breach else BroadcastUI.ACID)
	_status_icon.modulate.a = pulse if breach else 1.0
	_hazard_text.visible = _status_icon.visible
	_hazard_text.text = {"shelter": "DRY", "puddle": "ACID POOL", "rain": "ACID RAIN"}.get(hazard, "")
	_hazard_text.add_theme_color_override("font_color", _status_icon.color)
	_suit_icon.color = BroadcastUI.PINK.lerp(BroadcastUI.CYAN, pulse) if breach else BroadcastUI.CYAN
	_decon_text.text = str(GameManager.decon_charges)
	_tarp_icon.visible = player.has_tarp
	_tarp_key.visible = player.has_tarp
	if player.has_tarp:
		_tarp_key.show_prompt(BroadcastUI.input_hint("use_item"), "")
	var charge := GameManager.has_mutation("static_charge") and player.static_charge > 0.01
	_static_icon.visible = charge
	_static_text.visible = charge
	if charge:
		var ready := player.static_charge >= 0.25
		_static_icon.color = BroadcastUI.AMBER if ready else BroadcastUI.MUTED
		_static_text.text = "%d%%" % roundi(player.static_charge * 100.0)
	_vitals_hot = maxf(0.0, _vitals_hot - delta)
	var hot := hazard in ["rain", "puddle"] or _vitals_hot > 0.0 or player.health < player.max_health * 0.5 or _suit.value < 50.0 or player.state != "ok"
	_fade(_vitals, hot, 0.45, delta)
	_update_center(player, delta)


func _update_center(player: Player, delta: float) -> void:
	if player.state != _last_state:
		_last_state = player.state
		_state_flash = 2.5
	_state_flash = maxf(0.0, _state_flash - delta)
	var prompt := player.interact_prompt
	var key := ""
	if prompt.begins_with("["):
		var close := prompt.find("]")
		if close > 0:
			key = prompt.substr(1, close - 1)
			prompt = prompt.substr(close + 1).strip_edges()
	var interacting := not prompt.is_empty() and player.state in ["ok", "downed"]
	_reticle.progress = player.interact_progress
	_reticle.targeted = interacting
	_reticle.downed = player.state == "downed"
	_reticle.bleed = player.bleed_left / maxf(player.bleed_out_time, 0.01) if player.state == "downed" else 0.0
	_reticle.bleed_seconds = ceili(player.bleed_left)
	if interacting:
		_prompt.show_prompt(key, prompt.to_upper())
	elif player.state == "turned":
		_prompt.show_prompt(BroadcastUI.input_hint("fire"), "ATTACK", Color(0.55, 1.0, 0.3))
	_prompt.visible = interacting or player.state == "turned"
	var spectating := player.state == "out" and SpectatorView.has_target(get_tree(), player)
	_downed.visible = (player.state == "turned" and _state_flash > 0.0) or (player.state == "out" and not spectating)
	match player.state:
		"turned":
			_downed.text = "TURNED"
			_downed.add_theme_color_override("font_color", Color(0.55, 1.0, 0.3))
		"out":
			_downed.text = "OUT"
			_downed.add_theme_color_override("font_color", BroadcastUI.PINK)


func _update_damage(player: Player, delta: float) -> void:
	_damage_cue_left = maxf(0.0, _damage_cue_left - delta)
	if _last_health >= 0.0 and player.health < _last_health:
		_damage_left = 0.65
		_vitals_hot = 3.0
		if _damage_cue_left <= 0.0:
			Sound.play("player_hurt", -7.0)
			_damage_cue_left = 0.4
	if _last_suit >= 0.0 and _suit.value < _last_suit:
		_suit_flash = 0.5
	_last_health = player.health
	_last_suit = _suit.value
	_damage_left = maxf(0.0, _damage_left - delta)
	_suit_flash = maxf(0.0, _suit_flash - delta)
	_hurt.set_shader_parameter("strength", minf(_damage_left * 2.0, 0.85) * Settings.flash_scale())
	_acid.set_shader_parameter("strength", _suit_flash * 0.5 * Settings.flash_scale())


func _update_weapon(player: Player, delta: float) -> void:
	var holder := player.get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponHolder
	if holder != _holder:
		if _holder and is_instance_valid(_holder) and _holder.fired.is_connected(_on_fired):
			_holder.fired.disconnect(_on_fired)
		_holder = holder
		if holder:
			holder.fired.connect(_on_fired)
	_reticle.visible = player.state in ["ok", "turned", "downed"]
	_reticle.modulate.a = move_toward(_reticle.modulate.a, 0.0 if holder and holder.sighted() else 1.0, 0.2)
	_slots.visible = holder != null and player.state == "ok"
	if holder:
		_slots.refresh(holder)
		var slot_state := "%d|%s" % [holder.current, str(_slots.state_key())]
		if slot_state != _last_slot_state:
			if not _last_slot_state.is_empty():
				_hotbar_hot = 3.0
				_armory_hot = 3.0
				_name_left = 1.6
			_last_slot_state = slot_state
		# Belt pouch counts (frags / domes) wake the hotbar without re-showing the gun name.
		var pouch_state := str(_slots.pouch_key())
		if pouch_state != _last_pouch_state:
			if not _last_pouch_state.is_empty():
				_hotbar_hot = 3.0
			_last_pouch_state = pouch_state
	_hotbar_hot = maxf(0.0, _hotbar_hot - delta)
	_fade(_slots, _hotbar_hot > 0.0, 0.45, delta)
	var definition: ItemDefinition = holder.selected_definition() if holder else null
	_armory.visible = player.state == "ok" and definition != null
	_reticle.reload = 0.0
	_reticle.jammed = false
	if not _armory.visible:
		return
	var item: ItemInstance = holder.selected()
	var is_gun := definition.kind == ItemDefinition.Kind.GUN
	_name_left = maxf(0.0, _name_left - delta)
	_weapon.modulate.a = clampf(_name_left * 2.0, 0.0, 1.0)
	if _name_left > 0.0:
		_weapon.text = _unlock_name if not _unlock_name.is_empty() else definition.display_name.to_upper()
		var weapon_color := BroadcastUI.AMBER if not _unlock_name.is_empty() else ItemCatalog.tier_color(definition.id, item.tier)
		if _weapon.get_theme_color("font_color") != weapon_color:
			_weapon.add_theme_color_override("font_color", weapon_color)
	else:
		_unlock_name = ""
	var reloading := holder.reload_remaining() > 0.0
	var jammed := holder.jammed()
	var mag := maxi(1, definition.weapon.mag_size) if is_gun else 1
	var low := is_gun and item.count <= ceili(mag * 0.25)
	_ammo.text = str(item.count) if is_gun else "x%d" % item.count
	_reserve.text = "/ %d" % holder.selected_reserve() if is_gun else ""
	var ammo_color := BroadcastUI.PINK if jammed else (BroadcastUI.AMBER if low else BroadcastUI.PAPER)
	if _ammo.get_theme_color("font_color") != ammo_color:
		_ammo.add_theme_color_override("font_color", ammo_color)
	_pips.visible = is_gun
	_pips.rounds = item.count
	_pips.capacity = definition.weapon.mag_size if is_gun else 0
	_pips.reload_progress = 1.0 - holder.reload_remaining() / maxf(holder._reload_total, 0.01) if reloading else 0.0
	_reticle.reload = _pips.reload_progress
	_reticle.jammed = jammed
	if is_gun and item.count == 0 and not reloading and not jammed and holder.selected_reserve() > 0 and not _prompt.visible:
		_prompt.show_prompt(BroadcastUI.input_hint("reload"), "RELOAD", BroadcastUI.AMBER)
		_prompt.visible = true
	_armory_hot = maxf(0.0, _armory_hot - delta)
	_fade(_armory, _armory_hot > 0.0 or reloading or jammed or low, 0.35, delta)


## Show the compact stat card while the crosshair rests on a vending bay or
## ground pickup. The card only re-renders when the target signature changes.
func _update_item_card(player: Player) -> void:
	var info: Dictionary = {}
	if player.state == "ok" and not InventoryMenu.is_open() and not GameManager.is_voting():
		info = player.targeted_item_info()
	if info.is_empty():
		if _item_card.visible:
			_item_card.hide()
		_item_card_key = ""
		return
	var holder := _holder if is_instance_valid(_holder) else null
	var id := str(info.id)
	var tier := int(info.get("tier", 0))
	var price := int(info.get("price", 0))
	var scrap := holder.scrap if holder else 0
	info["scrap"] = scrap
	info["affordable"] = scrap >= price
	info["pouch_full"] = holder != null and holder.pouch_full(id)
	info["swap"] = holder != null and _needs_swap(holder, id, tier, int(info.get("count", 0)))
	var key := "%s|%d|%d|%s|%d|%d|%s|%s|%s" % [info.get("source", ""), id.hash(), tier, price, int(info.get("count", -1)),
		scrap if price > 0 else 0, info.affordable, info.pouch_full, info.swap]
	if key != _item_card_key:
		_item_card_key = key
		_item_card.configure(info)
		# Anchored controls only ever grow to their minimum size; drop the top
		# edge so a shorter card shrinks back (it grows upward from the bottom).
		_item_card.offset_top = _item_card.offset_bottom - 64.0
	if not _item_card.visible:
		_item_card.show()
		if not Settings.reduced_flash:
			BroadcastUI.reveal(_item_card)


## Mirrors WeaponHolder.needs_swap for an offer that has no ItemInstance yet.
func _needs_swap(holder: WeaponHolder, id: String, tier: int, count: int) -> bool:
	var definition := ItemCatalog.definition(id)
	if definition == null or ItemCatalog.is_pouch(id) or holder.slots.has(null):
		return false
	if definition.kind != ItemDefinition.Kind.GUN:
		var amount := count if count > 0 else definition.spawn_count
		for other in holder.slots:
			if other and other.id == id and other.tier == tier and other.count + amount <= definition.stack_cap:
				return false
	return true


func _on_fired(_data: WeaponData) -> void:
	_armory_hot = 2.5


func _update_teammates(local: Player) -> void:
	var seen := {}
	for other in get_tree().get_nodes_in_group("players"):
		if other == local:
			continue
		seen[other] = true
		if not _cards.has(other):
			var card := TeammateCard.instantiate() as PanelContainer
			var name_label := card.get_node("%Name") as Label
			BroadcastUI.hud_text(name_label, BroadcastUI.T_META)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			name_label.get_parent().add_child(row)
			name_label.get_parent().move_child(row, 0)
			name_label.reparent(row)
			var state_icon := _icon("health", BroadcastUI.PINK, 14.0)
			state_icon.name = "StateIcon"
			row.add_child(_ignore(state_icon))
			(card.get_node("%State") as Label).hide()
			BroadcastUI.thin_bar(card.get_node("%Health"), BroadcastUI.PINK)
			BroadcastUI.thin_bar(card.get_node("%Suit"), BroadcastUI.CYAN)
			_ignore(card)
			_teammates.add_child(card)
			_cards[other] = card
		var card: PanelContainer = _cards[other]
		var name_label := card.find_child("Name", true, false) as Label
		name_label.text = str(other.get("display_name")).to_upper()
		var suit_color: Variant = other.get("suit_color")
		name_label.add_theme_color_override("font_color", suit_color if suit_color is Color else BroadcastUI.PAPER)
		var hp := card.get_node("%Health") as ProgressBar
		hp.max_value = float(other.get("max_health"))
		hp.value = float(other.get("health"))
		(card.get_node("%Suit") as ProgressBar).value = float(other.get("suit_integrity"))
		var state := str(other.get("state"))
		var icon := card.find_child("StateIcon", true, false) as GameIcon
		icon.visible = state != "ok"
		match state:
			"downed":
				icon.kind = "health"
				icon.color = BroadcastUI.PINK
				icon.modulate.a = 1.0 if Settings.reduced_flash else 0.55 + 0.45 * sin(_clock * 8.0)
			"turned":
				icon.kind = "skull"
				icon.color = Color(0.55, 1.0, 0.3)
				icon.modulate.a = 1.0
			_:
				icon.kind = "skull"
				icon.color = BroadcastUI.MUTED
				icon.modulate.a = 1.0
		card.modulate.a = 0.45 if state == "out" else 1.0
	for gone in _cards.keys():
		if not seen.has(gone):
			_cards[gone].queue_free()
			_cards.erase(gone)
