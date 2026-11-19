extends Node3D
## Flare or Bug Bomb in flight. Every peer simulates the same throw from the
## same start, so everyone sees it; only the copy with `authoritative` (the
## host's) deals damage.
##
## Flare: flies until it hits something, sticks, burns for effect_time with a
## red light and keeps every enemy within effect_radius revealed. A direct
## hit on an enemy does `damage`.
## Bug Bomb: bounces, and after effect_time bursts in a green cloud that hurts
## enemies within effect_radius (more near the center), knocks them back and
## dries any puddle it touches.

var data: WeaponData
var authoritative := false
var shooter: Node = null
var velocity := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _age := 0.0
var _stuck := false
var _done := false
var _light: OmniLight3D
var _reveal_tick := 0.0
var _exclude: Array[RID] = []


func launch(from: Vector3, direction: Vector3, weapon: WeaponData, is_authoritative: bool, from_shooter: Node) -> void:
	data = weapon
	authoritative = is_authoritative
	shooter = from_shooter
	global_position = from
	velocity = direction * weapon.projectile_speed
	if weapon.kind == WeaponData.Kind.GRENADE:
		velocity += Vector3.UP * 3.0
	if from_shooter is CollisionObject3D:
		_exclude.append(from_shooter.get_rid())
	if weapon.model:
		var model := weapon.model.instantiate() as Node3D
		model.scale = Vector3.ONE * 2.0
		add_child(model)
	if weapon.kind == WeaponData.Kind.FLARE:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.25, 0.2)
		_light.light_energy = 2.0
		_light.omni_range = 6.0
		add_child(_light)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	match data.kind:
		WeaponData.Kind.FLARE:
			_flare_process(delta)
		WeaponData.Kind.ROCKET:
			if not _step(delta).is_empty() or _age > 4.0:
				_explode()
		_:
			_bomb_process(delta)


func _flare_process(delta: float) -> void:
	if not _stuck:
		var hit := _step(delta)
		if not hit.is_empty():
			_stuck = true
			global_position = hit.position + hit.normal * 0.1
			_light.light_energy = 4.0
			_light.omni_range = data.effect_radius * 1.6
			if authoritative and WeaponHolder.is_damageable(hit.collider):
				hit.collider.take_damage(data.damage, shooter)
	else:
		_light.light_energy = 3.5 + randf() * 1.5
	_reveal_tick -= delta
	if _reveal_tick <= 0.0:
		_reveal_tick = 0.5
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.global_position.distance_to(global_position) <= data.effect_radius:
				enemy.reveal(1.0)
		for boss in get_tree().get_nodes_in_group("boss"):
			if boss.has_method("burn") and boss.global_position.distance_to(global_position) <= data.effect_radius + 8.0:
				boss.burn(1.0)
	if _age > data.effect_time + 1.5:
		queue_free()


func _bomb_process(delta: float) -> void:
	var hit := _step(delta)
	if not hit.is_empty():
		global_position = hit.position + hit.normal * 0.1
		velocity = velocity.bounce(hit.normal) * 0.4
	if _age >= data.effect_time:
		_explode()


func _step(delta: float) -> Dictionary:
	velocity.y -= _gravity * data.projectile_gravity * delta
	var next := global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, (1 << 0) | (1 << 2), _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = next
	return hit


func _explode() -> void:
	Sound.play_at("explosion", global_position)
	_done = true
	var center := global_position
	if authoritative:
		var targets: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss_parts") + get_tree().get_nodes_in_group("players")
		for target in targets:
			if not WeaponHolder.is_damageable(target):
				continue
			var d: float = target.global_position.distance_to(center)
			if d <= data.effect_radius:
				var falloff := 1.0 - 0.6 * d / data.effect_radius
				target.take_damage(data.damage * falloff, shooter)
				if target.has_method("knockback"):
					var push: Vector3 = (target.global_position - center)
					push.y = 0.0
					target.knockback(push.normalized() * data.knockback * falloff)
	for puddle in get_tree().get_nodes_in_group("puddles"):
		if puddle.global_position.distance_to(center) <= data.effect_radius + puddle.radius():
			puddle.clear()
	var parent := get_parent()
	if data.kind == WeaponData.Kind.ROCKET:
		ShotFX.puff(parent, center, Color(1.0, 0.5, 0.8, 0.7), data.effect_radius * 0.4, 0.6)
		ShotFX.flash(parent, center + Vector3.UP, Color(1.0, 0.4, 0.8), 8.0, 0.12)
		queue_free()
		return
	ShotFX.puff(parent, center, Color(0.7, 0.95, 0.3, 0.6), data.effect_radius * 0.4, 0.7)
	ShotFX.flash(parent, center + Vector3.UP, Color(0.8, 1.0, 0.4), 8.0, 0.12)
	queue_free()
