extends Interactable
## "Interact" child of a crate. Hold E to open. A Double-or-nothing crate needs
## two players opening it within 1.5 s of each other.

var opened := false


func _init() -> void:
	prompt = "Open mystery crate"
	hold_time = 0.6
	radius = 2.4


func can_interact(player: Node) -> bool:
	return not opened and player.get("state") == "ok"


func get_prompt(_player: Node) -> String:
	if get_parent().double:
		if GameManager.is_solo():
			return "Gamble alone (long hold)"
		return "Open together"
	return "Open"


## Solo players can still take the double-or-nothing gamble, but must stand
## in the open holding for 3 seconds.
func get_hold_time(_player: Node) -> float:
	if get_parent().double and GameManager.is_solo():
		return 3.0
	return hold_time


func interact(player: Node) -> void:
	GameManager.crates.open(get_parent(), player)
