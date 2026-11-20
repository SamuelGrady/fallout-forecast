extends Control
## North is -Z, east is +X. Positions are sampled separately from camera yaw.

const ARC := 90.0
const RANGE_METERS := 45.0
const SCAN_INTERVAL := 0.10
const WARNING_TIME := 2.5
const INFECTED := Color("#ff554f")
const OBJECTIVE := Color("#ffd56a")
const CARDINALS := ["N", "E", "S", "W"]

enum Marker { INFECTED, ELITE, BOSS, TEAMMATE }

var _markers := PackedVector4Array()
var _objectives: Array[Node] = []
var _backing: StyleBoxFlat
var _scan_left := 0.0
var _warning_left := 0.0
var _warning_at := Vector3.ZERO
var _camera_at := Vector3.ZERO
var _heading := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	offset_left = -250
	offset_right = 250
	offset_top = 21
	offset_bottom = 53
	pivot_offset.x = 250
	scale = Vector2.ONE * Settings.hud_scale
	_backing = BroadcastUI.panel(BroadcastUI.OVERLAY, BroadcastUI.CYAN)
	_backing.border_width_left = 0
	_backing.border_width_bottom = 1
	_backing.set_content_margin_all(0)
	if DisplayServer.get_name() == "headless" or Net.dedicated:
		hide()
		set_process(false)
		return
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner:
		spawner.group_incoming.connect(warn)


func warn(at: Vector3) -> void:
	_warning_at = at
	_warning_left = WARNING_TIME
	Sound.play("incoming_group", -12.0)


func _process(delta: float) -> void:
	_warning_left = maxf(0.0, _warning_left - delta)
	var player := get_tree().get_first_node_in_group("local_player") as Player
	var camera := get_viewport().get_camera_3d()
	visible = player != null and player.state in ["ok", "turned"] and camera != null
	if not visible:
		_scan_left = 0.0
		return
	_camera_at = camera.global_position
	var right := camera.global_basis.x
	_heading = fposmod(rad_to_deg(atan2(right.z, right.x)), 360.0)
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_INTERVAL
		_scan(player)
	queue_redraw()


func _scan(player: Player) -> void:
	_markers.clear()
	_objectives = get_tree().get_nodes_in_group("compass_marker")
	for node in get_tree().get_nodes_in_group("players"):
		var teammate := node as Player
		if teammate and teammate != player and teammate.state in ["ok", "downed"]:
			_add_marker(teammate.global_position, Marker.TEAMMATE)
	for node in get_tree().get_nodes_in_group("enemies"):
		var infected := node as EnemyBase
		if infected and infected.health > 0.0 and not infected.is_queued_for_deletion():
			var elite := infected.is_elite or infected.miniboss_wave > 0
			_add_marker(infected.global_position, Marker.ELITE if elite else Marker.INFECTED)
	for node in get_tree().get_nodes_in_group("boss"):
		var boss := node as Node3D
		if boss and not bool(boss.get("dead")):
			_add_marker(boss.global_position, Marker.BOSS)


func _add_marker(at: Vector3, kind: Marker) -> void:
	if _camera_at.distance_squared_to(at) <= RANGE_METERS * RANGE_METERS:
		_markers.append(Vector4(at.x, at.y, at.z, kind))


func _offset(at: Vector3) -> float:
	var displacement := at - _camera_at
	var world_bearing := rad_to_deg(atan2(displacement.x, -displacement.z))
	return wrapf(world_bearing - _heading, -180.0, 180.0)


func _tape_x(angle: float) -> float:
	return size.x * 0.5 + clampf(angle / ARC, -1.0, 1.0) * (size.x * 0.5 - 10.0)


func _draw() -> void:
	if _backing == null:
		return
	draw_style_box(_backing, Rect2(Vector2.ZERO, size))
	var first := floori((_heading - ARC) / 15.0)
	for i in range(first, first + 14):
		var bearing := i * 15
		var offset := float(bearing) - _heading
		if absf(offset) > ARC:
			continue
		var x := _tape_x(offset)
		var major := bearing % 45 == 0
		draw_line(Vector2(x, 16.0 if major else 19.0), Vector2(x, 23), BroadcastUI.MUTED, 1.0)
		if major:
			var degrees := posmod(bearing, 360)
			var text := "%03d" % degrees
			if degrees % 90 == 0:
				text = "%s %s" % [CARDINALS[degrees / 90], text]
			_caption(text, Vector2(clampf(x, 24.0, size.x - 24.0), 13), 16, BroadcastUI.PAPER if degrees % 90 == 0 else BroadcastUI.MUTED)
	if _warning_left > 0.0:
		_draw_warning()
	for marker in _markers:
		_draw_marker(marker)
	_draw_objectives()
	var center := size.x * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(center - 5, 32), Vector2(center, 27), Vector2(center + 5, 32)]), BroadcastUI.CYAN)
	draw_rect(Rect2(center - 22, -12, 44, 15), BroadcastUI.OVERLAY)
	_caption("%03d°" % posmod(roundi(_heading), 360), Vector2(center, -1), 17, BroadcastUI.CYAN)


