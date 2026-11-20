extends Node3D
## Shader / pipeline warm-up at the start of a run (main.gd runs it while
## loading_map is true, behind SceneLoader's loading card).
##
## WebGL (and d3d12 pipelines on desktop) compile a shader the first time
## something draws with it, which causes multi-second hitches on ANGLE if many
## materials compile in a single frame. This spreads the warm-up across small
## per-stage batches, freeing each stage before drawing the next and reporting
## progress on the loading card.
##
## On web (see WebMaterials) main.gd hides the world from the camera until
## the first stage has drawn one small swatch per distinct shader key in the
## run (plus a copy inside a temporary omni light for the lit variant), a few
## per frame. Then "district" shows the real level for two frames.

signal finished

const Spawner := preload("res://enemies/enemy_spawner.gd")
const SporeProjectile := preload("res://enemies/mister/spore_projectile.gd")
const SporeCloud := preload("res://enemies/mister/spore_cloud.gd")
const BossScene := preload("res://enemies/boss/boss_cumulus.tscn")
const WeatherEnemy := preload("res://enemies/weather_enemy.gd")

## Render layer the swatches use while the world is hidden from the camera.
const WARM_LAYER := 1 << 19

const STAGES: Array[String] = [
	"surfaces",
	"district",
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
var _surface_queue: Array[Dictionary] = []
var _surface_total := 0
var _swatch_box: BoxMesh
var _keys_drawn := {}


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
	if _stage == 3 and _hold == 1 and is_instance_valid(_undertow):
		_undertow.play_tell("undertow_emerge", 0.6, -80.0)
	if _hold > 0:
		return
	if _stage == 0 and not _surface_queue.is_empty():
		_clear_holder()
		_draw_surface_batch()
		return
	var stage_ms := (Time.get_ticks_usec() - _stage_us) / 1000.0
	if _stage >= 0 and _stage < STAGES.size() and stage_ms >= 100.0:
		Perf.mark("warm-up %s %.0f ms" % [STAGES[_stage], stage_ms])
	if _stage == 1:
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
			_warm_puddle_and_bolt(base, right, up)
			_begin_screen_warm()
			_queue_surfaces()
		"district":
			# Everything the world uses has compiled: let it draw.
			var main := get_parent()
			if main.has_method("reveal_world"):
				main.reveal_world()
			_hold = 2
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


## One entry per distinct shader key the run can draw so far (level,
## players, held guns, HUD 3D bits), including hidden nodes that switch on
## later (objective beacons, flicker states). Hidden CSG is collision only.
func _queue_surfaces() -> void:
	_surface_queue.clear()
	_keys_drawn.clear()
	var main := get_parent()
	for node in main.find_children("*", "GeometryInstance3D", true, false):
		if is_ancestor_of(node) or (node is CSGShape3D and not (node as Node3D).is_visible_in_tree()):
			continue
		if node is GPUParticles3D or node is CPUParticles3D:
			continue  # Rain: WeatherFX.warm_rain draws it.
		var gi := node as GeometryInstance3D
		if node is Label3D:
			var label := node as Label3D
			if label.material_override:
				_queue_material(label.material_override, "mesh", null)
			else:
				_queue_entry("label:%s|%s|%s|%s|%s|%s|%s" % [label.shaded, label.double_sided,
					label.no_depth_test, label.fixed_size, label.alpha_cut, label.billboard, label.texture_filter],
					{"kind": "label", "source": label, "lit": label.shaded})
			continue
		var source: MultiMesh = (node as MultiMeshInstance3D).multimesh if node is MultiMeshInstance3D else null
		var kind := "instanced" if node is MultiMeshInstance3D else "mesh"
		if gi.material_overlay:
			_queue_material(gi.material_overlay, kind, source)
		if gi.material_override:
			_queue_material(gi.material_override, kind, source)
			continue
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					_queue_material(mi.get_active_material(i), kind, source)
			continue
		var mesh: Mesh = null
		if source:
			mesh = source.mesh
		elif node is CSGShape3D and (node as CSGShape3D).is_root_shape():
			var meshes := (node as CSGShape3D).get_meshes()
			mesh = meshes[1] if meshes.size() > 1 else null
		if mesh:
			for i in mesh.get_surface_count():
				_queue_material(mesh.surface_get_material(i), kind, source)
	_surface_total = _surface_queue.size()
	Perf.mark("warm-up %d surface keys" % _surface_total)
	_draw_surface_batch()


func _queue_material(material: Material, kind: String, source: MultiMesh) -> void:
	var guard := 0
	while material and guard < 4:
		var lit := true
		if material is BaseMaterial3D:
			lit = (material as BaseMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
		_queue_entry(kind + ":" + WebMaterials.shader_key(material), {"kind": kind, "material": material, "source": source, "lit": lit})
		material = material.next_pass
		guard += 1


func _queue_entry(key: String, entry: Dictionary) -> void:
	if _keys_drawn.has(key):
		return
	_keys_drawn[key] = true
	entry["key"] = key
	_surface_queue.append(entry)


## A few swatches per frame so no single frame compiles everything. Each lit
## key also draws once inside a small temporary omni light: street lamps give
## the level's lit shaders an omni-light variant.
func _draw_surface_batch() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_surface_queue.clear()
		return
	var per_frame := 2 if _web else 8
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var base := camera.global_position + forward * 4.0
	var count := mini(per_frame, _surface_queue.size())
	var light := OmniLight3D.new()
	light.omni_range = 0.9
	light.light_energy = 1.0
	light.shadow_enabled = false
	_holder.add_child(light)
	light.global_position = base + up * -0.7 - forward * 0.3
	for i in count:
		var entry: Dictionary = _surface_queue.pop_front()
		var x := (float(i) - (count - 1) * 0.5) * 0.45
		_add_swatch(entry, base + right * x + up * 1.0)
		if entry.get("lit", true):
			_add_swatch(entry, base + right * x * 0.4 + up * -0.7)
	_set_holder_layers()
	var done := _surface_total - _surface_queue.size()
	SceneLoader.set_stage("TUNING IN...", 0.60 + 0.38 * (float(done) / maxf(1.0, _surface_total)) / STAGES.size(), "SURFACES %d / %d" % [done, _surface_total])
	if _label:
		_label.text = "TUNING IN...  SURFACES %d / %d" % [done, _surface_total]
	_hold = 2 if _web else 1


func _add_swatch(entry: Dictionary, at: Vector3) -> void:
	if _swatch_box == null:
		_swatch_box = BoxMesh.new()
		_swatch_box.size = Vector3.ONE * 0.2
	var node: GeometryInstance3D
	match str(entry.kind):
		"label":
			var src := entry.source as Label3D
			if not is_instance_valid(src):
				return
			var label := Label3D.new()
			label.text = "A"
			label.font = src.font
			label.font_size = 24
			label.pixel_size = 0.01
			for p in ["shaded", "double_sided", "no_depth_test", "fixed_size", "alpha_cut", "billboard", "texture_filter", "alpha_antialiasing_mode"]:
				label.set(p, src.get(p))
			node = label
		"instanced":
			var mm := MultiMesh.new()
			var src_mm := entry.source as MultiMesh
			mm.transform_format = MultiMesh.TRANSFORM_3D
			if src_mm:
				mm.use_colors = src_mm.use_colors
				mm.use_custom_data = src_mm.use_custom_data
			mm.mesh = _swatch_box
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D.IDENTITY)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = entry.material
			node = mmi
		_:
			var mi := MeshInstance3D.new()
			mi.mesh = _swatch_box
			mi.material_override = entry.material
			node = mi
	_holder.add_child(node)
	node.global_position = at


## While the world is hidden the camera only renders WARM_LAYER.
func _set_holder_layers() -> void:
	for node in _holder.find_children("*", "VisualInstance3D", true, false):
		if not (node is Light3D):
			(node as VisualInstance3D).layers = WARM_LAYER


func _complete() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	_end_screen_warm()
	if get_parent() and get_parent().has_method("reveal_world"):
		get_parent().reveal_world()
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
