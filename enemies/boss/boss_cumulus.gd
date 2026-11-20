extends Node3D
## Boss_Cumulus (wave 5): a bloated spore cloud over the district that makes its
## own Acid Storm.
## - Three glowing sacs. Each one destroyed lowers storm_intensity a step
##   (1.0 -> 0.7 -> 0.3 -> 0.0) and drops the boss 4 m lower.
## - With all sacs gone the core's shell breaks and it can be killed.
## - It heals while rain falls on it (faster the harder it rains), unless a
##   Flare Gun flare burned near it in the last few seconds.
## - Attacks: lobs spore globs at players (exposed ones first) and calls in
##   Misters and Drips.
## Host runs all of it; the parts are built the same way on every peer.

signal defeated

const BossPart := preload("res://enemies/boss/boss_part.gd")
const STORM_STEPS := [0.7, 0.3, 0.0]

@export var sac_health := 300.0
@export var core_health := 800.0
@export var heal_per_second := 10.0
@export var spore_interval := 2.6
@export var summon_interval := 14.0
@export var drift_radius := 10.0
@export var drop_per_sac := 4.0

var part_health: Array[float] = [0.0, 0.0, 0.0, 0.0]  # sacs 0-2, core 3
var part_max: Array[float] = [0.0, 0.0, 0.0, 0.0]
var sacs_left := 3
var dead := false

var _anchor := Vector3.ZERO
var _height := 0.0
var _t := 0.0
var _burn_left := 0.0
var _net_left := 0.0
var _spore_timer := 3.0
var _summon_timer := 8.0
var _parts: Array[Node] = []
var _sac_halos: Array[MeshInstance3D] = []
var _shell: MeshInstance3D
var _body: Node3D
var _cloud_material := StandardMaterial3D.new()
var _sac_material := StandardMaterial3D.new()
var _core_material := StandardMaterial3D.new()
var _core_rings: Node3D
var _entrance_left := 1.8


