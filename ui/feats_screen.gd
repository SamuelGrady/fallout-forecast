class_name FeatsScreen
extends Control
## FEATS & ACHIEVEMENTS: every entry in game/feats.gd with its progress on this
## machine. Opened from the title menu, the SUIT screen (suit-unlock filter)
## and the pause menu. Emits `closed` and frees itself on BACK / ESC.

signal closed

enum Filter { ALL, SUITS, EARNED }

const CARD_SIZE := Vector2(404, 92)

var filter := Filter.ALL
var _grid := GridContainer.new()
var _scroll := ScrollContainer.new()
var _tabs: Array[Button] = []
var _count := Label.new()


func _init(start_filter := Filter.ALL) -> void:
	filter = start_filter


func _ready() -> void:
	theme = BroadcastUI.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := BroadcastUI.panel(BroadcastUI.OVERLAY, BroadcastUI.CYAN)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(840, 640)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var title := Label.new()
	title.text = "FEATS & ACHIEVEMENTS"
	BroadcastUI.text(title, 34, BroadcastUI.CYAN)
	header.add_child(title)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	BroadcastUI.text(_count, 22, BroadcastUI.ACID)
	header.add_child(_count)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	for spec: Array in [[Filter.ALL, "ALL"], [Filter.SUITS, "SUIT UNLOCKS"], [Filter.EARNED, "EARNED"]]:
		var tab := Button.new()
		tab.text = spec[1]
		tab.custom_minimum_size = Vector2(150, 38)
		BroadcastUI.animate_button(tab)
		var which: int = spec[0]
		tab.pressed.connect(func(): _set_filter(which))
		tabs.add_child(tab)
		_tabs.append(tab)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(120, 38)
	BroadcastUI.button_role(back, false, true)
	BroadcastUI.animate_button(back)
	back.pressed.connect(close)
	tabs.add_child(back)

	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)

	var hint := Label.new()
	hint.text = "PROGRESS IS SAVED ON THIS MACHINE.  THE HOST CONFIRMS EVERY FEAT IN ONLINE RUNS."
	BroadcastUI.text(hint, 17, BroadcastUI.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_set_filter(filter)
	_tabs[filter].grab_focus()
	BroadcastUI.reveal(panel)


func close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Sound.play("ui_click")
		close()


func _set_filter(which: int) -> void:
	filter = which as Filter
	for i in _tabs.size():
		BroadcastUI.button_role(_tabs[i], i == filter, i != filter)
	for child in _grid.get_children():
		child.queue_free()
	var shown := 0
	for feat in Feats.LIST:
		var id := str(feat.id)
		if filter == Filter.SUITS and not Feats.is_suit_unlock(id):
			continue
		if filter == Filter.EARNED and not Feats.is_done(id):
			continue
		_grid.add_child(_card(feat))
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "NOTHING ON THIS TAPE YET."
		BroadcastUI.text(empty, 22, BroadcastUI.MUTED)
		_grid.add_child(empty)
	_count.text = "%d / %d EARNED" % [Feats.done_count(), Feats.LIST.size()]
	_scroll.scroll_vertical = 0


func _card(feat: Dictionary) -> Control:
	var id := str(feat.id)
	var done := Feats.is_done(id)
	var secret := bool(feat.get("hidden", false)) and not done
	var reward := Feats.reward_name(id)
	var accent := BroadcastUI.ACID if done else (BroadcastUI.AMBER if reward != "" else BroadcastUI.MUTED.darkened(0.3))
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal := BroadcastUI.panel(Color("#13202b") if done else Color("#0e1822"), accent)
	normal.set_content_margin_all(8)
	normal.content_margin_left = 10
	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = BroadcastUI.CYAN
	focused.set_border_width_all(1)
	focused.border_width_left = 3
	card.add_theme_stylebox_override("panel", normal)
	card.focus_entered.connect(func():
		card.add_theme_stylebox_override("panel", focused)
		Sound.ui_focus())
	card.focus_exited.connect(func(): card.add_theme_stylebox_override("panel", normal))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := _FeatIcon.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.done = done
	icon.secret = secret
	icon.swatch = Cosmetics.color(int(feat.color)) if feat.has("color") else Color.TRANSPARENT
	icon.skin = feat.has("skin")
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_label := Label.new()
	name_label.text = "???" if secret else str(feat.name)
	BroadcastUI.text(name_label, 23, BroadcastUI.PAPER if done else Color("#c9d2cf"))
	col.add_child(name_label)
	var desc := Label.new()
	desc.text = "HIDDEN BROADCAST. KEEP THE TAPE ROLLING." if secret else str(feat.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = CARD_SIZE.x - 80
	BroadcastUI.text(desc, 17, BroadcastUI.MUTED)
	col.add_child(desc)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	if reward != "":
		var tag := Label.new()
		tag.text = ("UNLOCKED  " if done else "UNLOCKS  ") + reward
		BroadcastUI.text(tag, 16, BroadcastUI.ACID if done else BroadcastUI.AMBER)
		foot.add_child(tag)
	var goal := Feats.goal(id)
	if goal > 1 and not secret:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110, 9)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = goal
		bar.value = Feats.progress(id)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		BroadcastUI.bar(bar, BroadcastUI.ACID if done else BroadcastUI.CYAN)
		foot.add_child(bar)
		var count := Label.new()
		count.text = "%d/%d" % [Feats.progress(id), goal]
		BroadcastUI.text(count, 16, BroadcastUI.PAPER)
		foot.add_child(count)
	elif done and reward == "":
		var tag := Label.new()
		tag.text = "EARNED"
		BroadcastUI.text(tag, 16, BroadcastUI.ACID)
		foot.add_child(tag)
	return card


## Check, padlock, or the colour/skin the feat unlocks.
class _FeatIcon extends Control:
	var done := false
	var secret := false
	var swatch := Color.TRANSPARENT
	var skin := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var ink := Color("#0c1422")
		if swatch.a > 0.0:
			draw_rect(r, swatch if done else swatch.darkened(0.6))
		elif skin:
			# Skin rewards: an amber plate with hazard stripes along the bottom.
			draw_rect(r, Color("#4a3a1c") if done else Color("#2a2214"))
			for k in 4:
				var x := size.x * (0.05 + 0.25 * k)
				draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + size.x * 0.12, size.y * 0.8),
					Vector2(x + size.x * 0.22, size.y * 0.8), Vector2(x + size.x * 0.1, size.y)]), Color(BroadcastUI.AMBER, 0.55))
		else:
			draw_rect(r, Color("#1d3844") if done else Color("#121e27"))
		draw_rect(r, BroadcastUI.ACID if done else BroadcastUI.MUTED.darkened(0.4), false, 1.5)
		if done:
			var pts := PackedVector2Array([size * Vector2(0.24, 0.53), size * Vector2(0.43, 0.72), size * Vector2(0.77, 0.30)])
			draw_polyline(pts, ink, 7.0, true)
			draw_polyline(pts, Color.WHITE, 3.5, true)
		elif secret:
			draw_string(BroadcastUI.FONT, Vector2(0, size.y * 0.72), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, BroadcastUI.MUTED)
		else:
			SuitPicker.draw_padlock(self, size * 0.5 + Vector2(0, size.y * 0.04), size.y * 0.5, Color("#c9d2cf"))
