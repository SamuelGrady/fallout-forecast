extends Control
## A bearing on the screen edge, even if the spawn is behind the camera.

var _from := Vector3.ZERO
var _left := 0.0
var _bearing := Vector2.UP


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func warn(at: Vector3) -> void:
	_from = at
	_left = 2.5
	Sound.play("incoming_group", -12.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - delta)
	var camera := get_viewport().get_camera_3d()
	if camera:
		var direction := _from - camera.global_position
		var local := camera.global_basis.inverse() * Vector3(direction.x, 0.0, direction.z)
		_bearing = Vector2(local.x, local.z).normalized()
	queue_redraw()


func _draw() -> void:
	if _left <= 0.0 or _bearing.is_zero_approx():
		return
	var half := size * .5
	var edge := half - Vector2(76, 99)
	var reach := minf(edge.x / maxf(.001, absf(_bearing.x)), edge.y / maxf(.001, absf(_bearing.y)))
	var tip := half + _bearing * reach
	var normal := _bearing.orthogonal()
	var tail := tip - _bearing * 28.0
	var points := PackedVector2Array([tip, tail + normal * 14.0, tail + _bearing * 7.0, tail - normal * 14.0])
	var opacity := minf(1.0, _left * 2.5)
	draw_colored_polygon(points, Color(1.0, .66, .35, opacity))
	points.append(tip)
	draw_polyline(points, Color(.10, .07, .10, opacity), 2.5, true)
	var font := get_theme_default_font()
	var caption := "INFECTED"
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var at := tip - _bearing * 51.0 + Vector2(-width * .5, 7)
	draw_string_outline(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 5, Color(.05, .04, .08, opacity))
	draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1.0, .80, .55, opacity))
