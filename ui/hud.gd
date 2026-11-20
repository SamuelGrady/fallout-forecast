extends CanvasLayer
## Run HUD (design doc "UI and game flow"):
## - bottom left: health and suit integrity bars, EXPOSED warning that flashes in rain
## - bottom right: weapon and ammo (shown once the player has them)
## - top center: storm state, wave number and phase timer
## - left edge: one card per teammate with name, health, suit, downed/Turned state
##
## It reads plain properties off Player nodes and falls back to defaults when
## a property doesn't exist yet: health, max_health, suit_integrity,
## display_name, state ("ok", "downed", "turned"), weapon_name, ammo, max_ammo.
## Week 3 restyles it with the pixel font.

const TeammateCard := preload("res://ui/teammate_card.tscn")

const STORM_COLORS := [Color(0.75, 0.85, 0.9), Color(0.6, 0.8, 1.0), Color(0.45, 0.6, 1.0), Color(0.5, 1.0, 0.35)]

@onready var health_bar: ProgressBar = %HealthBar
@onready var suit_bar: ProgressBar = %SuitBar
@onready var exposed_label: Label = %ExposedLabel
@onready var storm_label: Label = %StormLabel
@onready var wave_label: Label = %WaveLabel
@onready var weapon_label: Label = %WeaponLabel
@onready var ammo_label: Label = %AmmoLabel
@onready var teammates: VBoxContainer = %Teammates

var _cards := {}
var _time := 0.0
var _combat_status := Label.new()
var _hit_marker := Control.new()
var _weather := GameIcon.new()
var _enemy_icon := GameIcon.new()
var _exposure := GameIcon.new()
var _tarp_icon := GameIcon.new()
var _regen := GameIcon.new()
var _active_icons := HBoxContainer.new()
var _active_ids: Array = []
var _breather := ProgressBar.new()
var _pips := Control.new()
var _slots := HBoxContainer.new()
var _unlock_box := HBoxContainer.new()
var _unlock_label := Label.new()
var _unlock_left := 0.0
var _last_weapon := ""
var _weapon_name_left := 0.0
var _sac_bars: Array[ProgressBar] = []
var _hit_time := 0.0
var _last_health := -1.0
var _damage_left := 0.0
var _last_suit := -1.0
var _suit_flash := 0.0
var _acid := ColorRect.new()
var _damage_cue_left := 0.0
var _damage_label := Label.new()
var _hurt := ColorRect.new()
var _downed := Label.new()
var _prompt := Label.new()
var _progress := ProgressBar.new()
var _decon := Label.new()
var _banner := Label.new()
var _banner_left := 0.0
var _tarp := Label.new()
var _mutation := Label.new()
var _boss_label := Label.new()
var _boss_bar := ProgressBar.new()


