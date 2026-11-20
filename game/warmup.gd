extends Node3D
## Shader / pipeline warm-up at the start of a run (main.gd runs it while
## loading_map is true, behind SceneLoader's loading card).
##
## WebGL (and d3d12 pipelines on desktop) compile a shader the first time
## something draws with it, which causes multi-second hitches on ANGLE if many
## materials compile in a single frame. This spreads the warm-up across small
## per-stage batches, freeing each stage before drawing the next and reporting
## progress on the loading card.

signal finished

const Spawner := preload("res://enemies/enemy_spawner.gd")
const SporeProjectile := preload("res://enemies/mister/spore_projectile.gd")
const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")
const BossScene := preload("res://enemies/boss/boss_cumulus.tscn")
const WeatherEnemy := preload("res://enemies/weather_enemy.gd")

const STAGES: Array[String] = [
	"surfaces",
	"classic_infected",
	"weather_infected_a",
	"weather_infected_b",
	"enemy_hazards",
	"boss",
	"guns_a",
	"guns_b",
	"combat_fx",
]

var _overlay: CanvasLayer
var _label: Label
var _holder := Node3D.new()
var _undertow: EnemyBase
var _stage := -1
var _hold := 0
var _started_us := 0
var _stage_us := 0
var _web := OS.has_feature("web")
var _done := false


func _ready() -> void:
	set_process(false)
	add_child(_holder)
	# When entered via SceneLoader, reuse its loading card for progress instead
	# of stacking a second black screen. Keep a fallback card for direct runs.
	if not SceneLoader.visible:
		_overlay = CanvasLayer.new()
		_overlay.layer = 100
		var black := ColorRect.new()
		black.color = Color(0.02, 0.02, 0.04)
		black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(black)
		_label = Label.new()
		_label.text = "TUNING IN..."
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_override("font", BroadcastUI.FONT)
		_label.add_theme_font_size_override("font_size", 34)
		_label.add_theme_color_override("font_color", BroadcastUI.CYAN)
		_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_label.offset_left = -200
		_label.offset_right = 200
		_label.offset_top = -20
		_overlay.add_child(_label)
		add_child(_overlay)
	_begin.call_deferred()


func _begin() -> void:
	if get_viewport().get_camera_3d() == null:
		_complete()
		return
	_started_us = Time.get_ticks_usec()
	Perf.mark("warm-up start")
	_advance_stage()
	set_process(true)


func _process(_delta: float) -> void:
	if _done:
		return
	_hold -= 1
	if _stage == 2 and _hold == 1 and is_instance_valid(_undertow):
		_undertow.play_tell("undertow_emerge", 0.6, -80.0)
	if _hold > 0:
		return
	var stage_ms := (Time.get_ticks_usec() - _stage_us) / 1000.0
	if _stage >= 0 and _stage < STAGES.size() and stage_ms >= 100.0:
		Perf.mark("warm-up %s %.0f ms" % [STAGES[_stage], stage_ms])
	if _stage == 0:
		_end_screen_warm()
	_clear_holder()
	_advance_stage()


func _advance_stage() -> void:
	_stage += 1
	if _stage >= STAGES.size():
		_complete()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_complete()
		return
	_stage_us = Time.get_ticks_usec()
	var total := STAGES.size()
	var frac := float(_stage) / float(total)
	var caption := "TUNING IN..."
	var detail := "%d / %d" % [_stage + 1, total]
	SceneLoader.set_stage(caption, 0.60 + frac * 0.38, detail)
	if _label:
		_label.text = "%s  %s" % [caption, detail]

	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var base := camera.global_position + forward * 7.0
	_holder.global_position = Vector3.ZERO
	_undertow = null

	var spawner := get_parent().get_node_or_null("Enemies") as Spawner
	match STAGES[_stage]:
		"surfaces":
			_warm_level_surfaces(base, right, up)
			_warm_puddle_and_bolt(base, right, up)
			_begin_screen_warm()
			_hold = 2 if _web else 1
		"classic_infected":
			if spawner:
				_spawn_enemies([spawner.drip_scene, spawner.gutter_scene, spawner.mister_scene], base, forward, right, up, 0)
			_hold = 2 if _web else 1
		"weather_infected_a":
			_spawn_enemies(Spawner.WEATHER_SCENES.slice(0, 3), base, forward, right, up, 3)
			# Always hold at least 2 frames so Undertow draws both lurk and emerge.
			_hold = 2
		"weather_infected_b":
			_spawn_enemies(Spawner.WEATHER_SCENES.slice(3, 6), base, forward, right, up, 6)
			_hold = 2 if _web else 1
		"enemy_hazards":
			_warm_enemy_hazards(base, right, up)
			_hold = 2 if _web else 1
		"boss":
			_warm_boss(base, up)
			_hold = 2 if _web else 1
		"guns_a":
			_warm_guns(["rifle", "shotgun", "flare", "dome", "frag"], base, right)
			_warm_dome_shell(base, right)
			_hold = 2 if _web else 1
		"guns_b":
			_warm_guns(["bug_bomb", "revolver", "nailgun", "boombox"], base, right)
			_warm_props_fx(base, right, up)
			_hold = 2 if _web else 1
		"combat_fx":
			_warm_combat_fx(base, right, up)
			_hold = 2 if _web else 1