func _caption(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := BroadcastUI.FONT
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := at - Vector2(width * 0.5, 0)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, BroadcastUI.INK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_marker(marker: Vector4) -> void:
	var at := Vector3(marker.x, marker.y, marker.z)
	var angle := _offset(at)
	var proximity := 1.0 - clampf(_camera_at.distance_to(at) / RANGE_METERS, 0.0, 1.0)
	var kind := int(marker.w)
	var color := INFECTED
	if kind == Marker.ELITE or kind == Marker.BOSS:
		color = BroadcastUI.PINK
	elif kind == Marker.TEAMMATE:
		color = BroadcastUI.CYAN
	color.a = lerpf(0.56, 1.0, proximity)
	var point := Vector2(_tape_x(angle), 25.0)
	if absf(angle) > ARC:
		_edge_marker(point, angle, color)
		return
	var radius := lerpf(2.5, 4.4, proximity)
	match kind:
		Marker.TEAMMATE: draw_circle(point, radius * 0.68, color, true, -1.0, true)
		Marker.INFECTED: draw_circle(point, radius, color, true, -1.0, true)
		Marker.ELITE: _diamond(point, radius + 1.5, color)
		Marker.BOSS:
			_diamond(point, radius + 4, color)
			draw_circle(point, 2.0, BroadcastUI.PAPER)


func _draw_objectives() -> void:
	var nearest: Node3D
	var best_angle := 10.0
	for node in _objectives:
		if not is_instance_valid(node) or not node is Node3D or node.is_queued_for_deletion():
			continue
		var objective := node as Node3D
		var angle := _offset(objective.global_position)
		var point := Vector2(_tape_x(angle), 24.0)
		var color := _objective_color(objective)
		if absf(angle) > ARC:
			_edge_marker(point, angle, color)
		else:
			_objective_icon(point, str(objective.get_meta("compass_icon", "")), color)
		# Reserve the label slot for the marker closest to the caret.
		if absf(angle) <= best_angle:
			best_angle = absf(angle)
			nearest = objective
	if nearest:
		var title := str(nearest.get_meta("compass_label", "OBJECTIVE")).strip_edges().left(28)
		if title.is_empty():
			title = "OBJECTIVE"
		var distance := roundi(_camera_at.distance_to(nearest.global_position))
		var text := "%s  %dm" % [title.to_upper(), distance]
		var width := BroadcastUI.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16.0
		var x := _tape_x(_offset(nearest.global_position))
		draw_rect(Rect2(x - width * 0.5, 33, width, 17), BroadcastUI.OVERLAY)
		_caption(text, Vector2(x, 45), 16, _objective_color(nearest))


func _objective_color(node: Node3D) -> Color:
	var color: Variant = node.get_meta("compass_color", OBJECTIVE)
	return color if color is Color else OBJECTIVE


func _objective_icon(point: Vector2, icon: String, color: Color) -> void:
	match icon:
		"drop":
			draw_arc(point + Vector2(0, -1), 6.0, PI, TAU, 12, color, 1.5, true)
			draw_polyline(PackedVector2Array([point + Vector2(-6, -1), point + Vector2(-2, 3),
				point + Vector2(2, 3), point + Vector2(6, -1)]), color, 1.0, true)
			draw_rect(Rect2(point + Vector2(-2, 3), Vector2(4, 4)), color)
		"station":
			draw_rect(Rect2(point - Vector2(5, 5), Vector2(10, 10)), color, false, 1.5)
			draw_line(point + Vector2(-4, -1), point + Vector2(4, -1), color)
		_:
			_diamond(point, 5.0, color)


func _edge_marker(at: Vector2, angle: float, color: Color) -> void:
	var inward := -signf(angle)
	draw_polyline(PackedVector2Array([at + Vector2(inward * 4, -3), at,
		at + Vector2(inward * 4, 3)]), color, 1.8, true)


func _diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2.UP * radius, at + Vector2.RIGHT * radius,
		at + Vector2.DOWN * radius, at + Vector2.LEFT * radius]), color)


func _draw_warning() -> void:
	var x := _tape_x(_offset(_warning_at))
	var pulse := 0.76 if Settings.reduced_flash else 0.58 + 0.30 * sin(_warning_left * TAU * 2.0)
	var color := Color(INFECTED, pulse * minf(1.0, _warning_left * 3.0))
	draw_colored_polygon(PackedVector2Array([Vector2(maxf(0.0, x - 12), 0), Vector2(minf(size.x, x + 12), 0),
		Vector2(x, 18)]), color)