## Lightning outlines every infected within 40 m through walls for 2 s
## (LightningFX). The playtest didn't know that, so each strike says so.
func _on_lightning(_at: Vector3, _seed: int) -> void:
	var tip := Label.new()
	tip.text = "LIGHTNING  -  INFECTED REVEALED THROUGH WALLS"
	tip.theme = BroadcastUI.theme()
	tip.add_theme_font_size_override("font_size", 22)
	tip.add_theme_color_override("font_color", Color("#9fe8ff"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tip.offset_left = -320
	tip.offset_right = 320
	tip.offset_top = 112
	add_child(tip)
	var tween := tip.create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(tip, "modulate:a", 0.0, 0.5)
	tween.tween_callback(tip.queue_free)


var _countdown_label: Label
var _last_countdown := -1


## Big "STORM IN 5..1" in the last seconds of Calm, with a tick each second,
## so the start of a wave is never a surprise.
func _update_storm_countdown(seconds: int) -> void:
	if _countdown_label == null:
		_countdown_label = Label.new()
		_countdown_label.theme = BroadcastUI.theme()
		_countdown_label.add_theme_font_size_override("font_size", 46)
		_countdown_label.add_theme_color_override("font_color", Color("#ffb04a"))
		_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_countdown_label.offset_left = -300
		_countdown_label.offset_right = 300
		_countdown_label.offset_top = 150
		add_child(_countdown_label)
	var show := WeatherManager.phase == WeatherManager.Phase.CALM and WeatherManager.running and seconds <= 5 and seconds > 0
	_countdown_label.visible = show
	if show:
		_countdown_label.text = "STORM IN  %d" % seconds
		if seconds != _last_countdown:
			Sound.play("reel_tick", -6.0, 0.8)
	_last_countdown = seconds if show else -1


func _ready() -> void:
	WeatherManager.lightning_struck.connect(_on_lightning)
	_combat_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_combat_status.offset_left = -280
	_combat_status.offset_right = 280
	_combat_status.offset_top = 88
	_combat_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_combat_status, 18, BroadcastUI.CYAN)
	add_child(_combat_status)
	_hit_marker.set_script(preload("res://ui/reticle.gd"))
	_hit_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hit_marker)
	$Crosshair.visible = false
	GameManager.combat_hit.connect(_hit_marker.hit)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt.color = Color.WHITE
	var damage_material := ShaderMaterial.new()
	damage_material.shader = preload("res://ui/damage.gdshader")
	_hurt.material = damage_material
	add_child(_hurt)
	move_child(_hurt, 0)
	_acid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_acid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var acid_material := ShaderMaterial.new()
	acid_material.shader = preload("res://ui/damage.gdshader")
	acid_material.set_shader_parameter("tint", Vector3(0.65, 1.0, 0.08))
	_acid.material = acid_material
	add_child(_acid)
	move_child(_acid, 0)
	_damage_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_damage_label.offset_left = -180
	_damage_label.offset_right = 180
	_damage_label.offset_top = 65
	_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_damage_label.text = ""
	_style(_damage_label, 28, Color("#ff6b77"))
	add_child(_damage_label)
	_downed.text = "DOWNED"
	_downed.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_downed.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_downed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed.add_theme_font_size_override("font_size", 48)
	_downed.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
	_downed.add_theme_color_override("font_outline_color", Color.BLACK)
	_downed.add_theme_constant_override("outline_size", 8)
	_downed.position.y += 60
	_downed.visible = false
	add_child(_downed)

	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = -170
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_prompt, 22, Color(1, 1, 0.85))
	add_child(_prompt)
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_progress.custom_minimum_size = Vector2(220, 8)
	_progress.offset_left = -110
	_progress.offset_right = 110
	_progress.offset_top = -136
	_progress.offset_bottom = -128
	_progress.show_percentage = false
	_progress.max_value = 1.0
	add_child(_progress)

	_decon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_decon.offset_left = 56
	_decon.offset_right = 150
	_decon.offset_top = -174
	_decon.offset_bottom = -148
	_style(_decon, 18, Color(0.4, 1, 0.9))
	add_child(_decon)
	_tarp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_tarp.offset_left = 56
	_tarp.offset_right = 150
	_tarp.offset_top = -204
	_tarp.offset_bottom = -178
	_style(_tarp, 18, Color(0.6, 0.8, 1))
	add_child(_tarp)

	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -140
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_banner, 44, Color.WHITE)
	_banner.visible = false
	add_child(_banner)
	GameManager.banner.connect(_show_banner)
	GameManager.weapon_unlocked.connect(_on_weapon_unlocked)
	_mutation.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_mutation.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mutation.offset_top = 114
	_mutation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_mutation, 16, Color("FF3EA5"))
	add_child(_mutation)
	_boss_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_label.offset_top = 140
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_boss_label, 18, Color("8FD65A"))
	add_child(_boss_label)
	_boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_bar.offset_left = -260
	_boss_bar.offset_right = 260
	_boss_bar.offset_top = 168
	_boss_bar.offset_bottom = 182
	_boss_bar.show_percentage = false
	_boss_bar.max_value = 1.0
	var fill := StyleBoxFlat.new(); fill.bg_color = Color("8FD65A")
	_boss_bar.add_theme_stylebox_override("fill", fill)
	add_child(_boss_bar)
	for child in get_children():
		BroadcastUI.apply(child)
	BroadcastUI.bar(health_bar, BroadcastUI.PINK)
	BroadcastUI.bar(_boss_bar, Color("#b8e56d"))
	for box in [$BottomLeft, $BottomRight, $TopCenter]:
		var backing := Panel.new()
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backing.offset_left = -14
		backing.offset_top = -10
		backing.offset_right = 14
		backing.offset_bottom = 10
		backing.add_theme_stylebox_override("panel", BroadcastUI.panel(Color(0.03, 0.06, 0.1, 0.86)))
		box.add_child(backing)
		backing.show_behind_parent = true
		box.add_theme_constant_override("separation", 6)
	storm_label.add_theme_font_size_override("font_size", 36)
	ammo_label.add_theme_font_size_override("font_size", 48)
	_build_visual_status()