func _begin_screen_warm() -> void:
	var weather := get_parent().get_node_or_null("WeatherFX")
	if weather and weather.has_method("warm_rain"):
		weather.warm_rain(true)
	var juice := get_parent().get_node_or_null("JuiceHud")
	if juice and juice.has_method("warm_shaders"):
		juice.warm_shaders(true)


func _end_screen_warm() -> void:
	var weather := get_parent().get_node_or_null("WeatherFX")
	if weather and weather.has_method("warm_rain"):
		weather.warm_rain(false)
	var juice := get_parent().get_node_or_null("JuiceHud")
	if juice and juice.has_method("warm_shaders"):
		juice.warm_shaders(false)


func _clear_holder() -> void:
	for child in _holder.get_children():
		_holder.remove_child(child)
		child.queue_free()


func _spawn_enemies(scenes: Array, base: Vector3, forward: Vector3, right: Vector3, up: Vector3, slot_offset: int) -> void:
	for i in scenes.size():
		var scene := scenes[i] as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as EnemyBase
		enemy.position = base + right * (i - 1) * 1.65 + up * -1.1
		_holder.add_child(enemy)
		enemy.remove_from_group("enemies")
		enemy.set_physics_process(false)
		enemy.look_at(enemy.global_position - forward)
		_warm_enemy.call_deferred(enemy, slot_offset + i)


func _warm_enemy(enemy: EnemyBase, slot: int) -> void:
	if not is_instance_valid(enemy):
		return
	match slot % 4:
		0: enemy.hit_flash()
		1: enemy.reveal(0.6)
		2: enemy.attack_flash(0.6)
	match enemy.data.display_name:
		"Hailstone": enemy.play_tell("hailstone_charge", 0.6, -80.0)
		"Undertow":
			_undertow = enemy
			enemy.play_tell("undertow_lurk", 0.0, -80.0)
		"Static":
			enemy.play_tell("static_power", 0.0, -80.0)
			enemy.play_tell("static_shock", 0.6, -80.0)
		"Thunderhead": enemy.play_tell("thunderhead_fuse", 0.6, -80.0)


func _warm_enemy_hazards(base: Vector3, right: Vector3, up: Vector3) -> void:
	for acid in [false, true]:
		var spot := base + right * (-2.0 if acid else 2.0) + up * -0.55
		var spore := SporeProjectile.new()
		spore.acid = acid
		_holder.add_child(spore)
		spore.launch(spot + up, spot, 1.0)
		spore.set_physics_process(false)
		var pool := SporeCloud.new()
		pool.acid = acid
		pool.radius = 0.48
		pool.position = spot
		_holder.add_child(pool)
		pool.set_physics_process(false)
		pool.remove_from_group("spore_clouds")
		pool.remove_from_group("enemy_hazards")
		spore.remove_from_group("enemy_hazards")
	# Weather enemy warning ring + lane (unshaded alpha) & Static shock arc.
	var warn_mat := StandardMaterial3D.new()
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_mat.albedo_color = Color(1.0, 0.9, 0.3, 0.7)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.55
	torus.rings = 16
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = warn_mat
	ring.position = base + up * -0.8
	_holder.add_child(ring)


func _warm_boss(base: Vector3, up: Vector3) -> void:
	var boss := BossScene.instantiate() as Node3D
	boss.set("preview_only", true)
	boss.position = base + up * 1.1
	boss.scale = Vector3.ONE * 0.19
	_holder.add_child(boss)
	boss.set_process(false)


func _warm_guns(ids: Array[String], base: Vector3, right: Vector3) -> void:
	var x := -1.5
	for id in ids:
		var gun := GunModels.build(id)
		_holder.add_child(gun)
		gun.global_position = base + right * x + Vector3.UP * 0.3
		var round_model := GunModels.projectile(id)
		_holder.add_child(round_model)
		round_model.global_position = base + right * x + Vector3.UP * 0.85
		x += 0.75


func _warm_dome_shell(base: Vector3, right: Vector3) -> void:
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.is_hemisphere = true
	sphere.radius = 0.8
	sphere.height = 0.8
	dome.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.albedo_color = Color(0.35, 0.95, 1.0, 0.2)
	dome.material_override = mat
	_holder.add_child(dome)
	dome.global_position = base + right * 2.2


