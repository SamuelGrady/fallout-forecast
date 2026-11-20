extends Node3D
## Shader / pipeline warm-up at the start of a run (main.gd adds it).
##
## WebGL (and d3d12 pipelines on desktop) compile a shader the first time
## something draws with it, which is the hitch you feel at the first enemy,
## gunshot, explosion or damage number. For a few frames behind a "tuning in"
## card this draws one of everything in front of the camera, including the
## enemy hit/reveal/windup overlays, then frees it all.

const FRAMES := 6

var _overlay := CanvasLayer.new()
var _frames := 0
var _holder := Node3D.new()


func _ready() -> void:
	_overlay.layer = 100
	var black := ColorRect.new()
	black.color = Color(0.02, 0.02, 0.04)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(black)
	var label := Label.new()
	label.text = "TUNING IN..."
	label.add_theme_font_override("font", BroadcastUI.FONT)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", BroadcastUI.CYAN)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -120
	label.offset_top = -20
	_overlay.add_child(label)
	add_child(_overlay)
	add_child(_holder)
	_spawn.call_deferred()


func _spawn() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		queue_free()
		return
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	var base := camera.global_position + forward * 4.0
	_holder.global_position = Vector3.ZERO
	var slot := 0
	# Infected of each kind, with every overlay they can show.
	for path in ["res://enemies/drip/drip.tscn", "res://enemies/gutter/gutter.tscn", "res://enemies/mister/mister.tscn"]:
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate()
		_holder.add_child(enemy)
		enemy.remove_from_group("enemies")
		enemy.set_physics_process(false)
		enemy.global_position = base + right * (slot - 1) * 1.4 - Vector3.UP * 1.0
		slot += 1
		_flash_overlays.call_deferred(enemy)
	# Every gun and thrown round.
	var x := -2.0
	for id in ["rifle", "shotgun", "flare", "dome", "frag", "bug_bomb", "revolver", "nailgun", "boombox"]:
		var gun := GunModels.build(id)
		_holder.add_child(gun)
		gun.global_position = base + right * x + Vector3.UP * 0.8
		var round_model := GunModels.projectile(id)
		_holder.add_child(round_model)
		round_model.global_position = base + right * x + Vector3.UP * 1.2
		x += 0.5
	# Combat FX: tracer, flash, puffs, sparks, a damage number, pickups.
	ShotFX.tracer(_holder, base + right * -1.0, base + right * 1.0, Color(1, 0.82, 0.5), 0.5)
	ShotFX.flash(_holder, base, Color(1.0, 0.7, 0.4), 2.0, 0.3)
	ShotFX.puff(_holder, base + Vector3.UP * 0.5, Color(1, 0.6, 0.2, 0.8), 0.3, 0.4)
	ShotFX.sparks(_holder, base + Vector3.UP * 0.4, Vector3.UP, 4)
	var number := Label3D.new()
	number.set_script(preload("res://weapons/damage_number.gd"))
	number.set("amount", 12)
	_holder.add_child(number)
	number.global_position = base + Vector3.UP * 1.6
	for kind in ["ammo", "health", "suit", "supply"]:
		var drop := Node3D.new()
		drop.set_script(preload("res://weapons/ammo_drop.gd"))
		drop.set("kind", kind)
		drop.set("expires_after", 1.0)
		_holder.add_child(drop)
		drop.global_position = base + right * (randf() - 0.5) * 2.0 - Vector3.UP * 0.5
	# Shield Dome / spore-cloud style transparent unshaded shells.
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
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
	dome.global_position = base + right * 1.5


func _flash_overlays(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	for method in ["hit_flash", "reveal", "attack_flash"]:
		if enemy.has_method(method):
			if method == "hit_flash":
				enemy.call(method)
			else:
				enemy.call(method, 0.3)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < FRAMES:
		return
	set_process(false)
	_holder.queue_free()
	var tween := create_tween()
	for child in _overlay.get_children():
		tween.parallel().tween_property(child, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
