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
## Controls: fire (LMB / RT), aim (RMB / LT), reload (R / X), weapon_1-4 (1-4),
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
var _aim := 0.0
var _equip_left := 0.0
var _fire_buffer := 0.0
var _recoil := 0.0
var _camera_kick := 0.0
var _heat := 0.0
var _hip_fov := 75.0
## Time left before a weapon lowered for sprinting can fire.
var _raise_left := 0.0
var _reload_total := 1.0
## Model-space point that should sit dead center on screen while aiming
## (the red dot or the shotgun bead). Vector3.INF = no sight.
var _sight_point := Vector3.INF
const SPRINT_RAISE := 0.15
var _model: Node3D
var player: Node3D
var camera: Camera3D


func _ready() -> void:
	camera = get_parent() as Camera3D
	_hip_fov = camera.fov
	player = _find_player()
	loadout = loadout.filter(func(w): return w.resource_path in Settings.unlocked_guns)
	for w in loadout:
		ammo.append(w.mag_size)
		reserve.append(w.reserve_ammo)
	if not loadout.is_empty():
		_equip(0)


func _process(delta: float) -> void:
	_cooldown -= delta
	_fire_buffer = maxf(0.0, _fire_buffer - delta)
	if player and player.get("is_sprinting"):
		_raise_left = SPRINT_RAISE
	else:
		_raise_left = maxf(0.0, _raise_left - delta)
	_heat = move_toward(_heat, 0.0, delta * 1.6)
	_camera_kick = move_toward(_camera_kick, 0.0, delta * deg_to_rad(8.0))
	if player and player.is_multiplayer_authority():
		camera.rotation.x = _camera_kick
	_recoil = move_toward(_recoil, 0.0, delta * 2.8)
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
	if loadout.is_empty() or player.get("state") != "ok" or GameManager.mutations.stage != "":
		_fire_buffer = 0.0
		_reload_left = 0.0
		return
	if not GameManager.has_method("is_voting") or not GameManager.is_voting():
		for i in range(mini(loadout.size(), 5)):
			if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
				_equip(i)
	if loadout.size() > 1:
		if Input.is_action_just_pressed("weapon_next"):
			_equip((current + 1) % loadout.size())
		if Input.is_action_just_pressed("weapon_prev"):
			_equip((current - 1 + loadout.size()) % loadout.size())
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _pad_connected():
		_fire_buffer = 0.0
		return
	if player.get("tarp_raised"):
		return
	var data := loadout[current]
	if Input.is_action_just_pressed("fire"):
		_fire_buffer = 0.15 + _raise_left
	var wants := Input.is_action_pressed("fire") if data.automatic else _fire_buffer > 0.0
	if wants:
		# Firing drops out of a sprint; the gun takes a beat to come up.
		player.set("sprint_lock", 0.35)
	if wants and data.shell_reload and ammo[current] > 0:
		_reload_left = 0.0
	if wants and _cooldown <= 0.0 and _reload_left <= 0.0 and _raise_left <= 0.0:
		if ammo[current] > 0:
			fire()
		elif reserve[current] > 0:
			start_reload()


