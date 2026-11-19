extends EnemyBase
## Drip: basic melee infected. Shambles toward the nearest EXPOSED player
## first, and only goes after sheltered players when nobody is out in the rain.


func choose_target() -> Node3D:
	var exposed: Array = []
	var everyone := get_tree().get_nodes_in_group("players")
	for player in everyone:
		if not player.get("sheltered"):
			exposed.append(player)
	return _nearest(exposed if not exposed.is_empty() else everyone)
