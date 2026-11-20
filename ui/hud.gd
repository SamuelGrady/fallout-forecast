extends CanvasLayer
## Local vitals, ammunition, team status and the current forecast.

const TeammateCard := preload("res://ui/teammate_card.tscn")
const WEATHER_COLORS := [BroadcastUI.CYAN, Color("#9fd8ff"), Color("#adbaff"), BroadcastUI.ACID]
const PHASE_NAMES := ["CLEAR", "MUTATION DRAFT", "DRIZZLE", "DOWNPOUR", "CLEARING"]

var _layout := Control.new()
var _health := ProgressBar.new()
var _suit := ProgressBar.new()
var _health_text := Label.new()
var _suit_text := Label.new()
var _equipment := Label.new()
var _suit_status := Label.new()
var _forecast := Label.new()
var _wave := Label.new()
var _wave_progress := ProgressBar.new()
var _combat := HBoxContainer.new()
var _combat_status := Label.new()
var _ready_hint := Label.new()
var _weather := GameIcon.new()
var _tape_counter := Label.new()
var _teammates := VBoxContainer.new()
var _cards := {}
var _enemy_icons := HFlowContainer.new()
var _squad_icons := HFlowContainer.new()
var _enemy_ids: Array = []
var _squad_ids: Array = []
var _armory: PanelContainer
var _weapon := Label.new()
var _ammo := Label.new()
var _pips := preload("res://ui/ammo_pips.gd").new()
var _slots := HBoxContainer.new()
var _unlock := Label.new()
var _unlock_left := 0.0
var _reticle := preload("res://ui/reticle.gd").new()
var _downed := Label.new()
var _prompt := Label.new()
var _revive_progress := ProgressBar.new()
var _banner := Label.new()
var _banner_left := 0.0
var _lightning := Label.new()
var _lightning_left := 0.0
var _last_countdown := -1
var _boss_panel: PanelContainer
var _boss_label := Label.new()
var _boss_bar := ProgressBar.new()
var _sacs: Array[ProgressBar] = []
var _last_health := -1.0
var _last_suit := -1.0
var _damage_left := 0.0
var _suit_flash := 0.0
var _damage_cue_left := 0.0
var _hurt := ShaderMaterial.new()
var _acid := ShaderMaterial.new()


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


func _panel_at(preset: Control.LayoutPreset, width: float, margin: Vector2, pivot: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(preset)
	panel.offset_left = margin.x - width * pivot.x
	panel.offset_right = panel.offset_left + width
	panel.offset_top = margin.y
	panel.offset_bottom = margin.y
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN if pivot.y > 0.0 else Control.GROW_DIRECTION_END
	panel.scale = Vector2.ONE * Settings.hud_scale
	panel.resized.connect(func(): panel.pivot_offset = panel.size * pivot)
	var style := BroadcastUI.panel(BroadcastUI.OVERLAY)
	style.set_content_margin_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", style)
	_layout.add_child(panel)
	return panel


func _column(parent: Control, spacing: int = 4) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box


func _row(parent: Control, row: HBoxContainer) -> void:
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)


func _bar(parent: Control, bar: ProgressBar, height: float, color: Color, max_value: float = 1.0) -> void:
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.max_value = max_value
	bar.step = 0.001
	bar.custom_minimum_size.y = height
	BroadcastUI.bar(bar, color)
	parent.add_child(bar)


