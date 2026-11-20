extends CanvasLayer
## Nameplates and pointers for the other players, drawn as a 2D overlay so
## they show through walls. On-screen: name, distance and a health sliver over
## the teammate's head in their suit colour. Off-screen (or behind you): an
## arrow clamped to the screen edge pointing their way. Downed teammates
## pulse red with REVIVE; Turned ones show as a hostile marker.

const EDGE := 34.0
const FONT := preload("res://assets/fonts/VT323-Regular.ttf")

var _canvas := Control.new()
var _clock := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or Net.dedicated:
		set_process(false)
		return
	layer = 5
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_markers)
	add_child(_canvas)


func _process(delta: float) -> void:
	_clock += delta
	_canvas.queue_redraw()


func _draw_markers() -> void:
	var camera := get_viewport().get_camera_3d()
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if camera == null or not camera.is_inside_tree() or me == null or DisplayServer.get_name() == "headless":
		return
	var view := _canvas.get_viewport_rect().size
	if view.x <= EDGE * 2.0 or view.y <= EDGE * 2.0:
		return
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Node3D
		if p == null or p == me or not p.is_inside_tree():
			continue
		var state := str(p.get("state"))
		if state == "out":
			continue
		var color: Color = p.get("suit_color") if p.get("suit_color") != null else Color.WHITE
		var head := p.global_position + Vector3.UP * 2.15
		var dist := me.global_position.distance_to(p.global_position)
		var behind := camera.is_position_behind(head)
		var screen := Vector2.ZERO
		if behind:
			# Projecting an exact camera-plane point can divide by zero.
			# Use camera-local lateral displacement for the behind-view arrow.
			var local := camera.to_local(head)
			screen = view * 0.5 + Vector2(local.x, -local.y) * 20.0
		else:
			screen = camera.unproject_position(head)
			if not screen.is_finite():
				continue
		var on_screen := not behind and Rect2(Vector2.ZERO, view).grow(-EDGE).has_point(screen)
		var name := str(p.get("display_name")) if p.get("display_name") != null else "PLAYER"
		var label := name.to_upper()
		var accent := color
		if state == "downed":
			label = "REVIVE " + label
			accent = BroadcastUI.PINK
			if not Settings.reduced_flash:
				accent = accent.lerp(Color("#ffc1cd"), 0.25 + 0.25 * sin(_clock * 8.0))
		elif state == "turned":
			label = "TURNED " + label
			accent = Color(0.55, 1.0, 0.3)
		if on_screen:
			_plate(screen, label, dist, accent, p)
		else:
			_edge_arrow(screen, behind, view, label, dist, accent)


func _plate(at: Vector2, label: String, dist: float, color: Color, p: Node) -> void:
	var size := 17
	var text := "%s  %dm" % [label, roundi(dist)]
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := at + Vector2(-width * 0.5, -6)
	_canvas.draw_string_outline(FONT, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.85))
	_canvas.draw_string(FONT, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	# Health sliver under the name.
	var hp := float(p.get("health")) if p.get("health") != null else 100.0
	var max_hp := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	var bar := Rect2(at + Vector2(-28, 0), Vector2(56, 4))
	_canvas.draw_rect(bar, Color(0, 0, 0, 0.7))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0), bar.size.y)), color)
	# Small chevron pointing down at them.
	var tip := at + Vector2(0, 14)
	_canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, -7), tip + Vector2(6, -7)]), color)


func _edge_arrow(screen: Vector2, behind: bool, view: Vector2, label: String, dist: float, color: Color) -> void:
	var center := view * 0.5
	var dir := screen - center
	if behind:
		dir.y = absf(dir.y) + 16.0
	if dir.length_squared() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	# Push out from the center until the arrow hits the screen edge.
	var half := center - Vector2(EDGE, EDGE)
	var scale := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := center + dir * scale
	var side := dir.orthogonal()
	var tip := at + dir * 12.0
	_canvas.draw_colored_polygon(PackedVector2Array([tip, at - dir * 6.0 + side * 9.0, at - dir * 6.0 - side * 9.0]), Color(0, 0, 0, 0.6))
	_canvas.draw_colored_polygon(PackedVector2Array([tip - dir * 2.0, at - dir * 4.0 + side * 7.0, at - dir * 4.0 - side * 7.0]), color)
	var text := "%s %dm" % [label, roundi(dist)]
	var size := 15
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var text_at := (at - dir * 26.0) + Vector2(-width * 0.5, 5)
	text_at.x = clampf(text_at.x, 6.0, view.x - width - 6.0)
	text_at.y = clampf(text_at.y, 18.0, view.y - 6.0)
	_canvas.draw_string_outline(FONT, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.85))
	_canvas.draw_string(FONT, text_at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
