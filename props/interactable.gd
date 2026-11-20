class_name Interactable
extends Node3D
## Something a player can use with the interact key (E / pad Y): decon
## showers, crates, a downed teammate. The local player finds the nearest one
## in range, the HUD shows "[E] <prompt>", and after hold_time the request goes
## to the host through GameManager.interact(), which calls interact() there.
## Subclasses override can_interact / get_prompt / interact.

var _highlight: MeshInstance3D

@export var prompt := "Use"
@export var hold_time := 0.0
@export var radius := 2.2


func _ready() -> void:
	add_to_group("interactables")
	_highlight = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.47
	_highlight.mesh = ring
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#66dfda")
	_highlight.material_override = material
	add_child(_highlight)
	_highlight.visible = false


func can_interact(_player: Node) -> bool:
	return true


func get_prompt(_player: Node) -> String:
	return prompt


func get_hold_time(_player: Node) -> float:
	return hold_time


## Host only.
func interact(_player: Node) -> void:
	pass


func set_targeted(value: bool) -> void:
	if _highlight:
		_highlight.visible = value