func _exit_tree() -> void:
	if GameManager.combat_hit.is_connected(_hit_marker.hit):
		GameManager.combat_hit.disconnect(_hit_marker.hit)
	if GameManager.banner.is_connected(_show_banner):
		GameManager.banner.disconnect(_show_banner)
	if GameManager.weapon_unlocked.is_connected(_on_weapon_unlocked):
		GameManager.weapon_unlocked.disconnect(_on_weapon_unlocked)


func _style(l: Label, size: int, color: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)


func _show_banner(text: String, color: Color, seconds: float) -> void:
	_banner.text = text
	_banner.modulate = color
	_banner.visible = true
	_banner_left = seconds


func _on_weapon_unlocked(weapon_name: String) -> void:
	_unlock_label.text = weapon_name
	_unlock_box.visible = true
	_unlock_left = 4.0
	_weapon_name_left = 4.0
	BroadcastUI.reveal(_unlock_box)


func _process(delta: float) -> void:
	_time += delta
	_weapon_name_left = maxf(0.0, _weapon_name_left - delta)
	if _unlock_left > 0.0:
		_unlock_left = maxf(0.0, _unlock_left - delta)
		if _unlock_left <= 0.0:
			_unlock_box.visible = false
	var player := get_tree().get_first_node_in_group("local_player")
	_update_storm()
	if player == null:
		return
	_update_vitals(player)
	_update_weapon(player)
	_update_teammates(player)


func _update_storm() -> void:
	var spawner := get_parent().get_node_or_null("Enemies")
	var combat := WeatherManager.phase in [WeatherManager.Phase.DRIZZLE,WeatherManager.Phase.DOWNPOUR]
	_enemy_icon.visible = spawner != null and combat
	_combat_status.text = str(spawner.remaining()) if spawner and combat else ""
	storm_label.visible = false
	var seconds := maxi(0,ceili(WeatherManager.phase_time_left))
	wave_label.text = "WAVE %d / %d    %d:%02d" % [WeatherManager.wave,WeatherManager.FINAL_WAVE,seconds/60,seconds%60]
	_update_storm_countdown(seconds)
	if GameManager.can_ready_up():
		var hint := "[%s] READY" % BroadcastUI.input_hint("ready_up")
		if GameManager.player_count() > 1:
			hint += " %d/%d" % [GameManager.ready_count, GameManager.player_count()]
		wave_label.text += "    " + hint
	_weather.value = WeatherManager.storm_intensity
	_weather.color = STORM_COLORS[WeatherManager.storm_state]
	_breather.visible = spawner != null and combat and spawner._timer > 1.0
	if _breather.visible:
		var breather_max: float = spawner.drizzle_breather if WeatherManager.phase == WeatherManager.Phase.DRIZZLE else spawner.downpour_breather
		_breather.value = clampf(spawner._timer / maxf(breather_max, 0.1), 0.0, 1.0)
	var active: Array = GameManager.mutations.active
	if active != _active_ids:
		_active_ids = active.duplicate()
		for old in _active_icons.get_children():
			old.queue_free()
		for id in active:
			var icon := GameIcon.new()
			icon.kind = id
			icon.custom_minimum_size = Vector2(36,36)
			icon.color = GameManager.mutations.table.get_entry(id).color
			icon.tooltip_text = GameManager.mutations.table.get_entry(id).description
			_active_icons.add_child(icon)
	_mutation.visible = false
	var boss := get_tree().get_first_node_in_group("boss")
	_boss_label.visible = boss != null
	_boss_bar.visible = boss != null and boss.core_exposed()
	_regen.visible = boss != null and boss.is_burning()
	for i in _sac_bars.size():
		_sac_bars[i].visible = boss != null and not boss.core_exposed()
		if boss:
			_sac_bars[i].value = boss.part_health[i]/maxf(1,boss.part_max[i])
	if boss:
		_boss_label.text = "CUMULUS"
		_boss_bar.value = boss.part_health[3]/maxf(1,boss.part_max[3])


