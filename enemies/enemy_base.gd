class_name EnemyBase
extends CharacterBody3D
## Shared enemy logic: health, NavigationAgent3D chasing, melee attacks.
## AI runs on the host only (the design doc's authority table); clients just
## show the synced position. Drip, Gutter, Mister and Boss_Cumulus inherit
## enemy_base.tscn and override choose_target() / attack().
##
## Speed and damage both scale with WeatherManager.enemy_buff(), but status
## effects split them: Runners and leg-shot slow only change speed, while
## flare weaken lowers both. See speed_multiplier() and damage_multiplier().

signal damaged(amount: float, health_left: float)
signal winding_up
signal staggered
signal molted
signal attacked(target: Node3D, amount: float)
signal died(enemy: EnemyBase)

@export var data: EnemyData

var health := 0.0
## Host-assigned, used by the spawner to match this enemy across peers.
var net_id := 0
var _bullet_critical := false
var target: Node3D
var _stagger_left := 0.0
var _slow_left := 0.0
var _weaken_left := 0.0
var _molt_boost_left := 0.0
var _molted := false
var _windup_left := 0.0
var _recover_left := 0.0
var _attack_victim: Node3D
var _attack_amount := 0.0
var _dead := false
var _status_frame := -1
var _last_hit_dir := Vector3.ZERO
var _last_hit_force := 0.0
static var _fragment_materials: Array[StandardMaterial3D] = []
static var _fragment_mesh: BoxMesh

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _retarget_timer := 0.0
var _attack_timer := 0.0
var _last_target_position := Vector3.INF
var _path := PackedVector3Array()
var _path_index := 0

const WAYPOINT_REACHED := 0.4
const REPATH_INTERVAL := 1.5
const POS_HISTORY_LIMIT := 24

var _repath_timer := 0.0
## Host-recorded recent positions for hitscan lag compensation.
var _pos_history: Array[Dictionary] = []
## Client-side interpolation target from _sync_enemies.
var _net_target_pos := Vector3.ZERO
var _net_target_yaw := 0.0
var _net_has_target := false

@onready var agent: NavigationAgent3D = $NavigationAgent3D

static var _last_headshot_ms := 0
static var _visibility_material: ShaderMaterial
static var _reveal_material: StandardMaterial3D
static var _hit_material: StandardMaterial3D
static var _attack_material: StandardMaterial3D
var _reveal_left := 0.0
var _hit_left := 0.0
var _attack_flash_left := 0.0
var _last_bullet_point := Vector3.ZERO
var _push := Vector3.ZERO
var _last_hit_by: Node = null
## Splitters mutation: the small copies don't split again.
var is_small := false
## False Clearing mutation: heavy elite spawn.
var is_elite := false
## Wave 1-4 Mini-Boss tier (0 = regular enemy).
var miniboss_wave := 0
var miniboss_name := ""
var max_health := 1.0
var _miniboss_ability_timer := 4.0
static var _web := OS.has_feature("web")

const MINIBOSS_NAMES := {
	1: "THE DREDGE",
	2: "SEWER MATRIARCH",
	3: "MIASMA HERALD",
	4: "VOLT GOLIATH",
}
const MINIBOSS_HP_MULT := {1: 4.5, 2: 4.2, 3: 4.5, 4: 5.5}
const MINIBOSS_SCALES := {1: 1.85, 2: 1.8, 3: 1.85, 4: 1.95}


