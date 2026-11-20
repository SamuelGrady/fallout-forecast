class_name EnemyBase
extends CharacterBody3D
## Shared enemy logic: health, NavigationAgent3D chasing, melee attacks.
## AI runs on the host only (the design doc's authority table); clients just
## show the synced position. Drip, Gutter, Mister and Boss_Cumulus inherit
## enemy_base.tscn and override choose_target() / attack().
##
## Speed and damage are multiplied by WeatherManager.enemy_buff().

signal damaged(amount: float, health_left: float)
signal attacked(target: Node3D, amount: float)
signal died(enemy: EnemyBase)

@export var data: EnemyData

var health := 0.0
var _bullet_critical := false
var target: Node3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _retarget_timer := 0.0
var _attack_timer := 0.0
var _last_target_position := Vector3.INF
var _path := PackedVector3Array()
var _path_index := 0

const WAYPOINT_REACHED := 0.4
const REPATH_INTERVAL := 1.5

var _repath_timer := 0.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D

static var _visibility_material: ShaderMaterial
static var _reveal_material: StandardMaterial3D
static var _hit_material: StandardMaterial3D
var _reveal_left := 0.0
var _hit_left := 0.0
var _push := Vector3.ZERO
var _last_hit_by: Node = null
## Splitters mutation: the small copies don't split again.
var is_small := false


func _ready() -> void:
	add_to_group("enemies")
	if has_node("Model"):
		$Model.queue_free()
	var model := Node3D.new()
	model.set_script(preload("res://enemies/infected_model.gd"))
	add_child(model)
	if _visibility_material == null:
		_visibility_material = ShaderMaterial.new()
		_visibility_material.shader = preload("res://enemies/visibility.gdshader")
	_set_overlay.call_deferred(_visibility_material)
	health = data.max_health * GameManager.enemy_health_scale() * (0.3 if is_small else 1.0)
	if is_small:
		scale = Vector3.ONE * 0.6
	if not Net.is_host():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	_retarget_timer -= delta
	_attack_timer -= delta
	if _retarget_timer <= 0.0 or not is_instance_valid(target):
		_retarget_timer = data.retarget_interval
		target = choose_target()

	var buff := WeatherManager.enemy_buff() * GameManager.enemy_speed_scale()
	var move := Vector3.ZERO
	if is_instance_valid(target):
		var to_target := target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() <= data.attack_range:
			if _attack_timer <= 0.0:
				_attack_timer = data.attack_cooldown
				attack(target, data.damage * buff)
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


func _process(delta: float) -> void:
	if _hit_left > 0.0:
		_hit_left -= delta
		if _hit_left <= 0.0:
			_set_overlay(_reveal_material if _reveal_left > 0.0 else _visibility_material)
	if _reveal_left > 0.0:
		_reveal_left -= delta
		if _reveal_left <= 0.0 and _hit_left <= 0.0:
			_set_overlay.call_deferred(_visibility_material)


## Host only: shove the enemy (shotgun, Bug Bomb). Fades over a fraction of a second.
func knockback(impulse: Vector3) -> void:
	_push += impulse


## Local only: brief red flash when a shot lands.
func hit_flash() -> void:
	if _hit_material == null:
		_hit_material = StandardMaterial3D.new()
		_hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_material.albedo_color = Color(1, 0.2, 0.15, 0.6)
		_hit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hit_material.grow = true
		_hit_material.grow_amount = 0.02
	_hit_left = 0.08
	_set_overlay(_hit_material)


## Local only: outline this enemy through walls and fog for `duration` seconds
## (lightning strikes, the Flare Gun).
func reveal(duration: float) -> void:
	if _reveal_material == null:
		_reveal_material = StandardMaterial3D.new()
		_reveal_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_reveal_material.albedo_color = Color(1.0, 0.95, 0.6)
		_reveal_material.grow = true
		_reveal_material.grow_amount = 0.05
		_reveal_material.cull_mode = BaseMaterial3D.CULL_FRONT
		_reveal_material.no_depth_test = true
		_reveal_material.disable_fog = true
	_reveal_left = maxf(_reveal_left, duration)
	_set_overlay(_reveal_material)


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
	# Armor mutation: half damage from the front.
	if GameManager.has_mutation("armor") and _source is Node3D:
		var to_source: Vector3 = (_source as Node3D).global_position - global_position
		to_source.y = 0.0
		if (-global_basis.z).dot(to_source.normalized()) > 0.3:
			amount *= 0.5
	health -= amount
	if is_instance_valid(_source) and _source.is_in_group("local_player"):
		GameManager.combat_hit.emit(health <= 0.0, _bullet_critical)
	damaged.emit(amount, maxf(health, 0.0))
	if health <= 0.0:
		die()


func die() -> void:
	if not is_small and get_tree().get_nodes_in_group("ammo_drops").size() < 32:
		var drop := Node3D.new()
		drop.set_script(preload("res://weapons/ammo_drop.gd"))
		get_parent().add_child(drop)
		drop.global_position = global_position
	for i in 6:
		var fragment := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * randf_range(0.1, 0.22)
		fragment.mesh = cube
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b5df68") if i % 2 == 0 else Color("#337c87")
		fragment.material_override = material
		get_parent().add_child(fragment)
		fragment.global_position = global_position + Vector3.UP
		var tween := fragment.create_tween()
		tween.tween_property(fragment, "position", fragment.position + Vector3(randf_range(-1.5, 1.5), randf_range(.3, 1.2), randf_range(-1.5, 1.5)), .25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(fragment, "scale", Vector3.ZERO, .3)
		tween.tween_callback(fragment.queue_free)
	Sound.play_at("enemy_death", global_position)
	GameManager.record_kill(_last_hit_by)
	if GameManager.has_mutation("spores"):
		GameManager.spawn_cloud(global_position + Vector3.UP * 0.5, 6.0, 2.5)
	if GameManager.has_mutation("splitters") and not is_small and get_parent().has_method("spawn_copy"):
		for i in 2:
			get_parent().spawn_copy(self, global_position + Vector3(randf_range(-0.8, 0.8), 0.1, randf_range(-0.8, 0.8)), true)
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


func take_bullet(amount: float, point: Vector3, source: Node) -> void:
	if health <= 0.0:
		return
	var height := to_local(point).y
	var head_height := 1.42
	match data.display_name.to_lower():
		"gutter": head_height = 1.16
		"mister": head_height = 1.63
	_bullet_critical = height >= head_height
	var before := health
	take_damage(amount * (2.0 if _bullet_critical else 1.0), source)
	if is_instance_valid(source) and source.is_in_group("local_player"):
		var number := Label3D.new()
		number.set_script(preload("res://weapons/damage_number.gd"))
		number.amount = ceili(minf(before, before - health))
		number.critical = _bullet_critical
		get_parent().add_child(number)
		number.global_position = point + Vector3.UP * .25
		if _bullet_critical:
			Sound.play("headshot", -10.0)
	_bullet_critical = false
