class_name SupplyStation
extends Node3D
## Station cabinet or parachute pallet. State changes come from CrateManager.

const CYAN := Color("#64e4de")
const AMBER := Color("#ffc365")
const DESCENT := 2.4
const OFFER_PADS := ["offer_1", "offer_2", "offer_3"]
const BAY_CENTERS := [-0.62, 0.0, 0.62]
var key: String
var is_drop := false
var has_double := false
var price := 20
var offers: Array = []
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
var _offer_titles: Array[Label3D] = []
var _offer_prices: Array[Label3D] = []
var _offer_items: Array[Node3D] = []
var _offer_rims: Array[StandardMaterial3D] = []

func _ready() -> void:
	add_to_group("compass_marker")
	add_to_group("crates")  # Team pings mark stations and the drop as "crate".
	set_meta("compass_color", AMBER if is_drop else CYAN)
	set_meta("compass_label", "SUPPLY DROP" if is_drop else "STATION")
	set_meta("compass_icon", "drop" if is_drop else "station")
	_frame = Node3D.new()
	add_child(_frame)
	if not Net.dedicated:
		if is_drop:
			var custom := ItemCatalog.prop_model("airdrop")
			if custom:
				_frame.add_child(custom)
				_chute = custom.get_node_or_null("Parachute") as Node3D
				_lid = custom.get_node_or_null("Lid") as Node3D
				_display = _label("SUPPLY", Vector3(0.0, 1.05, -0.63), Color("#fff0d9"), 48)
				_display.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			else:
				_build_pallet()
		else:
			_build_station()
		_spin_root = Node3D.new()
		_spin_root.position = Vector3(0.0, 1.35 if is_drop else 0.42, -0.58)
		_frame.add_child(_spin_root)
	if is_drop:
		_add_pad("airdrop", Vector3(0, 0.85, 0.0))
	else:
		for i in OFFER_PADS.size():
			_add_pad(OFFER_PADS[i], Vector3(BAY_CENTERS[i], 1.25, -0.58))
		if has_double:
			_add_pad("double", Vector3(0.72, 0.59, -0.61))

func _add_pad(mode: String, at: Vector3) -> void:
	var pad := SupplyInteract.new()
	pad.name = mode
	pad.mode = mode
	pad.position = at
	add_child(pad)

func can_ping() -> bool:
	return not is_queued_for_deletion() and (not is_drop or not opened)

func available(mode: String) -> bool:
	if is_queued_for_deletion():
		return false
	if mode == "airdrop":
		return descent_left <= 0.0 and not opened
	return not is_drop and (not offer_for(mode).is_empty() or (mode == "double" and has_double and WeatherManager.wave >= 4))

func offer_for(mode: String) -> Array:
	var index := OFFER_PADS.find(mode)
	return offers[index] if index >= 0 and index < offers.size() else []

func set_offers(next: Array) -> void:
	var previous := offers
	offers = next
	if Net.dedicated:
		return
	for i in offers.size():
		if i < previous.size() and previous[i] == offers[i]:
			continue
		var offer: Array = offers[i]
		var id: String = offer[0]
		var tint := ItemCatalog.tier_color(id, offer[1])
		var title := ItemCatalog.definition(id).display_name.to_upper()
		_offer_titles[i].text = "\n".join(title.split(" ", false, 1))
		_offer_titles[i].modulate = tint
		_offer_prices[i].text = "%d SCRAP" % offer[2]
		var mount := _offer_items[i]
		for child in mount.get_children():
			mount.remove_child(child)
			child.queue_free()
		var item := ItemCatalog.model(id, true)
		item.scale *= 0.44
		item.rotation_degrees = Vector3(0.0, -75.0, 6.0)
		mount.add_child(item)

func highlight_offer(mode: String, active: bool) -> void:
	var index := OFFER_PADS.find(mode)
	if index >= 0 and index < _offer_rims.size():
		_offer_rims[index].albedo_color = AMBER if active else CYAN.darkened(0.57)

func _process(delta: float) -> void:
	if is_drop:
		var airborne := descent_left > 0.0
		descent_left = maxf(0.0, descent_left - delta)
		_frame.position.y = 5.8 * descent_left
		if not Net.dedicated:
			if airborne and descent_left == 0.0:
				Sound.play_at("airdrop_land", global_position, -4.0)
				ShotFX.puff(self, global_position + Vector3.UP * 0.25,
					Color(0.67, 0.50, 0.35, 0.76), 0.95, 0.7)
				if not Settings.reduced_flash:
					create_tween().tween_method(_compass_tint, 1.0, 0.0, 0.6)
			if _chute:
				_chute.visible = descent_left > 0.0
			_smoke_left -= delta
			if _smoke_left <= 0.0 and not opened:
				_smoke_left = 0.4 if OS.has_feature("web") else 0.2
				ShotFX.puff(self, global_position + Vector3.UP * (_frame.position.y + 0.8),
					Color(1.0, 0.47, 0.23, 0.68), 0.25, 1.3)
	if not Net.dedicated:
		_tick_reveal(delta)

func _compass_tint(amount: float) -> void:
	set_meta("compass_color", AMBER.lerp(BroadcastUI.PAPER, amount))

func _build_station() -> void:
	_box(_frame, Vector3(0, 1.01, 0), Vector3(2.00, 2.02, 0.80), Color("#173640"))
	_box(_frame, Vector3(0, 0.18, 0), Vector3(2.09, 0.30, 0.91), Color("#425963"))
	_box(_frame, Vector3(0, 1.92, -0.02), Vector3(2.07, 0.29, 0.88), Color("#11282b"))
	_box(_frame, Vector3(0, 1.75, -0.425), Vector3(1.99, 0.025, 0.06), CYAN)
	_box(_frame, Vector3(0, 0.49, -0.42), Vector3(1.26, 0.28, 0.09), Color("#0d1418"))
	_label("WEATHER SERVICE / SURPLUS", Vector3(0, 1.92, -0.48), CYAN, 43)
	_display = _label("", Vector3(0, 0.69, -0.49), CYAN, 28)
	for i in BAY_CENTERS.size():
		var x: float = BAY_CENTERS[i]
		_box(_frame, Vector3(x, 1.23, -0.42), Vector3(0.59, 0.88, 0.052), Color("#0c1c21"))
		_box(_frame, Vector3(x, 1.25, -0.45), Vector3(0.54, 0.43, 0.038), Color("#244f54"))
		var rim := _box(_frame, Vector3(x, 0.81, -0.468), Vector3(0.59, 0.027, 0.03), CYAN)
		var strip := StandardMaterial3D.new()
		strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		strip.albedo_color = CYAN.darkened(0.57)
		rim.material_override = strip
		_offer_rims.append(strip)
		var title := _label("", Vector3(x, 1.57, -0.49), Color.WHITE, 46)
		title.pixel_size = 0.00245
		title.line_spacing = -9.0
		title.outline_size = 3
		_offer_titles.append(title)
		var tag := _label("", Vector3(x, 0.92, -0.49), AMBER, 43)
		tag.pixel_size = 0.0029
		tag.outline_size = 3
		_offer_prices.append(tag)
		var mount := Node3D.new()
		mount.position = Vector3(x, 1.24, -0.50)
		_frame.add_child(mount)
		_offer_items.append(mount)
	if has_double:
		_box(_frame, Vector3(0.72, 0.56, -0.45), Vector3(0.30, 0.25, 0.12), Color("#224353"))
		_label("2X W4+", Vector3(0.72, 0.56, -0.52), AMBER, 35)

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
	label.shaded = false
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
		_display.text = "SUPPLY" if is_drop else ""
		_active.clear()
