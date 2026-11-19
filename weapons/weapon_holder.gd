class_name WeaponHolder
extends Node3D
## The player's guns: inventory, viewmodel, firing, reloading, switching.
## Sits under the player's Camera3D.
##
## Networking follows the design doc's "shooting and damage" row:
## the shooting client plays its effects at once and sends
## request_shot(weapon, origin, dir, seed) to the host; the host checks the
## shot is possible, does the raycast with the same seed and applies damage,
## then tells the other peers to play the effects. Offline (or on the host
## itself) the same path runs locally.
##
## Controls: fire (LMB / RT), reload (R / X), weapon_1-4 (1-4),
## weapon_next / weapon_prev (wheel / RB / LB).

signal weapon_changed(data: WeaponData)
signal fired(data: WeaponData)

const HIT_MASK := (1 << 0) | (1 << 2)  # world + enemies
const Projectile := preload("res://weapons/projectile.gd")

@export var loadout: Array[WeaponData] = []

var current := 0
var ammo: Array[int] = []
var reserve: Array[int] = []

var _cooldown := 0.0
var _reload_left := 0.0
var _kick := 0.0
var _bob := 0.0
var _model: Node3D
var player: Node3D
var camera: Camera3D


func _ready() -> void:
	camera = get_parent() as Camera3D
	player = _find_player()
	for w in loadout:
		ammo.append(w.mag_size)
		reserve.append(w.reserve_ammo)
	if not loadout.is_empty():
		_equip(0)


func _process(delta: float) -> void:
	_cooldown -= delta
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if player and player.is_multiplayer_authority():
		_handle_input()
		_publish()
	_animate(delta)


func _handle_input() -> void:
	if loadout.is_empty() or player.get("state") != "ok":
		return
	if not GameManager.has_method("is_voting") or not GameManager.is_voting():
		for i in range(mini(loadout.size(), 5)):
			if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
				_equip(i)
	if Input.is_action_just_pressed("weapon_next"):
		_equip((current + 1) % loadout.size())
	if Input.is_action_just_pressed("weapon_prev"):
		_equip((current - 1 + loadout.size()) % loadout.size())
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _pad_connected():
		return
	if player.get("tarp_raised"):
		return
	var data := loadout[current]
	var wants := Input.is_action_pressed("fire") if data.automatic else Input.is_action_just_pressed("fire")
	if wants and _cooldown <= 0.0 and _reload_left <= 0.0:
		if ammo[current] > 0:
			fire()
		elif reserve[current] > 0:
			start_reload()


func fire() -> void:
	var data := loadout[current]
	ammo[current] -= 1
	_cooldown = data.fire_interval
	_kick = 1.0
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	var shot_seed := randi()
	_play_shot(current, origin, dir, shot_seed, true)
	if _is_host():
		_resolve_shot(current, origin, dir, shot_seed)
		_broadcast_fx(current, origin, dir, shot_seed, player.get_multiplayer_authority())
	else:
		_request_shot.rpc_id(1, current, origin, dir, shot_seed)
	fired.emit(data)
	if ammo[current] == 0 and reserve[current] > 0:
		get_tree().create_timer(data.fire_interval).timeout.connect(start_reload)


func start_reload() -> void:
	var data := loadout[current]
	if _reload_left > 0.0 or ammo[current] >= data.mag_size or reserve[current] <= 0:
		return
	_reload_left = data.reload_time


func _finish_reload() -> void:
	var data := loadout[current]
	var take := mini(data.mag_size - ammo[current], reserve[current])
	ammo[current] += take
	reserve[current] -= take


