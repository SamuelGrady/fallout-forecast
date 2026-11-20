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
		return "Open supply drop"
	var cost: int = get_parent().price
	if mode == "double" and GameManager.player_count() < 2:
		return "Double or nothing · NEEDS 2 PLAYERS"
	var verb := "Double or nothing (2P)" if mode == "double" else "Roll surplus"
	var missing := RunLoot.holder(player).scrap < cost
	return "%s · %d SCRAP%s" % [verb, cost, " • NEED SCRAP" if missing else ""]

func action(player: Node, step: String) -> void:
	GameManager.crates.request_hold(get_parent().key, mode, step, player)
