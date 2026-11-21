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
	var cost: int = get_parent().price
	if mode == "double" and GameManager.player_count() < 2:
		return "Needs 2 players"
	if RunLoot.holder(player).scrap < cost:
		return "Need %d scrap" % cost
	return "%s  %d scrap" % ["Double or nothing" if mode == "double" else "Roll", cost]

func action(player: Node, step: String) -> void:
	GameManager.crates.request_hold(get_parent().key, mode, step, player)