func _update_vitals(player: Node) -> void:
	health_bar.max_value = _num(player, "max_health", 100.0)
	var actual_health := _num(player, "health", health_bar.max_value)
	health_bar.value = lerpf(health_bar.value, actual_health, 1.0 - exp(-12.0 * get_process_delta_time()))
	var delta := get_process_delta_time()
	_damage_cue_left = maxf(0.0, _damage_cue_left - delta)
	if _last_health >= 0.0 and actual_health < _last_health:
		_damage_left = 0.65
		if _damage_cue_left <= 0.0:
			Sound.play("player_hurt", -7.0)
			_damage_cue_left = 0.4
	_last_health = actual_health
	_damage_left = maxf(0.0, _damage_left - delta)
	(_hurt.material as ShaderMaterial).set_shader_parameter("strength", minf(_damage_left * 2.0, 0.85))
	_damage_label.visible = false
	var state := str(player.get("state"))
	_downed.visible = state != "ok"
	match state:
		"downed":
			_downed.text = "DOWNED  %ds" % ceili(float(player.get("bleed_left")))
		"turned":
			_downed.text = "TURNED: hunt your old team (LMB)"
		"out":
			_downed.text = "OUT until Clearing"
	_prompt.text = str(player.get("interact_prompt"))
	# Show the hold bar while a hold interaction (decon, revive, crate) fills.
	_progress.visible = float(player.get("interact_progress")) > 0.0
	_hit_marker.progress = float(player.get("interact_progress"))
	_hit_marker.targeted = not str(player.get("interact_prompt")).is_empty()
	_progress.value = float(player.get("interact_progress"))
	_decon.text = str(GameManager.decon_charges)
	_tarp.text = "[%s]" % BroadcastUI.input_hint("use_item") if player.get("has_tarp") else ""
	_tarp_icon.visible = player.get("has_tarp")
	_tarp_icon.value = lerpf(_tarp_icon.value,1.0 if player.get("tarp_raised") else 0.0,0.15)
	if _banner_left > 0.0:
		_banner_left -= get_process_delta_time()
		_banner.visible = _banner_left > 0.0
	suit_bar.value = _num(player, "suit_integrity", 100.0)
	if _last_suit >= 0.0 and suit_bar.value < _last_suit:
		_suit_flash = 0.5
	_last_suit = suit_bar.value
	_suit_flash = maxf(0.0, _suit_flash - delta)
	(_acid.material as ShaderMaterial).set_shader_parameter("strength", _suit_flash * (0.5 + 0.12 * sin(_time * 18.0)))
	$BottomLeft/SuitText.text = "SUIT  %d%%" % int(suit_bar.value)
	$BottomLeft/HealthText.text = "HEALTH  %d" % int(health_bar.value)
	var exposed_in_rain: bool = player.get("exposed") != false and WeatherManager.is_raining()
	exposed_label.visible = false
	_exposure.visible = exposed_in_rain
	var protected: bool = preload("res://weapons/projectile.gd").protects(player.global_position+Vector3.UP,get_tree())
	_exposure.kind = "suit" if protected else "weather"
	_exposure.color = BroadcastUI.CYAN if protected else Color("#b8e56d")
	_exposure.value = 1.0
	_exposure.modulate.a = 1.0 if protected else .65 + .35*sin(_time*6)



