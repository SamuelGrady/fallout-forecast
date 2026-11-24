class_name WeaponProjectile
extends Node3D
## The host moves, deploys and expires effects. Replicas render host events.
##
## Lightning Rod Spike: planted, it charges for data.effect_time (a humming,
## sparking telegraph on every peer), then the host calls a real strike down
## on it (WeatherManager.strike_at) and the bolt blasts, stuns and reveals the
## infected around it. Players are never hurt by their own rod.

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
var _dome_rim: MeshInstance3D
var _dome_shell: MeshInstance3D
var _dome_replica_left := 0.0
var _dome_warning := DomeWarning.NONE
static var _ring: TorusMesh
static var _hemisphere: SphereMesh
static var _zone_mats: Dictionary = {}

enum DomeWarning { NONE, STEADY, PULSE }
const DOME_PULSE_PERIOD := 0.60
const DOME_WARNING_TIME := 3.0 * DOME_PULSE_PERIOD
const DOME_WARNING_COLOR := Color("#ffc365")
const ROD_ARC_COLOR := Color(0.62, 0.95, 1.0)
const ROD_STUN := 1.1
const ROD_REVEAL := 3.0

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
	set_process(false)
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
		if id == "lightning_rod":
			left -= delta
			if left <= 0.0:
				_call_down_strike()
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
					hit.collider.ignite(3.0, 18.0 * scale, source)
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
			if id == "umbrella":
				add_to_group("repair_weapon_zones")
		"bleach_bomb":
			add_to_group("repair_weapon_zones")
		"flare_launcher":
			add_to_group("dry_weapon_zones")
		"bait_radio":
			if Net.is_host():
				add_to_group("enemy_lures")
		"sandbag":
			_make_wall()
			add_to_group("sandbag_walls")
		"lightning_rod":
			add_to_group("lightning_rods")
			if left <= 0.0:
				left = maxf(data.effect_time, 0.1)
	if not Net.dedicated:
		_build_zone(announce)
	if _dome_shell:
		_dome_replica_left = duration
		_update_dome_warning(duration)
		set_process(true)

func _process(delta: float) -> void:
	# Deploy events and late-join snapshots already carry the lifetime.
	# Replicas count it down for visuals while the host owns removal.
	if Net.is_host():
		_update_dome_warning(left)
	else:
		_dome_replica_left = maxf(0.0, _dome_replica_left - delta)
		_update_dome_warning(_dome_replica_left)

func _update_dome_warning(remaining: float) -> void:
	if remaining > DOME_WARNING_TIME:
		return
	var warning := DomeWarning.STEADY
	if not Settings.reduced_flash and remaining > 0.0:
		var pulse_time := fposmod(DOME_WARNING_TIME - remaining, DOME_PULSE_PERIOD)
		if pulse_time < 0.20:
			warning = DomeWarning.PULSE
	if warning == _dome_warning:
		return
	_dome_warning = warning
	var bright := warning == DomeWarning.PULSE
	_dome_rim.material_override = _zone_material(DOME_WARNING_COLOR, 0.96 if bright else 0.64)
	_dome_shell.material_override = _zone_material(DOME_WARNING_COLOR, 0.29 if bright else 0.13)

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
			_rod_charge_fx()
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
	if announce and not data.deploy_sound.is_empty():
		Sound.play_at(data.deploy_sound, global_position, -10.0)
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
	if announce and id == "shield_dome" and not Settings.reduced_flash:
		var radius_scale := rim.scale
		rim.scale = Vector3(0.18, 1.0, 0.18) * radius_scale
		rim.create_tween().tween_property(rim, "scale", radius_scale, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
		if id == "shield_dome":
			_dome_rim = rim
			_dome_shell = dome
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
	if id not in ["shield_dome", "umbrella", "flare_launcher", "bleach_bomb", "disruptor"]:
		return
	var source: Node = shooter if is_instance_valid(shooter) else null
	var scale := float(ItemCatalog.DAMAGE_SCALE[tier])
	if id != "umbrella":
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
					enemy.suppress_mutations(0.6)
					enemy.weaken(0.6)
					enemy.reveal(0.65)
					enemy.take_damage(14.0 * scale * 0.25, source)
				"flare_launcher", "bleach_bomb":
					enemy.reveal(0.65)
					var dps: float = 18.0 * scale if id == "flare_launcher" else data.damage
					if id == "flare_launcher":
						enemy.ignite(2.5, dps, source)
					else:
						enemy.take_damage(dps * 0.25, source)
		if source:
			source.end_hit_batch()
	if id == "umbrella":
		for target: Node3D in GameManager.players():
			var offset := target.global_position - global_position
			if Vector2(offset.x, offset.z).length() <= data.effect_radius and absf(offset.y) < 2.7:
				WeaponCombat.repair(target, 0.625)
	if id == "bleach_bomb":
		for target: Node3D in GameManager.players():
			if _contains(target.global_position + Vector3.UP):
				WeaponCombat.repair(target, 2.6)
		for cloud: Node3D in get_tree().get_nodes_in_group("spore_clouds"):
			if not cloud.get("acid") or cloud.is_queued_for_deletion():
				continue
			var positions: Array = cloud.lobe_world_positions() if cloud.has_method("lobe_world_positions") else [cloud.global_position]
			for pos: Vector3 in positions:
				if _contains(pos + Vector3.UP * 0.25):
					GameManager.disperse_cloud(cloud)
					break

func _contains(point: Vector3) -> bool:
	return global_position.distance_to(point) <= data.effect_radius \
			and WeaponCombat.clear_path(get_world_3d(), global_position + Vector3.UP * 0.25, point)

## Every peer: the planted rod's telegraph. A ring sweeps in from the blast
## radius, sparks spit off the tip and an electric hum climbs until the strike.
func _rod_charge_fx() -> void:
	var charge := maxf(left, 0.1)
	var tip := Vector3.UP * 0.95
	Sound.play_at("static_power", global_position + tip, -4.0, 0.85)
	var sweep_mesh := TorusMesh.new()
	sweep_mesh.inner_radius = 0.9
	sweep_mesh.outer_radius = 1.0
	sweep_mesh.rings = 28
	sweep_mesh.ring_segments = 4
	var sweep := MeshInstance3D.new()
	sweep.mesh = sweep_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	mat.albedo_color = Color(ROD_ARC_COLOR, 0.35)
	sweep.material_override = mat
	sweep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var radius := maxf(data.effect_radius, 1.0)
	sweep.scale = Vector3(radius, 0.6, radius)
	sweep.position.y = 0.08
	add_child(sweep)
	var tween := sweep.create_tween().set_parallel(true)
	tween.tween_property(sweep, "scale", Vector3(0.25, 0.6, 0.25), charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "albedo_color:a", 0.95, charge)
	# Sparks crackle off the tip, faster as the charge peaks.
	var spark_tween := create_tween()
	var steps := 5
	for i in steps:
		spark_tween.tween_interval(charge / steps * (1.0 - i * 0.12))
		spark_tween.tween_callback(func():
			if is_inside_tree() and registry:
				ShotFX.sparks(registry, global_position + tip, Vector3.UP, 3 + i))
	spark_tween.tween_callback(func():
		if is_inside_tree():
			Sound.play_at("static_shock", global_position + tip, -14.0, 1.4))
	if not OS.has_feature("web"):
		_light = OmniLight3D.new()
		_light.light_color = ROD_ARC_COLOR
		_light.light_energy = 0.2
		_light.omni_range = 4.0
		_light.shadow_enabled = false
		_light.position = tip
		add_child(_light)
		_light.create_tween().tween_property(_light, "light_energy", 2.6, charge).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)


