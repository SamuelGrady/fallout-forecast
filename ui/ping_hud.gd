extends Control
## Ping input, the radial wheel, on-screen markers and the ping feed.
## Built by PingSystem (game/ping_system.gd) on every peer with a screen.
##
## Controls ("ping": middle mouse, Z, D-pad down):
## - tap: ping what's under the crosshair (enemy, crate, decon, objective,
##   pickup, or GO HERE on the spot). Downed, a tap is REVIVE ME.
## - hold: the wheel opens and the camera freezes. Mouse or right stick
##   picks a slice; release sends it, release in the middle cancels.
##
## Markers are drawn here rather than as Label3Ds: they stay sharp under the
## RetroScreen pixelation, show through walls, and clamp to the screen edge
## as an arrow when the spot is off-screen.

const HOLD := 0.2
const WHEEL_RADIUS := 150.0
const WHEEL_INNER := 46.0
const DEADZONE := 26.0
const EDGE := 44.0
const FEED_TIME := 3.5
const FEED_MAX := 4
## Clockwise from the top. REVIVE ME sits at the bottom.
const SLICES := ["enemy", "crate", "go", "revive", "shelter", "danger"]
const SLICE_LABELS := {"enemy": "ENEMY HERE", "crate": "CRATE HERE", "go": "GO HERE",
	"revive": "REVIVE ME", "shelter": "SHELTER HERE", "danger": "LOOK OUT"}

var system: PingSystem
var _pinger: Player
var _hold := 0.0
var _open := false
var _select := Vector2.ZERO
var _last_slice := -1
var _pending := ""
var _run_ended := false
var _wheel_icons: Array[GameIcon] = []
## [ping dictionary, GameIcon] for each live marker.
var _markers: Array = []
var _feed: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in SLICES:
		var icon := GameIcon.new()
		icon.kind = PingSystem.KINDS[kind].icon
		icon.size = Vector2(30, 30)
		icon.visible = false
		add_child(icon)
		_wheel_icons.append(icon)
	system.pinged.connect(_on_pinged)
	get_window().focus_exited.connect(_cancel)
	GameManager.run_finished.connect(func(_won: bool, _results: Dictionary):
		_run_ended = true
		_cancel())


func _local() -> Player:
	return get_tree().get_first_node_in_group("local_player") as Player


func _can_ping(player: Player) -> bool:
	return is_instance_valid(player) and player.is_multiplayer_authority() and player.state in ["ok", "downed"] \
		and not _run_ended and GameManager.mutations.stage == "" and not get_tree().paused


# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if event.is_action("ping") and not event.is_echo():
		if event.is_pressed():
			var player := _local()
			if not is_instance_valid(_pinger) and _can_ping(player):
				_pinger = player
				_hold = 0.0
		elif is_instance_valid(_pinger):
			if event.is_canceled():
				_cancel()
			else:
				_release()
	elif _open and event is InputEventMouseMotion:
		# The wheel eats mouse look while it's open.
		Settings.using_gamepad = false
		_select = (_select + event.relative).limit_length(WHEEL_RADIUS * 0.6)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _can_ping(_local()):
		_cancel()
	elif _open and not is_instance_valid(_pinger):
		_close()
	elif is_instance_valid(_pinger):
		if not _can_ping(_pinger):
			_cancel()
		else:
			_hold += delta
			if not _open and _hold >= HOLD:
				_open = true
				_select = Vector2.ZERO
				_last_slice = -1
				_pinger.look_locked = true
				Sound.play("ui_click", -14.0, 1.4)
			if _open:
				if Settings.using_gamepad:
					_select = Input.get_vector("look_left", "look_right", "look_up", "look_down") * WHEEL_RADIUS * 0.6
				var slice := _slice_index()
				if slice != _last_slice and slice >= 0:
					Sound.play("reel_tick", -16.0, 1.3)
				_last_slice = slice
	for i in range(_feed.size() - 1, -1, -1):
		_feed[i].age += delta
		if _feed[i].age > FEED_TIME:
			_feed.remove_at(i)
	_sync_marker_icons()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if _pending == "":
		return
	var kind := _pending
	_pending = ""
	var player := _local()
	if not _can_ping(player):
		return
	if kind == "context" and player.state == "downed":
		kind = "revive"
	var ping := system.context_ping(player) if kind == "context" else system.wheel_ping(player, kind)
	system.send(ping.kind, ping.pos, int(ping.enemy_id))


