extends Interactable
## Decon shower: restores the user's suit integrity to 100 and spends one
## charge from the team's shared pool (GameManager.decon_charges).


func _init() -> void:
	prompt = "Decon shower"
	hold_time = 1.0
	radius = 2.0


func can_interact(player: Node) -> bool:
	return player.get("state") == "ok"


func get_prompt(player: Node) -> String:
	if GameManager.decon_charges <= 0:
		return "Decon shower (empty)"
	if float(player.get("suit_integrity")) >= 99.0:
		return "Decon shower (suit full, %d left)" % GameManager.decon_charges
	return "Decon shower (%d charges)" % GameManager.decon_charges


func interact(player: Node) -> void:
	GameManager.use_decon(player)
