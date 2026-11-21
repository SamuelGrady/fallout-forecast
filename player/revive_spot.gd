extends Interactable
## Child of every Player. Live while that player is downed: a teammate holds
## E for 3 s to revive them; in solo the player can use it on themself once
## per wave.


func _init() -> void:
	prompt = "Revive"
	hold_time = 3.0
	radius = 2.2


func can_interact(player: Node) -> bool:
	var owner_player := get_parent()
	if owner_player.get("state") != "downed":
		return false
	if player == owner_player:
		return owner_player.can_self_revive()
	return player.get("state") == "ok"


func get_prompt(_player: Node) -> String:
	return "Revive"


func interact(player: Node) -> void:
	get_parent().revive(player)
