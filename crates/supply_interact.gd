class_name SupplyInteract
extends Interactable

var mode := "station"

func _init() -> void:
	hold_time = 0.6
	radius = 2.8

func can_interact(player: Node) -> bool:
	return player.state == "ok" and get_parent().available(mode)

func get_prompt(player: Node) -> String:
	if mode == "airdrop":
		return "Open"
	var station := get_parent() as SupplyStation
	var offer := station.offer_for(mode)
	var cost: int = station.price if offer.is_empty() else offer[2]
	if mode == "double" and GameManager.player_count() < 2:
		return "Needs 2 players"
	if RunLoot.holder(player).scrap < cost:
		return "Need %d scrap" % cost
	var action_label := "Double or nothing"
	if not offer.is_empty():
		var item := ItemCatalog.definition(offer[0])
		action_label = "Buy %s" % item.display_name
		if item.spawn_count > 1:
			action_label += " ×%d" % item.spawn_count
	return "%s  %d scrap" % [action_label, cost]

func action(player: Node, step: String) -> void:
	var station := get_parent() as SupplyStation
	var offer := station.offer_for(mode)
	GameManager.crates.request_hold(station.key, mode, step, player, 0 if offer.is_empty() else offer[3])

func set_targeted(active: bool) -> void:
	var station := get_parent() as SupplyStation
	if station and mode in SupplyStation.OFFER_PADS:
		station.highlight_offer(mode, active)
	else:
		super.set_targeted(active)
