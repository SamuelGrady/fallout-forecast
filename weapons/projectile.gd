class_name WeaponProjectile
extends Node3D
## The host moves, deploys and expires effects. Replicas render host events.

var registry: RunLoot
var seq: int
var id: String
var data: WeaponData
var shooter: Node3D
var tier: int
var velocity: Vector3
var deployed := false
var left := 0.0
var yaw := 0.0
var age := 0.0
var _started_at: Vector3
var _replica_at: Vector3
var _exclude: Array[RID] = []
var _tick_left := 0.0
var _body: Node3D
var _visual: Node3D
var _light: OmniLight3D
static var _ring: TorusMesh
static var _hemisphere: SphereMesh
static var _zone_mats: Dictionary = {}

func configure(system: RunLoot, key: int, definition_id: String, at: Vector3, motion: Vector3, quality: int, source: Node3D) -> void:
	registry = system
	seq = key
	id = definition_id
	data = ItemCatalog.definition(id).weapon
	shooter = source
	tier = quality
	_started_at = at
	_replica_at = at
	velocity = motion
	if source is CollisionObject3D:
		_exclude.append(source.get_rid())

func _ready() -> void:
	global_position = _started_at
	if not Net.dedicated:
		_visual = ItemCatalog.projectile_model(id)
		add_child(_visual)

static func launch_velocity(weapon: WeaponData, dir: Vector3) -> Vector3:
	var lift := 3.0 if weapon.kind in [WeaponData.Kind.GRENADE, WeaponData.Kind.FLARE] else 0.0
	return dir * weapon.projectile_speed + Vector3.UP * lift

static func gravity(weapon: WeaponData) -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity")) * weapon.projectile_gravity

static func motion_hit(world: World3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	return world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WeaponHolder.HIT_MASK, exclude))

static func bounce(weapon: WeaponData, hit: Dictionary, motion: Vector3, elapsed: float) -> Vector3:
	var normal: Vector3 = hit.normal
	if weapon.kind == WeaponData.Kind.GRENADE:
		return motion.bounce(normal) * 0.4
	if weapon.kind == WeaponData.Kind.FLARE and normal.y < 0.6 and elapsed < 3.0 \
			and (weapon.mechanic != "burn" or not WeaponCombat.is_damageable(hit.collider)):
		return motion.bounce(normal) * 0.35
	return Vector3.ZERO

static func flight_time(weapon: WeaponData) -> float:
	return (weapon.fuse if weapon.fuse > 0.0 else weapon.effect_time) if weapon.kind == WeaponData.Kind.GRENADE else 5.0

func snapshot() -> Array:
	return [id, global_position, velocity, tier, deployed, left, yaw]

func sync_flight(at: Vector3, motion: Vector3) -> void:
	_replica_at = at
	velocity = motion

func _physics_process(delta: float) -> void:
	if deployed:
		if not Net.is_host():
			return
		if id == "shield_dome":
			_hold_out_enemies()
		if data.effect_time > 0.0:
			left -= delta
			if left <= 0.0:
				registry.effect_finished(seq, global_position, false)
				return
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = 0.25
			_tick_zone()
		return
	age += delta
	if not Net.is_host():
		velocity.y -= gravity(data) * delta
		_replica_at += velocity * delta
		global_position = global_position.lerp(_replica_at, clampf(delta * 18.0, 0.0, 1.0))
		return
	velocity.y -= gravity(data) * delta
	var next := global_position + velocity * delta
	var hit := motion_hit(get_world_3d(), global_position, next, _exclude)
	if hit.is_empty():
		global_position = next
	else:
		var normal: Vector3 = hit.normal
		global_position = (hit.position as Vector3) + normal * 0.07
		velocity = bounce(data, hit, velocity, age)
		if data.kind == WeaponData.Kind.ROCKET:
			explode()
			return
		if data.kind == WeaponData.Kind.FLARE and velocity == Vector3.ZERO:
			if data.mechanic == "burn" and WeaponCombat.is_damageable(hit.collider):
				var source: Node = shooter if is_instance_valid(shooter) else null
				var scale: float = float(ItemCatalog.DAMAGE_SCALE[tier])
				hit.collider.take_damage(data.damage * scale, source)
				if hit.collider is EnemyBase:
					hit.collider.ignite(3.0, 14.0 * scale, source)
			_host_deploy()
			return
	if data.kind == WeaponData.Kind.GRENADE and age >= flight_time(data):
		if id == "frag":
			explode()
		else:
			_host_deploy()
	elif age > 5.0:
		registry.effect_finished(seq, global_position, false)

