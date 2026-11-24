extends Node3D
## Run this scene directly to exercise the catalog or set FF_POSE_CAPTURE to a PNG path.
func _ready() -> void:
	var ids := ItemCatalog.GUNS.keys() + ItemCatalog.STACKS.keys()
	var poses := preload("res://weapons/item_pose.gd")
	var failures := 0
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	camera.position.z = 2
	add_child(camera)
	var light := DirectionalLight3D.new()
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	camera.environment = environment
	light.rotation_degrees = Vector3(-35, -30, 0)
	add_child(light)
	for index in ids.size():
		var id: String = ids[index]
		if not poses.PROFILES.has(id):
			push_error("Missing profile " + id)
			failures += 1
			continue
		var model := ItemCatalog.model(id)
		add_child(model)
		var pose := poses.new()
		pose.bind(model, id)
		if poses.PROFILES[id][1] != "" and not pose.part:
			push_error("Missing moving part " + id)
			failures += 1
		pose.pose(model, 0.5, 0.7, 0.5, 0.016)
		pose.pose(model, 0, 0, 0, 0.016)
		if pose.support.position.distance_to(pose.grip) > 0.001:
			failures += 1
		model.position = Vector3((index % 6 - 2.5) * 0.52, (1.5 - floori(index / 6.0)) * 0.42, 0)
		model.rotation_degrees = Vector3(12, 60, 0)
		var reload_phase := 0.42 if ItemCatalog.GUNS.has(id) and id != "flare_launcher" else 0.0
		pose.pose(model, reload_phase, 0.65, 0.2 if id == "disruptor" else 0.0, 0.016)
	if OS.has_environment("FF_POSE_CAPTURE"):
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(OS.get_environment("FF_POSE_CAPTURE"))
		if error != OK:
			failures += 1
	print("Catalog poses: ", ids.size(), " checked, ", failures, " failures")
	get_tree().quit(1 if failures else 0)
