extends Node3D
## Flare or Bug Bomb in flight. Every peer simulates the same throw from the
## same start, so everyone sees it; only the copy with `authoritative` (the
## host's) deals damage.
##
## Shield Dome (Kind.FLARE slot): thrown, bounces off walls, settles on the
## ground and projects a dome of effect_radius for effect_time. Players inside
## are fully sheltered from acid rain (see protects()); infected inside are
## shoved back out, weakened and outlined.
## Frag grenade (Kind.GRENADE): bounces, and after effect_time explodes,
## hurting enemies within effect_radius (more near the center), knocking them
## back and drying any puddle it touches.

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
	if weapon.gun_model != "":
		add_child(GunModels.projectile(weapon.gun_model))
	elif weapon.model:
		var model := weapon.model.instantiate() as Node3D
		model.scale = Vector3.ONE * 2.0
		add_child(model)
	if weapon.kind == WeaponData.Kind.FLARE:
		velocity += Vector3.UP * 3.0
		if not OS.has_feature("web") and not Net.dedicated:
			_light = OmniLight3D.new()
			_light.light_color = Color(0.35, 0.95, 1.0)
			_light.light_energy = 1.0
			_light.omni_range = 3.0
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
		if _age > 5.0:
			queue_free()
			return
		var hit := _step(delta)
		if not hit.is_empty():
			global_position = hit.position + hit.normal * 0.05
			if hit.normal.y < 0.6 and _age < 3.0:
				# Walls and cars: bounce off and keep falling.
				velocity = velocity.bounce(hit.normal) * 0.35
			else:
				_stuck = true
				_deploy_dome()
		return
	var left := data.effect_time - (_age - _deployed_at)
	if _dome:
		# Shimmer, then flicker out in the last second.
		var fade := clampf(left, 0.0, 1.0)
		_dome_material.albedo_color.a = (0.16 + 0.04 * sin(_age * 6.0)) * fade * (1.0 if left > 1.0 or fmod(_age, 0.2) < 0.1 else 0.3)
		_dome_rim.albedo_color.a = 0.7 * fade
		if _light:
			_light.light_energy = 2.2 * fade
	_reveal_tick -= delta
	if _reveal_tick <= 0.0 and left > 0.0:
		_reveal_tick = 0.25
		for enemy in get_tree().get_nodes_in_group("enemies"):
			var offset: Vector3 = enemy.global_position - global_position
			offset.y = 0.0
			if offset.length() <= data.effect_radius:
				enemy.reveal(0.5)
				if authoritative:
					enemy.weaken(0.6)
					# Push infected out through the dome wall.
					var push := offset.normalized() if offset.length_squared() > 0.01 else Vector3.RIGHT
					enemy.knockback(push * 3.5)
	if left <= 0.0:
		if is_in_group("active_flares"):
			remove_from_group("active_flares")
			Sound.play_at("dome_collapse", global_position, -10.0)
		if left < -0.3:
			queue_free()


var _dome: MeshInstance3D
var _dome_material: StandardMaterial3D
var _dome_rim: StandardMaterial3D
var _deployed_at := 0.0