func _host_deploy() -> void:
	deploy(global_position, data.effect_time, yaw)
	registry.effect_deployed(seq, global_position, data.effect_time, yaw)

func deploy(at: Vector3, duration: float, angle: float, announce := true) -> void:
	if deployed:
		return
	global_position = at
	deployed = true
	left = duration
	yaw = angle
	rotation.y = yaw
	if _visual:
		_visual.hide()
	match id:
		"shield_dome", "umbrella":
			_make_shelter()
			add_to_group("active_flares")
		"flare_launcher":
			add_to_group("dry_weapon_zones")
		"bait_radio":
			if Net.is_host():
				add_to_group("enemy_lures")
		"sandbag":
			_make_wall()
			add_to_group("sandbag_walls")
		"lightning_rod":
			if Net.is_host():
				add_to_group("lightning_rods")
				WeatherManager.lightning_struck.connect(_strike_rod)
	if not Net.dedicated:
		_build_zone(announce)

func _make_shelter() -> void:
	var area := Area3D.new()
	area.collision_layer = 8
	area.collision_mask = 0
	area.monitoring = false
	area.add_to_group("shelter")
	var collider := CollisionShape3D.new()
	if id == "umbrella":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = data.effect_radius
		cylinder.height = 2.7
		collider.shape = cylinder
		collider.position.y = 1.25
	else:
		var bubble := SphereShape3D.new()
		bubble.radius = data.effect_radius
		collider.shape = bubble
	area.add_child(collider)
	add_child(area)
	_body = area

func _make_wall() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.78, 0.72)
	collider.shape = shape
	collider.position.y = 0.39
	wall.add_child(collider)
	add_child(wall)
	_body = wall

func _build_zone(announce: bool) -> void:
	var color := data.tracer_color
	if id == "sandbag":
		var custom := ItemCatalog.prop_model("sandbag_wall")
		if custom:
			add_child(custom)
		else:
			var bag := ItemCatalog.placeholder(color)
			bag.scale = Vector3(1.8, 0.78, 0.72)
			bag.position.y = 0.39
			add_child(bag)
		return
	if id in ["bait_radio", "lightning_rod", "flare_launcher"]:
		_visual.show()
		if id == "lightning_rod":
			_visual.position = Vector3.ZERO
			_visual.rotation = Vector3.ZERO
		else:
			_visual.position.y = 0.25
	if id == "bait_radio":
		var audio := AudioStreamPlayer3D.new()
		var tune := load("res://assets/audio/sfx/gun_bait_loop.wav").duplicate() as AudioStreamWAV
		tune.loop_mode = AudioStreamWAV.LOOP_FORWARD
		tune.loop_end = int(tune.get_length() * tune.mix_rate)
		audio.stream = tune
		audio.volume_db = -16.0
		audio.max_distance = data.effect_radius
		add_child(audio)
		audio.play()
	if announce and id == "shield_dome":
		Perf.mark("shield dome deploy")
		Sound.play_at("dome_deploy", global_position, -7.0)
	elif announce:
		Sound.play_at("gun_field_deploy", global_position, -13.0)
	if data.effect_radius <= 0.0:
		return
	if _ring == null:
		_ring = TorusMesh.new()
		_ring.inner_radius = 0.96
		_ring.outer_radius = 1.0
		_ring.rings = 28
		_ring.ring_segments = 5
	var rim := MeshInstance3D.new()
	rim.mesh = _ring
	rim.material_override = _zone_material(color, 0.65)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.scale = Vector3(data.effect_radius, 1.0, data.effect_radius)
	rim.position.y = 0.055
	add_child(rim)
	var canopy_missing := false
	if id == "umbrella":
		var custom_umbrella := ItemCatalog.prop_model("umbrella_open")
		if custom_umbrella:
			add_child(custom_umbrella)
		else:
			canopy_missing = true
	if id in ["shield_dome", "bleach_bomb", "disruptor"] or canopy_missing:
		if _hemisphere == null:
			_hemisphere = SphereMesh.new()
			_hemisphere.radius = 1.0
			_hemisphere.height = 1.0
			_hemisphere.is_hemisphere = true
			_hemisphere.radial_segments = 24
			_hemisphere.rings = 8
		var dome := MeshInstance3D.new()
		dome.mesh = _hemisphere
		dome.material_override = _zone_material(color, 0.16)
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.scale = Vector3(data.effect_radius, 2.4 if id == "umbrella" else data.effect_radius, data.effect_radius)
		add_child(dome)
	if not OS.has_feature("web") and not Net.dedicated and id in ["shield_dome", "flare_launcher"]:
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 1.8
		_light.omni_range = data.effect_radius * 1.5
		_light.position.y = 0.6
		add_child(_light)