func _release() -> void:
	if _can_ping(_pinger):
		_pending = _selected_kind(_pinger) if _open else "context"
	_close()


func _cancel() -> void:
	_pending = ""
	_close()


func _close() -> void:
	if _open and is_instance_valid(_pinger):
		_pinger.look_locked = false
	_pinger = null
	_hold = 0.0
	_open = false


func _slice_index() -> int:
	if _select.length() < DEADZONE:
		return -1
	var step := TAU / SLICES.size()
	return posmod(roundi((_select.angle() + PI * 0.5) / step), SLICES.size())


func _selected_kind(player: Player) -> String:
	var index := _slice_index()
	if index < 0 or player == null:
		return ""
	var kind: String = SLICES[index]
	if kind == "revive" and player.state != "downed":
		return ""
	return kind


func _on_pinged(ping: Dictionary) -> void:
	var label: String = PingSystem.KINDS[ping.kind].label
	if ping.kind != "revive" or ping.owner != multiplayer.get_unique_id():
		var icon := GameIcon.new()
		icon.kind = PingSystem.KINDS[ping.kind].icon
		icon.color = ping.color
		icon.size = Vector2(26, 26)
		add_child(icon)
		_markers.append([ping, icon])
	_feed.append({"text": "%s  /  %s" % [ping.name, label], "color": ping.color, "age": 0.0})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()


func _sync_marker_icons() -> void:
	for i in range(_markers.size() - 1, -1, -1):
		if not system.pings.has(_markers[i][0]):
			(_markers[i][1] as Node).queue_free()
			_markers.remove_at(i)


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	for entry in _markers:
		if GameManager.mutations.stage == "":
			_draw_marker(entry[0], entry[1], camera)
		else:
			entry[1].visible = false
	if GameManager.mutations.stage == "":
		_draw_feed()
	for icon in _wheel_icons:
		icon.visible = _open
	if _open:
		_draw_wheel()
	elif _can_ping(_local()):
		var key := "D-PAD DOWN" if Settings.using_gamepad else "Z / MMB"
		var hint := "[%s] TAP TO PING  /  HOLD FOR WHEEL" % key
		_text(BroadcastUI.FONT, Vector2(size.x * 0.5 - 145.0, size.y - 24.0), hint, 290, 16, Color(BroadcastUI.PAPER, 0.8))


func _draw_marker(ping: Dictionary, icon: GameIcon, camera: Camera3D) -> void:
	if camera == null:
		icon.visible = false
		return
	var lift := 2.1 if ping.kind == "enemy" or ping.kind == "revive" else 0.9
	var world: Vector3 = ping.pos + Vector3.UP * lift
	var alpha := clampf((ping.life - ping.age) / 0.8, 0.0, 1.0)
	var pop := 1.0 + 0.6 * (1.0 - minf(ping.age / 0.2, 1.0))
	var color: Color = ping.color
	color.a = alpha
	var ink := Color(BroadcastUI.INK, 0.85 * alpha)
	var paper := Color(BroadcastUI.PAPER, alpha)
	var meters := "%d M" % roundi(camera.global_position.distance_to(ping.pos))
	var center := size * 0.5
	var bounds := Rect2(Vector2.ONE * EDGE, size - Vector2.ONE * EDGE * 2.0)
	var screen := camera.unproject_position(world)
	var on_screen := not camera.is_position_behind(world) and bounds.has_point(screen)
	var font := BroadcastUI.FONT
	icon.visible = true
	icon.modulate.a = alpha
	icon.color = ping.color
	if on_screen:
		var radius := 17.0 * pop
		var below := screen.y < 108.0
		var at := screen + Vector2(0, 30 if below else -30)
		# Stem down to the exact spot, then the icon disc and the caption.
		draw_line(at, screen, color, 2.0, true)
		draw_circle(screen, 3.0, color)
		draw_circle(at, radius + 2.0, ink)
		draw_arc(at, radius + 2.0, 0, TAU, 28, color, 2.5, true)
		icon.size = Vector2.ONE * radius * 1.4
		icon.position = at - icon.size * 0.5
		var label: String = PingSystem.KINDS[ping.kind].label
		var width := 96.0
		var top := Vector2(clampf(at.x - width * 0.5, 8.0, size.x - width - 8.0),
			at.y + (radius + 8.0 if below else -radius - 30.0))
		draw_rect(Rect2(top, Vector2(width, 22)), ink)
		draw_rect(Rect2(top, Vector2(3, 22)), color)
		_text(font, top + Vector2(0, 17), label, width, 16, color)
		_text(font, screen + Vector2(-40, -10 if below else 18), meters, 80, 15, paper)
		return
	# Off-screen: an arrow on the edge, pointing the way to turn.
	var local := camera.global_transform.affine_inverse() * world
	var direction := Vector2(local.x, -local.y)
	if direction.length() < 0.01:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var half := bounds.size * 0.5
	var reach := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	var tip := center + direction * reach
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip + direction * 14.0, tip + side * 10.0, tip - side * 10.0]), color)
	var body := tip - direction * 26.0
	draw_circle(body, 16.0, ink)
	draw_arc(body, 16.0, 0, TAU, 24, color, 2.5, true)
	icon.size = Vector2(22, 22)
	icon.position = body - icon.size * 0.5
	var caption := body + Vector2(-40, 34) if direction.y < 0.6 else body + Vector2(-40, -22)
	_text(font, caption, meters, 80, 15, paper)