func _build_forecast() -> void:
	var top := _column(_panel_at(Control.PRESET_CENTER_TOP, 396, Vector2(0, 78), Vector2(.5, 0)))
	var header := HBoxContainer.new()
	_row(top, header)
	_weather.kind = "weather"
	_weather.custom_minimum_size = Vector2(28, 28)
	header.add_child(_weather)
	BroadcastUI.text(_forecast, 27, BroadcastUI.CYAN)
	_forecast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_forecast)
	BroadcastUI.text(_wave, 23)
	header.add_child(_wave)
	_row(top, _combat)
	BroadcastUI.text(_combat_status, 19, BroadcastUI.MUTED)
	_combat.add_child(_combat_status)
	_wave_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar(_combat, _wave_progress, 6, BroadcastUI.CYAN)
	BroadcastUI.text(_ready_hint, 19, BroadcastUI.CYAN)
	_ready_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_ready_hint)

	_boss_panel = _panel_at(Control.PRESET_CENTER_TOP, 356, Vector2(0, 166), Vector2(.5, 0))
	var boss := _column(_boss_panel)
	BroadcastUI.text(_boss_label, 24, BroadcastUI.ACID)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss.add_child(_boss_label)
	_bar(boss, _boss_bar, 8, BroadcastUI.ACID)
	var sac_row := HBoxContainer.new()
	_row(boss, sac_row)
	for i in 3:
		var sac := ProgressBar.new()
		sac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar(sac_row, sac, 8, BroadcastUI.ACID)
		_sacs.append(sac)
	_boss_panel.hide()

	_tape_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_tape_counter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tape_counter.offset_right = -20
	_tape_counter.offset_top = 56
	_tape_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BroadcastUI.text(_tape_counter, roundi(24 * Settings.hud_scale), BroadcastUI.AMBER)
	BroadcastUI.back_label(_tape_counter, BroadcastUI.AMBER, 4)
	_layout.add_child(_tape_counter)

	_teammates.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_teammates.offset_left = 20
	_teammates.offset_top = -142
	_teammates.add_theme_constant_override("separation", 7)
	_teammates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.add_child(_teammates)


func _build_vitals() -> void:
	# Kept compact so a future ~360x64 bottom-center hotbar clears even at Large HUD scale.
	var box := _column(_panel_at(Control.PRESET_BOTTOM_LEFT, 232, Vector2(20, -20), Vector2(0, 1)))
	for row in [_enemy_icons, _squad_icons]:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("h_separation", 4)
		box.add_child(row)
		row.hide()
	BroadcastUI.text(_suit_status, 20, BroadcastUI.ACID)
	box.add_child(_suit_status)
	BroadcastUI.text(_suit_text, 22, BroadcastUI.CYAN)
	box.add_child(_suit_text)
	_suit.name = "SuitBar"
	_bar(box, _suit, 9, BroadcastUI.CYAN, 100.0)
	_suit.value = 100.0
	BroadcastUI.text(_health_text, 22, BroadcastUI.PINK)
	box.add_child(_health_text)
	_health.name = "HealthBar"
	_bar(box, _health, 9, BroadcastUI.PINK, 100.0)
	_health.value = 100.0
	BroadcastUI.text(_equipment, 19, BroadcastUI.MUTED)
	_equipment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_equipment)


func _build_armory() -> void:
	_armory = _panel_at(Control.PRESET_BOTTOM_RIGHT, 212, Vector2(-20, -20), Vector2(1, 1))
	var box := _column(_armory, 2)
	for label in [_unlock, _weapon, _ammo]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(label)
	BroadcastUI.text(_unlock, 18, BroadcastUI.AMBER)
	_unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unlock.hide()
	BroadcastUI.text(_weapon, 21)
	_weapon.clip_text = true
	_weapon.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BroadcastUI.text(_ammo, 38)
	_pips.custom_minimum_size.y = 20
	box.add_child(_pips)
	_row(box, _slots)
	_slots.alignment = BoxContainer.ALIGNMENT_END


func _build_messages() -> void:
	# Directly under the forecast panel, clear of the wave card (JuiceHud) and the draft strip.
	_notice(_banner, Control.PRESET_CENTER_TOP, 480, 158, 28, BroadcastUI.PAPER)
	_notice(_lightning, Control.PRESET_TOP_RIGHT, 224, 100, 19, BroadcastUI.CYAN)
	_notice(_downed, Control.PRESET_CENTER, 408, 48, 34, BroadcastUI.PINK)
	_notice(_prompt, Control.PRESET_CENTER_BOTTOM, 360, -112, 22, BroadcastUI.PAPER)
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_revive_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_revive_progress.offset_left = -100
	_revive_progress.offset_right = 100
	_revive_progress.offset_top = -102
	_revive_progress.offset_bottom = -94
	_bar(_layout, _revive_progress, 8, BroadcastUI.CYAN)
	_revive_progress.hide()


