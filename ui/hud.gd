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
