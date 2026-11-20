extends Node3D
## Boss_Cumulus (wave 5): a bloated spore cloud over Main Street that makes its
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
@export var start_height := 18.0
@export var drop_per_sac := 4.0

var part_health: Array[float] = [0.0, 0.0, 0.0, 0.0]  # sacs 0-2, core 3
var part_max: Array[float] = [0.0, 0.0, 0.0, 0.0]
var sacs_left := 3
var dead := false

var _anchor := Vector3.ZERO
var _height := 18.0
var _t := 0.0
var _burn_left := 0.0
var _net_left := 0.0
var _spore_timer := 3.0
var _summon_timer := 8.0
var _parts: Array[Node] = []
var _shell: MeshInstance3D
var _body: Node3D
var _sac_material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("boss")
	_anchor = global_position
	_height = start_height
	var scale_hp := GameManager.enemy_health_scale() if GameManager.has_method("enemy_health_scale") else 1.0
	for i in 3:
		part_max[i] = sac_health * scale_hp
	part_max[3] = core_health * scale_hp
	part_health = part_max.duplicate()
	_build()


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var cloud := StandardMaterial3D.new()
	cloud.albedo_color = Color(0.36, 0.48, 0.28)
	cloud.roughness = 1.0
	cloud.disable_fog = true
	cloud.emission_enabled = true
	cloud.emission = Color(0.12, 0.2, 0.08)
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
		s.material = cloud
		m.mesh = s
		m.position = Vector3(rng.randf_range(-4, 4), rng.randf_range(0.5, 2.5), rng.randf_range(-4, 4))
		_body.add_child(m)

	_sac_material.albedo_color = Color(0.85, 1.0, 0.3)
	_sac_material.emission_enabled = true
	_sac_material.emission = Color(0.6, 1.0, 0.2)
	_sac_material.emission_energy_multiplier = 2.0
	for i in 3:
		var a := TAU * i / 3.0
		_parts.append(_make_part("Sac%d" % i, i, 1.7, Vector3(cos(a) * 5.0, -1.2, sin(a) * 5.0), _sac_material))
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(1.0, 0.3, 0.6)
	core_material.emission_enabled = true
	core_material.emission = Color(1.0, 0.2, 0.5)
	core_material.emission_energy_multiplier = 1.5
	_parts.append(_make_part("Core", 3, 2.2, Vector3(0, -1.8, 0), core_material))
	_shell = MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 2.8
	shell_mesh.height = 5.6
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.5, 0.7, 0.4, 0.55)
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
	_sac_material.emission_energy_multiplier = 1.5 + sin(_t * 4.0) * 0.8
	# Clients only draw it: position, part health and the burn timer ride one
	# unreliable packet ten times a second, the kill is sent reliably below.
	if Net.is_host() and Net.is_online():
		_net_left -= delta
		if _net_left <= 0.0:
			_net_left = 0.1
			_sync.rpc(global_position, part_health, sacs_left, _burn_left)
	if not Net.is_host() or dead:
		return
	# Drift in a slow circle over Main Street and sink as sacs pop.
	var goal_height := start_height - drop_per_sac * (3 - sacs_left)
	_height = move_toward(_height, goal_height, delta * 2.0)
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


func damage_part(i: int, amount: float, _source: Node) -> void:
	if not Net.is_host() or dead or part_health[i] <= 0.0:
		return
	if i == 3 and not core_exposed():
		return
	part_health[i] = maxf(part_health[i] - amount, 0.0)
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
	sacs_left -= 1
	var part: Node3D = _parts[i]
	GameManager.spawn_cloud(part.global_position, 10.0, 4.0)
	part.visible = false
	part.collision_layer = 0
	WeatherManager.set_intensity_override(STORM_STEPS[2 - sacs_left])
	if sacs_left == 0:
		_shell.visible = false
		GameManager.show_banner("THE CORE IS EXPOSED!", Color("FF3EA5"), 3.0)
	else:
		GameManager.show_banner("SAC BURST: the storm weakens (%d left)" % sacs_left, Color("8FD65A"), 2.5)


func _die() -> void:
	Sound.play_at("explosion_big", global_position)
	dead = true
	for k in 6:
		GameManager.spawn_cloud(global_position + Vector3(randf_range(-5, 5), randf_range(-3, 1), randf_range(-5, 5)), 0.0, 3.5)
	defeated.emit()
	GameManager.boss_defeated()
	if Net.is_online():
		_died.rpc()
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
