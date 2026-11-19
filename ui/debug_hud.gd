extends CanvasLayer
## Graybox debug readout: FPS, speed, movement state, shelter state.

@onready var info: Label = $Info


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as Player
	if player == null:
		info.text = "no local player"
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	info.text = "FPS %d\nspeed %.1f m/s\nstate %s\n%s\n\nwave %d  %s  %ds\nstorm %s  intensity %.2f\n\nWASD move  Shift sprint  Ctrl/C crouch  Space jump  Esc free mouse\nF1 next phase  F2 jump to wave 5  F3 spawn Drip  F11 fullscreen" % [
		Engine.get_frames_per_second(),
		speed,
		player.get_move_state(),
		"SHELTERED" if player.sheltered else "EXPOSED",
		WeatherManager.wave,
		WeatherManager.phase_name(),
		ceili(WeatherManager.phase_time_left),
		WeatherManager.storm_name(),
		WeatherManager.storm_intensity,
	]