func _update_weapon(player: Node) -> void:
	var holder := player.get_node_or_null("Head/Camera3D/WeaponHolder")
	if holder == null or holder.loadout.is_empty():
		weapon_label.visible = false
		ammo_label.visible = false
		return
	var weapon: WeaponData = holder.loadout[holder.current]
	# The red dot or bead is the aim point while sighted; hide the crosshair.
	_hit_marker.modulate.a = move_toward(_hit_marker.modulate.a, 0.0 if holder.sighted() else 1.0, 0.2)
	if _last_weapon != weapon.resource_path:
		_last_weapon = weapon.resource_path
		_weapon_name_left = 3.0
	weapon_label.text = weapon.display_name.to_upper()
	weapon_label.visible = _weapon_name_left > 0.0
	ammo_label.visible = true
	ammo_label.text = "%d / %d" % [holder.ammo[holder.current],holder.reserve[holder.current]]
	_pips.rounds = holder.ammo[holder.current]
	_pips.capacity = weapon.mag_size
	_pips.reload_progress = 1.0-holder._reload_left/maxf(holder._reload_total,0.01) if holder._reload_left > 0 else 0.0
	if _slots.get_child_count() != holder.loadout.size():
		for child in _slots.get_children():
			_slots.remove_child(child)
			child.queue_free()
		for i in holder.loadout.size():
			var slot := Label.new()
			slot.text = str(i+1)
			slot.custom_minimum_size = Vector2(34,30)
			slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_slots.add_child(slot)
	for i in _slots.get_child_count():
		var active_slot: bool = i == holder.current
		_slots.get_child(i).modulate = Color("#ffe066") if (active_slot and _unlock_left > 0.0) else (BroadcastUI.CYAN if active_slot else Color(1,1,1,.3))


func _update_teammates(local: Node) -> void:
	var seen := {}
	for other in get_tree().get_nodes_in_group("players"):
		if other == local:
			continue
		seen[other] = true
		if not _cards.has(other):
			var card := TeammateCard.instantiate()
			teammates.add_child(card)
			BroadcastUI.apply(card)
			BroadcastUI.bar(card.get_node("%Health"),BroadcastUI.PINK)
			card.get_node("%Health").custom_minimum_size.y = 6
			card.get_node("%Suit").custom_minimum_size.y = 10
			_cards[other] = card
		var c: Control = _cards[other]
		var display = other.get("display_name")
		c.get_node("%Name").text = str(display if display != null else other.name).to_upper()
		var hp: ProgressBar = c.get_node("%Health")
		hp.max_value = _num(other, "max_health", 100.0)
		hp.value = _num(other, "health", hp.max_value)
		(c.get_node("%Suit") as ProgressBar).value = _num(other, "suit_integrity", 100.0)
		var state := str(other.get("state")) if other.get("state") != null else "ok"
		var state_label: Label = c.get_node("%State")
		state_label.visible = state != "ok"
		state_label.text = state.to_upper()
	for gone in _cards.keys():
		if not seen.has(gone):
			_cards[gone].queue_free()
			_cards.erase(gone)


func _num(node: Node, property: String, fallback: float) -> float:
	var value = node.get(property)
	return float(value) if value != null else fallback


