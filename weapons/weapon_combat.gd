class_name WeaponCombat
extends RefCounted

static func clear_path(world: World3D, from: Vector3, to: Vector3) -> bool:
	if from.is_equal_approx(to):
		return true
	return world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()

static func throw_origin(world: World3D, eye: Vector3, dir: Vector3) -> Vector3:
	var want := eye + dir * 0.45
	return want if clear_path(world, eye, want) else eye

static func can_use(holder: WeaponHolder, id: String, dir: Vector3) -> bool:
	match id:
		"med_tin":
			return holder.player.health < holder.player.max_health
		"suit_patch":
			return holder.player.suit_integrity < 100.0
		"sandbag", "lightning_rod":
			return placement(holder, dir) != Vector3.INF
	return true

static func placement(holder: WeaponHolder, dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var at := holder.loot.ground_at(holder.player, flat * 2.0)
	if at == Vector3.INF:
		return at
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 0.75, 0.8) if holder.equipped_id == "sandbag" else Vector3(0.35, 0.75, 0.35)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 7
	query.shape = box
	query.transform = Transform3D(Basis.looking_at(flat if flat != Vector3.ZERO else Vector3.FORWARD), at + Vector3.UP * 0.43)
	return at if holder.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty() else Vector3.INF

static func resolve(holder: WeaponHolder, item: ItemInstance, origin: Vector3, dir: Vector3, seed: int, spread: float, ads: bool, lucky: bool, rewind_ms: int) -> Array:
	var data := ItemCatalog.definition(item.id).weapon
	var damage: float = data.damage * float(ItemCatalog.DAMAGE_SCALE[item.tier])
	var world := holder.get_world_3d()
	var shooter := holder.player
	var registry := holder.loot
	if data.pull_radius > 0.0:
		for enemy: EnemyBase in holder.get_tree().get_nodes_in_group("enemies"):
			var pull := shooter.global_position - enemy.global_position
			pull.y = 0.0
			if pull.length() <= data.pull_radius:
				enemy.knockback(pull.normalized() * 9.0)
	match data.kind:
		WeaponData.Kind.PLACE:
			var at := placement(holder, dir)
			registry.place(item.id, at, dir, item.tier, shooter)
			return []
		WeaponData.Kind.USE:
			if data.mechanic == "heal":
				shooter.heal(data.damage)
			else:
				repair(shooter, data.damage)
			return []
		WeaponData.Kind.HITSCAN:
			pass
		_:
			registry.launch(item.id, throw_origin(world, origin, dir), dir, item.tier, shooter)
			return []
	damage *= GameManager.ads_damage_scale() if ads else 1.0
	if data.mechanic == "gust":
		return _gust(holder, origin, dir, data, damage)
	var traces: Array = []
	var voltaic := GameManager.has_player_mutation("voltaic_veins") and holder._shot_counter % 4 == 0
	var special_hits: Dictionary = {}
	var flinches: Dictionary = {}
	for ray: Vector3 in pellet_rays(dir, seed, spread, data.pellets):
		var hits := _cast_hits(holder, origin, ray, data.max_range, data.pierce + 1 + GameManager.extra_pierce(), rewind_ms)
		if data.mechanic == "reel":
			_find_submerged(holder, origin, ray, data.max_range, hits)
		var terminal := origin + ray * data.max_range
		var impact := 0
		if data.mechanic == "wash":
			var friendly := _teammate_ray(holder, origin, ray, data.max_range)
			if not friendly.is_empty() and (hits.is_empty() or friendly.distance < origin.distance_to(hits[0].position)):
				repair(friendly.collider, 2.4)
				traces.append([friendly.position, 1])
				_clear_hazards(holder, origin, ray, data.max_range, 0.94, true)
				continue
			_clear_hazards(holder, origin, ray, data.max_range, 0.94, true)
		for hit: Dictionary in hits:
			var target: Object = hit.collider
			var at: Vector3 = hit.position
			var distance := origin.distance_to(at)
			if impact == 0:
				terminal = at
				impact = 2 if is_damageable(target) else _surface_impact(target)
			if not is_damageable(target):
				break
			var falloff := clampf(1.0 - 0.7 * maxf(distance - data.max_range * 0.5, 0.0) / (data.max_range * 0.5), 0.3, 1.0)
			if data.mechanic == "reel" and target.has_method("harpoon_surface"):
				target.harpoon_surface()
			var amount: float = 9999.0 if lucky else damage * falloff
			if target.has_method("take_bullet"):
				if target is EnemyBase:
					var critical: bool = target.take_bullet(amount, at, shooter, hit.get("rewound_pos", Vector3.INF), data.critical_bonus)
					var existing: Array = flinches.get(target, [])
					if existing.is_empty() or (critical and not existing[2]):
						flinches[target] = [target.net_id, ray, critical]
				else:
					target.take_bullet(amount, at, shooter)
			else:
				target.take_damage(amount, shooter)
			var enemy := target as EnemyBase
			if enemy == null or enemy.health <= 0.0:
				continue
			var force := Vector3(ray.x, 0, ray.z).normalized() * data.knockback * falloff / data.pellets
			if data.knockback > 0.0 and _allows_impact(enemy, origin):
				enemy.knockback(force)
			if not special_hits.has(enemy):
				special_hits[enemy] = true
				_hit_special(holder, enemy, at, ray, origin, data, damage)
			if voltaic:
				voltaic = false
				_chain(holder, enemy, at, 18.0, 2, false)
		if data.mechanic == "suppress":
			registry.place("disruptor", terminal, dir, item.tier, shooter)
		traces.append([terminal, impact])
	if not flinches.is_empty():
		var rows: Array = []
		for enemy: EnemyBase in flinches:
			if enemy.health > 0.0:
				var row: Array = flinches[enemy]
				rows.append(row)
				if not Net.dedicated:
					enemy.impact_reaction.emit(row[1], row[2])
		var spawner := holder.get_tree().current_scene.get_node_or_null("Enemies")
		if Net.is_online() and spawner and not rows.is_empty():
			spawner.notify_impacts(rows)
	return traces