func _ready() -> void:
	add_to_group("enemies")
	if has_node("Model"):
		$Model.queue_free()
	var model := Node3D.new()
	model.set_script(preload("res://enemies/infected_model.gd"))
	add_child(model)
	if not _web:
		if _visibility_material == null:
			_visibility_material = ShaderMaterial.new()
			_visibility_material.shader = preload("res://enemies/visibility.gdshader")
		_set_overlay.call_deferred(_visibility_material)
	var mult := 0.3 if is_small else (float(MINIBOSS_HP_MULT.get(miniboss_wave, 4.5)) if miniboss_wave > 0 else (2.2 if is_elite else 1.0))
	max_health = data.max_health * GameManager.enemy_health_scale() * mult
	health = max_health
	if miniboss_wave > 0:
		add_to_group("miniboss")
		miniboss_name = str(MINIBOSS_NAMES.get(miniboss_wave, "ALPHA INFECTED"))
		scale = Vector3.ONE * float(MINIBOSS_SCALES.get(miniboss_wave, 1.85))
		_miniboss_ability_timer = 4.0
	elif is_small:
		scale = Vector3.ONE * 0.6
	elif is_elite:
		scale = Vector3.ONE * 1.35
	if Net.is_host():
		_record_position()
	else:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_tick_status(delta)
	_attack_timer -= delta
	if miniboss_wave > 0:
		_tick_miniboss_ability(delta)
	if _stagger_left > 0.0 or _recover_left > 0.0 or _windup_left > 0.0:
		_stagger_left = maxf(0.0, _stagger_left - delta)
		_recover_left = maxf(0.0, _recover_left - delta)
		if _windup_left > 0.0:
			_windup_left = maxf(0.0, _windup_left - delta)
			if _windup_left <= 0.0:
				if is_instance_valid(_attack_victim) and _can_attack(_attack_victim):
					attack(_attack_victim, _attack_amount)
				_recover_left = 0.5
		velocity = Vector3(_push.x, velocity.y - _gravity * delta, _push.z)
		_push = _push.move_toward(Vector3.ZERO, 25.0 * delta)
		move_and_slide()
		_record_position()
		return
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not is_instance_valid(target):
		_retarget_timer = data.retarget_interval
		target = choose_target()
		var lure := _nearest(get_tree().get_nodes_in_group("enemy_lures"))
		if lure and global_position.distance_to(lure.global_position) < 12.0:
			target = lure

	var buff := speed_multiplier()
	var move := Vector3.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		var is_lure := target.is_in_group("enemy_lures")
		var stop_range := 1.0 if is_lure else data.attack_range
		# In range but walled off: keep pathing around the cover instead of
		# winding up swings that can never land.
		var in_range := to_target.length() <= stop_range and (is_lure or _has_attack_los(target))
		if in_range:
			if _attack_timer <= 0.0 and not is_lure:
				_attack_timer = data.attack_cooldown
				_begin_attack(target, data.damage * damage_multiplier())
			move = in_range_move(to_target, buff)
		else:
			# Re-path when the target has moved, or every REPATH_INTERVAL in case
			# this enemy was pushed off its path. Not every frame.
			_repath_timer -= delta
			if _repath_timer <= 0.0 or _last_target_position.distance_to(target.global_position) > 1.0:
				_repath_timer = REPATH_INTERVAL
				_last_target_position = target.global_position
				_repath(_last_target_position)
			move = _path_direction(target.global_position) * data.move_speed * buff
		_face(to_target)

	move += _push
	_push = _push.move_toward(Vector3.ZERO, 25.0 * delta)
	velocity.x = move.x
	velocity.z = move.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	_record_position()


## Movement multiplier: storm, Runners mutation, Molting burst, leg-shot slow, flare weaken.
func speed_multiplier() -> float:
	var m := WeatherManager.enemy_buff() * GameManager.enemy_speed_scale()
	if _molt_boost_left > 0.0:
		m *= 1.45
	if _slow_left > 0.0:
		m *= 0.5
	if _weaken_left > 0.0:
		m *= 0.65
	return m


## Attack damage multiplier: storm and flare weaken only.
func damage_multiplier() -> float:
	return WeatherManager.enemy_buff() * (0.65 if _weaken_left > 0.0 else 1.0)