func _deploy_dome() -> void:
	Perf.mark("shield dome deploy")
	_deployed_at = _age
	add_to_group("active_flares")
	rotation = Vector3.ZERO
	Sound.play_at("dome_deploy", global_position, -7.0)
	ShotFX.flash(get_parent(), global_position + Vector3.UP, Color(0.35, 0.95, 1.0), 6.0, 0.2)
	var r := data.effect_radius
	_dome = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r  # a hemisphere's height is its radius
	sphere.is_hemisphere = true
	sphere.radial_segments = 24
	sphere.rings = 8
	_dome.mesh = sphere
	_dome_material = StandardMaterial3D.new()
	_dome_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dome_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dome_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_dome_material.albedo_color = Color(0.35, 0.95, 1.0, 0.18)
	_dome_material.disable_fog = true
	_dome.material_override = _dome_material
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dome)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.08
	torus.outer_radius = r
	torus.rings = 32
	rim.mesh = torus
	rim.position.y = 0.05
	_dome_rim = StandardMaterial3D.new()
	_dome_rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dome_rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dome_rim.albedo_color = Color(0.5, 1.0, 1.0, 0.7)
	rim.material_override = _dome_rim
	add_child(rim)
	_dome.scale = Vector3.ONE * 0.1
	_dome.create_tween().tween_property(_dome, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _light:
		_light.omni_range = r * 1.4
		_light.position.y = 1.0


func _bomb_process(delta: float) -> void:
	var hit := _step(delta)
	if not hit.is_empty():
		global_position = hit.position + hit.normal * 0.1
		velocity = velocity.bounce(hit.normal) * 0.4
	if data.kind == WeaponData.Kind.GRENADE:
		rotation.x += delta * 7.0
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


func _has_los(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _explode() -> void:
	Perf.mark("explosion " + data.display_name)
	Juice.shake(0.7 if data.kind == WeaponData.Kind.GRENADE else 0.5, global_position)
	Sound.play_at("explosion_big" if data.kind == WeaponData.Kind.GRENADE else "explosion", global_position)
	_done = true
	if is_in_group("enemy_lures"):
		remove_from_group("enemy_lures")
	var center := global_position
	var blast_eye := center + Vector3.UP * 0.35
	var blast_radius := data.effect_radius * GameManager.explosive_radius_scale()
	var dmg_scale := GameManager.explosive_damage_scale()
	var kb_scale := GameManager.explosive_knockback_scale()
	if authoritative:
		var targets: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss_parts") + get_tree().get_nodes_in_group("players")
		for target in targets:
			if not WeaponHolder.is_damageable(target):
				continue
			var d: float = target.global_position.distance_to(center)
			if d <= blast_radius:
				var aim_point: Vector3 = target.global_position + (Vector3.ZERO if target.is_in_group("boss_parts") else Vector3.UP * 0.9)
				if not _has_los(blast_eye, aim_point):
					continue
				var falloff := 1.0 - 0.6 * d / blast_radius
				target.take_damage(data.damage * falloff * dmg_scale, shooter)
				if target.has_method("knockback"):
					var push: Vector3 = (target.global_position - center)
					push.y = 0.0
					target.knockback(push.normalized() * data.knockback * falloff * kb_scale)
	for puddle in get_tree().get_nodes_in_group("puddles"):
		if puddle.global_position.distance_to(center) <= blast_radius + puddle.radius() \
				and _has_los(blast_eye, puddle.global_position + Vector3.UP * 0.2):
			puddle.clear()
	var parent := get_parent()
	if data.kind == WeaponData.Kind.ROCKET:
		ShotFX.puff(parent, center, Color(1.0, 0.5, 0.8, 0.7), blast_radius * 0.4, 0.6)
		ShotFX.flash(parent, center + Vector3.UP, Color(1.0, 0.4, 0.8), 8.0, 0.12)
		queue_free()
		return
	# Frag: white-hot core, orange fireball, dark smoke, flying debris.
	ShotFX.puff(parent, center + Vector3.UP * 0.4, Color(1.0, 0.95, 0.75, 0.95), blast_radius * 0.15, 0.18)
	ShotFX.puff(parent, center + Vector3.UP * 0.5, Color(1.0, 0.55, 0.15, 0.85), blast_radius * 0.3, 0.45)
	ShotFX.puff(parent, center + Vector3.UP * 1.0, Color(0.18, 0.17, 0.16, 0.6), blast_radius * 0.38, 1.1)
	ShotFX.sparks(parent, center + Vector3.UP * 0.3, Vector3.UP, 14)
	ShotFX.flash(parent, center + Vector3.UP, Color(1.0, 0.6, 0.25), 10.0, 0.15)
	queue_free()


## True if `point` is under an active Shield Dome.
static func protects(point: Vector3, tree: SceneTree) -> bool:
	for dome in tree.get_nodes_in_group("active_flares"):
		if dome.is_queued_for_deletion():
			continue
		if dome.global_position.distance_to(point) <= dome.data.effect_radius:
			return true
	return false