static func _surface_impact(target: Object) -> int:
	var node := target as Node
	while node and node != node.get_tree().current_scene:
		var label := str(node.name).to_lower()
		if "metal" in label or "container" in label or "vehicle" in label or "railing" in label:
			return 3
		node = node.get_parent()
	return 1

static func _allows_impact(enemy: EnemyBase, origin: Vector3) -> bool:
	return not enemy.has_method("blocks_impact") or not enemy.blocks_impact(origin)

static func _cast_hits(holder: WeaponHolder, origin: Vector3, dir: Vector3, distance: float, passes: int, rewind_ms: int) -> Array:
	var result: Array = []
	if rewind_ms > 0:
		result.assign(LagComp.cast_rewound(holder.get_world_3d(), holder.get_tree(), origin, dir, distance, holder.player, rewind_ms, passes))
		if not result.is_empty():
			return result
		# Rewind is authoritative for moving targets. Only show geometry on a miss.
		var wall := holder.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir * distance, 1))
		if not wall.is_empty():
			result.append(wall)
		return result
	var exclude: Array[RID] = [holder.player.get_rid()]
	var end := origin + dir * distance
	for i in passes:
		var ray := PhysicsRayQueryParameters3D.create(origin, end, 7, exclude)
		var hit := holder.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			break
		if hit.collider.is_in_group("players") and not is_damageable(hit.collider):
			exclude.append(hit.rid)
			# Friendly bodies should not use up a penetration.
			ray.exclude = exclude
			hit = holder.get_world_3d().direct_space_state.intersect_ray(ray)
			while not hit.is_empty() and hit.collider.is_in_group("players") and not is_damageable(hit.collider):
				exclude.append(hit.rid)
				ray.exclude = exclude
				hit = holder.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty():
				break
		result.append(hit)
		if not is_damageable(hit.collider):
			break
		exclude.append(hit.rid)
	return result

static func _teammate_ray(holder: WeaponHolder, from: Vector3, dir: Vector3, length: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * length, 3, [holder.player.get_rid()])
	var hit := holder.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.is_in_group("players") and hit.collider.state == "ok":
		hit["distance"] = from.distance_to(hit.position)
		return hit
	return {}

