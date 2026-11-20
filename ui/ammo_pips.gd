extends Control
var rounds := 0
var capacity := 6
var reload_progress := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(_delta: float) -> void:
	queue_redraw()
func _draw() -> void:
	var count := mini(capacity,12)
	var step := size.x / maxf(count,1)
	for i in count:
		var filled := float(rounds)/maxf(capacity,1) >= float(i+1)/count
		draw_rect(Rect2(i*step,4,step-3,8),BroadcastUI.PAPER if filled else Color("#344550"))
	if reload_progress > 0:
		draw_line(Vector2(0,18),Vector2(size.x*reload_progress,18),BroadcastUI.CYAN,3,true)
