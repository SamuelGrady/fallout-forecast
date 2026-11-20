extends CanvasLayer
## "ACHIEVEMENT" / "SUIT UNLOCKED" card: a VHS on-screen-display strip that
## tracks in from the right edge with a short jingle (ui_achievement.wav).
## Owned by GameManager/Feats so it shows over any scene. Cards queue up.

const HOLD := 3.4
const WIDTH := 340.0

var _queue: Array[String] = []
var _busy := false
var _panel := PanelContainer.new()
var _tag := Label.new()
var _name := Label.new()
var _desc := Label.new()
var _swatch := ColorRect.new()


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size.x = WIDTH
	_panel.size.x = WIDTH
	_panel.position = Vector2(960.0, 150.0)
	root.add_child(_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	_swatch.custom_minimum_size = Vector2(10, 0)
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_swatch)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	BroadcastUI.text(_tag, 17, BroadcastUI.AMBER)
	col.add_child(_tag)
	BroadcastUI.text(_name, 27, BroadcastUI.PAPER, 2)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_name)
	BroadcastUI.text(_desc, 18, BroadcastUI.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_desc)
	_panel.hide()


func show_feat(id: String) -> void:
	_queue.append(id)
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		_panel.hide()
		return
	_busy = true
	var id: String = _queue.pop_front()
	var feat := Feats.entry(id)
	var reward := Feats.reward_name(id)
	var accent := BroadcastUI.ACID if reward != "" else BroadcastUI.AMBER
	_tag.text = ("SUIT UNLOCKED  /  " + reward) if reward != "" else "ACHIEVEMENT  /  REC"
	_tag.add_theme_color_override("font_color", accent)
	_name.text = str(feat.get("name", id))
	_desc.text = str(feat.get("desc", ""))
	_swatch.color = Cosmetics.color(int(feat.color)) if feat.has("color") else accent
	var style := BroadcastUI.panel(BroadcastUI.OVERLAY, accent)
	style.border_width_left = 0
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(accent, 0.7)
	style.content_margin_left = 0
	style.content_margin_top = 8
	style.content_margin_bottom = 9
	style.content_margin_right = 14
	_panel.add_theme_stylebox_override("panel", style)
	_panel.size = Vector2(WIDTH, 0.0)
	_panel.reset_size()
	_panel.show()
	Sound.play("ui_achievement", -7.0)
	var shown_x := 960.0 - WIDTH - 16.0
	_panel.position = Vector2(960.0 + 8.0, 150.0)
	_panel.modulate = Color(1, 1, 1, 0)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_panel, "position:x", shown_x, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_panel, "modulate:a", 1.0, 0.16)
	if not Settings.reduced_flash:
		# A tracking hiccup as it lands, like a tape catching up.
		tween.tween_property(_panel, "position:x", shown_x - 7.0, 0.04)
		tween.tween_property(_panel, "position:x", shown_x + 3.0, 0.05)
		tween.tween_property(_panel, "position:x", shown_x, 0.05)
	tween.tween_interval(HOLD)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_next)
