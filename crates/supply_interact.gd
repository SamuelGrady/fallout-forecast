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
	if mode == "ammo":
		var ammo_holder := RunLoot.holder(player)
		if not ammo_holder.can_collect_ammo():
			return "Ammo FULL"
		if ammo_holder.scrap < SupplyStation.AMMO_PRICE:
			return "Need %d scrap" % SupplyStation.AMMO_PRICE
		return "Buy Ammo Refill  %d scrap" % SupplyStation.AMMO_PRICE
	var offer := station.offer_for(mode)
	if offer.is_empty():
		return ""
	var cost: int = offer[2]
	var holder := RunLoot.holder(player)
	if ItemCatalog.is_pouch(offer[0]) and holder.pouch_full(offer[0]):
		var full_item := ItemCatalog.definition(offer[0])
		var cap := ItemCatalog.pouch_cap(offer[0])
		return "%s pouch FULL (%d/%d)" % [full_item.display_name, cap, cap]
	if holder.scrap < cost:
		return "Need %d scrap" % cost
	var item := ItemCatalog.definition(offer[0])
	var action_label := "Buy %s" % item.display_name
	if item.spawn_count > 1:
		action_label += " ×%d" % item.spawn_count
	return "%s  %d scrap" % [action_label, cost]

func action(player: Node, step: String) -> void:
	var station := get_parent() as SupplyStation
	var offer := station.offer_for(mode)
	GameManager.crates.request_hold(station.key, mode, step, player, 0 if offer.is_empty() else offer[3])

func set_targeted(active: bool) -> void:
	var station := get_parent() as SupplyStation
	if station and (mode in SupplyStation.OFFER_PADS or mode == "ammo"):
		station.highlight_offer(mode, active)
	else:
		super.set_targeted(active)