func fire() -> void:
	var data := loadout[current]
	if data.shell_reload and ammo[current] > 0:
		_reload_left = 0.0
	if ammo[current] <= 0 or _cooldown > 0.0 or _reload_left > 0.0:
		return
	_fire_buffer = 0.0
	ammo[current] -= 1
	_cooldown = data.fire_interval
	var shot_seed := randi()
	# Lucky Penny: the same seed decides jams here and lucky kills on the host.
	if data.jam_chance > 0.0 and _seeded(shot_seed, 1) < data.jam_chance:
		Sound.play("jam")
		_cooldown = data.jam_time
		player.set("weapon_name", data.display_name + " (JAMMED!)")
		return
	_kick = 1.0
	_recoil = minf(_recoil + (0.28 if data.pellets > 1 else 0.10), 0.55)
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	_play_shot(data, origin, dir, shot_seed, true)
	if Net.is_host():
		_resolve_shot(data, origin, dir, shot_seed)
		_broadcast_fx(data.resource_path, origin, dir, shot_seed, player.get_multiplayer_authority())
	else:
		_request_shot.rpc_id(1, data.resource_path, origin, dir, shot_seed)
	_camera_kick = minf(_camera_kick + deg_to_rad(data.recoil_degrees) * lerpf(1.0, 0.65, _aim), deg_to_rad(5.0))
	_heat = minf(1.0, _heat + 0.22)
	fired.emit(data)
	if _model and _model.has_node("Pump") and ammo[current] > 0:
		# Rack sound lines up with the forend animation in _animate.
		get_tree().create_timer(data.fire_interval * 0.2).timeout.connect(func(): Sound.play("shotgun_pump", -11.0))
	if ammo[current] == 0 and reserve[current] > 0:
		get_tree().create_timer(data.fire_interval).timeout.connect(func():
			if is_instance_valid(player) and player.get("state") == "ok" and loadout[current] == data and ammo[current] == 0:
				start_reload())


func start_reload() -> void:
	var data := loadout[current]
	if _reload_left > 0.0 or ammo[current] >= data.mag_size or reserve[current] <= 0:
		return
	Sound.play("reel_tick" if data.shell_reload else ("rifle_reload" if data.automatic else "reload"), -12.0 if data.shell_reload else -8.0)
	_reload_total = data.reload_time * GameManager.reload_scale()
	_reload_left = _reload_total


func _finish_reload() -> void:
	var data := loadout[current]
	var missing := 1 if data.shell_reload else data.mag_size - ammo[current]
	var take := mini(missing, reserve[current])
	ammo[current] += take
	reserve[current] -= take
	if data.shell_reload and ammo[current] < data.mag_size and reserve[current] > 0:
		start_reload()
	elif data.shell_reload:
		# Last shell in: rack the pump.
		Sound.play("shotgun_pump", -8.0)
		_kick = 0.6