func _notice(label: Label, preset: Control.LayoutPreset, width: float, y: float, font_size: int, color: Color) -> void:
	label.set_anchors_and_offsets_preset(preset)
	label.offset_left = -width - 20 if preset == Control.PRESET_TOP_RIGHT else -width * .5
	label.offset_right = -20 if preset == Control.PRESET_TOP_RIGHT else width * .5
	label.offset_top = y
	label.offset_bottom = y
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BroadcastUI.text(label, roundi(font_size * Settings.hud_scale), color)
	BroadcastUI.back_label(label, color)
	label.hide()
	_layout.add_child(label)


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


func _show_banner(message: String, color: Color, seconds: float) -> void:
	_banner.text = message.replace("OBJECTIVE: ", "OBJECTIVE  /  ")
	_banner.add_theme_color_override("font_color", color)
	BroadcastUI.back_label(_banner, color)
	_banner_left = seconds


func _on_lightning(_at: Vector3, _seed: int) -> void:
	_lightning.text = "LIGHTNING  /  INFECTED REVEALED"
	_lightning_left = 2.0


func _show_unlock(weapon_name: String) -> void:
	_unlock.text = "UNLOCKED  /  " + weapon_name
	_unlock_left = 4.0


func _process(delta: float) -> void:
	_banner_left = maxf(0.0, _banner_left - delta)
	_lightning_left = maxf(0.0, _lightning_left - delta)
	_unlock_left = maxf(0.0, _unlock_left - delta)
	_banner.visible = _banner_left > 0.0
	_lightning.visible = _lightning_left > 0.0
	_unlock.visible = _unlock_left > 0.0
	_update_forecast()
	_update_mutations()
	_update_boss()
	var player := get_tree().get_first_node_in_group("local_player") as Player
	if player == null:
		return
	_update_vitals(player, delta)
	_update_weapon(player)
	_update_teammates(player)


func _update_forecast() -> void:
	var phase := WeatherManager.phase
	var state := WeatherManager.storm_state
	var seconds := maxi(0, ceili(WeatherManager.phase_time_left))
	var countdown := phase == WeatherManager.Phase.CALM and WeatherManager.running and seconds in [1, 2, 3, 4, 5]
	_forecast.text = ("STORM IN %d" % seconds) if countdown else PHASE_NAMES[phase]
	if state == WeatherManager.StormState.ACID_STORM and phase == WeatherManager.Phase.DOWNPOUR:
		_forecast.text = "ACID STORM"
	var accent: Color = BroadcastUI.AMBER if countdown else WEATHER_COLORS[state]
	if _weather.color != accent:
		_weather.color = accent
		_forecast.add_theme_color_override("font_color", accent)
	_weather.value = WeatherManager.storm_intensity
	if countdown and seconds != _last_countdown:
		Sound.play("storm_countdown", -15.0, lerpf(0.88, 1.16, (5.0 - seconds) / 4.0))
	_last_countdown = seconds if countdown else -1
	var wave := WeatherManager.wave
	var wave_text := "WAVE %d/%d" % [wave, WeatherManager.FINAL_WAVE]
	if GameManager.endless:
		wave_text = "ENDLESS %d" % (wave - WeatherManager.FINAL_WAVE)
	_wave.text = "%s   %d:%02d" % [wave_text, seconds / 60, seconds % 60]
	_tape_counter.visible = GameManager.endless
	if _tape_counter.visible:
		_tape_counter.text = "CNT  %08d" % GameManager.endless_score
	_ready_hint.visible = GameManager.can_ready_up()
	if _ready_hint.visible:
		_ready_hint.text = "[%s] READY" % BroadcastUI.input_hint("ready_up")
		if GameManager.player_count() > 1:
			_ready_hint.text += "  %d/%d" % [GameManager.ready_count, GameManager.player_count()]
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	var fighting := phase in [WeatherManager.Phase.DRIZZLE, WeatherManager.Phase.DOWNPOUR] and not GameManager.victory_locked
	var total: int = spawner.wave_total() if spawner and fighting else 0
	_combat.visible = total > 0
	if _combat.visible:
		var left: int = spawner.remaining()
		var recovery: float = spawner.recovery_time()
		_combat_status.text = "%d INFECTED LEFT" % left
		if recovery > 1.0:
			_combat_status.text += "   /   NEXT GROUP %ds" % ceili(recovery)
		_wave_progress.value = clampf(1.0 - float(left) / total, 0.0, 1.0)


