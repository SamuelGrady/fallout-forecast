extends CanvasLayer
## Graybox debug readout: FPS, speed, movement state, shelter state.

@onready var info: Label = $Info


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as Player
	if player == null:
		info.text = "no local player"
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	info.text = "FPS %d\nspeed %.1f m/s\nstate %s\n%s\n\nWASD move  Shift sprint  Ctrl/C crouch  Space jump  Esc free mouse" % [
		Engine.get_frames_per_second(),
		speed,
		player.get_move_state(),
		"SHELTERED" if player.sheltered else "EXPOSED",
	]
