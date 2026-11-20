extends Node3D
## Placeholder wave spawner (host only) until GameManager owns waves.
## During Drizzle and Downpour it spawns, by weight:
## - Drips at enemy_spawn markers (all rainy phases)
## - Gutters from storm drains (drain_spawn markers) and grown puddles
## - Misters at enemy_spawn markers, wave 2 and later
##
## The host runs the AI and replicates: one reliable spawn per enemy, one
## reliable despawn per death, and one unreliable packet per tick carrying
## every enemy's position. Clients never run the AI, they only draw.
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

## Position broadcasts per second when the host is relaying to clients.
const NET_HZ := 10.0

var _timer := 0.0
var _next_net_id := 1
var _net_sync := 0.0


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	if Net.is_online():
		_net_sync -= delta
		if _net_sync <= 0.0:
			_net_sync = 1.0 / NET_HZ
			_push_enemies()
	var interval := 0.0
	match WeatherManager.phase:
		WeatherManager.Phase.DRIZZLE:
			interval = drizzle_interval
		WeatherManager.Phase.DOWNPOUR:
			interval = downpour_interval
		_:
			return
	var scale := GameManager.enemy_spawn_scale()
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval / scale
		if alive_count() < int(max_alive * scale):
			spawn(_pick_scene())


func _unhandled_input(event: InputEvent) -> void:
	if not (OS.is_debug_build() and Net.is_host() and event is InputEventKey and event.pressed and not event.echo):
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
	var where: Vector3 = (at as Vector3) + Vector3(randf_range(-1.0, 1.0), 0.1, randf_range(-1.0, 1.0))
	var enemy := _make(scene, where, false)
	if enemy and Net.is_online():
		_spawn_enemy.rpc(enemy.net_id, _kind_of(scene), where, false)
	return enemy


## Splitters: a small copy of `enemy` at `at`.
func spawn_copy(enemy: EnemyBase, at: Vector3, small: bool) -> void:
	var scene := load(enemy.scene_file_path) as PackedScene
	if scene == null:
		return
	# Deferred: this runs from inside the parent's death.
	var copy := scene.instantiate() as EnemyBase
	copy.is_small = small
	copy.net_id = _next_net_id
	_next_net_id += 1
	add_child.call_deferred(copy, true)
	copy.set_deferred("global_position", at)
	if Net.is_online():
		_spawn_enemy.rpc(copy.net_id, _kind_of(scene), at, small)


## Build one enemy on this peer. `is_small` and net_id are set before add_child
## because EnemyBase._ready() reads them. Clients pass the host's id in;
## only the host hands out new ones.
func _make(scene: PackedScene, at: Vector3, small: bool, forced_id := 0) -> EnemyBase:
	var enemy := scene.instantiate() as EnemyBase
	enemy.is_small = small
	if forced_id > 0:
		enemy.net_id = forced_id
	else:
		enemy.net_id = _next_net_id
		_next_net_id += 1
	add_child(enemy, true)
	enemy.global_position = at
	return enemy


## Which kind of enemy this is, for the wire. Compares resource paths rather
## than instances, because splitters reload the scene by path.
func _kind_of(scene: PackedScene) -> int:
	var path := scene.resource_path
	if path == gutter_scene.resource_path:
		return 1
	if path == mister_scene.resource_path:
		return 2
	return 0


func _scene_of(kind: int) -> PackedScene:
	match kind:
		1:
			return gutter_scene
		2:
			return mister_scene
	return drip_scene


# ------------------------------------------------------------------ network
## Host: an ammo drop every peer will see (it is collected locally by whoever
## walks over it, so the node has to exist on every machine).
func spawn_ammo_drop(at: Vector3) -> void:
	var drop := Node3D.new()
	drop.set_script(preload("res://weapons/ammo_drop.gd"))
	add_child(drop)
	drop.global_position = at


@rpc("authority", "call_remote", "reliable")
func _spawn_enemy(net_id: int, kind: int, at: Vector3, small: bool) -> void:
	if _find_net(net_id) != null:
		return
	_make(_scene_of(kind), at, small, net_id)


## Host: one enemy died. Tell the clients which one, and whether it left ammo.
func notify_despawn(enemy: EnemyBase, drop: bool) -> void:
	if Net.is_host() and Net.is_online():
		_despawn_enemy.rpc(enemy.net_id, enemy.global_position, drop)


@rpc("authority", "call_remote", "reliable")
func _despawn_enemy(net_id: int, at: Vector3, drop: bool) -> void:
	var enemy := _find_net(net_id)
	if enemy:
		enemy.remove_from_group("enemies")
		enemy.queue_free()
	if drop:
		spawn_ammo_drop(at)


## One packet per tick for every enemy, rather than one per enemy: positions
## and yaws only, since the AI itself runs on the host alone.
func _push_enemies() -> void:
	var ids := PackedInt32Array()
	var places := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		ids.append(int(enemy.get("net_id")))
		places.append(enemy.global_position)
		yaws.append(enemy.rotation.y)
	if ids.is_empty():
		return
	_sync_enemies.rpc(ids, places, yaws)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_enemies(ids: PackedInt32Array, places: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	for i in ids.size():
		var enemy := _find_net(ids[i])
		if enemy:
			enemy.global_position = places[i]
			enemy.rotation.y = yaws[i]


func _find_net(net_id: int) -> EnemyBase:
	for node in get_tree().get_nodes_in_group("enemies"):
		if int(node.get("net_id")) == net_id:
			return node as EnemyBase
	return null


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