static func _zone_material(color: Color, alpha: float) -> StandardMaterial3D:
	var key := Color(color, alpha).to_rgba32()
	if not _zone_mats.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(color, alpha)
		_zone_mats[key] = material
	return _zone_mats[key]

func _tick_zone() -> void:
	if id not in ["shield_dome", "flare_launcher", "bleach_bomb", "disruptor"]:
		return
	var source: Node = shooter if is_instance_valid(shooter) else null
	if source:
		source.begin_hit_batch()
	for enemy: EnemyBase in get_tree().get_nodes_in_group("enemies"):
		var at := enemy.global_position + Vector3.UP
		if not _contains(at):
			continue
		match id:
			"shield_dome":
				enemy.reveal(0.65)
				enemy.weaken(0.6)
				var away := enemy.global_position - global_position
				away.y = 0.0
				if not enemy.has_method("blocks_impact") or not enemy.blocks_impact(global_position):
					enemy.knockback(away.normalized() * 3.5)
			"disruptor":
				enemy.suppress_mutations(0.45)
				enemy.reveal(0.65)
			"flare_launcher", "bleach_bomb":
				enemy.reveal(0.65)
				var dps: float = 14.0 * float(ItemCatalog.DAMAGE_SCALE[tier]) if id == "flare_launcher" else data.damage
				if id == "flare_launcher":
					enemy.ignite(2.5, dps, source)
				else:
					enemy.take_damage(dps * 0.25, source)
	if source:
		source.end_hit_batch()
	if id == "bleach_bomb":
		for target: Node3D in GameManager.players():
			if _contains(target.global_position + Vector3.UP):
				WeaponCombat.repair(target, 2.6)
		for cloud: Node3D in get_tree().get_nodes_in_group("spore_clouds"):
			if cloud.get("acid") and not cloud.is_queued_for_deletion() and _contains(cloud.global_position + Vector3.UP * 0.25):
				GameManager.disperse_cloud(cloud)

func _contains(point: Vector3) -> bool:
	return global_position.distance_to(point) <= data.effect_radius 		and WeaponCombat.clear_path(get_world_3d(), global_position + Vector3.UP * 0.25, point)

func _strike_rod(at: Vector3, _seed: int) -> void:
	if not is_queued_for_deletion() and at.is_equal_approx(global_position) and Net.is_host():
		explode()

