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

const HARPOON_FLIGHT := 0.07
const HARPOON_HOLD := 0.18
const HARPOON_REEL := 0.14
const HARPOON_DURATION := HARPOON_FLIGHT + HARPOON_HOLD + HARPOON_REEL


static func harpoon_shot(parent: Node, muzzle: Vector3, target: Vector3, color: Color, hit_enemy: bool,
		muzzle_model: Node3D = null, on_contact := Callable()) -> void:
	var flight := HarpoonFlight.new()
	flight.name = "HarpoonFlight"
	flight.process_priority = 1 # Sample the muzzle after the viewmodel animates.
	flight.muzzle = muzzle
	flight.contact = target
	flight.muzzle_model = muzzle_model
	flight.on_contact = on_contact
	flight.bolt = ItemModels.projectile("harpoon")
	flight.add_child(flight.bolt)
	flight.tip = flight.bolt.get_node("Tip")
	flight.tail = flight.bolt.get_node("CableStart")
	for mesh: MeshInstance3D in flight.bolt.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _streak_mesh == null:
		_streak_mesh = BoxMesh.new()
		_streak_mesh.size = Vector3(0.018, 0.018, 1.0)
	flight.cable = MeshInstance3D.new()
	flight.cable.name = "WinchCable"
	flight.cable.mesh = _streak_mesh
	flight.cable.material_override = _unshaded(color.lerp(Color("#ffd184"), 0.55))
	flight.cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flight.add_child(flight.cable)
	parent.add_child(flight)
	if hit_enemy:
		flight.anchor = _harpoon_anchor(parent.get_tree(), target)
		if flight.anchor:
			flight.anchor_offset = target - flight.anchor.global_position
	flight._process(0.0)


## The visual can follow a nearby capsule using the replicated impact point.
## When the target dies or has moved out of reach, use the last contact point.
static func _harpoon_anchor(tree: SceneTree, point: Vector3) -> EnemyBase:
	var best: EnemyBase
	var margin := 0.55 if Net.is_online() else 0.12
	for enemy: EnemyBase in tree.get_nodes_in_group("enemies"):
		if enemy.is_queued_for_deletion() or enemy.health <= 0.0:
			continue
		var capsule := LagComp.capsule_at(enemy, enemy.global_position)
		var closest := Geometry3D.get_closest_point_to_segment(point, capsule[0], capsule[1])
		var distance := closest.distance_to(point) - float(capsule[2])
		if distance < margin:
			best = enemy
			margin = distance
	return best


class HarpoonFlight extends Node3D:
	var muzzle: Vector3
	var contact: Vector3
	var muzzle_model: Node3D
	var on_contact: Callable
	var anchor: EnemyBase
	var anchor_offset: Vector3
	var bolt: Node3D
	var tip: Node3D
	var tail: Node3D
	var cable: MeshInstance3D
	var age := 0.0

	func _process(delta: float) -> void:
		var previous := age
		age += delta
		if age >= HARPOON_DURATION:
			queue_free()
			return
		if is_instance_valid(muzzle_model) and muzzle_model.is_inside_tree() and not muzzle_model.is_queued_for_deletion():
			muzzle = muzzle_model.to_global(ItemModels.muzzle("harpoon"))
		if is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
			contact = anchor.global_position + anchor_offset
		if previous < HARPOON_FLIGHT and age >= HARPOON_FLIGHT:
			if on_contact.is_valid():
				on_contact.call(contact)
			if is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
				anchor.reveal(2.0)
		var reel_start := HARPOON_FLIGHT + HARPOON_HOLD
		if previous < reel_start and age >= reel_start:
			Sound.play_at("reel_tick", muzzle, -12.0, 0.86)
		var direction := muzzle.direction_to(contact)
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		var basis := Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT)
		var head := muzzle.lerp(contact, minf(age / HARPOON_FLIGHT, 1.0))
		if age > reel_start:
			var shaft_length := tail.position.z - tip.position.z
			var dock := muzzle + direction * minf(shaft_length, muzzle.distance_to(contact))
			head = contact.lerp(dock, smoothstep(reel_start, HARPOON_DURATION, age))
		bolt.global_transform = Transform3D(basis, head - basis * tip.position)
		var end := tail.global_position
		var length := muzzle.distance_to(end)
		cable.visible = length > 0.015 and (end - muzzle).dot(direction) > 0.0
		if cable.visible:
			var cable_dir := (end - muzzle) / length
			var cable_basis := Basis.looking_at(cable_dir, Vector3.UP if absf(cable_dir.y) < 0.99 else Vector3.RIGHT)
			cable.global_transform = Transform3D(cable_basis.scaled_local(Vector3(1.5, 1.5, length)), (muzzle + end) * 0.5)


static func _unshaded(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		if color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
	mesh.mesh = _puff_mesh
	# Cached per color; the fade tweens the instance transparency instead.
	mesh.material_override = _unshaded(Color(color, minf(color.a, 0.99)))
	mesh.scale = Vector3.ONE * size
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	mesh.global_position = at
	var tween := mesh.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh, "scale", Vector3.ONE * (size * 2.5), life)
	tween.tween_property(mesh, "transparency", 1.0, life)
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
	for i in mini(count, 4) if OS.has_feature("web") else count:
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


static func beam(parent: Node, from: Vector3, to: Vector3, color: Color, width: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.05:
		return
	if _streak_mesh == null:
		_streak_mesh = BoxMesh.new()
		_streak_mesh.size = Vector3(0.018, 0.018, 1.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _streak_mesh
	mesh.material_override = _unshaded(Color(color, 0.72))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	var direction := (to - from) / length
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	mesh.look_at_from_position((from + to) / 2.0, to, up)
	mesh.scale = Vector3(width / 0.018, width / 0.018, length)
	var tween := mesh.create_tween()
	tween.tween_property(mesh, "transparency", 1.0, 0.11)
	tween.tween_callback(mesh.queue_free)