# ------------------------------------------------------------------ network
## A shot travels as its WeaponData path, not a loadout index: every machine
## unlocks guns independently (Settings.unlocked_guns is local), so index 2
## is not the same weapon on the host and the client.
@rpc("any_peer", "call_remote", "reliable")
func _request_shot(path: String, origin: Vector3, dir: Vector3, shot_seed: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not Net.is_host() or sender != player.get_multiplayer_authority():
		return
	var data := _weapon_at(path)
	if data == null:
		return
	# The shot must start near where the host thinks this player's head is.
	# At 20 Hz the host's copy is a few centimetres stale, so this is loose.
	if origin.distance_to(camera.global_position) > 4.0:
		return
	_resolve_shot(data, origin, dir.normalized(), shot_seed)
	_broadcast_fx(path, origin, dir.normalized(), shot_seed, sender)
	_play_shot(data, origin, dir, shot_seed, false)


## Only the weapons folder, so a client can't ask the host to load anything.
func _weapon_at(path: String) -> WeaponData:
	if not (path.begins_with("res://weapons/") and path.ends_with(".tres")):
		return null
	return load(path) as WeaponData


@rpc("any_peer", "call_remote", "unreliable")
func _shot_fx(path: String, origin: Vector3, dir: Vector3, shot_seed: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var data := _weapon_at(path)
	if data:
		_play_shot(data, origin, dir, shot_seed, false)


func _broadcast_fx(path: String, origin: Vector3, dir: Vector3, shot_seed: int, shooter_peer: int) -> void:
	if not Net.is_online():
		return
	for peer in multiplayer.get_peers():
		if peer != shooter_peer:
			_shot_fx.rpc_id(peer, path, origin, dir, shot_seed)


# ------------------------------------------------------------------ shot logic
## Host only: damage. Projectiles deal their own damage on the host's copy.
func _resolve_shot(data: WeaponData, origin: Vector3, dir: Vector3, shot_seed: int) -> void:
	if data.pull_radius > 0.0:
		# Boombox: every shot drags nearby enemies toward the shooter.
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var to: Vector3 = player.global_position - enemy.global_position
			to.y = 0.0
			if to.length() <= data.pull_radius:
				enemy.knockback(to.normalized() * 9.0)
	if data.kind != WeaponData.Kind.HITSCAN:
		return
	var lucky := data.lucky_kill_chance > 0.0 and _seeded(shot_seed, 2) < data.lucky_kill_chance
	for ray in _pellet_rays(data, origin, dir, shot_seed):
		var start := origin
		var exclude: Array[RID] = []
		for pass_i in data.pierce + 1:
			var hit := _cast(start, ray, data.max_range, exclude)
			if hit.is_empty() or not is_damageable(hit.collider):
				break
			var distance := origin.distance_to(hit.position)
			var falloff := clampf(1.0 - 0.7 * maxf(distance - data.max_range * 0.5, 0.0) / (data.max_range * 0.5), 0.3, 1.0)
			var damage := 9999.0 if lucky else data.damage * falloff
			if hit.collider.has_method("take_bullet"):
				hit.collider.take_bullet(damage, hit.position, player)
			else:
				hit.collider.take_damage(damage, player)
			if data.knockback > 0.0 and hit.collider.has_method("knockback"):
				hit.collider.knockback(Vector3(ray.x, 0, ray.z).normalized() * data.knockback / data.pellets * falloff)
			exclude.append(hit.rid)
			start = hit.position


## Every peer: effects. Projectiles are simulated by every peer from here.
func _play_shot(data: WeaponData, origin: Vector3, dir: Vector3, shot_seed: int, is_local: bool) -> void:
	var world := player.get_parent()
	var muzzle := _muzzle_position() if is_local else origin + dir * 0.6
	var ballistic := data.kind == WeaponData.Kind.HITSCAN
	# Ballistic guns: slightly lower, varied report so they read as gunpowder
	# rather than identical zaps.
	var pitch := randf_range(0.86, 0.97) if ballistic else 1.0
	if not data.shot_sound.is_empty():
		if is_local:
			Sound.play(data.shot_sound, -7.0, pitch)
		else:
			Sound.play_at(data.shot_sound, muzzle, -6.0, pitch)
	if ballistic:
		ShotFX.flash(world, muzzle, Color(1.0, 0.72, 0.38), 3.5)
		ShotFX.puff(world, muzzle, Color(1.0, 0.86, 0.55, 0.9), 0.07, 0.05)
	else:
		ShotFX.flash(world, muzzle, data.tracer_color.lightened(0.3), 3.0)
	match data.kind:
		WeaponData.Kind.HITSCAN:
			var hit_points: Array[Vector3] = []
			for ray in _pellet_rays(data, origin, dir, shot_seed):
				var hit := _cast(origin, ray, data.max_range)
				var end: Vector3 = hit.position if not hit.is_empty() else origin + ray * data.max_range
				ShotFX.tracer(world, muzzle, end, data.tracer_color)
				if not hit.is_empty():
					var enemy_hit: bool = is_damageable(hit.collider)
					ShotFX.puff(world, end, Color(0.6, 1.0, 0.4, 0.8) if enemy_hit else Color(0.8, 0.8, 0.75, 0.7), 0.08, 0.2)
					if enemy_hit:
						hit_points.append(end)
						if hit.collider.has_method("hit_flash"):
							hit.collider.hit_flash()
			# One layered impact per shot, louder for more pellets, instead of
			# a voice per pellet.
			if not hit_points.is_empty():
				var center := Vector3.ZERO
				for p in hit_points:
					center += p
				Sound.play_at("hit_flesh", center / hit_points.size(), -18.0 + minf(6.0, 2.0 * (hit_points.size() - 1)))

		_:
			var projectile := Projectile.new()
			world.add_child(projectile)
			projectile.launch(muzzle, dir, data, Net.is_host(), player)


func _pellet_rays(data: WeaponData, _origin: Vector3, dir: Vector3, shot_seed: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = shot_seed
	var rays: Array[Vector3] = []
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var spread := deg_to_rad((data.spread_degrees + data.burst_spread * _heat) * lerpf(1.0, 0.45, _aim))
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
	elif item.begins_with("issue:"):
		_issue_weapon(load(item.trim_prefix("issue:")))


## Wave reward: make sure the player carries this gun with a full reserve,
## without switching to it mid-fight or stacking ammo past the cap.
func _issue_weapon(data: WeaponData) -> void:
	if data == null:
		return
	for i in loadout.size():
		if loadout[i].resource_path == data.resource_path:
			reserve[i] = maxi(reserve[i], data.reserve_ammo)
			return
	if loadout.size() >= 5:
		return
	loadout.append(data)
	ammo.append(data.mag_size)
	reserve.append(data.reserve_ammo)
	weapon_changed.emit(loadout[current])


## Owner: add a weapon (cursed ones from crates) and switch to it.
## A fifth slot is replaced if one is already there.
func add_weapon(data: WeaponData) -> void:
	if data == null:
		return
	for i in loadout.size():
		if loadout[i].resource_path == data.resource_path:
			reserve[i] += data.reserve_ammo
			_equip(i)
			return
	if loadout.size() >= 5:
		loadout.remove_at(4)
		ammo.remove_at(4)
		reserve.remove_at(4)
	loadout.append(data)
	ammo.append(data.mag_size)
	reserve.append(data.reserve_ammo)
	_equip(loadout.size() - 1)


func _seeded(shot_seed: int, salt: int) -> float:
	var r := RandomNumberGenerator.new()
	r.seed = shot_seed * 31 + salt
	return r.randf()


func _cast(origin: Vector3, ray: Vector3, max_range: float, extra_exclude: Array[RID] = []) -> Dictionary:
	var exclude: Array[RID] = extra_exclude.duplicate()
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * max_range, HIT_MASK, exclude)
	return get_world_3d().direct_space_state.intersect_ray(query)


# ------------------------------------------------------------------ viewmodel
func _equip(index: int) -> void:
	if index < 0 or index >= loadout.size():
		return
	_equip_left = 1.0
	_heat = 0.0
	_fire_buffer = 0.0
	current = index
	_reload_left = 0.0
	_cooldown = maxf(_cooldown, 0.25)
	if _model:
		_model.queue_free()
		_model = null
	var data := loadout[index]
	_model = data.make_model()
	_sight_point = Vector3.INF
	if _model:
		add_child(_model)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sight_point = _model.get_meta("sight", Vector3.INF)
	weapon_changed.emit(data)


func _animate(delta: float) -> void:
	if loadout.is_empty() or _model == null:
		return
	var data := loadout[current]
	# Only the owning player aims down sights; Input on this machine says
	# nothing about anyone else's.
	var aiming: bool = player.is_multiplayer_authority() and player.get("state") == "ok" and not player.get("tarp_raised") 			and _reload_left <= 0.0 and GameManager.mutations.stage == "" 			and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or _pad_connected()) and Input.is_action_pressed("aim")
	if player.is_multiplayer_authority():
		player.set("aiming", aiming)
	_aim = lerpf(_aim, 1.0 if aiming else 0.0, 1.0 - exp(-14.0 * delta))
	camera.fov = lerpf(_hip_fov, data.ads_fov, _aim)
	var speed := 0.0
	if player is CharacterBody3D:
		speed = Vector2(player.velocity.x, player.velocity.z).length()
	_bob += delta * speed * 1.6
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.014, 0.0) * minf(speed, 6.0) / 6.0
	_equip_left = move_toward(_equip_left, 0.0, delta * 4.0)
	var reload_dip := 0.0
	var reload_roll := 0.0
	var reload_push := 0.0
	if _reload_left > 0.0:
		var t := 1.0 - _reload_left / maxf(_reload_total, 0.01)
		if data.shell_reload:
			# Shell by shell: rolled to the side, a thumb-push bump per shell.
			reload_dip = 0.35
			reload_roll = 28.0
			reload_push = sin(t * PI) * 0.05
		elif data.kind == WeaponData.Kind.FLARE:
			# Break action: barrel tips down, then snaps shut at the end.
			reload_dip = 1.25 * sin(minf(t / 0.8, 1.0) * PI * 0.5) * (1.0 if t < 0.85 else (1.0 - t) / 0.15)
		else:
			# Mag swap: tilt and drop, then a sharp bolt rack near the end.
			reload_dip = sin(minf(t / 0.75, 1.0) * PI) * 0.8
			reload_roll = -32.0 * sin(minf(t / 0.75, 1.0) * PI)
			if t > 0.8:
				reload_push = sin((t - 0.8) / 0.2 * PI) * 0.07
	var lowered := _raise_left / SPRINT_RAISE
	_model.position = data.view_position.lerp(_ads_position(data), _aim) + bob * (1.0 - _aim * 0.85) + Vector3(0, -0.12 * reload_dip - .35 * _equip_left - 0.06 * lowered, 0.08 * _kick + reload_push)
	_model.rotation_degrees = data.view_rotation_degrees + Vector3(6.0 * _kick + _recoil * 8.0 - 35.0 * reload_dip - 14.0 * lowered, 12.0 * lowered, sin(_bob) * _kick * 1.5 + reload_roll)
	_model.scale = Vector3.ONE * data.view_scale
	# Moving parts on the custom models.
	var pump := _model.get_node_or_null("Pump") as Node3D
	if pump:
		# Rack the forend back and forward in the middle of the pump delay.
		var since := 1.0 - clampf(_cooldown / maxf(data.fire_interval, 0.01), 0.0, 1.0)
		pump.position.z = 0.055 * sin(clampf((since - 0.15) / 0.6, 0.0, 1.0) * PI)
	var barrel := _model.get_node_or_null("Barrel") as Node3D
	if barrel:
		# Break action: the barrel tips open for the reload.
		barrel.rotation.x = -deg_to_rad(42.0) * clampf(reload_dip / 1.25, 0.0, 1.0)


