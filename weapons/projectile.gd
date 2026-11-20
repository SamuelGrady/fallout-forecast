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
		add_to_group("enemy_lures")
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
			add_to_group("active_flares")
			_build_flare_ring()
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
		var flare_eye := global_position + Vector3.UP * 0.25
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.global_position.distance_to(global_position) <= data.effect_radius \
					and _has_los(flare_eye, enemy.global_position + Vector3.UP * 0.9):
				enemy.reveal(1.0)
				if authoritative:
					enemy.weaken(0.7)
		for boss in get_tree().get_nodes_in_group("boss"):
			if boss.has_method("burn") and boss.global_position.distance_to(global_position) <= data.effect_radius + 8.0 \
					and _has_los(flare_eye, boss.global_position):
				boss.burn(1.0)
	if _age > data.effect_time + 1.5:
		queue_free()


func _bomb_process(delta: float) -> void:
	var hit := _step(delta)
	if not hit.is_empty():
		global_position = hit.position + hit.normal * 0.1
		velocity = velocity.bounce(hit.normal) * 0.4
	if data.kind == WeaponData.Kind.GRENADE:
		rotation.y += delta * 4.0
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
	Sound.play_at("explosion", global_position)
	_done = true
	if is_in_group("enemy_lures"):
		remove_from_group("enemy_lures")
	var center := global_position
	var blast_eye := center + Vector3.UP * 0.35
	if authoritative:
		var targets: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss_parts") + get_tree().get_nodes_in_group("players")
		for target in targets:
			if not WeaponHolder.is_damageable(target):
				continue
			var d: float = target.global_position.distance_to(center)
			if d <= data.effect_radius:
				var aim_point: Vector3 = target.global_position + (Vector3.ZERO if target.is_in_group("boss_parts") else Vector3.UP * 0.9)
				if not _has_los(blast_eye, aim_point):
					continue
				var falloff := 1.0 - 0.6 * d / data.effect_radius
				target.take_damage(data.damage * falloff, shooter)
				if target.has_method("knockback"):
					var push: Vector3 = (target.global_position - center)
					push.y = 0.0
					target.knockback(push.normalized() * data.knockback * falloff)
	for puddle in get_tree().get_nodes_in_group("puddles"):
		if puddle.global_position.distance_to(center) <= data.effect_radius + puddle.radius() \
				and _has_los(blast_eye, puddle.global_position + Vector3.UP * 0.2):
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


func _build_flare_ring() -> void:
	var zone := Node3D.new()
	zone.position.y = 0.06
	add_child(zone)
	var border_mat := StandardMaterial3D.new()
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.albedo_color = Color(0.32, 0.92, 0.92, 0.62)
	var tick_mat := StandardMaterial3D.new()
	tick_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tick_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tick_mat.albedo_color = Color(1.0, 0.68, 0.35, 0.5)
	# Dashed perimeter segments + inward shelter ticks clearly distinguish safe ground from enemy rings.
	var segments := 16
	var r := data.effect_radius
	var arc_len := (TAU * r / segments) * 0.58
	for i in segments:
		var angle := TAU * i / segments
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(arc_len, 0.03, 0.14)
		seg.mesh = box
		seg.position = Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		seg.rotation.y = -angle + PI * 0.5
		seg.material_override = border_mat
		zone.add_child(seg)
		if i % 2 == 0:
			var tick := MeshInstance3D.new()
			var tbox := BoxMesh.new()
			tbox.size = Vector3(0.08, 0.025, 0.55)
			tick.mesh = tbox
			tick.position = Vector3(cos(angle) * (r - 0.35), 0.0, sin(angle) * (r - 0.35))
			tick.rotation.y = -angle + PI * 0.5
			tick.material_override = tick_mat
			zone.add_child(tick)
	var inner := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r * 0.96
	disc.bottom_radius = r * 0.96
	disc.height = 0.01
	disc.radial_segments = 24
	inner.mesh = disc
	var inner_mat := StandardMaterial3D.new()
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.albedo_color = Color(0.25, 0.85, 0.88, 0.08)
	inner.material_override = inner_mat
	zone.add_child(inner)


static func protects(point: Vector3, tree: SceneTree) -> bool:
	for flare in tree.get_nodes_in_group("active_flares"):
		if flare.is_queued_for_deletion() or flare.global_position.distance_to(point) > flare.data.effect_radius:
			continue
		var query := PhysicsRayQueryParameters3D.create(flare.global_position + Vector3.UP * 0.2, point, 1)
		if flare.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false
