extends Control
## Crosshair plus the rings that replace HUD text: hold-to-interact, reload,
## jam, and the bleed-out timer while downed.

var progress := 0.0
var targeted := false
var hit_left := 0.0
var critical := false
var killed := false
var reload := 0.0
var jammed := false
var downed := false
var bleed := 0.0
var bleed_seconds := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit(is_kill: bool, is_critical: bool) -> void:
	hit_left = 0.28 if is_kill else 0.13
	critical = is_critical
	killed = is_kill


func _process(delta: float) -> void:
	hit_left = maxf(0.0, hit_left - delta)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	if downed:
		_draw_bleed(center)
	else:
		var color := BroadcastUI.CYAN if targeted else Color(1,1,1,0.65)
		if jammed:
			color = BroadcastUI.PINK
		for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			draw_line(center+direction*4,center+direction*9,Color.BLACK,4,true)
			draw_line(center+direction*4,center+direction*9,color,2,true)
	if progress > 0:
		draw_arc(center,20,-PI/2,-PI/2+TAU*progress,40,BroadcastUI.CYAN,4,true)
	elif reload > 0.0:
		draw_arc(center,15,0,TAU,32,Color(BroadcastUI.INK,0.6),3,true)
		draw_arc(center,15,-PI/2,-PI/2+TAU*reload,32,BroadcastUI.PAPER,2,true)
	if hit_left > 0:
		var hit_color := Color("#ffd56a") if critical else (BroadcastUI.PINK if killed else Color.WHITE)
		var duration := 0.28 if killed else 0.13
		var pulse := 0.0 if Settings.reduced_flash else (hit_left / duration) * (6.0 if critical or killed else 3.0)
		var inner := (13.0 if killed else 10.0) + pulse
		var outer := inner + (9.0 if critical or killed else 6.0)
		for i in 4:
			var direction := Vector2.from_angle(PI/4+i*PI/2)
			draw_line(center+direction*inner,center+direction*outer,Color.BLACK,5,true)
			draw_line(center+direction*inner,center+direction*outer,hit_color,3,true)


func _draw_bleed(center: Vector2) -> void:
	var radius := 30.0
	draw_arc(center, radius, 0, TAU, 48, Color(BroadcastUI.INK, 0.65), 6, true)
	draw_arc(center, radius, -PI/2, -PI/2 + TAU * clampf(bleed, 0.0, 1.0), 48, BroadcastUI.PINK, 4, true)
	var text := str(bleed_seconds)
	var font := BroadcastUI.FONT
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string_outline(font, center + Vector2(-width * 0.5, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 3, BroadcastUI.INK)
	draw_string(font, center + Vector2(-width * 0.5, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, BroadcastUI.PINK)
