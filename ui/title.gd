extends Control
## Title screen: a VHS tape slides into the deck, the screen snows, then the
## menu: PLAY, SETTINGS, QUIT. (Host and Join will join them when networking
## goes in.)

const RUN_SCENE := "res://main.tscn"
const LOBBY_SCENE := "res://ui/lobby.tscn"
const BROWSER_SCENE := "res://ui/server_browser.tscn"

var _menu := VBoxContainer.new()
var _settings := VBoxContainer.new()
var _tape := Panel.new()
var _snow := ColorRect.new()
var _logo := Label.new()
var _sub := Label.new()
var _t := 0.0
var _menu_ready := false
var _vhs: CanvasLayer


func _ready() -> void:
	theme = BroadcastUI.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("100A1E")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_street_backdrop()
	bg.queue_free()

	# The tape.
	_tape.size = Vector2(460, 260)
	var tape_style := StyleBoxFlat.new()
	tape_style.bg_color = Color("1A1A20")
	tape_style.set_corner_radius_all(12)
	tape_style.border_color = Color("33333D")
	tape_style.set_border_width_all(6)
	_tape.add_theme_stylebox_override("panel", tape_style)
	var sticker := Label.new()
	sticker.text = "FALLOUT FORECAST\nSP  T-120  OCT 31 1987"
	sticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sticker.add_theme_font_size_override("font_size", 22)
	sticker.add_theme_color_override("font_color", Color("1F2A55"))
	var sticker_bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("F2E3C6")
	sticker_bg.add_theme_stylebox_override("panel", sb)
	sticker_bg.position = Vector2(40, 40)
	sticker_bg.size = Vector2(380, 90)
	sticker.size = sticker_bg.size
	sticker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sticker_bg.add_child(sticker)
	_tape.add_child(sticker_bg)
	add_child(_tape)

	_snow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var snow_mat := ShaderMaterial.new()
	snow_mat.shader = _snow_shader()
	_snow.material = snow_mat
	_snow.modulate.a = 0.0
	add_child(_snow)

	_logo.text = "FALLOUT\nFORECAST"
	_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_logo.offset_top = 82
	_logo.add_theme_font_size_override("font_size", 80)
	_logo.add_theme_color_override("font_color", Color("FF3EA5"))
	_logo.add_theme_color_override("font_outline_color", Color("2EE6E6"))
	_logo.add_theme_constant_override("outline_size", 0)
	_logo.modulate.a = 0.0
	add_child(_logo)
	_sub.text = "PHD"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub.offset_top = 286
	_sub.add_theme_font_size_override("font_size", 20)
	_sub.add_theme_color_override("font_color", Color("8FD65A"))
	_sub.modulate.a = 0.0
	add_child(_sub)

	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.offset_left = -190
	_menu.offset_right = 190
	_menu.anchor_top = 0.0
	_menu.anchor_bottom = 0.0
	_menu.grow_vertical = Control.GROW_DIRECTION_END
	_menu.offset_top = 340
	_menu.offset_bottom = 340
	_menu.add_theme_constant_override("separation", 10)
	_menu.modulate.a = 0.0
	add_child(_menu)
	_button(_menu, "PLAY SOLO", _on_play)
	_button(_menu, "HOST GAME", _on_host)
	_button(_menu, "JOIN GAME", _on_join)
	_button(_menu, "SETTINGS", _on_settings)
	_button(_menu, "QUIT", get_tree().quit)

	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.offset_left = -220
	_settings.offset_right = 220
	_settings.anchor_top = 0.0
	_settings.anchor_bottom = 0.0
	_settings.grow_vertical = Control.GROW_DIRECTION_END
	_settings.offset_top = 350
	_settings.offset_bottom = 350
	_settings.add_theme_constant_override("separation", 10)
	_settings.visible = false
	add_child(_settings)
	_slider(_settings, "MOUSE SENSITIVITY", 0.0005, 0.006, Settings.mouse_sensitivity, func(v): Settings.mouse_sensitivity = v)
	_slider(_settings, "VOLUME", 0.0, 1.0, Settings.master_volume, func(v): Settings.master_volume = v; Settings.apply())
	var retro := CheckButton.new()
	retro.text = "RETRO VHS EFFECT"
	retro.button_pressed = Settings.retro_enabled
	retro.toggled.connect(Settings.set_retro)
	_style_button(retro)
	_settings.add_child(retro)
	var calm := CheckButton.new()
	calm.text = "REDUCED FLASHING"
	calm.button_pressed = Settings.reduced_flash
	calm.toggled.connect(Settings.set_reduced_flash)
	_style_button(calm)
	_settings.add_child(calm)
	_button(_settings, "BACK", _on_back)
	for button in _menu.get_children():
		button.disabled = true
	BroadcastUI.button_role(_menu.get_child(0), true)
	BroadcastUI.button_role(_menu.get_child(2), false, true)
	_vhs = (load("res://retro/retro_screen.tscn") as PackedScene).instantiate()
	_vhs.interface_only = true
	add_child(_vhs)