func explode() -> void:
	if not Net.is_host() or is_queued_for_deletion():
		return
	Perf.mark("explosion " + data.display_name)
	var at := global_position
	var eye := at + Vector3.UP * 0.32
	var radius: float = data.effect_radius * GameManager.explosive_radius_scale()
	var damage: float = data.damage * float(ItemCatalog.DAMAGE_SCALE[tier]) * GameManager.explosive_damage_scale()
	var source: Node = shooter if is_instance_valid(shooter) else null
	if source:
		source.begin_hit_batch()
	var targets := get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss_parts") + GameManager.players()
	for target: Node3D in targets:
		if not WeaponCombat.is_damageable(target):
			continue
		var distance := target.global_position.distance_to(at)
		if distance > radius:
			continue
		var to := target.global_position + (Vector3.ZERO if target.is_in_group("boss_parts") else Vector3.UP * 0.9)
		if not WeaponCombat.clear_path(get_world_3d(), eye, to):
			continue
		var falloff := 1.0 - 0.6 * distance / radius
		if target is EnemyBase:
			var push := target.global_position - at
			push.y = 0.0
			var impulse := push.normalized() * data.knockback * falloff * GameManager.explosive_knockback_scale()
			target.take_blast(damage * falloff, source, at, impulse)
		else:
			target.take_damage(damage * falloff, source)
	if source:
		source.end_hit_batch()
	var dry: Dictionary = {}
	for puddle: Node3D in get_tree().get_nodes_in_group("puddles"):
		if puddle.global_position.distance_to(at) <= radius + puddle.radius() 				and WeaponCombat.clear_path(get_world_3d(), eye, puddle.global_position + Vector3.UP * 0.2):
			puddle.clear()
			dry[puddle.get_path()] = 0.0
	WeatherManager.replicate_puddle_growth(dry)
	registry.effect_finished(seq, at, true)

func finish(at: Vector3, blast: bool) -> void:
	hide()
	if WeatherManager.lightning_struck.is_connected(_strike_rod):
		WeatherManager.lightning_struck.disconnect(_strike_rod)
	for group: String in ["active_flares", "dry_weapon_zones", "enemy_lures", "sandbag_walls", "lightning_rods"]:
		if is_in_group(group):
			remove_from_group(group)
	if not Net.dedicated:
		if blast:
			Juice.shake(0.7, at)
			Sound.play_at("explosion_big" if id == "frag" else "explosion", at)
			ShotFX.puff(registry, at + Vector3.UP * 0.4, data.tracer_color, data.effect_radius * 0.3, 0.45)
			ShotFX.sparks(registry, at + Vector3.UP * 0.3, Vector3.UP, 12)
			ShotFX.flash(registry, at + Vector3.UP, data.tracer_color, 8.0, 0.15)
		elif id == "shield_dome" and deployed:
			Sound.play_at("dome_collapse", at, -10.0)
	queue_free()


## Host: the dome is a wall for infected. Anything inside (except the boss)
## is put back just outside the shell, so they can't walk in or be spawned in.
func _hold_out_enemies() -> void:
	var wall: float = data.effect_radius + 0.35
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or enemy.is_in_group("boss") or enemy.is_queued_for_deletion():
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance >= wall:
			continue
		var out := offset / distance if distance > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		enemy.global_position += out * (wall - distance)
		if enemy is CharacterBody3D:
			var body := enemy as CharacterBody3D
			var inward := body.velocity.dot(-out)
			if inward > 0.0:
				body.velocity += out * inward


## True if `point` is under an active Shield Dome or Umbrella Stand.
static func protects(point: Vector3, tree: SceneTree) -> bool:
	for dome: WeaponProjectile in tree.get_nodes_in_group("active_flares"):
		var offset := point - dome.global_position
		if dome.id == "umbrella" and Vector2(offset.x, offset.z).length() <= dome.data.effect_radius and absf(offset.y) < 2.7:
			return true
		if dome.id == "shield_dome" and offset.length() <= dome.data.effect_radius:
			return true
	return false

static func dries(point: Vector3, tree: SceneTree) -> bool:
	for zone: WeaponProjectile in tree.get_nodes_in_group("dry_weapon_zones"):
		if zone._contains(point):
			return true
	return false