## Status timers decay once per physics frame, even when a subclass and the
## base class both run their physics step.
func _tick_status(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _status_frame:
		return
	_status_frame = frame
	_slow_left = maxf(0.0, _slow_left - delta)
	_weaken_left = maxf(0.0, _weaken_left - delta)
	_molt_boost_left = maxf(0.0, _molt_boost_left - delta)


func _record_position() -> void:
	_pos_history.append({"ms": Time.get_ticks_msec(), "pos": global_position})
	if _pos_history.size() > POS_HISTORY_LIMIT:
		_pos_history.remove_at(0)


## Host lag compensation: interpolated position at `target_ms` (ticks_msec).
func sample_position(target_ms: int) -> Vector3:
	if _pos_history.is_empty():
		return global_position
	var last := _pos_history[_pos_history.size() - 1]
	if target_ms >= int(last.ms):
		return last.pos
	var first := _pos_history[0]
	if target_ms <= int(first.ms):
		return first.pos
	for i in range(_pos_history.size() - 1, 0, -1):
		var a := _pos_history[i - 1]
		var b := _pos_history[i]
		if target_ms >= int(a.ms) and target_ms <= int(b.ms):
			var span := float(int(b.ms) - int(a.ms))
			var frac := (float(target_ms - int(a.ms)) / span) if span > 0.0 else 0.0
			return (a.pos as Vector3).lerp(b.pos as Vector3, clampf(frac, 0.0, 1.0))
	return global_position


var _net_vel := Vector3.ZERO
var _net_age := 0.0
var _net_last_ms := 0


## Client: receive a host position/yaw snapshot and glide smoothly toward it.
func set_net_state(pos: Vector3, yaw: float) -> void:
	var now := Time.get_ticks_msec()
	if _net_has_target and _net_last_ms > 0:
		var dt := clampf(float(now - _net_last_ms) * 0.001, 0.02, 0.25)
		var step_v := (pos - _net_target_pos) / dt
		# Ignore teleports/respawns when estimating travel velocity.
		if step_v.length() < 16.0:
			_net_vel = _net_vel.lerp(step_v, 0.55)
		else:
			_net_vel = Vector3.ZERO
	else:
		_net_vel = Vector3.ZERO
	_net_last_ms = now
	_net_target_pos = pos
	_net_target_yaw = yaw
	_net_age = 0.0
	if not _net_has_target or global_position.distance_to(pos) > 4.0:
		global_position = pos
		rotation.y = yaw
	_net_has_target = true


func _has_attack_los(victim: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, victim.global_position + Vector3.UP, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Spatial warning audio: a periodic growl when near the local player, kept
## to a small budget so a horde doesn't drown the mix.
static var _growl_budget_ms := 0
var _growl_left := randf_range(2.0, 6.0)


func _growl(delta: float) -> void:
	_growl_left -= delta
	if _growl_left > 0.0 or _dead:
		return
	_growl_left = randf_range(4.0, 8.0)
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me == null or me.global_position.distance_to(global_position) > 16.0:
		return
	var now := Time.get_ticks_msec()
	if now < _growl_budget_ms:
		return
	_growl_budget_ms = now + 700
	var kind := str(data.display_name).to_lower()
	match kind:
		"mister":
			Sound.play_at("spore_burst", global_position + Vector3.UP, -20.0, 0.55)
		"gutter":
			Sound.play_at("turned", global_position, -20.0, 1.35)
		_:
			# Drips stay restrained: quiet, low.
			Sound.play_at("turned", global_position + Vector3.UP, -24.0, 0.8)


func _process(delta: float) -> void:
	if not Net.is_host() and _net_has_target:
		_net_age += delta
		var predicted := _net_target_pos + _net_vel * minf(_net_age, 0.12)
		var blend := 1.0 - exp(-14.0 * delta)
		global_position = global_position.lerp(predicted, blend)
		rotation.y = lerp_angle(rotation.y, _net_target_yaw, blend)
		velocity = velocity.lerp(_net_vel, 1.0 - exp(-10.0 * delta))
	_growl(delta)
	var changed := false
	if _hit_left > 0.0:
		_hit_left = maxf(0.0, _hit_left - delta)
		if _hit_left <= 0.0:
			changed = true
	if _attack_flash_left > 0.0:
		_attack_flash_left = maxf(0.0, _attack_flash_left - delta)
		if _attack_flash_left <= 0.0:
			changed = true
	if _reveal_left > 0.0:
		_reveal_left = maxf(0.0, _reveal_left - delta)
		if _reveal_left <= 0.0:
			changed = true
	if changed:
		_refresh_overlay()


func _refresh_overlay() -> void:
	if _hit_left > 0.0 and _hit_material:
		_set_overlay(_hit_material)
	elif _attack_flash_left > 0.0 and _attack_material:
		_set_overlay(_attack_material)
	elif _reveal_left > 0.0 and _reveal_material:
		_set_overlay(_reveal_material)
	else:
		_set_overlay(null if _web else _visibility_material)


## Host: Wave 1-4 Mini-Boss signature abilities.
func _tick_miniboss_ability(delta: float) -> void:
	_miniboss_ability_timer -= delta
	if _miniboss_ability_timer > 0.0 or target == null or not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	match miniboss_wave:
		1:
			# THE DREDGE: acid ground-slam shockwave when close.
			if dist > 7.5:
				_miniboss_ability_timer = 0.6
				return
			_miniboss_ability_timer = 5.5
			announce_tell("drip_windup", 0.35, -4.0)
			GameManager.broadcast_blast(global_position + Vector3.UP * 0.7, 2.2, Color(0.65, 1.0, 0.25, 0.9))
			GameManager.spawn_cloud(global_position + Vector3.UP * 0.3, 6.0, 3.0)
			for p in targetable_players():
				var pl := p as Node3D
				if pl and pl.global_position.distance_to(global_position) <= 5.5:
					if pl.has_method("take_damage"):
						pl.take_damage(18.0, self)
		2:
			# SEWER MATRIARCH: spawns 2 small Gutter hatchlings around herself.
			_miniboss_ability_timer = 6.5
			var spawner := get_parent()
			if spawner and spawner.has_method("alive_count") and spawner.alive_count() < 45 and spawner.has_method("spawn_copy"):
				announce_tell("gutter_windup", 0.3, -4.0)
				GameManager.broadcast_blast(global_position + Vector3.UP * 0.8, 1.4, Color(1.0, 0.24, 0.48, 0.85))
				for i in 2:
					spawner.spawn_copy(self, global_position + Vector3(randf_range(-1.6, 1.6), 0.15, randf_range(-1.6, 1.6)), true)
		3:
			# MIASMA HERALD: 3-glob spore barrage fan.
			if dist > 24.0:
				_miniboss_ability_timer = 0.8
				return
			_miniboss_ability_timer = 5.0
			announce_tell("mister_windup", 0.35, -4.0)
			var start := global_position + Vector3.UP * 2.4
			var to_t := target.global_position - global_position
			to_t.y = 0.0
			var base_dir := to_t.normalized() if to_t.length_squared() > 0.01 else -global_basis.z
			var reach := clampf(to_t.length(), 6.0, 20.0)
			for angle in [-0.32, 0.0, 0.32]:
				var goal := global_position + base_dir.rotated(Vector3.UP, angle) * reach
				goal.y = target.global_position.y
				GameManager.spawn_spore(start, goal, 1.15, 10.0)
		_:
			# VOLT GOLIATH: telegraphed lightning strike + chain arc near target.
			if dist > 26.0:
				_miniboss_ability_timer = 0.8
				return
			_miniboss_ability_timer = 5.0
			announce_tell("drip_windup", 0.4, -3.0)
			var strike_at := target.global_position + Vector3(randf_range(-2.2, 2.2), 0.0, randf_range(-2.2, 2.2))
			WeatherManager.strike_lightning(strike_at)
			GameManager.broadcast_arc([global_position + Vector3.UP * 2.8, strike_at + Vector3.UP * 1.0], Color(0.45, 0.96, 1.0))
			for p in targetable_players():
				var pl := p as Node3D
				if pl and pl.global_position.distance_to(strike_at) <= 4.2 and pl.has_method("take_damage"):
					pl.take_damage(16.0, self)


## Host only: shove the enemy (shotgun, Bug Bomb). Fades over a fraction of a second.
func knockback(impulse: Vector3) -> void:
	_push += impulse
	if impulse.length_squared() > 0.0001:
		_last_hit_dir = impulse.normalized()
		_last_hit_force = maxf(_last_hit_force, impulse.length())
	if impulse.length() >= 0.8:
		stagger(0.4)


## Local only: brief white-red hit confirmation flash when a shot lands.
func hit_flash() -> void:
	if _hit_material == null:
		_hit_material = StandardMaterial3D.new()
		_hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_material.albedo_color = Color(1.0, 0.25, 0.2, 0.55)
		_hit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hit_material.grow = true
		_hit_material.grow_amount = 0.015
	_hit_left = 0.08
	_refresh_overlay()


## Local only: distinct warm front-lit attack windup pulse (does not draw through walls).
func attack_flash(duration: float) -> void:
	if _attack_material == null:
		_attack_material = StandardMaterial3D.new()
		_attack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_attack_material.albedo_color = Color(1.0, 0.32, 0.12, 0.42)
		_attack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_attack_material.grow = true
		_attack_material.grow_amount = 0.025
	_attack_flash_left = maxf(_attack_flash_left, duration)
	_refresh_overlay()


func announce_tell(cue: String, duration: float, volume: float) -> void:
	play_tell(cue, duration, volume)
	if Net.is_online() and get_parent().has_method("notify_tell"):
		get_parent().notify_tell(net_id, cue, duration, volume)


func play_tell(cue: String, duration: float, volume: float) -> void:
	if duration > 0.0:
		attack_flash(duration)
	var height := 0.2 if str(data.display_name) == "Gutter" else 1.0
	Sound.play_at(cue, global_position + Vector3.UP * height, volume, randf_range(0.93, 1.07))


## Molting carapace burst (plays on host and via RPC on every client).
func play_molt() -> void:
	_molted = true
	molted.emit()
	if not Net.dedicated and get_parent():
		ShotFX.sparks(get_parent(), global_position + Vector3.UP * 1.1, Vector3.UP, 8)
		Sound.play_at("hit_flesh", global_position + Vector3.UP, -12.0, 1.4)


## Shared death fragments: runs on the host and on every client from _despawn_enemy.
static func spawn_death_fragments(parent: Node, at: Vector3, throw_vec: Vector3, critical: bool) -> void:
	if Net.dedicated or parent == null:
		return
	if _fragment_materials.is_empty():
		for c in [Color("#b5df68"), Color("#337c87")]:
			var material := StandardMaterial3D.new()
			material.albedo_color = c
			_fragment_materials.append(material)
	if _fragment_mesh == null:
		_fragment_mesh = BoxMesh.new()
		_fragment_mesh.size = Vector3.ONE
	for i in 6:
		var fragment := MeshInstance3D.new()
		fragment.mesh = _fragment_mesh
		fragment.scale = Vector3.ONE * randf_range(0.1, 0.22)
		fragment.material_override = _fragment_materials[i % 2]
		parent.add_child(fragment)
		fragment.global_position = at + Vector3.UP * (1.6 if critical else 1.0)
		var scatter := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.2), randf_range(-1.0, 1.0)) + throw_vec * randf_range(0.7, 1.3)
		var tween := fragment.create_tween()
		tween.tween_property(fragment, "position", fragment.position + scatter, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(fragment, "scale", Vector3.ZERO, 0.3)
		tween.tween_callback(fragment.queue_free)


## Local only: explicit through-wall reveal outline (lightning strikes, Flare Gun).
func reveal(duration: float) -> void:
	if _reveal_material == null:
		_reveal_material = StandardMaterial3D.new()
		_reveal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_reveal_material.albedo_color = Color(0.55, 0.96, 1.0)
		_reveal_material.grow = true
		_reveal_material.grow_amount = 0.055
		_reveal_material.cull_mode = BaseMaterial3D.CULL_FRONT
		_reveal_material.no_depth_test = true
		_reveal_material.disable_fog = true
	_reveal_left = maxf(_reveal_left, duration)
	_refresh_overlay()


func _set_overlay(material: Material) -> void:
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.visible:
			mesh.material_overlay = material


## Override to change who the enemy hunts. Default: the nearest player.
func choose_target() -> Node3D:
	return _nearest(targetable_players())


## Players who are up (not downed, Turned or out).
func targetable_players() -> Array:
	return get_tree().get_nodes_in_group("players").filter(func(p): return p.get("state") == null or p.get("state") == "ok")


## Override to move while in attack range (e.g. back away). Default: stand still.
func in_range_move(_to_target: Vector3, _buff: float) -> Vector3:
	return Vector3.ZERO


## Override for ranged or special attacks. Default: melee hit on the target.
## Damage lands only when the target has take_damage(amount, source).
func attack(victim: Node3D, amount: float) -> void:
	if victim.has_method("take_damage"):
		victim.take_damage(amount, self)
	attacked.emit(victim, amount)


## Host only. Shooting calls this after the host's raycast hits.
func take_damage(amount: float, _source: Node = null) -> void:
	if not Net.is_host() or health <= 0.0:
		return
	if _source and _source.is_in_group("players"):
		_last_hit_by = _source
	# Molting mutation: first hit sheds carapace for half damage + speed burst.
	if GameManager.has_mutation("molting") and not _molted and amount > 0.0:
		_molted = true
		_molt_boost_left = 3.5
		amount *= 0.5
		play_molt()
		if Net.is_online() and get_parent() and get_parent().has_method("notify_molt"):
			get_parent().notify_molt(net_id)
	# Armor mutation: half damage from the front with visible deflection sparks.
	if GameManager.has_mutation("armor") and _source is Node3D:
		var to_source: Vector3 = (_source as Node3D).global_position - global_position
		to_source.y = 0.0
		if to_source.length_squared() > 0.001 and (-global_basis.z).dot(to_source.normalized()) > 0.3:
			amount *= 0.5
			var hit_at := _last_bullet_point if _last_bullet_point != Vector3.ZERO else global_position + Vector3.UP * 1.1
			ShotFX.sparks(get_parent(), hit_at, to_source.normalized(), 4)
	health -= amount
	if miniboss_wave > 0 and Net.is_online() and get_parent() and get_parent().has_method("notify_miniboss_hp"):
		get_parent().notify_miniboss_hp(net_id, maxf(health, 0.0), max_health)
	# Hit feedback belongs to whoever fired, host or client, so the shooter's
	# Player node decides where it appears (see Player.notify_hit).
	if is_instance_valid(_source) and _source.has_method("notify_hit"):
		var where := _last_bullet_point if _last_bullet_point != Vector3.ZERO else global_position
		_source.notify_hit(health <= 0.0, _bullet_critical, where, ceili(amount), net_id)
	damaged.emit(amount, maxf(health, 0.0))
	if health <= 0.0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	# The spawner owns the drops and tells every peer to make them: a drop is
	# collected locally by whoever walks over it, so it has to exist everywhere.
	var drops: Array = []
	if miniboss_wave > 0:
		drops.append([global_position, "supply"])
		drops.append([global_position + Vector3(0.9, 0.0, 0.0), "health"])
		GameManager.show_banner("%s DEFEATED" % miniboss_name, Color("ffd56a"), 2.4)
		Sound.play("reel_land", -6.0, 1.15)
	elif not is_small and get_tree().get_nodes_in_group("ammo_drops").size() < 32:
		drops.append([global_position, "ammo"])
	if miniboss_wave == 0 and not is_small and data.display_name != "Drip" and randf() < 0.4 and get_tree().get_nodes_in_group("ammo_drops").size() < 32:
		drops.append([global_position + Vector3(0.6, 0.0, 0.0), "health" if randf() < 0.5 else "suit"])
	if get_parent() and get_parent().has_method("spawn_drop"):
		for entry in drops:
			get_parent().spawn_drop(entry[0], str(entry[1]))
	# Debris carries the killing hit: shotgun blasts and headshots throw it
	# further along the shot direction, replicated to every client.
	var throw_vec := _last_hit_dir * clampf(0.6 + _last_hit_force * 0.12, 0.6, 2.6)
	spawn_death_fragments(get_parent(), global_position, throw_vec, _bullet_critical)
	if miniboss_wave > 0:
		spawn_death_fragments(get_parent(), global_position + Vector3.UP * 1.1, throw_vec * 1.3, true)
	Sound.play_at("enemy_death", global_position)
	GameManager.record_kill(_last_hit_by, global_position)
	if GameManager.has_mutation("spores"):
		GameManager.spawn_cloud(global_position + Vector3.UP * 0.5, 6.0, 2.5)
	if GameManager.has_mutation("splitters") and not is_small and miniboss_wave == 0 and get_parent().has_method("spawn_copy"):
		for i in 2:
			get_parent().spawn_copy(self, global_position + Vector3(randf_range(-0.8, 0.8), 0.1, randf_range(-0.8, 0.8)), true)
	if get_parent() and get_parent().has_method("notify_despawn"):
		get_parent().notify_despawn(self, drops, throw_vec, _bullet_critical)
	died.emit(self)
	queue_free()


## Ask the NavigationAgent3D for a path, then follow its points ourselves,
## advancing on horizontal distance (navmesh points sit above the floor).
func _repath(destination: Vector3) -> void:
	agent.target_position = destination
	agent.get_next_path_position()  # forces the path query
	_path = agent.get_current_navigation_path()
	_path_index = 0
	if _path.is_empty():
		_last_target_position = Vector3.INF  # map not ready yet; retry next frame


func _path_direction(fallback: Vector3) -> Vector3:
	while _path_index < _path.size() and _flat_distance(_path[_path_index]) < WAYPOINT_REACHED:
		_path_index += 1
	var goal := _path[_path_index] if _path_index < _path.size() else fallback
	var step := goal - global_position
	step.y = 0.0
	return step.normalized() if step.length_squared() > 0.0001 else Vector3.ZERO


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _nearest(candidates: Array) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in candidates:
		var n := node as Node3D
		var d := global_position.distance_squared_to(n.global_position)
		if d < best_distance:
			best_distance = d
			best = n
	return best


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.01:
		rotation.y = atan2(-direction.x, -direction.z)


func take_bullet(amount: float, point: Vector3, source: Node, rewound_pos := Vector3.INF) -> void:
	if health <= 0.0 or not Net.is_host():
		return
	var height := (point.y - rewound_pos.y) / maxf(absf(scale.y), 0.01) if rewound_pos != Vector3.INF else to_local(point).y
	var head_height := 1.42
	match data.display_name.to_lower():
		"gutter": head_height = 1.16
		"mister": head_height = 1.63
	_bullet_critical = height >= head_height
	if source is Node3D:
		var shot_dir := point - (source as Node3D).global_position
		shot_dir.y = 0.0
		if shot_dir.length_squared() > 0.001:
			_last_hit_dir = shot_dir.normalized()
			_last_hit_force = amount * 0.1 * (2.0 if _bullet_critical else 1.0)
	if height < 0.65:
		_slow_left = 1.8
	if _bullet_critical:
		stagger(0.3)
	if GameManager.has_mutation("pressure_front"):
		amount *= 0.72
	_last_bullet_point = point
	take_damage(amount * (GameManager.headshot_multiplier() if _bullet_critical else 1.0), source)
	_last_bullet_point = Vector3.ZERO
	# The floating number is the shooter's business: take_damage routes it
	# through Player.notify_hit, so it stacks on their screen wherever the host
	# is. Drew's stacking moved to Player.local_hit for that reason.
	_bullet_critical = false


func stagger(duration: float) -> void:
	_stagger_left = maxf(_stagger_left, duration)
	_windup_left = 0.0
	_attack_victim = null
	staggered.emit()


func weaken(duration: float) -> void:
	_weaken_left = maxf(_weaken_left, duration)


func _can_attack(victim: Node3D) -> bool:
	if victim.get("state") != "ok" or global_position.distance_to(victim.global_position) > data.attack_range + 0.25:
		return false
	var direction := victim.global_position - global_position
	direction.y = 0.0
	if data.attack_range < 3.0 and direction.length_squared() > 0.01 and (-global_basis.z).dot(direction.normalized()) < 0.3:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, victim.global_position + Vector3.UP, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _begin_attack(victim: Node3D, amount: float) -> void:
	_attack_victim = victim
	_attack_amount = amount
	_windup_left = 0.45
	winding_up.emit()
	# Audible windup tell so attacks from behind can still be dodged.
	var cue := "mister_windup" if data.display_name == "Mister" else "drip_windup"
	announce_tell(cue, _windup_left, -12.0)