## Where the model sits while aiming: the sight point lands on the camera's
## center line at the weapon's eye relief.
func _ads_position(data: WeaponData) -> Vector3:
	if _sight_point == Vector3.INF:
		return Vector3(0.0, -0.12, data.view_position.z - 0.08)
	var basis := Basis.from_euler(data.view_rotation_degrees * PI / 180.0).scaled(Vector3.ONE * data.view_scale)
	return Vector3(0.0, 0.0, -data.ads_eye_relief) - basis * _sight_point


## True while the sight picture is up (HUD hides the crosshair).
func sighted() -> bool:
	return _sight_point != Vector3.INF and _aim > 0.85


func _muzzle_position() -> Vector3:
	if _model:
		return _model.global_transform * (_model.get_meta("muzzle", loadout[current].muzzle) as Vector3)
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


## Kill drops refill ballistic guns only; supply packs also restock flares and
## Bug Bombs so those stay tactical.
func collect_ammo(include_special := false) -> bool:
	var collected := false
	for i in loadout.size():
		var data := loadout[i]
		if not include_special and data.kind in [WeaponData.Kind.FLARE, WeaponData.Kind.GRENADE]:
			continue
		var cap := data.reserve_ammo
		if reserve[i] < cap:
			var amount := maxi(1, roundi(data.mag_size * GameManager.ammo_pickup_fraction()))
			reserve[i] = mini(cap, reserve[i] + amount)
			collected = true
	return collected