func _process(delta: float) -> void:
	if _t < 1.4 and _t + delta >= 1.4:
		Sound.play("vhs_glitch")
	_t += delta
	if not _menu_ready and _t >= 2.5:
		_menu_ready = true
		for button in _menu.get_children():
			button.disabled = false
		_menu.get_child(0).grab_focus()
	var view := get_viewport_rect().size
	# 0-1.4 s: tape slides up into the deck. 1.4-2.0 s: snow. Then the menu.
	var slide := clampf(_t / 1.4, 0.0, 1.0)
	_tape.position = Vector2((view.x - _tape.size.x) * 0.5, lerpf(view.y + 20.0, view.y * 0.5 - 100.0, ease(slide, 0.4)))
	_tape.modulate.a = 1.0 - clampf((_t - 1.4) / 0.3, 0.0, 1.0)
	_tape.visible = _tape.modulate.a > 0.01
	_snow.modulate.a = clampf(1.0 - absf(_t - 1.7) / 0.4, 0.0, 1.0) * 0.9
	var menu_a := clampf((_t - 2.0) / 0.5, 0.0, 1.0)
	_logo.modulate.a = menu_a
	_sub.modulate.a = menu_a
	if not _settings.visible:
		_menu.modulate.a = menu_a
	_logo.position.x += sin(_t * 23.0) * 0.6 * menu_a


func _input(event: InputEvent) -> void:
	if not _menu_ready and event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		_t = 2.5
		get_viewport().set_input_as_handled()
	elif _settings.visible and event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()



func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	BroadcastUI.animate_button(b)
	b.custom_minimum_size = Vector2(320, 54)
	b.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	_style_button(b)
	parent.add_child(b)
	return b


func _style_button(b: Control) -> void:
	b.theme = BroadcastUI.theme()
	b.add_theme_font_size_override("font_size", 26)


func _slider(parent: Control, label: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color("F2E3C6"))
	l.add_theme_font_size_override("font_size", 18)
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.value = value
	s.custom_minimum_size = Vector2(320, 24)
	s.value_changed.connect(on_change)
	parent.add_child(s)


func _on_play() -> void:
	Settings.save()
	Net.leave()
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_host() -> void:
	Settings.save()
	var err := Net.host()
	if err != OK:
		_show_error("Could not open port %d (error %d). Another copy running?" % [Net.PORT, err])
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_join() -> void:
	Settings.save()
	Net.leave()
	get_tree().change_scene_to_file(BROWSER_SCENE)


## Replaces the menu with a one-line error, e.g. a busy port, plus a way back.
func _show_error(text: String) -> void:
	Sound.play("ui_click")
	_menu.visible = false
	var row := VBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.offset_left = -320
	row.offset_right = 320
	row.offset_top = 40
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 520
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("FF3EA5"))
	row.add_child(label)
	_button(row, "BACK", func():
		row.queue_free()
		_menu.visible = true)
	BroadcastUI.reveal(row)


func _on_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	BroadcastUI.reveal(_settings)
	_settings.get_child(1).grab_focus()


func _on_back() -> void:
	Settings.save()
	_settings.visible = false
	_menu.visible = true
	_menu.get_child(1).grab_focus()


func _snow_shader() -> Shader:
	var s := Shader.new()
	s.code = """shader_type canvas_item;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 cell = floor(SCREEN_UV * vec2(320.0, 240.0));
	float n = h(cell + floor(TIME * 30.0));
	COLOR = vec4(vec3(n), 1.0);
}"""
	return s


func _build_street_backdrop() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	container.add_child(viewport)
	var level := (load("res://levels/pinecrest/level_pinecrest.tscn") as PackedScene).instantiate()
	viewport.add_child(level)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(-28,2.2,-2)
	camera.look_at(Vector3(-5,1.5,1))
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02,0.04,0.08,0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var insignia := GameIcon.new()
	insignia.kind = "department"
	insignia.color = BroadcastUI.CYAN
	insignia.position = Vector2(30,30)
	insignia.size = Vector2(48,48)
	add_child(insignia)
	# A quiet streak texture animates the wet street without changing gameplay weather.
	var rain := ColorRect.new()
	rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
void fragment(){ vec2 p=UV*vec2(170.0,35.0); p.y+=TIME*9.0; float streak=step(.97,fract(p.x+p.y*.08))*step(.72,fract(p.y)); COLOR=vec4(.55,.8,.86,streak*.16); }"""
	material.shader = shader
	rain.material = material
	add_child(rain)