func _build_visual_status() -> void:
	_combat_status.offset_left = 100
	_combat_status.offset_right = 160
	_combat_status.offset_top = 24
	_combat_status.add_theme_font_size_override("font_size",24)
	$TopCenter.offset_top = 26
	_weather.kind = "weather"
	_weather.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_weather.offset_left = -175
	_weather.offset_top = 14
	_weather.size = Vector2(48,48)
	add_child(_weather)
	_enemy_icon.kind = "enemy"
	_enemy_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_enemy_icon.offset_left = 75
	_enemy_icon.offset_top = 20
	_enemy_icon.size = Vector2(28,28)
	_enemy_icon.visible = false
	add_child(_enemy_icon)
	_breather.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_breather.offset_left = -110
	_breather.offset_right = 110
	_breather.offset_top = 60
	_breather.offset_bottom = 64
	_breather.max_value = 1
	_breather.show_percentage = false
	BroadcastUI.bar(_breather,BroadcastUI.CYAN)
	add_child(_breather)
	_active_icons.position = Vector2(28,82)
	add_child(_active_icons)
	_exposure.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_exposure.offset_left = 356
	_exposure.offset_top = -94
	_exposure.size = Vector2(36,36)
	add_child(_exposure)
	for spec in [
		["health", $BottomLeft/HealthText, Vector2(0, -1), BroadcastUI.PINK],
		["suit", $BottomLeft/SuitText, Vector2(0, -1), BroadcastUI.CYAN],
		["shower", _decon, Vector2(-28, 0), BroadcastUI.CYAN],
	]:
		var icon := GameIcon.new()
		icon.kind = spec[0]
		icon.color = spec[3]
		icon.position = spec[2]
		icon.size = Vector2(22,22)
		spec[1].add_child(icon)
		if spec[1] is Label and spec[2] == Vector2(0, -1):
			# Real gutter for the icon instead of padding the number with spaces
			# (the playtest found the icons overlapping zero-padded numbers).
			var gutter := StyleBoxEmpty.new()
			gutter.content_margin_left = 30
			spec[1].add_theme_stylebox_override("normal", gutter)
	_tarp_icon.kind = "tarp"
	_tarp_icon.color = Color(0.6, 0.85, 1.0)
	_tarp_icon.position = Vector2(-28,0)
	_tarp_icon.size = Vector2(22,22)
	_tarp.add_child(_tarp_icon)
	_pips.set_script(preload("res://ui/ammo_pips.gd"))
	_pips.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_pips.offset_left = -230
	_pips.offset_right = -28
	_pips.offset_top = -25
	_pips.offset_bottom = -4
	add_child(_pips)
	_slots.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_slots.offset_left = -230
	_slots.offset_right = -28
	_slots.offset_top = -170
	_slots.offset_bottom = -138
	_slots.alignment = BoxContainer.ALIGNMENT_END
	add_child(_slots)
	_unlock_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_unlock_box.offset_left = -260
	_unlock_box.offset_right = -28
	_unlock_box.offset_top = -206
	_unlock_box.offset_bottom = -176
	_unlock_box.alignment = BoxContainer.ALIGNMENT_END
	_unlock_box.add_theme_constant_override("separation", 8)
	_unlock_box.visible = false
	var unlock_icon := GameIcon.new()
	unlock_icon.kind = "unlock"
	unlock_icon.color = Color("#ffe066")
	unlock_icon.custom_minimum_size = Vector2(24, 24)
	_unlock_box.add_child(unlock_icon)
	_style(_unlock_label, 20, Color("#ffe066"))
	_unlock_box.add_child(_unlock_label)
	add_child(_unlock_box)
	_boss_label.offset_top = 84
	_boss_bar.offset_top = 120
	_boss_bar.offset_bottom = 132
	for i in 3:
		var bar := ProgressBar.new()
		bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		bar.offset_left = -200+i*136
		bar.offset_right = bar.offset_left+128
		bar.offset_top = 120
		bar.offset_bottom = 132
		bar.max_value = 1
		bar.show_percentage = false
		BroadcastUI.bar(bar,Color("#b8e56d"))
		add_child(bar)
		_sac_bars.append(bar)
	_regen.kind = "regen"
	_regen.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_regen.offset_left = 210
	_regen.offset_top = 88
	_regen.size = Vector2(30,30)
	add_child(_regen)