static func _find_submerged(holder: WeaponHolder, origin: Vector3, ray: Vector3, length: float, hits: Array) -> void:
	var limit := length if hits.is_empty() else origin.distance_to(hits[0].position)
	var best: EnemyBase
	var point := Vector3.ZERO
	for enemy: EnemyBase in holder.get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("harpoon_surface") or not enemy.get("_submerged"):
			continue
		var at := enemy.global_position + Vector3.UP * 0.15
		var distance := (at - origin).dot(ray)
		if distance > 0 and distance < limit and (origin + ray * distance).distance_to(at) < 0.72 \
				and clear_path(holder.get_world_3d(), origin, at):
			best = enemy
			point = at
			limit = distance
	if best:
		hits.push_front({"collider": best, "position": point})
		hits.resize(1)

static func _hit_special(holder: WeaponHolder, enemy: EnemyBase, point: Vector3, ray: Vector3, origin: Vector3, data: WeaponData, damage: float) -> void:
	match data.mechanic:
		"pin":
			if (enemy.is_small or enemy.data.display_name in ["Sleet", "Gutter", "Drip"]) and enemy.miniboss_wave == 0 \
					and not clear_path(holder.get_world_3d(), point, point + ray * 1.4):
				enemy.stagger(1.15)
				enemy.reveal(1.15)
		"salt":
			if _allows_impact(enemy, origin):
				enemy.stagger(0.52)
			if enemy.has_method("salt_stun"):
				enemy.salt_stun()
		"zap":
			_chain(holder, enemy, point, damage * 0.72, 2, true)
		"reel":
			var pull := holder.player.global_position - enemy.global_position
			pull.y = 0.0
			if _allows_impact(enemy, origin) and pull.length_squared() > 0.001:
				enemy.stagger(0.8)
				enemy.knockback(pull.normalized() * 15.0)

static func _chain(holder: WeaponHolder, first: EnemyBase, point: Vector3, damage: float, hops: int, water: bool) -> void:
	var visited: Array[EnemyBase] = [first]
	var points: Array = [point]
	var bonus := 0
	var active := first
	for hop in range(hops + (3 if water else 0)):
		if hop >= hops + bonus:
			break
		var wet := water and _in_water(holder.get_tree(), active.global_position)
		var best: EnemyBase
		var reach := 12.0 if wet else 7.0
		for enemy: EnemyBase in holder.get_tree().get_nodes_in_group("enemies"):
			if enemy in visited or enemy.health <= 0.0:
				continue
			var at := enemy.global_position + Vector3.UP
			var distance := point.distance_to(at)
			if distance < reach and clear_path(holder.get_world_3d(), point, at):
				best = enemy
				reach = distance
		if best == null:
			break
		if wet:
			bonus = mini(3, bonus + 1)
		visited.append(best)
		active = best
		point = best.global_position + Vector3.UP
		points.append(point)
		best.reveal(1.2)
		if _allows_impact(best, point):
			best.stagger(0.30)
		best.take_damage(damage * pow(0.84, hop), holder.player)
	if points.size() > 1:
		GameManager.broadcast_arc(points, Color("#fff267") if water else Color("#7aeeff"))

static func _in_water(tree: SceneTree, point: Vector3) -> bool:
	for puddle: Node3D in tree.get_nodes_in_group("puddles"):
		if puddle.radius() > 0.20 and absf(point.y - puddle.global_position.y) <= 0.8 \
				and Vector2(point.x - puddle.global_position.x, point.z - puddle.global_position.z).length() <= puddle.radius():
			return true
	return false

static func in_cone(world: World3D, from: Vector3, direction: Vector3, to: Vector3, length: float, cosine: float) -> bool:
	var offset := to - from
	return offset.length() <= length and direction.dot(offset.normalized()) >= cosine and clear_path(world, from, to)

static func _gust(holder: WeaponHolder, from: Vector3, dir: Vector3, data: WeaponData, damage: float) -> Array:
	_clear_hazards(holder, from, dir, data.max_range, 0.82, false)
	var traces: Array = []
	for enemy: EnemyBase in holder.get_tree().get_nodes_in_group("enemies"):
		var at := enemy.global_position + Vector3.UP
		if enemy.health > 0.0 and in_cone(holder.get_world_3d(), from, dir, at, data.max_range, 0.82):
			if enemy.has_method("blunt_shockwave"):
				enemy.blunt_shockwave()
			if _allows_impact(enemy, from):
				enemy.knockback((at - from).normalized() * data.knockback)
			enemy.take_damage(damage, holder.player)
			traces.append([at, 2])
	if traces.is_empty():
		traces.append([from + dir * data.max_range, 0])
	return traces

