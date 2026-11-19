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
var _last_health := -1.0
var _hurt := ColorRect.new()
var _downed := Label.new()
var _prompt := Label.new()
var _progress := ProgressBar.new()
var _decon := Label.new()
var _banner := Label.new()
var _banner_left := 0.0
var _tarp := Label.new()


func _ready() -> void:
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt.color = Color(0.8, 0.05, 0.05, 0.0)
	add_child(_hurt)
	move_child(_hurt, 0)
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

	_decon.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_decon.position = Vector2(28, 0)
	_decon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_decon.offset_left = 28
	_decon.offset_top = -205
	_style(_decon, 16, Color(0.4, 1, 0.9))
	add_child(_decon)
	_tarp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_tarp.offset_left = 28
	_tarp.offset_top = -228
	_style(_tarp, 16, Color(0.6, 0.8, 1))
	add_child(_tarp)

	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = -140
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(_banner, 44, Color.WHITE)
	_banner.visible = false
	add_child(_banner)
	GameManager.banner.connect(_show_banner)


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


func _process(delta: float) -> void:
	_time += delta
	var player := get_tree().get_first_node_in_group("local_player")
	_update_storm()
	if player == null:
		return
	_update_vitals(player)
	_update_weapon(player)
	_update_teammates(player)


func _update_storm() -> void:
	storm_label.text = WeatherManager.storm_name().to_upper()
	storm_label.modulate = STORM_COLORS[WeatherManager.storm_state]
	var seconds := ceili(WeatherManager.phase_time_left)
	wave_label.text = "WAVE %d / %d  ·  %s  ·  %d:%02d" % [
		WeatherManager.wave, WeatherManager.FINAL_WAVE, WeatherManager.phase_name().to_upper(),
		seconds / 60, seconds % 60]


func _update_vitals(player: Node) -> void:
	health_bar.max_value = _num(player, "max_health", 100.0)
	health_bar.value = _num(player, "health", health_bar.max_value)
	if _last_health >= 0.0 and health_bar.value < _last_health:
		_hurt.color.a = clampf(_hurt.color.a + 0.25, 0.0, 0.45)
	_last_health = health_bar.value
	_hurt.color.a = move_toward(_hurt.color.a, 0.0, get_process_delta_time() * 1.2)
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
	_progress.visible = float(player.get("interact_progress")) > 0.0
	_progress.value = float(player.get("interact_progress"))
	_decon.text = "DECON CHARGES  %d" % GameManager.decon_charges
	_tarp.text = ("TARP UP [T]" if player.get("tarp_raised") else "TARP READY [T]") if player.get("has_tarp") else ""
	if _banner_left > 0.0:
		_banner_left -= get_process_delta_time()
		_banner.visible = _banner_left > 0.0
	suit_bar.value = _num(player, "suit_integrity", 100.0)
	var exposed_in_rain: bool = player.get("exposed") != false and WeatherManager.is_raining()
	exposed_label.visible = exposed_in_rain
	if exposed_in_rain:
		exposed_label.modulate.a = 0.55 + 0.45 * sin(_time * 8.0)


func _update_weapon(player: Node) -> void:
	var weapon = player.get("weapon_name")
	weapon_label.visible = weapon != null
	ammo_label.visible = weapon != null and player.get("ammo") != null
	if weapon != null:
		weapon_label.text = str(weapon).to_upper()
	if ammo_label.visible:
		var max_ammo = player.get("max_ammo")
		ammo_label.text = str(player.get("ammo")) + ("" if max_ammo == null else " / %s" % max_ammo)


func _update_teammates(local: Node) -> void:
	var seen := {}
	for other in get_tree().get_nodes_in_group("players"):
		if other == local:
			continue
		seen[other] = true
		if not _cards.has(other):
			var card := TeammateCard.instantiate()
			teammates.add_child(card)
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
