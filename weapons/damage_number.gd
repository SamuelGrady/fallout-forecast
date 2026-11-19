extends Label3D
var amount := 0
var critical := false
var killed := false
func _ready() -> void:
	text = str(amount) + ("!" if critical else "")
	font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_size = 70 if critical else 52
	pixel_size = .006
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = false
	modulate = Color("#ffd56a") if critical else Color("#f4f5e5")
	outline_modulate = Color("#17212c")
	outline_size = 10
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position", position + Vector3(randf_range(-.3,.3), .75, 0), .7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, .25).set_delay(.45)
	tween.chain().tween_callback(queue_free)