static func _clear_hazards(holder: WeaponHolder, from: Vector3, dir: Vector3, length: float, cosine: float, acid_only: bool) -> void:
	var world := holder.get_world_3d()
	for cloud: Node3D in holder.get_tree().get_nodes_in_group("spore_clouds"):
		if (acid_only and not cloud.acid) or cloud.is_queued_for_deletion():
			continue
		var target := cloud.global_position + Vector3.UP * 0.25
		var hit_cone := in_cone(world, from, dir, target, length, cosine)
		if not hit_cone:
			var offset := target - from
			var along := clampf(offset.dot(dir), 0.0, length)
			var closest := from + dir * along
			var radius: float = float(cloud.get("radius")) if cloud.get("radius") != null else 2.0
			hit_cone = along > 0.0 and Vector2(closest.x - target.x, closest.z - target.z).length() <= radius + 0.45 and absf(closest.y - target.y) <= 2.2 and clear_path(world, from, target)
		if hit_cone:
			GameManager.disperse_cloud(cloud)

static func repair(player: Node, amount: float) -> void:
	if player.state == "ok":
		player.suit_integrity = minf(100.0, player.suit_integrity + amount)

static func pellet_rays(dir: Vector3, seed: int, spread_degrees: float, count: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rays: Array[Vector3] = []
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	var spread := deg_to_rad(spread_degrees)
	for i in count:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * spread
		rays.append((dir + (side * cos(angle) + up * sin(angle)) * tan(radius)).normalized())
	return rays

static func is_damageable(target: Object) -> bool:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return false
	return target is EnemyBase or (target is Node and (target.is_in_group("boss_parts") \
			or (target.is_in_group("players") and target.get("state") == "turned")))

static func play_fx(parent: Node, id: String, muzzle: Vector3, traces: Array, local: bool, muzzle_fx := true) -> void:
	var data := ItemCatalog.definition(id).weapon
	if muzzle_fx and not data.shot_sound.is_empty():
		if local:
			Sound.play(data.shot_sound, -7.0)
		else:
			Sound.play_at(data.shot_sound, muzzle, -8.0)
	if data.kind != WeaponData.Kind.HITSCAN:
		return
	var stream := data.mechanic in ["wash", "gust", "zap", "reel", "suppress"]
	if muzzle_fx:
		ShotFX.puff(parent, muzzle, data.tracer_color, 0.09, 0.07)
		if not stream:
			ShotFX.flash(parent, muzzle, data.tracer_color, 3.5)
	var surface_contact := 0
	var contact_at := Vector3.ZERO
	var sum := Vector3.ZERO
	var hits := 0
	for i in traces.size():
		var end: Vector3 = traces[i][0]
		var impact: int = traces[i][1]
		if not OS.has_feature("web") or i < 3:
			if stream:
				ShotFX.beam(parent, muzzle, end, data.tracer_color, 0.14 if data.mechanic in ["wash", "gust"] else 0.06)
			else:
				ShotFX.tracer(parent, muzzle, end, data.tracer_color)
			if impact > 0:
				if impact == 3 and not stream:
					ShotFX.sparks(parent, end, (muzzle - end).normalized(), 3)
				else:
					ShotFX.puff(parent, end, Color("#b0f580") if impact == 2 else Color("#bbad99"), 0.08, 0.17)
		if surface_contact == 0 and impact in [1, 3]:
			surface_contact = impact
			contact_at = end
		if impact == 2:
			hits += 1
			sum += end
	if hits > 0 and not stream:
		Sound.play_at("hit_flesh", sum / hits, -18.0 + minf(6.0, 2.0 * (hits - 1)))
	elif surface_contact and not stream:
		Sound.play_at("reel_tick" if surface_contact == 3 else "step_1", contact_at, -23.0, 1.25)
