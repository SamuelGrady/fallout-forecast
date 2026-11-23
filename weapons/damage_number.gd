extends Control
## One screen-space draw list for the run's floating damage numbers.

const STACK_TIME := 0.15
const POP_TIME := 0.14
const FADE_START := 0.45
const LIFETIME := 0.70
const DRIFT_SPEED := 36.0
const OUTLINE := Color("#17212c")
const NORMAL := Color("#f4f5e5")
const CRITICAL := Color("#ff4f6a")

class Marker:
	var enemy_id: int
	var world_position: Vector3
	var screen_position: Vector2
	var projected := false
	var jitter: float
	var amount := 0
	var critical := false
	var age := 0.0
	var text: String

var _active: Array[Marker] = []
var _latest: Dictionary[int, Marker] = {}
var _jitter := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 1
	set_process(false)


func add_hit(point: Vector3, amount: int, critical: bool, enemy_id := 0) -> void:
	var marker := _latest.get(enemy_id) as Marker
	if marker == null or marker.age >= STACK_TIME:
		marker = Marker.new()
		marker.enemy_id = enemy_id
		marker.jitter = _jitter.randf_range(-6.0, 6.0)
		_active.append(marker)
		if enemy_id > 0:
			_latest[enemy_id] = marker
	marker.world_position = point + Vector3.UP * 0.35
	marker.amount += amount
	marker.critical = marker.critical or critical
	marker.age = 0.0
	marker.text = str(marker.amount)
	_project(marker, get_viewport().get_camera_3d())
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for i in range(_active.size() - 1, -1, -1):
		var marker := _active[i]
		marker.age += delta
		if marker.age >= LIFETIME:
			if _latest.get(marker.enemy_id) == marker:
				_latest.erase(marker.enemy_id)
			_active.remove_at(i)
		else:
			_project(marker, camera)
	if _active.is_empty():
		set_process(false)
	queue_redraw()


func _project(marker: Marker, camera: Camera3D) -> void:
	marker.projected = camera != null and not camera.is_position_behind(marker.world_position)
	if marker.projected:
		marker.screen_position = camera.unproject_position(marker.world_position)
		marker.screen_position += Vector2(marker.jitter, -marker.age * DRIFT_SPEED)


func _draw() -> void:
	var font := BroadcastUI.FONT
	var hud_scale := Settings.hud_scale
	var outline_size := roundi(4.0 * hud_scale)
	for marker in _active:
		if not marker.projected:
			continue
		var pop := lerpf(1.35, 1.0, minf(marker.age / POP_TIME, 1.0))
		var font_size := roundi((38 if marker.critical else 28) * hud_scale * pop)
		var alpha := 1.0 - clampf(inverse_lerp(FADE_START, LIFETIME, marker.age), 0.0, 1.0)
		var color := Color(CRITICAL if marker.critical else NORMAL, alpha)
		var width := font.get_string_size(marker.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var at := (marker.screen_position - Vector2(width * 0.5, 0.0)).round()
		draw_string_outline(font, at, marker.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, Color(OUTLINE, alpha))
		draw_string(font, at, marker.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
