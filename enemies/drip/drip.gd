extends EnemyBase
## Drip: basic melee infected. Shambles toward the nearest EXPOSED player
## first, and only goes after sheltered players when nobody is out in the rain.


func choose_target() -> Node3D:
	var exposed: Array = []
	var everyone := targetable_players()
	for player in everyone:
		if player.get("exposed") != false:
			exposed.append(player)
	return _nearest(exposed if not exposed.is_empty() else everyone)
