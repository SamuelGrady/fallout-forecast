extends Node3D
## Placeholder wave spawner (host only) until GameManager owns waves.
## During Drizzle and Downpour it spawns, by weight:
## - Drips at enemy_spawn markers (all rainy phases)
## - Gutters from storm drains (drain_spawn markers) and grown puddles
## - Misters at enemy_spawn markers, wave 2 and later
## Enemies (and their spore projectiles and clouds) are added as children
## with readable names, so a MultiplayerSpawner pointed here can replicate them.
##
## Debug (debug builds, host only): F3 spawns a Drip, F4 a Gutter, F5 a Mister.

@export var drip_scene: PackedScene = preload("res://enemies/drip/drip.tscn")
@export var gutter_scene: PackedScene = preload("res://enemies/gutter/gutter.tscn")
@export var mister_scene: PackedScene = preload("res://enemies/mister/mister.tscn")
@export var drizzle_interval := 4.0
@export var downpour_interval := 2.0
@export var max_alive := 16
@export_group("Weights")
@export var drip_weight := 6.0
@export var gutter_weight := 3.0
@export var mister_weight := 2.0
@export var mister_first_wave := 2

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
		if alive_count() < max_alive:
			spawn(_pick_scene())


func _unhandled_input(event: InputEvent) -> void:
	if not (OS.is_debug_build() and _is_host() and event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F3:
			spawn(drip_scene)
		KEY_F4:
			spawn(gutter_scene)
		KEY_F5:
			spawn(mister_scene)


func alive_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func spawn(scene: PackedScene) -> EnemyBase:
	var at: Variant = _gutter_spawn_point() if scene == gutter_scene else _marker_position("enemy_spawn")
	if at == null:
		push_warning("No spawn point for %s" % scene.resource_path)
		return null
	var enemy := scene.instantiate() as EnemyBase
	add_child(enemy, true)
	enemy.global_position = (at as Vector3) + Vector3(randf_range(-1.0, 1.0), 0.1, randf_range(-1.0, 1.0))
	return enemy


func _pick_scene() -> PackedScene:
	var options := [[drip_scene, drip_weight], [gutter_scene, gutter_weight]]
	if WeatherManager.wave >= mister_first_wave:
		options.append([mister_scene, mister_weight])
	var total := 0.0
	for o in options:
		total += o[1]
	var roll := randf() * total
	for o in options:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return drip_scene


## Gutters crawl out of storm drains, or out of any puddle big enough.
func _gutter_spawn_point() -> Variant:
	var points: Array = []
	for marker in get_tree().get_nodes_in_group("drain_spawn"):
		points.append((marker as Node3D).global_position)
	for puddle in get_tree().get_nodes_in_group("puddles"):
		if puddle.has_method("can_spawn_gutter") and puddle.can_spawn_gutter():
			points.append((puddle as Node3D).global_position)
	return points.pick_random() if not points.is_empty() else null


func _marker_position(group: String) -> Variant:
	var markers := get_tree().get_nodes_in_group(group)
	return (markers.pick_random() as Node3D).global_position if not markers.is_empty() else null


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
