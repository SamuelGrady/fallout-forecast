class_name SuitPicker
extends VBoxContainer
## Suit colour swatches, skin arrows and a slowly turning 3D preview of the
## survivor. Used by the lobby and the title screen's SUIT panel. Emits
## `changed`; the owner decides what to do with the pick (save it, send it).

signal changed(color: int, skin: int)

const SurvivorModel := preload("res://player/player_model.gd")

var color := 0
var skin := 0

var _model: SurvivorModel
var _pivot: Node3D
var _viewport: SubViewport
var _swatches: Array[Button] = []
var _taken: Array = []
var _skin_label: Label
var _color_label: Label


func _init(preview_size := Vector2i(260, 250)) -> void:
	add_theme_constant_override("separation", 8)
	color = posmod(Settings.suit_color, Cosmetics.COLORS.size())
	skin = Cosmetics.wrap_skin(Settings.suit_skin)
	_build_preview(preview_size)
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
	_model.set_process(shown)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if shown else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
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
		swatch.text = "×" if taken else ("✓" if i == color else "")
		swatch.tooltip_text = Cosmetics.COLOR_NAMES[i] + (" (IN USE)" if taken else "")
	_skin_label.text = Cosmetics.skin_name(skin)
	_color_label.text = Cosmetics.COLOR_NAMES[color]
	if _model:
		_model.set_look(Cosmetics.color(color), skin)


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


func _build_preview(preview_size: Vector2i) -> void:
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
