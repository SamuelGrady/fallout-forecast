extends Node3D
## Graybox entry point: drops the local player on the first player spawn.
## F11 toggles fullscreen (the game starts fullscreen, set in project.godot).


func _ready() -> void:
	var spawns := get_tree().get_nodes_in_group("player_spawn")
	if not spawns.is_empty():
		$Player.global_transform = (spawns[0] as Node3D).global_transform


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
