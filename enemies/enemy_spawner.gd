extends Node3D
## Placeholder wave spawner (host only) until GameManager owns waves.
## Spawns Drips at enemy_spawn markers during Drizzle and Downpour.
## Enemies are added as children with readable names, so a
## MultiplayerSpawner pointed at this node can replicate them.
##
## Debug (debug builds, host only): F3 spawns a Drip now.

@export var drip_scene: PackedScene = preload("res://enemies/drip/drip.tscn")
@export var drizzle_interval := 4.0
@export var downpour_interval := 2.0
@export var max_alive := 12

var _timer := 0.0


func _physics_process(delta: float) -> void:
	if not _is_host():
		return
	var interval := 0.0
	match WeatherManager.phase:
		WeatherManager.Phase.DRIZZLE:
			interval = drizzle_interval
		WeatherManager.Phase.DOWNPOUR:
			interval = downpour_interval
		_:
			return
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval
		if get_child_count() < max_alive:
			spawn(drip_scene)


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and _is_host() and event is InputEventKey \
			and event.pressed and not event.echo and event.keycode == KEY_F3:
		spawn(drip_scene)


func spawn(scene: PackedScene) -> EnemyBase:
	var markers := get_tree().get_nodes_in_group("enemy_spawn")
	if markers.is_empty():
		push_warning("No enemy_spawn markers in the level")
		return null
	var marker := markers.pick_random() as Node3D
	var enemy := scene.instantiate() as EnemyBase
	add_child(enemy, true)
	enemy.global_position = marker.global_position + Vector3(randf_range(-1.5, 1.5), 0.1, randf_range(-1.5, 1.5))
	return enemy


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
