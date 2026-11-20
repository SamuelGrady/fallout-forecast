class_name ShotFX
## One-shot visual effects for weapons: tracer, muzzle flash, impact puff.
## All local and short-lived.


## Shared unit-length streak mesh and one material per color, so firing
## doesn't allocate resources per shot.
static var _streak_mesh: BoxMesh
static var _puff_mesh: SphereMesh
static var _spark_mesh: BoxMesh
static var _spark_mats: Array[StandardMaterial3D] = []
static var _materials := {}


static func _unshaded(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.disable_fog = true
		_materials[key] = material
	return _materials[key]


## A short bright bullet streak that travels from the muzzle to the hit,
## rather than a beam that spans the whole distance at once.
static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, _life := 0.06) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	if _streak_mesh == null:
		_streak_mesh = BoxMesh.new()
		_streak_mesh.size = Vector3(0.018, 0.018, 1.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _streak_mesh
	mesh.material_override = _unshaded(color.lerp(Color(1.0, 0.93, 0.7), 0.6))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streak := minf(1.6, length)
	mesh.scale = Vector3(1.0, 1.0, streak)
	parent.add_child(mesh)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var start := from + dir * streak * 0.5
	var finish := to - dir * streak * 0.5
	mesh.look_at_from_position(start, start + dir, up)
	var travel := maxf(0.02, length / 320.0)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "global_position", finish, travel)
	tween.tween_callback(mesh.queue_free)


static func flash(parent: Node, at: Vector3, color := Color(1.0, 0.8, 0.4), energy := 4.0, life := 0.05) -> void:
	# Web (Compatibility renderer): each dynamic light adds a draw pass for
	# everything it touches; the muzzle puff carries the flash instead.
	if OS.has_feature("web"):
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 6.0
	parent.add_child(light)
	light.global_position = at
	parent.get_tree().create_timer(life).timeout.connect(light.queue_free)


static func puff(parent: Node, at: Vector3, color: Color, size := 0.18, life := 0.25) -> void:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 1.0
		_puff_mesh.height = 2.0
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	mesh.mesh = _puff_mesh
	mesh.material_override = material
	mesh.scale = Vector3.ONE * size
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	var tween := mesh.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE * (size * 2.5), life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.chain().tween_callback(mesh.queue_free)


static func sparks(parent: Node, at: Vector3, outward := Vector3.UP, count := 6) -> void:
	if _spark_mesh == null:
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3(0.03, 0.03, 0.16)
	if _spark_mats.is_empty():
		for c in [Color("#ffe599"), Color("#7ce8ff")]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = c
			_spark_mats.append(m)
	var dir := outward.normalized() if outward.length_squared() > 0.001 else Vector3.UP
	for i in count:
		var spark := MeshInstance3D.new()
		spark.mesh = _spark_mesh
		spark.material_override = _spark_mats[i % 2]
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(spark)
		spark.global_position = at
		var spread := (dir + Vector3(randf_range(-0.9, 0.9), randf_range(0.1, 1.0), randf_range(-0.9, 0.9))).normalized()
		spark.look_at(at + spread, Vector3.UP if absf(spread.y) < 0.98 else Vector3.RIGHT)
		var tween := spark.create_tween().set_parallel(true)
		tween.tween_property(spark, "global_position", at + spread * randf_range(0.45, 0.95), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.18)
		tween.chain().tween_callback(spark.queue_free)