func _draw_wheel() -> void:
	var center := size * 0.5
	var player := _local()
	var color := PingSystem.color_of(player)
	var count := SLICES.size()
	var step := TAU / count
	var selected := _slice_index()
	var font := BroadcastUI.FONT
	draw_circle(center, WHEEL_RADIUS + 6.0, Color(BroadcastUI.INK, 0.78))
	for i in count:
		var kind: String = SLICES[i]
		var mid := -PI * 0.5 + i * step
		var enabled := kind != "revive" or (player != null and player.state == "downed")
		var points := PackedVector2Array()
		var gap := 0.03
		for j in 9:
			points.append(center + Vector2.from_angle(mid - step * 0.5 + gap + (step - gap * 2.0) * j / 8.0) * WHEEL_RADIUS)
		for j in 9:
			points.append(center + Vector2.from_angle(mid + step * 0.5 - gap - (step - gap * 2.0) * j / 8.0) * WHEEL_INNER)
		var fill := Color("#182837")
		if i == selected and enabled:
			fill = Color(color, 0.55)
		elif not enabled:
			fill = Color("#101a24")
		draw_colored_polygon(points, fill)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, color if i == selected and enabled else Color("#314655"), 2.0, true)
		var label_at := center + Vector2.from_angle(mid) * (WHEEL_INNER + WHEEL_RADIUS) * 0.5
		var tint := BroadcastUI.PAPER if enabled else Color(BroadcastUI.PAPER, 0.3)
		var icon := _wheel_icons[i]
		icon.color = color if enabled else Color(0.5, 0.55, 0.6, 0.4)
		icon.position = label_at + Vector2(-15, -30)
		_text(font, label_at + Vector2(-60, 16), SLICE_LABELS[kind], 120, 15, tint)
		if kind == "revive" and not enabled:
			_text(font, label_at + Vector2(-60, 32), "WHEN DOWNED", 120, 11, Color(BroadcastUI.PAPER, 0.3))
	draw_circle(center, WHEEL_INNER - 4.0, Color(BroadcastUI.INK, 0.95))
	draw_arc(center, WHEEL_INNER - 4.0, 0, TAU, 32, BroadcastUI.CYAN, 2.0, true)
	var hub := "CANCEL" if _selected_kind(player) == "" else "SEND"
	_text(font, center + Vector2(-40, 6), hub, 80, 17, BroadcastUI.CYAN)
	draw_circle(center + _select, 4.0, color)


func _draw_feed() -> void:
	var font := BroadcastUI.FONT
	var right := size.x - 28.0
	for i in _feed.size():
		var line: Dictionary = _feed[i]
		var alpha := clampf((FEED_TIME - line.age) / 0.6, 0.0, 1.0)
		var y := 104.0 + i * 24.0
		var width := 260.0
		var color: Color = line.color
		draw_rect(Rect2(right - 4, y - 17, 4, 22), Color(color, alpha))
		draw_string_outline(font, Vector2(right - width - 10, y), line.text, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, 5, Color(BroadcastUI.INK, alpha))
		draw_string(font, Vector2(right - width - 10, y), line.text, HORIZONTAL_ALIGNMENT_RIGHT, width, 17, Color(BroadcastUI.PAPER, alpha))


func _text(font: Font, at: Vector2, text: String, width: float, font_size: int, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 5, Color(BroadcastUI.INK, color.a))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)
