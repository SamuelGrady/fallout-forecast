class_name Interactable
extends Node3D
## Something a player can use with the interact key (E / pad Y): decon
## showers, crates, a downed teammate. The local player finds the nearest one
## in range, the HUD shows "[E] <prompt>", and after hold_time the request goes
## to the host through GameManager.interact(), which calls interact() there.
## Subclasses override can_interact / get_prompt / interact.

@export var prompt := "Use"
@export var hold_time := 0.0
@export var radius := 2.2


func _ready() -> void:
	add_to_group("interactables")


func can_interact(_player: Node) -> bool:
	return true


func get_prompt(_player: Node) -> String:
	return prompt


func get_hold_time(_player: Node) -> float:
	return hold_time


## Host only.
func interact(_player: Node) -> void:
	pass
