extends Node3D
## Run entry point. Offline (running main.tscn directly) it uses the Player
## already in the scene. Puts the level's decon showers in play and starts the
## run on the host.

const DeconShower := preload("res://props/decon_shower.gd")


func _ready() -> void:
	_setup_decon_showers()
	var spawns := get_tree().get_nodes_in_group("player_spawn")
	if has_node("Player") and not spawns.is_empty():
		$Player.global_transform = (spawns[0] as Node3D).global_transform
	if GameManager.is_host():
		GameManager.start_run.call_deferred()


## Each decon_shower marker gets an "Interact" child (same path on every peer).
func _setup_decon_showers() -> void:
	for marker in get_tree().get_nodes_in_group("decon_shower"):
		if marker.has_node("Interact"):
			continue
		var it := DeconShower.new()
		it.name = "Interact"
		marker.add_child(it)
		it.position = Vector3(0, 1.0, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
