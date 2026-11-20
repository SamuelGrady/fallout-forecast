class_name SupplyStation
extends Node3D
## Station cabinet or parachute pallet. State changes come from CrateManager.

const CYAN := Color("#64e4de")
const AMBER := Color("#ffc365")
const DESCENT := 7.0
var key: String
var is_drop := false
var has_double := false
var price := 20
var descent_left := 0.0
var opened := false
var _frame: Node3D
var _chute: Node3D
var _lid: Node3D
var _display: Label3D
var _spin_root: Node3D
var _smoke_left := 0.0
var _show_clock := 0.0
var _show_queue: Array[Array] = []
var _active: Array = []

func _ready() -> void:
	add_to_group("compass_marker")
	set_meta("compass_color", AMBER if is_drop else CYAN)
	set_meta("compass_label", "SUPPLY DROP" if is_drop else "STATION")
	set_meta("compass_icon", "drop" if is_drop else "station")
	_frame = Node3D.new()
	add_child(_frame)
	if not Net.dedicated:
		var custom := ItemCatalog.prop_model("airdrop" if is_drop else "crate_station")
		if custom:
			_frame.add_child(custom)
			if is_drop:
				_chute = custom.get_node_or_null("Parachute") as Node3D
				_lid = custom.get_node_or_null("Lid") as Node3D
				_display = _label("SUPPLY", Vector3(0.0, 1.05, -0.63), Color("#fff0d9"), 48)
				_display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			else:
				_display = _label("SURPLUS", Vector3(0, 1.50, -0.52), CYAN, 36)
		elif is_drop:
			_build_pallet()
		else:
			_build_station()
		_spin_root = Node3D.new()
		_spin_root.position = Vector3(0.0, 1.35 if is_drop else 1.18, -0.56)
		_frame.add_child(_spin_root)
	if is_drop:
		_add_pad("airdrop", Vector3(0, 0.85, 0.0))
	else:
		_add_pad("station", Vector3(0.0, 1.1, -0.57))
		if has_double:
			_add_pad("double", Vector3(0.87, 1.04, -0.45))

func _add_pad(mode: String, at: Vector3) -> void:
	var pad := SupplyInteract.new()
	pad.name = mode
	pad.mode = mode
	pad.position = at
	add_child(pad)

func available(mode: String) -> bool:
	if is_queued_for_deletion():
		return false
	if mode == "airdrop":
		return descent_left <= 0.0 and not opened
	return not is_drop and (mode == "station" or (mode == "double" and has_double))

func _process(delta: float) -> void:
	if is_drop:
		descent_left = maxf(0.0, descent_left - delta)
		_frame.position.y = 5.8 * descent_left
		if not Net.dedicated:
			if _chute:
				_chute.visible = descent_left > 0.0
			_smoke_left -= delta
			if _smoke_left <= 0.0 and not opened:
				_smoke_left = 0.4 if OS.has_feature("web") else 0.2
				ShotFX.puff(self, global_position + Vector3.UP * (_frame.position.y + 0.8),
					Color(1.0, 0.47, 0.23, 0.68), 0.25, 1.3)
	if not Net.dedicated:
		_tick_reveal(delta)

func _build_station() -> void:
	_box(_frame, Vector3(0, 1.02, 0), Vector3(1.18, 2.04, 0.85), Color("#263744"))
	_box(_frame, Vector3(0, 0.18, 0), Vector3(1.33, 0.30, 0.97), Color("#475c63"))
	_box(_frame, Vector3(0, 1.92, 0), Vector3(1.26, 0.22, 0.9), CYAN)
	_box(_frame, Vector3(0, 1.50, -0.44), Vector3(0.98, 0.48, 0.05), Color("#14262d"))
	_box(_frame, Vector3(0, 0.51, -0.46), Vector3(0.83, 0.36, 0.10), Color("#10191d"))
	_box(_frame, Vector3(0, 0.79, -0.49), Vector3(1.07, 0.035, 0.12), CYAN)
	_box(_frame, Vector3(0.48, 1.10, -0.46), Vector3(0.10, 0.16, 0.14), AMBER)
	_label("WEATHER SERVICE", Vector3(0, 1.92, -0.46), Color("#12292c"), 41)
	_display = _label("SURPLUS", Vector3(0, 1.50, -0.473), CYAN, 36)
	if has_double:
		_box(_frame, Vector3(0.86, 0.49, -0.25), Vector3(0.40, 0.98, 0.41), Color("#3e4b51"))
		_box(_frame, Vector3(0.86, 1.0, -0.29), Vector3(0.42, 0.09, 0.42), AMBER)
		_label("2X", Vector3(0.86, 0.9, -0.48), AMBER, 34)

