class_name LagComp
extends RefCounted
## Host-side lag compensation for hitscan shots.
##
## Godot 4's PhysicsServer3D queues synchronous body transform updates until the
## next physics step, so rewinding CharacterBody3D nodes directly doesn't move
## intersect_ray() hits inside the same frame. Instead, we cast once against
## static world geometry (layer 1) to cap the ray at walls, then analytically
## test the ray against each enemy's (and Turned player's) vertical capsule at
## its recorded historical position for `now_ms - rewind_ms`.

const WORLD_LAYER := 1 << 0
const BOSS_LAYER := 1 << 2
const MAX_REWIND_MS := 250


## Exact ray vs vertical capsule intersection.
## `bottom` and `top` are the centers of the lower and upper hemisphere caps.
## Returns hit distance `t` along unit `dir` in [0, max_dist], or -1.0 on miss.
static func ray_capsule(origin: Vector3, dir: Vector3, bottom: Vector3, top: Vector3, radius: float, max_dist: float) -> float:
	var best := INF
	var r2 := radius * radius

	# 1. Infinite vertical cylinder along X/Z around bottom.x, bottom.z.
	var ox := origin.x - bottom.x
	var oz := origin.z - bottom.z
	var a := dir.x * dir.x + dir.z * dir.z
	if a > 0.000001:
		var b := 2.0 * (ox * dir.x + oz * dir.z)
		var c := ox * ox + oz * oz - r2
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			for t: float in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
				if t >= 0.0 and t <= max_dist and t < best:
					var y := origin.y + dir.y * t
					if y >= bottom.y and y <= top.y:
						best = t

	# 2. Bottom and top hemisphere caps (full spheres clipped by best/min t).
	for center: Vector3 in [bottom, top]:
		var t_cap := _ray_sphere(origin, dir, center, radius, minf(max_dist, best))
		if t_cap >= 0.0 and t_cap < best:
			best = t_cap

	return best if best < INF else -1.0


static func _ray_sphere(origin: Vector3, dir: Vector3, center: Vector3, radius: float, max_dist: float) -> float:
	var oc := origin - center
	var b := oc.dot(dir)
	var c := oc.dot(oc) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var sq := sqrt(disc)
	var t0 := -b - sq
	if t0 >= 0.0 and t0 <= max_dist:
		return t0
	var t1 := -b + sq
	if t1 >= 0.0 and t1 <= max_dist:
		return t1
	return -1.0


## Capsule endpoints and radius for an EnemyBase or Player placed at `pos`.
static func capsule_at(node: Node3D, pos: Vector3) -> Array:
	var radius := 0.4
	var height := 1.7
	var center_y := 0.85
	var col := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is CapsuleShape3D:
		var cap := col.shape as CapsuleShape3D
		radius = cap.radius
		height = cap.height
		center_y = col.position.y
	var sx := maxf(absf(node.scale.x), absf(node.scale.z))
	var sy := absf(node.scale.y)
	var r := radius * sx
	var half_span := maxf(0.0, (height * sy) * 0.5 - r)
	var cy := pos.y + center_y * sy
	return [Vector3(pos.x, cy - half_span, pos.z), Vector3(pos.x, cy + half_span, pos.z), r]


## Cast one hitscan ray against static world geometry + rewound enemies / Turned
## players / boss parts. Returns up to `max_hits` sorted by ascending distance.
## Each entry: {"collider": Object, "position": Vector3, "rewound_pos": Vector3, "distance": float}.
static func cast_rewound(world: World3D, tree: SceneTree, origin: Vector3, dir: Vector3, max_range: float, shooter: Node, rewind_ms: int, max_hits: int) -> Array[Dictionary]:
	var space := world.direct_space_state
	var exclude: Array[RID] = []
	if shooter is CollisionObject3D:
		exclude.append(shooter.get_rid())

	# 1. World walls strictly limit reach so rewound targets can never be shot through cover.
	var wall_dist := max_range
	var wall_q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, WORLD_LAYER, exclude)
	var wall_hit := space.intersect_ray(wall_q)
	if not wall_hit.is_empty():
		wall_dist = origin.distance_to(wall_hit.position)

	var target_ms := Time.get_ticks_msec() - clampi(rewind_ms, 0, MAX_REWIND_MS)
	var hits: Array[Dictionary] = []

	# 2. Rewound enemies (analytical vertical capsule).
	for node in tree.get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_inside_tree() or enemy.health <= 0.0:
			continue
		var pos: Vector3 = enemy.sample_position(target_ms) if enemy.has_method("sample_position") else enemy.global_position
		var cap := capsule_at(enemy, pos)
		var t := ray_capsule(origin, dir, cap[0], cap[1], cap[2], wall_dist)
		if t >= 0.0:
			hits.append({"collider": enemy, "position": origin + dir * t, "rewound_pos": pos, "distance": t})

	# 3. Rewound Turned players (if any).
	for node in tree.get_nodes_in_group("players"):
		if node == shooter or node.get("state") != "turned" or not (node is Node3D):
			continue
		var p := node as Node3D
		var pos: Vector3 = p.sample_position(target_ms) if p.has_method("sample_position") else p.global_position
		var cap := capsule_at(p, pos)
		var t := ray_capsule(origin, dir, cap[0], cap[1], cap[2], wall_dist)
		if t >= 0.0:
			hits.append({"collider": p, "position": origin + dir * t, "rewound_pos": pos, "distance": t})

	# 4. Boss parts (large slow targets — use physics raycast up to wall_dist).
	if not tree.get_nodes_in_group("boss_parts").is_empty():
		var boss_exclude := exclude.duplicate()
		for _i in 4:
			var bq := PhysicsRayQueryParameters3D.create(origin, origin + dir * wall_dist, BOSS_LAYER, boss_exclude)
			var bh := space.intersect_ray(bq)
			if bh.is_empty():
				break
			boss_exclude.append(bh.rid)
			if bh.collider is Node and (bh.collider as Node).is_in_group("boss_parts"):
				var bd := origin.distance_to(bh.position)
				hits.append({"collider": bh.collider, "position": bh.position, "rewound_pos": Vector3.INF, "distance": bd})

	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	if hits.size() > max_hits:
		hits.resize(max_hits)
	return hits
