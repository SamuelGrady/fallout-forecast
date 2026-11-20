class_name VcrDeck
extends Control
## The title intro's VCR and cassette, drawn from primitives (no art assets).
## Laid out for the 960 x 720 canvas. The title drives it by setting
## tape_depth (how far the cassette's bottom edge is below the slot: negative
## is above it, CASSETTE.y is fully inside), shake, display and play_lit.

const SLOT_Y := 470.0
const DECK := Rect2(50, 430, 860, 220)
const SLOT := Rect2(250, 459, 460, 22)
const CASSETTE := Vector2(400, 240)
const INK := Color("22306E")
const VFD := Color("4CFFD8")

var tape_depth := -800.0:
	set(v):
		tape_depth = v
		queue_redraw()
var shake := 0.0:
	set(v):
		shake = v
		queue_redraw()
var display := "--:--":
	set(v):
		if v != display:
			display = v
			queue_redraw()
var play_lit := false:
	set(v):
		if v != play_lit:
			play_lit = v
			queue_redraw()
var reel_angle := 0.0:
	set(v):
		reel_angle = v
		queue_redraw()

const FONT := BroadcastUI.FONT

var _shell := StyleBoxFlat.new()
var _hand: FontVariation


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Marker-on-sticker lettering: the UI font, slanted and a little heavier.
	_hand = FontVariation.new()
	_hand.base_font = BroadcastUI.FONT
	_hand.variation_embolden = 0.6
	_hand.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.28, 1), Vector2.ZERO)
	_hand.spacing_glyph = 1
	_shell.bg_color = Color("141417")
	_shell.border_color = Color("2C2C33")
	_shell.set_border_width_all(4)
	_shell.set_corner_radius_all(10)


func _draw() -> void:
	var jolt := Vector2(sin(shake * 37.0) * shake, absf(shake) * 0.6)
	# Shadow on the shelf, then the half of the face above the slot's centre.
	draw_rect(Rect2(DECK.position + Vector2(10, DECK.size.y), Vector2(DECK.size.x - 20, 14)), Color(0, 0, 0, 0.6))
	draw_set_transform(jolt)
	_face_top()
	# The cassette sits in front of the top strip and slides behind the bottom.
	if tape_depth < CASSETTE.y:
		var top_left := Vector2(480.0 - CASSETTE.x * 0.5, SLOT_Y + tape_depth - CASSETTE.y)
		_cassette(top_left, jolt)
	draw_set_transform(jolt)
	_face_bottom()


func _face_top() -> void:
	var top := Rect2(DECK.position, Vector2(DECK.size.x, SLOT_Y - DECK.position.y))
	draw_rect(top, Color("2E3038"))
	draw_rect(Rect2(top.position, Vector2(top.size.x, 3)), Color("6A6E7A"))
	draw_rect(Rect2(SLOT.position, Vector2(SLOT.size.x, SLOT.size.y * 0.5)), Color("050507"))
	draw_string(FONT, Vector2(SLOT.position.x, SLOT.position.y - 6), "VHS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9A9EA8"))
	draw_string(FONT, Vector2(SLOT.end.x - 120, SLOT.position.y - 6), "HQ  VIDEO CASSETTE", HORIZONTAL_ALIGNMENT_RIGHT, 120, 12, Color("80848E"))


