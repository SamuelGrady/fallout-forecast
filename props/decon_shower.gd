extends Interactable
## Decon shower: restores the user's suit integrity to 100 and spends one
## charge from the team's shared pool (GameManager.decon_charges).
## Displays physical charge cells, a working spray burst, and an empty state.

var _cells: Array[MeshInstance3D] = []
var _cell_rack := Node3D.new()
var _head_ring: MeshInstance3D
var _head_light: OmniLight3D
var _spray_root := Node3D.new()
var _spray_left := 0.0
var _spray_streams: Array[MeshInstance3D] = []
var _clock := 0.0


func _init() -> void:
	prompt = "Repair"
	hold_time = 1.0
	radius = 2.2


func _ready() -> void:
	super._ready()
	if _highlight:
		_highlight.position.y = -0.92
		_highlight.scale = Vector3(1.55, 1.0, 1.55)
	_build_station_visuals()
	GameManager.decon_changed.connect(_on_decon_changed)
	_refresh_cells(GameManager.decon_charges)


func _exit_tree() -> void:
	if GameManager.decon_changed.is_connected(_on_decon_changed):
		GameManager.decon_changed.disconnect(_on_decon_changed)


func _build_station_visuals() -> void:
	# Hide the redundant floating "DECON" text on the station marker; charge cells + spray show state.
	var parent_label := get_parent().get_node_or_null("Label")
	if parent_label:
		parent_label.visible = false
	# Charge cell rack mounted around the pipe at eye level.
	add_child(_cell_rack)
	_rebuild_cell_rack()
	# Showerhead status ring & light (cyan = ready, amber/red = empty).
	_head_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.rings = 24
	torus.ring_segments = 6
	torus.inner_radius = 0.32
	torus.outer_radius = 0.4
	_head_ring.mesh = torus
	_head_ring.position = Vector3(0, 1.58, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color("#2EE6E6")
	_head_ring.material_override = ring_mat
	add_child(_head_ring)
	if not OS.has_feature("web") and not Net.dedicated:
		_head_light = OmniLight3D.new()
		_head_light.position = Vector3(0, 1.45, 0)
		_head_light.light_color = Color("#2EE6E6")
		_head_light.light_energy = 1.4
		_head_light.omni_range = 3.8
		add_child(_head_light)
	# Spray nozzle streams (hidden until activated).
	_spray_root.position = Vector3(0, 1.5, 0)
	_spray_root.visible = false
	add_child(_spray_root)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.albedo_color = Color(0.55, 0.96, 1.0, 0.45)
	for i in 8:
		var angle := TAU * i / 8.0
		var stream := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.018
		cyl.bottom_radius = 0.032
		cyl.height = 2.35
		cyl.radial_segments = 6
		stream.mesh = cyl
		stream.material_override = mist_mat
		stream.position = Vector3(cos(angle) * 0.22, -1.18, sin(angle) * 0.22)
		stream.rotation = Vector3(sin(angle) * 0.14, 0.0, -cos(angle) * 0.14)
		_spray_root.add_child(stream)
		_spray_streams.append(stream)
	var cone := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.28
	cone_mesh.bottom_radius = 0.68
	cone_mesh.height = 2.3
	cone_mesh.radial_segments = 12
	cone.mesh = cone_mesh
	cone.position = Vector3(0, -1.18, 0)
	var cone_mat := StandardMaterial3D.new()
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.albedo_color = Color(0.35, 0.92, 0.95, 0.18)
	cone.material_override = cone_mat
	_spray_root.add_child(cone)


func _rebuild_cell_rack() -> void:
	for child in _cell_rack.get_children():
		child.queue_free()
	_cells.clear()
	var total := maxi(GameManager.decon_max, 4)
	for i in total:
		var cell := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.14
		cyl.bottom_radius = 0.14
		cyl.height = 0.13
		cyl.radial_segments = 12
		cell.mesh = cyl
		cell.position = Vector3(0, 0.05 + i * 0.19, 0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color("#2EE6E6")
		cell.material_override = mat
		_cell_rack.add_child(cell)
		_cells.append(cell)


func _on_decon_changed(charges: int) -> void:
	if _cells.size() != maxi(GameManager.decon_max, 4):
		_rebuild_cell_rack()
	_refresh_cells(charges)


func _refresh_cells(charges: int) -> void:
	var has_charge := charges > 0
	for i in _cells.size():
		var mat := _cells[i].material_override as StandardMaterial3D
		if i < charges:
			mat.albedo_color = Color("#39f0ec")
		else:
			mat.albedo_color = Color("#222b33")
	if _head_ring:
		(_head_ring.material_override as StandardMaterial3D).albedo_color = Color("#2EE6E6") if has_charge else Color("#ff5b4d")
	if _head_light:
		_head_light.light_color = Color("#2EE6E6") if has_charge else Color("#ff5b4d")
		_head_light.light_energy = 1.4 if has_charge else 0.45


@rpc("authority", "call_remote", "reliable")
func play_spray() -> void:
	Perf.mark("decon spray")
	_spray_left = 1.4
	_spray_root.visible = true
	Sound.play_at("decon_spray", global_position + Vector3.UP, -8.0)


func _process(delta: float) -> void:
	_clock += delta
	if _spray_left > 0.0:
		_spray_left -= delta
		_spray_root.rotation.y += delta * 5.0
		var fade := clampf(_spray_left / 0.35, 0.0, 1.0)
		_spray_root.scale = Vector3(1.0, fade, 1.0)
		if _spray_left <= 0.0:
			_spray_root.visible = false
	elif _head_light and GameManager.decon_charges <= 0:
		_head_light.light_energy = 0.25 + 0.3 * absf(sin(_clock * 3.0))


func can_interact(player: Node) -> bool:
	return player.get("state") == "ok" and GameManager.decon_charges > 0 and float(player.get("suit_integrity")) < 99.0


func get_prompt(_player: Node) -> String:
	return "Repair"


func interact(player: Node) -> void:
	var before := GameManager.decon_charges
	GameManager.use_decon(player)
	if GameManager.decon_charges < before:
		play_spray()
		Net.rpc_to_run(play_spray, [])
