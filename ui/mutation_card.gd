class_name MutationCard
extends Button
var symbol := GameIcon.new()
var heading := Label.new()
var caption := Label.new()
var entry_id := ""
var canceled := false

func _ready() -> void:
	custom_minimum_size = Vector2(220,270)
	theme = BroadcastUI.theme()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 14
	box.offset_bottom = -14
	add_child(box)
	symbol.custom_minimum_size = Vector2(180,145)
	box.add_child(symbol)
	for label in [heading,caption]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	heading.add_theme_font_size_override("font_size",26)
	caption.add_theme_font_size_override("font_size",19)
	disabled = true

func show_entry(entry: MutationData, landed: bool, badge := "") -> void:
	entry_id = entry.id
	symbol.kind = entry.id
	symbol.color = entry.color.lightened(.15)
	heading.text = entry.display_name.to_upper() if landed else ""
	caption.text = entry.description if landed else ""
	if badge != "":
		heading.text = "[%s]  %s" % [badge, heading.text]
	tooltip_text = entry.description
	queue_redraw()

func cross_out() -> void:
	canceled = true
	modulate.a = .45
	queue_redraw()

func _draw() -> void:
	if canceled:
		draw_line(Vector2(12,12),size-Vector2(12,12),BroadcastUI.PINK,6,true)
		draw_line(Vector2(size.x-12,12),Vector2(12,size.y-12),BroadcastUI.PINK,6,true)