func _update_mutations() -> void:
	var roll := GameManager.mutations
	if roll.active != _enemy_ids:
		_enemy_ids = roll.active.duplicate()
		_reset_icons(_enemy_icons, "INFECTED", BroadcastUI.PINK, not _enemy_ids.is_empty())
		for id in _enemy_ids:
			var entry: MutationData = roll.table.get_entry(id)
			if entry:
				_add_icon(_enemy_icons, id, entry.color, entry.display_name)
	if roll.player_mutations != _squad_ids:
		_squad_ids = roll.player_mutations.duplicate()
		_reset_icons(_squad_icons, "SQUAD", BroadcastUI.ACID, not _squad_ids.is_empty())
		for id in _squad_ids:
			if GameManager.PLAYER_MUTATIONS.has(id):
				var info: Dictionary = GameManager.PLAYER_MUTATIONS[id]
				_add_icon(_squad_icons, id, info.color, info.name)


func _reset_icons(row: HFlowContainer, heading: String, color: Color, shown: bool) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	row.visible = shown
	if shown:
		var label := Label.new()
		label.text = heading
		BroadcastUI.text(label, 17, color)
		row.add_child(label)


func _add_icon(row: HFlowContainer, id: String, color: Color, tip: String) -> void:
	var icon := GameIcon.new()
	icon.kind = id
	icon.custom_minimum_size = Vector2(22, 22)
	icon.color = color
	icon.tooltip_text = tip
	row.add_child(icon)


func _update_boss() -> void:
	var boss := get_tree().get_first_node_in_group("boss")
	var miniboss := get_tree().get_first_node_in_group("miniboss") if boss == null else null
	_boss_panel.visible = boss != null or miniboss != null
	if not _boss_panel.visible:
		return
	var sacs: bool = boss != null and not boss.core_exposed()
	_boss_bar.visible = not sacs
	for i in _sacs.size():
		_sacs[i].visible = sacs
		if sacs:
			_sacs[i].value = boss.part_health[i] / maxf(1.0, boss.part_max[i])
	if boss:
		_boss_label.text = "CUMULUS  /  BURNING" if boss.is_burning() else "CUMULUS"
		_boss_bar.value = boss.part_health[3] / maxf(1.0, boss.part_max[3])
	else:
		_boss_label.text = str(miniboss.get("miniboss_name")).to_upper()
		_boss_bar.value = float(miniboss.get("health")) / maxf(1.0, float(miniboss.get("max_health")))


func _update_vitals(player: Player, delta: float) -> void:
	_health.max_value = player.max_health
	_health.value = lerpf(_health.value, player.health, 1.0 - exp(-12.0 * delta))
	_suit.value = player.suit_integrity
	_suit_text.text = "SUIT  %d%%" % roundi(_suit.value)
	_health_text.text = "HEALTH  %d" % roundi(_health.value)
	_health.modulate = BroadcastUI.CYAN.lightened(.35) if player.invulnerable else Color.WHITE
	_update_damage(player, delta)
	var exposed := WeatherManager.is_raining() and player.exposed
	var protected := exposed and preload("res://weapons/projectile.gd").protects(player.global_position + Vector3.UP, get_tree())
	_suit_status.visible = exposed and player.state == "ok"
	_suit_status.text = "FLARE COVER" if protected else ("SUIT BREACH" if _suit.value < 25.0 else "EXPOSED TO RAIN")
	var status_color := BroadcastUI.CYAN if protected else (BroadcastUI.PINK if _suit.value < 25.0 else BroadcastUI.ACID)
	if _suit_status.get_theme_color("font_color") != status_color:
		_suit_status.add_theme_color_override("font_color", status_color)
	_equipment.text = "DECON  %d" % GameManager.decon_charges
	if player.has_tarp:
		_equipment.text += "   /   TARP [%s]" % BroadcastUI.input_hint("use_item")
	if GameManager.has_mutation("static_charge") and player.static_charge > 0.01:
		_equipment.text += "\nSTATIC  %d%%%s" % [roundi(player.static_charge * 100.0), "  READY" if player.static_charge >= 0.25 else ""]
	_prompt.text = player.interact_prompt.to_upper()
	_prompt.visible = not _prompt.text.is_empty() and player.state in ["ok", "downed"]
	_reticle.progress = player.interact_progress
	_reticle.targeted = _prompt.visible
	_revive_progress.visible = _prompt.visible and player.state == "downed" and player.interact_progress > 0.0
	_revive_progress.value = player.interact_progress
	_downed.visible = player.state in ["downed", "turned", "out"] and not (player.state == "out" and SpectatorView.has_target(get_tree(), player))
	match player.state:
		"downed": _downed.text = "DOWNED  /  %ds" % ceili(player.bleed_left)
		"turned": _downed.text = "TURNED  /  [%s] ATTACK" % ("RT" if Settings.using_gamepad else "LMB")
		"out": _downed.text = "OUT  /  BACK AT CLEARING"


