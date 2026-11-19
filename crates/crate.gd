extends StaticBody3D
## A mystery crate. CrateManager spawns these during Calm. Opening plays a
## short spin of item names over the crate, lands on the result, pops the lid
## and the crate disappears.

const TIER_COLORS := {"common": Color(0.95, 0.92, 0.85), "rare": Color("2EE6E6"), "cursed": Color("FF3EA5")}

@export var double := false

var _spin_left := 0.0
var _spin_tick := 0.0
var _names: Array = []
var _result := ""
var _result_color := Color.WHITE
var _gone_in := -1.0

@onready var label: Label3D = $Spin
@onready var model: Node3D = $Model


func _ready() -> void:
	add_to_group("crates")
	label.visible = double
	if double:
		label.text = "DOUBLE OR NOTHING"
		label.modulate = Color("FFE04A")


## Every peer: show the spin, then the result.
func play_spin(result: String, tier: String, pool: Array) -> void:
	_names = pool
	_result = result
	_result_color = TIER_COLORS.get(tier, Color.WHITE)
	_spin_left = 1.3
	label.visible = true
	model.position.y = 0.0
	var t := create_tween()
	t.tween_property(model, "rotation:y", model.rotation.y + TAU * 2.0, 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _spin_left > 0.0:
		_spin_left -= delta
		_spin_tick -= delta
		if _spin_left <= 0.0:
			label.text = _result
			label.modulate = _result_color
			label.font_size = 80
			var t := create_tween()
			t.tween_property(model, "position:y", 0.6, 0.25)
			t.tween_property(model, "scale", Vector3.ZERO, 0.4).set_delay(0.8)
			_gone_in = 2.0
		elif _spin_tick <= 0.0 and not _names.is_empty():
			_spin_tick = 0.07
			label.text = str(_names.pick_random())
			label.modulate = Color(1, 1, 1, 0.8)
	if _gone_in > 0.0:
		_gone_in -= delta
		label.position.y += delta * 0.4
		if _gone_in <= 0.0 and is_inside_tree():
			queue_free()