func _warm_props_fx(base: Vector3, right: Vector3, up: Vector3) -> void:
	# Emissive lit swatch (crate rewards/trim, player skins) and decon mist swatch.
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.25
	var emissive := StandardMaterial3D.new()
	emissive.albedo_color = Color("#66dfda")
	emissive.roughness = 0.55
	emissive.emission_enabled = true
	emissive.emission = Color("#66dfda")
	emissive.emission_energy_multiplier = 0.9
	var m1 := MeshInstance3D.new()
	m1.mesh = box
	m1.material_override = emissive
	m1.position = base + right * -1.2 + up * -0.4
	_holder.add_child(m1)

	var mist := StandardMaterial3D.new()
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.albedo_color = Color(0.55, 0.96, 1.0, 0.35)
	var m2 := MeshInstance3D.new()
	m2.mesh = box
	m2.material_override = mist
	m2.position = base + right * 1.2 + up * -0.4
	_holder.add_child(m2)


func _warm_puddle_and_bolt(base: Vector3, right: Vector3, up: Vector3) -> void:
	# Lit transparent puddle water (puddles start hidden at growth=0 in Calm).
	var disc := CylinderMesh.new()
	disc.top_radius = 0.35
	disc.bottom_radius = 0.35
	disc.height = 0.02
	disc.radial_segments = 12
	var water := StandardMaterial3D.new()
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color = Color(0.18, 0.3, 0.38, 0.72)
	water.roughness = 0.08
	water.metallic = 0.25
	var puddle_sample := MeshInstance3D.new()
	puddle_sample.mesh = disc
	puddle_sample.material_override = water
	puddle_sample.position = base + right * -1.4 + up * -1.2
	_holder.add_child(puddle_sample)

	# Unshaded no-fog bolt / objective beam swatch.
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.albedo_color = Color(0.9, 0.95, 1.0)
	bolt_mat.disable_fog = true
	var bolt_sample := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.9, 0.12)
	bolt_sample.mesh = box
	bolt_sample.material_override = bolt_mat
	bolt_sample.position = base + right * 1.4 + up * -0.9
	_holder.add_child(bolt_sample)


func _warm_combat_fx(base: Vector3, right: Vector3, up: Vector3) -> void:
	ShotFX.tracer(_holder, base + right * -1.0, base + right * 1.0, Color(1, 0.82, 0.5), 0.5)
	ShotFX.flash(_holder, base, Color(1.0, 0.7, 0.4), 2.0, 0.3)
	ShotFX.puff(_holder, base + up * 0.5, Color(1.0, 0.6, 0.2, 0.8), 0.3, 0.4)
	ShotFX.sparks(_holder, base + up * 0.4, Vector3.UP, 4)
	var number := Label3D.new()
	number.set_script(preload("res://weapons/damage_number.gd"))
	number.set("amount", 12)
	_holder.add_child(number)
	number.global_position = base + up * 1.4
	for kind in ["ammo", "health", "suit", "supply"]:
		var drop := Node3D.new()
		drop.set_script(preload("res://weapons/ammo_drop.gd"))
		drop.set("kind", kind)
		drop.set("expires_after", 1.0)
		_holder.add_child(drop)
		drop.global_position = base + right * (randf() - 0.5) * 2.0 - up * 0.5
	# Turned player overlay swatch (metallic/lit base + unshaded alpha overlay).
	var sample := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.3
	sample.mesh = box
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color("#e0a830")
	base_mat.metallic = 0.5
	base_mat.roughness = 0.4
	sample.material_override = base_mat
	var turned := StandardMaterial3D.new()
	turned.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	turned.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	turned.albedo_color = Color(0.55, 0.9, 0.3, 0.55)
	sample.material_overlay = turned
	sample.position = base + right * 1.8 + up * 0.2
	_holder.add_child(sample)


func _warm_level_surfaces(base: Vector3, right: Vector3, up: Vector3) -> void:
	var level := get_parent().get_node_or_null("Level")
	if level == null:
		return
	var seen := {}
	# Draw a small swatch for each unique material variant in the district,
	# including props outside the starting view, while keeping draws low.
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.22
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as StandardMaterial3D
			if material == null:
				continue
			var signature := [material.shading_mode, material.transparency, material.cull_mode,
				material.albedo_texture != null, material.uv1_triplanar, material.emission_enabled,
				material.vertex_color_use_as_albedo, material.disable_fog]
			if seen.has(signature):
				continue
			var slot := seen.size()
			seen[signature] = true
			var sample := MeshInstance3D.new()
			sample.mesh = box
			sample.material_override = material
			sample.position = base + right * (slot % 12 - 5.5) * 0.29 + up * (2.2 - floorf(slot / 12.0) * 0.3)
			_holder.add_child(sample)


func _complete() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_end_screen_warm()
	_clear_holder()
	SceneLoader.set_stage("TUNING IN...", 1.0, "READY")
	if _started_us > 0:
		Perf.mark("warm-up end %.1f ms (%d stages)" % [(Time.get_ticks_usec() - _started_us) / 1000.0, STAGES.size()])
	else:
		Perf.mark("warm-up end")
	finished.emit()
	if _overlay:
		var tween := create_tween()
		for child in _overlay.get_children():
			tween.parallel().tween_property(child, "modulate:a", 0.0, 0.2)
		tween.tween_callback(queue_free)
	else:
		queue_free()
