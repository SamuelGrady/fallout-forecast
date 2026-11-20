extends CanvasLayer
## Hit-direction indicators: a red arc around the crosshair pointing at
## whatever just hurt you (Player.hurt_from), fading out over LIFE seconds.
## Recomputed every frame from the source position, so the arc swings as you
## turn toward the threat.

const LIFE := 1.3
const RADIUS := 120.0
const MAX_HITS := 6

var _hits: Array = []  # [world position, time left]
var _canvas := Control.new()
var _player: Node


func _ready() -> void:
	layer = 7
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hits)
	add_child(_canvas)


func _process(delta: float) -> void:
	var me := get_tree().get_first_node_in_group("local_player")
	if me != _player:
		if _player and is_instance_valid(_player) and _player.hurt_from.is_connected(_on_hurt):
			_player.hurt_from.disconnect(_on_hurt)
		_player = me
		if _player and _player.has_signal("hurt_from"):
			_player.hurt_from.connect(_on_hurt)
	for h in _hits:
		h[1] -= delta
	_hits = _hits.filter(func(h): return h[1] > 0.0)
	_canvas.queue_redraw()


func _on_hurt(at: Vector3) -> void:
	_hits.append([at, LIFE])
	if _hits.size() > MAX_HITS:
		_hits.pop_front()


func _draw_hits() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _hits.is_empty():
		return
	var center := _canvas.get_viewport_rect().size * 0.5
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	for h in _hits:
		var to: Vector3 = h[0] - camera.global_position
		to.y = 0.0
		if to.length_squared() < 0.01:
			continue
		to = to.normalized()
		# 0 = straight ahead (top of the ring), clockwise positive.
		var angle := atan2(to.dot(right), to.dot(forward)) - PI * 0.5
		var alpha := clampf(float(h[1]) / LIFE, 0.0, 1.0)
		var color := Color(BroadcastUI.PINK, (0.52 if Settings.reduced_flash else 0.85) * alpha)
		_canvas.draw_arc(center, RADIUS, angle - 0.42, angle + 0.42, 18, Color(BroadcastUI.INK, alpha), 12.0, true)
		_canvas.draw_arc(center, RADIUS, angle - 0.42, angle + 0.42, 18, color, 9.0, true)
		_canvas.draw_arc(center, RADIUS + 9.0, angle - 0.2, angle + 0.2, 10, Color(color, color.a * 0.6), 5.0, true)