func _face_bottom() -> void:
	var y := SLOT_Y
	var face := Rect2(DECK.position.x, y, DECK.size.x, DECK.end.y - y)
	draw_rect(face, Color("26282F"))
	# Brushed-metal striping.
	for i in range(0, int(face.size.y), 6):
		draw_line(Vector2(face.position.x, y + i), Vector2(face.end.x, y + i), Color(1, 1, 1, 0.025), 1.0)
	draw_rect(Rect2(face.position.x, face.end.y - 4, face.size.x, 4), Color("15161A"))
	# Slot lip and the spring flap behind it.
	draw_rect(Rect2(SLOT.position.x, y, SLOT.size.x, SLOT.size.y * 0.5), Color("09090C"))
	draw_rect(Rect2(SLOT.position.x - 4, y + SLOT.size.y * 0.5, SLOT.size.x + 8, 4), Color("4A4D57"))
	var flap := 0.55 if tape_depth > 0.0 and tape_depth < CASSETTE.y else 0.2
	draw_rect(Rect2(SLOT.position.x + 6, y + 1, SLOT.size.x - 12, 8), Color(0.12, 0.12, 0.14, 1.0 - flap))
	# Brand, left.
	draw_string(FONT, Vector2(88, 538), "PINECREST", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("C9CCD4"))
	draw_string(FONT, Vector2(90, 560), "4-HEAD  HI-FI STEREO", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("8A8E98"))
	draw_circle(Vector2(98, 610), 5.0, Color("FF3B30"))
	draw_circle(Vector2(98, 610), 9.0, Color(1, 0.2, 0.15, 0.25))
	draw_string(FONT, Vector2(112, 615), "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8A8E98"))
	# Transport buttons under the slot.
	var labels := ["EJECT", "REW", "PLAY", "F.FWD", "STOP", "REC"]
	for i in labels.size():
		var r := Rect2(268 + i * 72, 540, 60, 22)
		draw_rect(r, Color("3A3D46"))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color("5C606C"))
		if labels[i] == "PLAY" and play_lit:
			draw_rect(Rect2(r.position + Vector2(24, 8), Vector2(12, 6)), Color("7CFF6B"))
		draw_string(FONT, Vector2(r.position.x, r.end.y + 16), labels[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color("A0A4AE"))
	# Fluorescent display, right.
	var vfd := Rect2(722, 512, 160, 58)
	draw_rect(vfd, Color("061412"))
	draw_rect(vfd, Color("3A3D46"), false, 2.0)
	var text_pos := Vector2(vfd.position.x + 12, vfd.position.y + 42)
	if play_lit:
		_triangle(Vector2(vfd.position.x + 20, vfd.position.y + 29), 11.0, VFD)
		text_pos.x += 30
	draw_string_outline(FONT, text_pos, display, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, 4, Color(VFD, 0.18))
	draw_string(FONT, text_pos, display, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, VFD)
	draw_string(FONT, Vector2(vfd.position.x, vfd.end.y + 16), "SP   CH 03   TIMER", HORIZONTAL_ALIGNMENT_CENTER, vfd.size.x, 12, Color("8A8E98"))


func _cassette(at: Vector2, jolt: Vector2) -> void:
	draw_style_box(_shell, Rect2(at, CASSETTE))
	for corner in [Vector2(16, 16), Vector2(CASSETTE.x - 16, 16), Vector2(16, CASSETTE.y - 16), Vector2(CASSETTE.x - 16, CASSETTE.y - 16)]:
		draw_circle(at + corner, 4.0, Color("3A3A42"))
	# Sticker: printed stripe, then marker handwriting.
	var label := Rect2(at + Vector2(30, 22), Vector2(340, 112))
	draw_rect(label, Color("EEE4CB"))
	draw_rect(Rect2(label.position, Vector2(label.size.x, 16)), Color("C8343A"))
	draw_rect(Rect2(label.position + Vector2(0, 18), Vector2(label.size.x, 3)), Color("2D6CC0"))
	draw_string(FONT, label.position + Vector2(8, 13), "VHS   T-120", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("FBEFD8"))
	draw_string(FONT, label.position + Vector2(label.size.x - 108, 13), "HIGH GRADE", HORIZONTAL_ALIGNMENT_RIGHT, 100, 12, Color("FBEFD8"))
	for i in 3:
		var ly := label.position.y + 52 + i * 26
		draw_line(Vector2(label.position.x + 10, ly), Vector2(label.end.x - 10, ly), Color(0.45, 0.55, 0.8, 0.35), 1.0)
	draw_set_transform(jolt + label.position + Vector2(14, 0), -0.035)
	draw_string(_hand, Vector2(0, 58), "FALLOUT FORECAST", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, INK)
	draw_string(_hand, Vector2(4, 80), "DO NOT TAPE OVER!!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("B3262E"))
	draw_line(Vector2(4, 85), Vector2(170, 83), Color("B3262E"), 2.0)
	draw_string(_hand, Vector2(200, 104), "OCT 31 1987", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_set_transform(jolt)
	# Smoked window with the two reels.
	var window := Rect2(at + Vector2(110, 150), Vector2(180, 56))
	draw_rect(window, Color("1E2228"))
	_reel(window.position + Vector2(40, 28), 27.0)
	_reel(window.position + Vector2(140, 28), 15.0)
	draw_rect(window, Color(0.55, 0.6, 0.7, 0.12))
	draw_rect(window, Color("2C2C33"), false, 2.0)
	# Grip ridges along the bottom edge.
	for i in 18:
		var x := at.x + 60 + i * 16
		draw_line(Vector2(x, at.y + CASSETTE.y - 22), Vector2(x, at.y + CASSETTE.y - 10), Color("24242A"), 3.0)


func _reel(center: Vector2, pack: float) -> void:
	draw_circle(center, pack, Color("3A2A20"))
	draw_circle(center, 11.0, Color("D8D8D2"))
	for i in 6:
		var a := reel_angle + i * TAU / 6.0
		draw_line(center + Vector2.from_angle(a) * 4.0, center + Vector2.from_angle(a) * 10.0, Color("1E2228"), 2.0)
	draw_circle(center, 3.5, Color("1E2228"))


func _triangle(center: Vector2, half: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-half * 0.8, -half), center + Vector2(half, 0), center + Vector2(-half * 0.8, half)]), color)
