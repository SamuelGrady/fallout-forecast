extends Label3D
var amount := 0
var critical := false
var killed := false
var age := 0.0
var _tween: Tween


func _ready() -> void:
	font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	pixel_size = .006
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Draw over the enemy that was hit; it spawns at the impact point, which
	# is often inside the body.
	no_depth_test = true
	render_priority = 10
	outline_modulate = Color("#17212c")
	outline_size = 10
	_refresh()
	_animate()


func _process(delta: float) -> void:
	age += delta


func add_hit(delta_amount: int, is_critical: bool) -> void:
	amount += delta_amount
	critical = critical or is_critical
	age = 0.0
	_refresh()
	scale = Vector3.ONE * (1.28 if critical else 1.15)
	_animate()


func _refresh() -> void:
	text = str(amount)
	font_size = 74 if critical else 54
	# Headshots get their own hot red instead of a "!" suffix.
	modulate = Color("#ff4f6a") if critical else Color("#f4f5e5")


func _animate() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	scale = Vector3.ONE * (1.28 if critical else 1.15)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector3.ONE, 0.14)
	_tween.tween_property(self, "modulate:a", 0.0, 0.25).set_delay(0.45)
	_tween.chain().tween_callback(queue_free)