# ------------------------------------------------------------------ network
@rpc("any_peer", "call_remote", "reliable")
func _request_shot(index: int, origin: Vector3, dir: Vector3, shot_seed: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or sender != player.get_multiplayer_authority():
		return
	# The shot must start near where the host thinks this player's head is.
	if index < 0 or index >= loadout.size() or origin.distance_to(camera.global_position) > 4.0:
		return
	_resolve_shot(index, origin, dir.normalized(), shot_seed)
	_broadcast_fx(index, origin, dir.normalized(), shot_seed, sender)
	if multiplayer.get_unique_id() != sender:
		_play_shot(index, origin, dir, shot_seed, false)


@rpc("any_peer", "call_remote", "unreliable")
func _shot_fx(index: int, origin: Vector3, dir: Vector3, shot_seed: int) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_play_shot(index, origin, dir, shot_seed, false)


func _broadcast_fx(index: int, origin: Vector3, dir: Vector3, shot_seed: int, shooter_peer: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	for peer in multiplayer.get_peers():
		if peer != shooter_peer:
			_shot_fx.rpc_id(peer, index, origin, dir, shot_seed)


# ------------------------------------------------------------------ shot logic
## Host only: damage. Projectiles deal their own damage on the host's copy.
func _resolve_shot(index: int, origin: Vector3, dir: Vector3, shot_seed: int) -> void:
	var data := loadout[index]
	if data.kind != WeaponData.Kind.HITSCAN:
		return
	for ray in _pellet_rays(data, origin, dir, shot_seed):
		var hit := _cast(origin, ray, data.max_range)
		if hit.is_empty() or not is_damageable(hit.collider):
			continue
		var distance := origin.distance_to(hit.position)
		var falloff := clampf(1.0 - 0.7 * maxf(distance - data.max_range * 0.5, 0.0) / (data.max_range * 0.5), 0.3, 1.0)
		hit.collider.take_damage(data.damage * falloff, player)
		if data.knockback > 0.0:
			hit.collider.knockback(Vector3(ray.x, 0, ray.z).normalized() * data.knockback / data.pellets * falloff)


## Every peer: effects. Projectiles are simulated by every peer from here.
func _play_shot(index: int, origin: Vector3, dir: Vector3, shot_seed: int, is_local: bool) -> void:
	var data := loadout[index]
	var world := player.get_parent()
	var muzzle := _muzzle_position() if is_local else origin + dir * 0.6
	ShotFX.flash(world, muzzle, data.tracer_color.lightened(0.3), 3.0)
	match data.kind:
		WeaponData.Kind.HITSCAN:
			for ray in _pellet_rays(data, origin, dir, shot_seed):
				var hit := _cast(origin, ray, data.max_range)
				var end: Vector3 = hit.position if not hit.is_empty() else origin + ray * data.max_range
				ShotFX.tracer(world, muzzle, end, data.tracer_color)
				if not hit.is_empty():
					var enemy_hit: bool = is_damageable(hit.collider)
					ShotFX.puff(world, end, Color(0.6, 1.0, 0.4, 0.8) if enemy_hit else Color(0.8, 0.8, 0.75, 0.7), 0.08, 0.2)
					if enemy_hit and hit.collider.has_method("hit_flash"):
						hit.collider.hit_flash()
		_:
			var projectile := Projectile.new()
			world.add_child(projectile)
			projectile.launch(muzzle, dir, data, _is_host(), player)


func _pellet_rays(data: WeaponData, _origin: Vector3, dir: Vector3, shot_seed: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = shot_seed
	var rays: Array[Vector3] = []
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var spread := deg_to_rad(data.spread_degrees)
	for i in data.pellets:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * spread
		rays.append((dir + (side * cos(angle) + up * sin(angle)) * tan(radius)).normalized())
	return rays


## Enemies, boss parts and Turned players take bullets; everyone else doesn't.
static func is_damageable(target: Object) -> bool:
	if target == null or not target.has_method("take_damage"):
		return false
	if target is EnemyBase or (target is Node and target.is_in_group("boss_parts")):
		return true
	return target is Node and target.is_in_group("players") and target.get("state") == "turned"


## Owner: an item from a crate.
func grant(item: String) -> void:
	if item == "ammo":
		for i in loadout.size():
			reserve[i] = loadout[i].reserve_ammo
	elif item == "flares":
		for i in loadout.size():
			if loadout[i].kind == WeaponData.Kind.FLARE:
				reserve[i] += 4
	elif item == "base_ammo":
		var i := randi() % loadout.size()
		reserve[i] += loadout[i].mag_size * 3
	elif item.begins_with("weapon:"):
		add_weapon(load(item.trim_prefix("weapon:")))


## Owner: add a weapon (cursed ones from crates) and switch to it.
## A fifth slot is replaced if one is already there.
func add_weapon(data: WeaponData) -> void:
	if data == null:
		return
	if loadout.size() >= 5:
		loadout.remove_at(4)
		ammo.remove_at(4)
		reserve.remove_at(4)
	loadout.append(data)
	ammo.append(data.mag_size)
	reserve.append(data.reserve_ammo)
	_equip(loadout.size() - 1)


func _cast(origin: Vector3, ray: Vector3, max_range: float) -> Dictionary:
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * max_range, HIT_MASK, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query)


# ------------------------------------------------------------------ viewmodel
func _equip(index: int) -> void:
	if index < 0 or index >= loadout.size():
		return
	current = index
	_reload_left = 0.0
	_cooldown = maxf(_cooldown, 0.25)
	if _model:
		_model.queue_free()
		_model = null
	var data := loadout[index]
	if data.model:
		_model = data.model.instantiate() as Node3D
		add_child(_model)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon_changed.emit(data)


func _animate(delta: float) -> void:
	if loadout.is_empty() or _model == null:
		return
	var data := loadout[current]
	var speed := 0.0
	if player is CharacterBody3D:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
	_bob += delta * speed * 1.6
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.014, 0.0) * minf(speed, 6.0) / 6.0
	var reload_dip := 0.0
	if _reload_left > 0.0:
		var t := 1.0 - _reload_left / data.reload_time
		reload_dip = sin(t * PI)
	_model.position = data.view_position + bob + Vector3(0, -0.12 * reload_dip, 0.08 * _kick)
	_model.rotation_degrees = data.view_rotation_degrees + Vector3(6.0 * _kick - 35.0 * reload_dip, 0, 0)
	_model.scale = Vector3.ONE * data.view_scale


func _muzzle_position() -> Vector3:
	if _model:
		return _model.global_transform * (loadout[current].muzzle)
	return camera.global_position


func _publish() -> void:
	if loadout.is_empty():
		return
	var data := loadout[current]
	player.set("weapon_name", data.display_name + (" (reloading)" if _reload_left > 0.0 else ""))
	player.set("holding_leaky", data.held_suit_drain > 0.0)
	player.set("ammo", ammo[current])
	player.set("max_ammo", reserve[current])


func _find_player() -> Node3D:
	var node := get_parent()
	while node and not node.is_in_group("players") and not (node is CharacterBody3D):
		node = node.get_parent()
	return node as Node3D


func _pad_connected() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