func _ready() -> void:
	add_to_group("boss")
	_anchor = global_position
	_height = _anchor.y + 16.0
	var scale_hp := GameManager.enemy_health_scale() if GameManager.has_method("enemy_health_scale") else 1.0
	for i in 3:
		part_max[i] = sac_health * scale_hp
	part_max[3] = core_health * scale_hp
	part_health = part_max.duplicate()
	_build()
	scale = Vector3.ONE * 0.15
	create_tween().tween_property(self, "scale", Vector3.ONE, 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if Net.is_host():
		WeatherManager.strike_lightning()


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_cloud_material.albedo_color = Color(0.36, 0.48, 0.28)
	_cloud_material.roughness = 1.0
	_cloud_material.disable_fog = true
	_cloud_material.emission_enabled = true
	_cloud_material.emission = Color(0.12, 0.2, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 9:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		var r := rng.randf_range(2.6, 4.2)
		s.radius = r
		s.height = r * 1.6
		s.radial_segments = 10
		s.rings = 6
		s.material = _cloud_material
		m.mesh = s
		m.position = Vector3(rng.randf_range(-4, 4), rng.randf_range(0.5, 2.5), rng.randf_range(-4, 4))
		_body.add_child(m)

	_sac_material.albedo_color = Color(0.85, 1.0, 0.3)
	_sac_material.emission_enabled = true
	_sac_material.emission = Color(0.6, 1.0, 0.2)
	_sac_material.emission_energy_multiplier = 2.2
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.albedo_color = Color(0.82, 1.0, 0.32, 0.72)
	for i in 3:
		var a := TAU * i / 3.0
		var sac := _make_part("Sac%d" % i, i, 1.7, Vector3(cos(a) * 5.0, -1.2, sin(a) * 5.0), _sac_material)
		var halo := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.rings = 24
		torus.ring_segments = 6
		torus.inner_radius = 2.05
		torus.outer_radius = 2.32
		halo.mesh = torus
		halo.material_override = halo_mat
		sac.add_child(halo)
		_sac_halos.append(halo)
		_parts.append(sac)

	_core_material.albedo_color = Color(1.0, 0.3, 0.6)
	_core_material.emission_enabled = true
	_core_material.emission = Color(1.0, 0.2, 0.5)
	_core_material.emission_energy_multiplier = 1.6
	var core := _make_part("Core", 3, 2.2, Vector3(0, -1.8, 0), _core_material)
	_parts.append(core)
	_core_rings = Node3D.new()
	_core_rings.visible = false
	core.add_child(_core_rings)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color("#ff5689")
	for tilt in [Vector3(0.4, 0, 0.2), Vector3(-0.5, 0.3, 0.7)]:
		var rmesh := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.rings = 24
		torus.ring_segments = 6
		torus.inner_radius = 2.75
		torus.outer_radius = 3.0
		rmesh.mesh = torus
		rmesh.rotation = tilt
		rmesh.material_override = ring_mat
		_core_rings.add_child(rmesh)

	_shell = MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radial_segments = 12
	shell_mesh.rings = 6
	shell_mesh.radius = 2.85
	shell_mesh.height = 5.7
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.5, 0.7, 0.4, 0.58)
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mesh.material = shell_mat
	_shell.mesh = shell_mesh
	_shell.position = Vector3(0, -1.8, 0)
	add_child(_shell)


func _make_part(part_name: String, i: int, radius: float, pos: Vector3, material: Material) -> Node:
	var body := StaticBody3D.new()
	body.name = part_name
	body.set_script(BossPart)
	body.position = pos
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	cs.shape = sphere
	body.add_child(cs)
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 12
	sm.rings = 6
	sm.radius = radius
	sm.height = radius * 2.0
	sm.material = material
	m.mesh = sm
	body.add_child(m)
	add_child(body)
	body.boss = self
	body.index = i
	return body


func _process(delta: float) -> void:
	_t += delta
	_body.rotation.y += delta * 0.15
	_sac_material.emission_energy_multiplier = 2.0 + sin(_t * 5.0) * 1.1
	for i in _sac_halos.size():
		var halo := _sac_halos[i]
		if is_instance_valid(halo):
			halo.rotation.x += delta * 1.4
			halo.rotation.y += delta * 1.9
			var s := 1.0 + 0.12 * sin(_t * 5.0 + i * 2.1)
			halo.scale = Vector3.ONE * s
	if _core_rings and _core_rings.visible:
		_core_rings.rotation.y += delta * 2.2
		_core_rings.rotation.x += delta * 1.1
		_core_material.emission_energy_multiplier = 2.6 + sin(_t * 7.5) * 1.2
	_cloud_material.emission = Color(0.65, 0.28, 0.08) if is_burning() else Color(0.12, 0.2, 0.08)
	# Clients only draw it: position, part health and the burn timer ride one
	# unreliable packet ten times a second, the kill is sent reliably below.
	if Net.is_host() and Net.is_online():
		_net_left -= delta
		if _net_left <= 0.0:
			_net_left = 0.1
			Net.rpc_to_run(_sync, [global_position, part_health, sacs_left, _burn_left])
	if not Net.is_host() or dead:
		return
	if _entrance_left > 0.0:
		_entrance_left = maxf(0.0, _entrance_left - delta)
	# Drift around the map's anchor and sink as sacs pop.
	var goal_height := _anchor.y - drop_per_sac * (3 - sacs_left)
	var descend_rate := 10.0 if _entrance_left > 0.0 else 2.2
	_height = move_toward(_height, goal_height, delta * descend_rate)
	var drift := Vector3(cos(_t * 0.12), 0, sin(_t * 0.12)) * drift_radius
	global_position = _anchor + drift + Vector3(0, _height - _anchor.y + sin(_t * 0.8) * 0.6, 0)
	# Rain heals it, unless a flare is burning nearby.
	_burn_left -= delta
	if _burn_left <= 0.0:
		var heal := heal_per_second * WeatherManager.storm_intensity * delta
		for i in 4:
			if part_health[i] > 0.0:
				part_health[i] = minf(part_health[i] + heal, part_max[i])
	_spore_timer -= delta
	if _spore_timer <= 0.0:
		_spore_timer = spore_interval
		_lob_spore()
	_summon_timer -= delta
	if _summon_timer <= 0.0:
		_summon_timer = summon_interval
		_summon()


## A flare burning near the boss stops its healing for a moment.
func burn(seconds: float) -> void:
	_burn_left = maxf(_burn_left, seconds)


func is_burning() -> bool:
	return _burn_left > 0.0


func core_exposed() -> bool:
	return sacs_left == 0


var _last_deflect_ms := 0


func damage_part(i: int, amount: float, source: Node, point := Vector3.INF) -> void:
	if not Net.is_host() or dead or part_health[i] <= 0.0:
		return
	var at: Vector3 = point if point != Vector3.INF else (_parts[i] as Node3D).global_position
	var shooter := is_instance_valid(source) and source.is_in_group("players")
	if i == 3 and not core_exposed():
		# Shielded core: metallic deflect so players know to pop the sacs first.
		if shooter and Time.get_ticks_msec() - _last_deflect_ms > 90:
			_last_deflect_ms = Time.get_ticks_msec()
			var away := Vector3.UP
			if source is Node3D:
				away = ((source as Node3D).global_position - at).normalized()
			ShotFX.sparks(get_parent(), at, away, 6)
			Sound.play_at("lever", at, -6.0, 1.8)
		return
	var before := part_health[i]
	part_health[i] = maxf(part_health[i] - amount, 0.0)
	# Hit marker and stacked number on the shooter's screen, host or client
	# (Player.notify_hit). Ids from 900000 keep boss parts apart from enemies.
	if shooter and source.has_method("notify_hit"):
		source.notify_hit(part_health[i] <= 0.0, false, at, ceili(before - part_health[i]), 900000 + i)
	if part_health[i] <= 0.0:
		if i < 3:
			_pop_sac(i)
		else:
			_die()


func total_fraction() -> float:
	var now := 0.0
	var full := 0.0
	for i in 4:
		now += part_health[i]
		full += part_max[i]
	return now / full


func _pop_sac(i: int) -> void:
	Juice.shake(0.8)
	Juice.duck_music(-6.0, 1.0)
	sacs_left -= 1
	var part: Node3D = _parts[i]
	Sound.play_at("explosion", part.global_position)
	# Sac shatter: a wet low burst plus a rising reel tick per sac popped.
	Sound.play("spore_burst", -4.0, 0.6)
	Sound.play("reel_land", -8.0, 0.9 + 0.15 * (3 - sacs_left))
	ShotFX.flash(get_parent(), part.global_position, Color(0.8, 1.0, 0.3), 8.0, 0.18)
	GameManager.spawn_cloud(part.global_position, 10.0, 4.0)
	part.visible = false
	part.collision_layer = 0
	WeatherManager.set_intensity_override(STORM_STEPS[2 - sacs_left])
	if sacs_left == 0:
		_shatter_shell()


func _shatter_shell() -> void:
	Sound.play_at("explosion_big", _shell.global_position)
	ShotFX.flash(get_parent(), _shell.global_position, Color("#ff5689"), 10.0, 0.25)
	_shell.visible = false
	if _core_rings:
		_core_rings.visible = true
	for k in 8:
		var shard := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 0.45, 0.3)
		shard.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.78, 0.45)
		shard.material_override = mat
		get_parent().add_child(shard)
		shard.global_position = _shell.global_position
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.4, 1.0), randf_range(-1, 1)).normalized()
		var t := shard.create_tween().set_parallel(true)
		t.tween_property(shard, "global_position", shard.global_position + dir * randf_range(5.0, 9.0), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(shard, "rotation", Vector3(randf() * 6, randf() * 6, randf() * 6), 0.7)
		t.tween_property(shard, "scale", Vector3.ZERO, 0.35).set_delay(0.35)
		t.chain().tween_callback(shard.queue_free)


func _die() -> void:
	Juice.shake(1.0)
	Juice.duck_music(-12.0, 2.5)
	Juice.hit_stop(120.0)
	Sound.play_at("explosion_big", global_position)
	# Final kill punctuation: a full-mix boom and the jackpot sting.
	Sound.play("explosion_big", -2.0, 0.8)
	Sound.play("reel_land", -4.0, 1.3)
	dead = true
	for k in 6:
		GameManager.spawn_cloud(global_position + Vector3(randf_range(-5, 5), randf_range(-3, 1), randf_range(-5, 5)), 0.0, 3.5)
	defeated.emit()
	GameManager.boss_defeated()
	if Net.is_online():
		Net.rpc_to_run(_died, [])
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 1.5)
	t.tween_callback(queue_free)


