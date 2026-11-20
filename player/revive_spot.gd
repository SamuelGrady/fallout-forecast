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


func get_prompt(player: Node) -> String:
	var owner_player := get_parent()
	if player == owner_player:
		return "Revive"
	return "Revive %s" % owner_player.get("display_name")


func interact(player: Node) -> void:
	get_parent().revive(player)