func _build_pallet() -> void:
	_box(_frame, Vector3(0, 0.20, 0), Vector3(1.70, 0.40, 1.38), Color("#354b53"))
	_box(_frame, Vector3(0, 0.63, 0), Vector3(1.54, 0.57, 1.20), Color("#d67b4c"))
	for x: float in [-0.52, 0.52]:
		_box(_frame, Vector3(x, 0.52, 0), Vector3(0.11, 0.78, 1.24), Color("#332a2b"))
	_box(_frame, Vector3(0, 0.94, 0), Vector3(1.66, 0.08, 1.26), AMBER)
	_display = _label("SUPPLY", Vector3(0.0, 0.64, -0.63), Color("#fff0d9"), 48)
	_display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_chute = Node3D.new()
	_frame.add_child(_chute)
	var canopy := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.is_hemisphere = true
	dome.radius = 2.25
	dome.height = 1.4
	dome.radial_segments = 12
	dome.rings = 6
	canopy.mesh = dome
	var canopy_style := ItemCatalog.placeholder(AMBER)
	canopy.material_override = canopy_style.material_override
	canopy_style.free()
	canopy.position.y = 3.8
	_chute.add_child(canopy)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			var low := Vector3(x * 0.65, 0.95, z * 0.5)
			var high := Vector3(x * 1.55, 3.8, z * 1.48)
			var cord := _box(_chute, (low + high) / 2.0, Vector3(0.028, 0.028, low.distance_to(high)), Color("#eee2c1"))
			cord.rotation = Basis.looking_at(high - low).get_euler()

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var result := ItemCatalog.placeholder(color)
	result.position = at
	result.scale = size
	parent.add_child(result)
	return result

func _label(caption: String, at: Vector3, color: Color, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = caption
	label.font = preload("res://assets/fonts/VT323-Regular.ttf")
	label.font_size = size
	label.pixel_size = 0.0027
	label.modulate = color
	label.outline_size = 0
	label.position = at
	label.rotation.y = PI
	_frame.add_child(label)
	return label

func reveal(id: String, tier: int, caption: String) -> void:
	if not Net.dedicated:
		_show_queue.append([id, tier, caption])

func _tick_reveal(delta: float) -> void:
	if _active.is_empty():
		if _show_queue.is_empty():
			return
		_active.assign(_show_queue.pop_front())
		_show_clock = 0.0
		Sound.play_at("crate_open", global_position, -8.0)
	var before := _show_clock
	_show_clock += delta
	if _show_clock < 0.65:
		_display.text = ["···", "◇ · ◇", "◆ ◇ ◆", "◇ ◆ ◇"][int(_show_clock * 18.0) % 4]
		return
	if before < 0.65:
		_display.text = _active[2]
		_display.modulate = ItemCatalog.tier_color(_active[0], _active[1])
		var item := ItemCatalog.model(_active[0], true)
		_spin_root.add_child(item)
		var target := item.scale
		item.scale *= 0.12
		item.create_tween().tween_property(item, "scale", target, 0.25)
		Sound.play_at("reel_land", global_position, -10.0)
	_spin_root.rotate_y(delta * 2.4)
	if _show_clock >= 1.45:
		for item: Node in _spin_root.get_children():
			item.queue_free()
		_display.modulate = AMBER if is_drop else CYAN
		_display.text = "SUPPLY" if is_drop else "SURPLUS"
		_active.clear()