@rpc("authority", "call_remote", "reliable")
func _sync(pos: Vector3, parts: Array, sacs: int, burn: float) -> void:
	if Net.is_host():
		return
	global_position = pos
	for i in mini(parts.size(), part_health.size()):
		part_health[i] = float(parts[i])
		if i < 3 and part_health[i] <= 0.0 and i < _parts.size():
			var part := _parts[i] as Node3D
			if part:
				part.visible = false
				part.collision_layer = 0
	sacs_left = sacs
	_burn_left = burn
	if _shell:
		_shell.visible = sacs > 0


@rpc("authority", "call_remote", "reliable")
func _died() -> void:
	if Net.is_host():
		return
	dead = true
	Sound.play_at("explosion_big", global_position)
	var t := create_tween()
	t.tween_property(self, "scale", Vector3.ONE * 0.01, 1.5)
	t.tween_callback(queue_free)


func _lob_spore() -> void:
	var players := get_tree().get_nodes_in_group("players").filter(func(p): return p.get("state") == "ok")
	if players.is_empty():
		return
	var exposed := players.filter(func(p): return p.get("exposed") != false)
	var target: Node3D = (exposed if not exposed.is_empty() else players).pick_random()
	var aim := target.global_position + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
	GameManager.spawn_spore(global_position + Vector3(0, -3, 0), aim, 1.8, 8.0)


func _summon() -> void:
	var spawner := get_parent()
	if spawner == null or not spawner.has_method("spawn"):
		return
	for k in 2:
		var scene: PackedScene = spawner.mister_scene if k == 0 else spawner.drip_scene
		spawner.spawn(scene)
