extends Node3D
## Graybox entry point: drops the local player on the first player spawn.


func _ready() -> void:
	var spawns := get_tree().get_nodes_in_group("player_spawn")
	if not spawns.is_empty():
		$Player.global_transform = (spawns[0] as Node3D).global_transform
