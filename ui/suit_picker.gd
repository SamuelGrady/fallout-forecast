class_name SuitPicker
extends VBoxContainer
## Suit colour swatches, skin arrows and a preview of the survivor.
## Desktop renders a slowly turning 3D preview; web uses a lightweight animated
## 2D vector portrait to avoid a multi-second ANGLE shader compile and +71 draw
## call jump when entering the lobby. Emits `changed`; the owner saves/syncs it.

signal changed(color: int, skin: int)

const SurvivorModel := preload("res://player/player_model.gd")

## Test hook so desktop gl_compatibility benchmarks can exercise the web path.
static var force_2d_preview := false

var color := 0
var skin := 0

var _model: SurvivorModel
var _pivot: Node3D
var _viewport: SubViewport
var _preview_2d: _SuitPreview2D
var _swatches: Array[Button] = []
var _taken: Array = []
var _skin_label: Label
var _color_label: Label


func _init(preview_size := Vector2i(260, 250)) -> void:
	add_theme_constant_override("separation", 8)
	color = posmod(Settings.suit_color, Cosmetics.COLORS.size())
	skin = Cosmetics.wrap_skin(Settings.suit_skin)
	if OS.has_feature("web") or force_2d_preview:
		_build_preview_2d(preview_size)
	else:
		_build_preview_3d(preview_size)
	_color_label = _label(16, Color("8FD65A"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(grid)
	for i in Cosmetics.COLORS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(56, 34)
		swatch.focus_mode = Control.FOCUS_ALL
		swatch.pressed.connect(func():
			Sound.play("ui_click")
			_pick(i, skin))
		grid.add_child(swatch)
		_swatches.append(swatch)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_arrow(row, "<", -1)
	_skin_label = Label.new()
	_skin_label.custom_minimum_size.x = 150
	_skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_label.add_theme_font_size_override("font_size", 22)
	row.add_child(_skin_label)
	_arrow(row, ">", 1)
	_refresh()


func _ready() -> void:
	visibility_changed.connect(_sync_preview)
	_sync_preview()


func _sync_preview() -> void:
	var shown := is_visible_in_tree()
	set_process(shown)
	if _model:
		_model.set_process(shown)
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if shown else SubViewport.UPDATE_DISABLED
	if _preview_2d:
		_preview_2d.set_process(shown)


func _process(delta: float) -> void:
	if _pivot:
		_pivot.rotation.y += delta * 0.8


func focus_selected() -> void:
	_swatches[color].grab_focus()


## Show the roster's look and dim colours already assigned to other players.
func set_value(new_color: int, new_skin: int, taken: Array) -> void:
	new_color = posmod(new_color, Cosmetics.COLORS.size())
	new_skin = Cosmetics.wrap_skin(new_skin)
	if color == new_color and skin == new_skin and _taken == taken:
		return
	color = new_color
	skin = new_skin
	_taken = taken
	_refresh()


func _pick(new_color: int, new_skin: int) -> void:
	set_value(new_color, new_skin, _taken)
	changed.emit(color, skin)


class _SwatchMark extends Control:
	var mode := 0  # 0 = none, 1 = check, 2 = taken X

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if mode == 0:
			return
		var w := size.x
		var h := size.y
		var stroke := Color("#0c1422")
		var fg := Color.WHITE
		if mode == 1:
			var pts := PackedVector2Array([
				Vector2(w * 0.24, h * 0.53),
				Vector2(w * 0.43, h * 0.72),
				Vector2(w * 0.77, h * 0.30),
			])
			draw_polyline(pts, stroke, 6.0, true)
			draw_polyline(pts, fg, 3.2, true)
		elif mode == 2:
			var pad := minf(w, h) * 0.28
			draw_line(Vector2(pad, pad), Vector2(w - pad, h - pad), stroke, 5.5, true)
			draw_line(Vector2(w - pad, pad), Vector2(pad, h - pad), stroke, 5.5, true)
			draw_line(Vector2(pad, pad), Vector2(w - pad, h - pad), Color(1.0, 0.7, 0.75), 3.0, true)
			draw_line(Vector2(w - pad, pad), Vector2(pad, h - pad), Color(1.0, 0.7, 0.75), 3.0, true)


## Lightweight animated 2D suit portrait for WebGL (zero 3D SubViewport draws).
class _SuitPreview2D extends Control:
	var suit_color := Color("#e6b83c")
	var skin_id := 0
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_look(new_color: Color, new_skin: int) -> void:
		suit_color = new_color
		skin_id = new_skin
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 2.0 or h <= 2.0:
			return
		# Subtle broadcast monitor grid + pink rim glow.
		draw_rect(Rect2(Vector2.ZERO, size), Color("#09111d"))
		var grid_col := Color(0.25, 0.55, 0.62, 0.14)
		for gx in range(1, 8):
			var x := w * float(gx) / 8.0
			draw_line(Vector2(x, 0.0), Vector2(x, h), grid_col, 1.0)
		for gy in range(1, 8):
			var y := h * float(gy) / 8.0
			draw_line(Vector2(0.0, y), Vector2(w, y), grid_col, 1.0)
		draw_circle(Vector2(w * 0.5, h * 0.87), w * 0.28, Color(0.03, 0.07, 0.12, 0.85))
		draw_arc(Vector2(w * 0.5, h * 0.87), w * 0.28, 0.0, TAU, 24, Color(0.4, 0.87, 0.85, 0.35), 2.0)

		var bob := sin(_t * 2.4) * 3.0
		var cx := w * 0.5
		var s := minf(w, h) / 250.0
		var suit := suit_color
		var shade := suit.darkened(0.26)
		var trim := suit.darkened(0.42)
		var rubber := Color("#232930")
		var metal := Color("#aeb7bf")
		var outline := Color("#0b121c")

		# Backpack / gear silhouette behind torso.
		var torso_top := h * 0.37 + bob
		if skin_id == 0:
			_box(Rect2(cx - 34 * s, torso_top + 6 * s, 68 * s, 54 * s), trim, outline)
		elif skin_id == 2:
			_box(Rect2(cx - 26 * s, torso_top + 4 * s, 52 * s, 56 * s), Color("#d9dde0"), outline)
		elif skin_id == 3:
			_box(Rect2(cx - 32 * s, torso_top + 4 * s, 26 * s, 54 * s), Color("#b8e0d0"), outline)
			_box(Rect2(cx + 6 * s, torso_top + 4 * s, 26 * s, 54 * s), Color("#b8e0d0"), outline)
			draw_line(Vector2(cx - 24 * s, torso_top + 6 * s), Vector2(cx - 24 * s, torso_top - 48 * s), Color("#3d4650"), 3.0 * s)
			draw_circle(Vector2(cx - 24 * s, torso_top - 50 * s), 4.5 * s, Color("#ff3a3a"))
		elif skin_id == 4:
			_box(Rect2(cx - 38 * s, torso_top - 6 * s, 76 * s, 64 * s), Color("#36414b"), outline)
			draw_rect(Rect2(cx - 28 * s, torso_top + 2 * s, 56 * s, 10 * s), Color("#5ef0ff"))

		# Legs & boots.
		var hip_y := torso_top + 64 * s
		for side: float in [-1.0, 1.0]:
			var lx := cx + side * 16 * s - 12 * s
			_box(Rect2(lx, hip_y, 24 * s, 58 * s), suit, outline)
			_box(Rect2(lx - 2 * s, hip_y + 52 * s, 28 * s, 16 * s), rubber, outline)
			draw_rect(Rect2(lx, hip_y + 42 * s, 24 * s, 5 * s), Color("#e9f2c4") if skin_id == 2 else trim)

		# Torso & shoulders.
		_box(Rect2(cx - 30 * s, torso_top, 60 * s, 66 * s), suit, outline)
		draw_rect(Rect2(cx - 28 * s, torso_top + 2 * s, 12 * s, 62 * s), shade)
		# Arms & gloves.
		for side: float in [-1.0, 1.0]:
			var ax := cx + side * 40 * s - 10 * s
			_box(Rect2(ax, torso_top + 4 * s, 20 * s, 52 * s), suit, outline)
			_box(Rect2(ax, torso_top + 52 * s, 20 * s, 14 * s), rubber, outline)
			if skin_id == 3:
				_box(Rect2(ax - 3 * s, torso_top + 2 * s, 26 * s, 10 * s), trim, outline)
			if skin_id == 2:
				draw_rect(Rect2(ax, torso_top + 38 * s, 20 * s, 5 * s), Color("#e9f2c4"))

		# Skin-specific torso details.
		if skin_id == 0:
			draw_rect(Rect2(cx + 12 * s, torso_top + 6 * s, 10 * s, 10 * s), Color("#ffe9a8"))
		elif skin_id == 1:
			draw_line(Vector2(cx - 26 * s, torso_top + 4 * s), Vector2(cx + 26 * s, torso_top + 60 * s), rubber, 7.0 * s)
			_box(Rect2(cx - 36 * s, hip_y - 4 * s, 14 * s, 24 * s), trim, outline)
		elif skin_id == 2:
			draw_rect(Rect2(cx - 30 * s, torso_top + 14 * s, 60 * s, 6 * s), Color("#e9f2c4"))
			draw_rect(Rect2(cx - 30 * s, torso_top + 50 * s, 60 * s, 6 * s), Color("#e9f2c4"))
			draw_rect(Rect2(cx - 3 * s, torso_top + 6 * s, 6 * s, 54 * s), rubber)
		elif skin_id == 3:
			draw_rect(Rect2(cx - 46 * s, torso_top + 34 * s, 10 * s, 14 * s), Color("#7dff6a"))
		elif skin_id == 4:
			draw_rect(Rect2(cx - 16 * s, torso_top + 14 * s, 32 * s, 18 * s), Color("#24303a"))
			draw_rect(Rect2(cx - 12 * s, torso_top + 19 * s, 24 * s, 8 * s), Color("#66dfda"))

		# Carried rifle across front.
		var gun_y := torso_top + 36 * s
		_box(Rect2(cx - 22 * s, gun_y, 68 * s, 10 * s), Color("#303840"), outline)
		draw_rect(Rect2(cx + 38 * s, gun_y + 2 * s, 20 * s, 5 * s), metal)

		# Head & helmet/mask per skin.
		var head_r := Rect2(cx - 22 * s, torso_top - 42 * s, 44 * s, 42 * s)
		_box(head_r, suit.darkened(0.08) if skin_id == 2 else suit, outline)
		match skin_id:
			1:
				_box(Rect2(cx - 18 * s, head_r.position.y + 8 * s, 36 * s, 28 * s), rubber, outline)
				for side: float in [-1.0, 1.0]:
					draw_circle(Vector2(cx + side * 9 * s, head_r.position.y + 18 * s), 7 * s, Color("#6b737c"))
					draw_circle(Vector2(cx + side * 9 * s, head_r.position.y + 18 * s), 5 * s, Color("#ffb347"))
				_box(Rect2(cx - 8 * s, head_r.position.y + 28 * s, 16 * s, 14 * s), Color("#5f6b52"), outline)
			2:
				_box(Rect2(cx - 16 * s, head_r.position.y + 14 * s, 32 * s, 20 * s), Color("#7fd6eb"), outline)
				var helm := suit.lightened(0.08)
				_box(Rect2(cx - 28 * s, head_r.position.y - 2 * s, 56 * s, 10 * s), helm, outline)
				_box(Rect2(cx - 22 * s, head_r.position.y - 14 * s, 44 * s, 14 * s), helm, outline)
				_box(Rect2(cx - 6 * s, head_r.position.y - 12 * s, 12 * s, 12 * s), Color("#d8b23a"), outline)
				draw_rect(Rect2(cx - 22 * s, head_r.position.y - 4 * s, 44 * s, 4 * s), Color("#e9f2c4"))
			3:
				_box(Rect2(cx - 18 * s, head_r.position.y + 10 * s, 36 * s, 24 * s), Color("#8fe8ff"), outline)
				_box(Rect2(cx - 8 * s, head_r.position.y - 6 * s, 16 * s, 8 * s), Color("#2a2f36"), outline)
				draw_rect(Rect2(cx - 5 * s, head_r.position.y - 4 * s, 10 * s, 4 * s), Color("#ffe9a8"))
			4:
				_box(Rect2(cx - 17 * s, head_r.position.y + 11 * s, 34 * s, 18 * s), Color("#5ef0ff"), outline)
				draw_rect(Rect2(cx - 25 * s, head_r.position.y + 12 * s, 5 * s, 16 * s), Color("#2a323b"))
				draw_rect(Rect2(cx + 20 * s, head_r.position.y + 12 * s, 5 * s, 16 * s), Color("#2a323b"))
			_:
				_box(Rect2(cx - 16 * s, head_r.position.y + 9 * s, 32 * s, 17 * s), Color("#6fd2e8"), outline)
				_box(Rect2(cx - 9 * s, head_r.position.y + 28 * s, 18 * s, 11 * s), rubber, outline)
				for side: float in [-1.0, 1.0]:
					_box(Rect2(cx + side * 13 * s - 4 * s, head_r.position.y + 29 * s, 8 * s, 8 * s), Color("#3d4650"), outline)

	func _box(rect: Rect2, fill: Color, stroke: Color) -> void:
		draw_rect(rect, fill)
		draw_rect(rect, stroke, false, 1.6)


func _refresh() -> void:
	for i in _swatches.size():
		var swatch := _swatches[i]
		var taken := i in _taken and i != color
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Cosmetics.COLORS[i].darkened(0.6 if taken else 0.0)
			var selected := i == color
			style.border_color = Color.WHITE if selected else (BroadcastUI.CYAN if state in ["hover", "focus"] else Color("#0c1422"))
			style.set_border_width_all(4 if selected else 2)
			swatch.add_theme_stylebox_override(state, style)
		swatch.disabled = taken
		swatch.text = ""
		var mark := swatch.get_node_or_null("Mark") as _SwatchMark
		if mark == null:
			mark = _SwatchMark.new()
			mark.name = "Mark"
			swatch.add_child(mark)
		mark.mode = 2 if taken else (1 if i == color else 0)
		mark.queue_redraw()
		swatch.tooltip_text = Cosmetics.COLOR_NAMES[i] + (" (IN USE)" if taken else "")
	_skin_label.text = Cosmetics.skin_name(skin)
	_color_label.text = Cosmetics.COLOR_NAMES[color]
	if _model:
		_model.set_look(Cosmetics.color(color), skin)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _preview_2d:
		_preview_2d.set_look(Cosmetics.color(color), skin)


func _arrow(parent: Control, text: String, step: int) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(48, 40)
	BroadcastUI.animate_button(b)
	b.pressed.connect(func():
		Sound.play("ui_click")
		_pick(color, skin + step))
	parent.add_child(b)


func _label(font_size: int, font_color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", font_color)
	add_child(l)
	return l


func _build_preview_2d(preview_size: Vector2i) -> void:
	var frame := PanelContainer.new()
	var style := BroadcastUI.panel(Color("#0a1320"), BroadcastUI.CYAN)
	style.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(frame)
	_preview_2d = _SuitPreview2D.new()
	_preview_2d.custom_minimum_size = preview_size
	_preview_2d.set_look(Cosmetics.color(color), skin)
	frame.add_child(_preview_2d)


func _build_preview_3d(preview_size: Vector2i) -> void:
	var frame := PanelContainer.new()
	var style := BroadcastUI.panel(Color("#0a1320"), BroadcastUI.CYAN)
	style.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(frame)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = preview_size
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = preview_size
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if OS.has_feature("web") else Viewport.MSAA_2X
	container.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6a7f99")
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	_viewport.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.2, 2.2, 1.5)
	rim.light_color = Color("#ff5689")
	rim.light_energy = 1.5
	rim.omni_range = 5.0
	_viewport.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 34
	# The model faces -Z, so the camera sits in front of it on -Z.
	camera.transform = Transform3D(Basis(), Vector3(0, 1.05, -4.2)).looking_at(Vector3(0, 1.0, 0))
	_viewport.add_child(camera)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_pivot.rotation.y = 0.5
	_model = SurvivorModel.new()
	_model.suit_color = Cosmetics.color(color)
	_model.skin = skin
	_pivot.add_child(_model)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