func _update_damage(player: Player, delta: float) -> void:
	_damage_cue_left = maxf(0.0, _damage_cue_left - delta)
	if _last_health >= 0.0 and player.health < _last_health:
		_damage_left = 0.65
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


func _update_weapon(player: Player) -> void:
	var holder := player.get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponHolder
	_armory.visible = player.state == "ok" and holder != null and not holder.loadout.is_empty()
	_reticle.visible = player.state in ["ok", "turned"]
	_reticle.modulate.a = move_toward(_reticle.modulate.a, 0.0 if holder and holder.sighted() else 1.0, 0.2)
	if not _armory.visible:
		return
	var weapon: WeaponData = holder.loadout[holder.current]
	_weapon.text = weapon.display_name.to_upper()
	var weapon_color := BroadcastUI.PINK if weapon.cursed else BroadcastUI.PAPER
	if _weapon.get_theme_color("font_color") != weapon_color:
		_weapon.add_theme_color_override("font_color", weapon_color)
	_ammo.text = "%d / %d" % [holder.ammo[holder.current], holder.reserve[holder.current]]
	_pips.rounds = holder.ammo[holder.current]
	_pips.capacity = weapon.mag_size
	_pips.reload_progress = 1.0 - holder._reload_left / maxf(holder._reload_total, 0.01) if holder._reload_left > 0 else 0.0
	if _slots.get_child_count() != holder.loadout.size():
		for child in _slots.get_children():
			_slots.remove_child(child)
			child.queue_free()
		for i in holder.loadout.size():
			var slot := Label.new()
			slot.text = str(i + 1)
			BroadcastUI.text(slot, 20)
			_slots.add_child(slot)
	for i in _slots.get_child_count():
		var slot := _slots.get_child(i) as Label
		slot.modulate = (BroadcastUI.AMBER if _unlock_left > 0.0 else BroadcastUI.CYAN) if i == holder.current else BroadcastUI.MUTED


func _update_teammates(local: Player) -> void:
	var seen := {}
	for other in get_tree().get_nodes_in_group("players"):
		if other == local:
			continue
		seen[other] = true
		if not _cards.has(other):
			var card := TeammateCard.instantiate() as PanelContainer
			var style := BroadcastUI.panel(BroadcastUI.OVERLAY, BroadcastUI.MUTED)
			style.set_content_margin_all(8)
			card.add_theme_stylebox_override("panel", style)
			BroadcastUI.text(card.get_node("%Name") as Label, 19, BroadcastUI.PAPER)
			BroadcastUI.text(card.get_node("%State") as Label, 18, BroadcastUI.PINK)
			BroadcastUI.bar(card.get_node("%Health"), BroadcastUI.PINK)
			BroadcastUI.bar(card.get_node("%Suit"), BroadcastUI.CYAN)
			_teammates.add_child(card)
			_cards[other] = card
		var card: PanelContainer = _cards[other]
		var name_label := card.get_node("%Name") as Label
		name_label.text = str(other.get("display_name")).to_upper()
		var hp := card.get_node("%Health") as ProgressBar
		hp.max_value = float(other.get("max_health"))
		hp.value = float(other.get("health"))
		(card.get_node("%Suit") as ProgressBar).value = float(other.get("suit_integrity"))
		var state := str(other.get("state"))
		var state_label := card.get_node("%State") as Label
		state_label.visible = state != "ok"
		state_label.text = state.to_upper()
	for gone in _cards.keys():
		if not seen.has(gone):
			_cards[gone].queue_free()
			_cards.erase(gone)