## Host: the charge is done. The sky answers: a real strike on this spot for
## every peer (bolt, flash, thunder, reveals), then the electric blast.
func _call_down_strike() -> void:
	if not Net.is_host() or is_queued_for_deletion():
		return
	WeatherManager.strike_at(global_position)
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
	var rod := id == "lightning_rod"
	var targets := get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("boss_parts")
	# The rod's bolt is aimed: it never hurts the squad. Frags still do.
	if not rod:
		targets += GameManager.players()
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
			if rod and target.health > 0.0:
				target.stagger(ROD_STUN)
				target.reveal(ROD_REVEAL)
		else:
			target.take_damage(damage * falloff, source)
	if source:
		source.end_hit_batch()
	var dry: Dictionary = {}
	for puddle: Node3D in get_tree().get_nodes_in_group("puddles"):
		if puddle.global_position.distance_to(at) <= radius + puddle.radius() \
				and WeaponCombat.clear_path(get_world_3d(), eye, puddle.global_position + Vector3.UP * 0.2):
			puddle.clear()
			dry[puddle.get_path()] = 0.0
	WeatherManager.replicate_puddle_growth(dry)
	registry.effect_finished(seq, at, true)

func finish(at: Vector3, blast: bool) -> void:
	hide()
	set_process(false)
	for group: String in ["active_flares", "dry_weapon_zones", "repair_weapon_zones", "enemy_lures", "sandbag_walls", "lightning_rods"]:
		if is_in_group(group):
			remove_from_group(group)
	if not Net.dedicated:
		if blast and id == "lightning_rod":
			# The strike itself (LightningFX) brings the bolt, flash, shake
			# and thunder; this is the electric splash on the ground.
			Sound.play_at("static_shock", at + Vector3.UP * 0.5, -2.0, 0.8)
			ShotFX.puff(registry, at + Vector3.UP * 0.3, Color(ROD_ARC_COLOR, 0.8), data.effect_radius * 0.22, 0.32)
			ShotFX.sparks(registry, at + Vector3.UP * 0.3, Vector3.UP, 16)
		elif blast:
			Juice.shake(0.7, at)
			Sound.play_at(data.blast_sound, at)
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

static func repairing(point: Vector3, tree: SceneTree) -> bool:
	for zone: WeaponProjectile in tree.get_nodes_in_group("repair_weapon_zones"):
		if zone.id == "umbrella":
			var offset := point - zone.global_position
			if Vector2(offset.x, offset.z).length() <= zone.data.effect_radius and absf(offset.y) < 2.7:
				return true
		elif zone._contains(point):
			return true
	return false
