class_name BroadcastUI
extends RefCounted

const FONT := preload("res://assets/fonts/VT323-Regular.ttf")
const INK := Color("#0c1422")
const PAPER := Color("#e8e9d5")
const CYAN := Color("#66dfda")
const PINK := Color("#ff5689")
const AMBER := Color("#ffbf68")
const ACID := Color("#b8e56d")
const MUTED := Color("#aabac7")
const PANEL := Color("#14232d")
const OVERLAY := Color(0.025, 0.045, 0.075, 0.94)

static func panel(color := INK, accent := CYAN) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = accent
	style.border_width_left = 3
	style.set_content_margin_all(18)
	return style

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 22
	result.set_color("font_color", "Label", PAPER)
	var focus := panel(Color.TRANSPARENT)
	focus.set_border_width_all(2)
	focus.set_content_margin_all(0)
	for type in ["Button", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var color := PANEL
			if state in ["hover", "hover_pressed"]:
				color = Color("#274452")
			elif state == "pressed":
				color = Color("#22404b")
			elif state == "disabled":
				color = INK
			var style := panel(color, MUTED if state == "disabled" else CYAN)
			style.set_content_margin_all(9)
			style.content_margin_left = 16
			style.content_margin_right = 16
			result.set_stylebox(state, type, style)
		result.set_stylebox("focus", type, focus)
		result.set_color("font_color", type, PAPER)
		result.set_color("font_focus_color", type, PAPER)
		result.set_color("font_hover_color", type, CYAN)
		result.set_color("font_disabled_color", type, MUTED.darkened(0.2))
		result.set_font_size("font_size", type, 24)
	result.set_stylebox("normal", "LineEdit", panel(PANEL, MUTED))
	result.set_stylebox("focus", "LineEdit", focus)
	result.set_color("font_color", "LineEdit", PAPER)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_stylebox("focus", "HSlider", focus)
	result.set_stylebox("panel", "PanelContainer", panel())
	for spec in [["slider", PANEL], ["grabber_area", CYAN], ["grabber_area_highlight", PAPER]]:
		var track := panel(spec[1], spec[1])
		track.set_content_margin_all(3)
		result.set_stylebox(spec[0], "HSlider", track)
	return result

static func text(label: Label, font_size: int, color := PAPER, outline := 0) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", outline)


static func back_label(label: Label, accent := CYAN, padding := 6) -> void:
	var style := panel(OVERLAY, accent)
	style.set_content_margin_all(padding)
	style.content_margin_left = padding + 6
	style.content_margin_right = padding + 6
	label.add_theme_stylebox_override("normal", style)

static func bar(control: ProgressBar, color: Color) -> void:
	var background := panel(Color("#142331"), Color("#314655"))
	background.border_width_left = 0
	background.set_content_margin_all(0)
	var fill := background.duplicate()
	fill.bg_color = color
	control.add_theme_stylebox_override("background", background)
	control.add_theme_stylebox_override("fill", fill)

static var _backdrop_shader: Shader

static func backdrop(parent: Control) -> void:
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _backdrop_shader == null:
		_backdrop_shader = Shader.new()
		_backdrop_shader.code = """shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	vec3 base = mix(vec3(.025,.055,.09), vec3(.07,.16,.20), 1.0-uv.y);
	float horizon = exp(-abs(uv.y-.64)*16.0);
	base += vec3(.18,.045,.09)*horizon;
	float lines = step(.97,fract(uv.y*180.0))*.025;
	float grid = step(.985,fract(uv.x*24.0)) + step(.98,fract(uv.y*32.0));
	base += vec3(.06,.16,.17)*grid*smoothstep(.55,1.0,uv.y);
	COLOR = vec4(base-lines,1.0);
}"""
	var material := ShaderMaterial.new()
	material.shader = _backdrop_shader
	background.material = material
	parent.add_child(background)
	parent.move_child(background, 0)

static func animate_button(button: BaseButton) -> void:
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	var active := [null]
	var animate := func():
		if active[0] is Tween and active[0].is_valid():
			active[0].kill()
		var highlighted := not button.disabled and (button.is_hovered() or button.has_focus())
		var pressed := not button.disabled and button.is_pressed() and not button.toggle_mode
		var brightness := 0.90 if pressed else (1.08 if highlighted else 1.0)
		var size_factor := 0.985 if pressed else (1.018 if highlighted else 1.0)
		if Settings.reduced_flash:
			size_factor = 1.0
		var tween := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		active[0] = tween
		tween.set_parallel(true)
		tween.tween_property(button, "modulate", Color(brightness, brightness, brightness), 0.10)
		tween.tween_property(button, "scale", Vector2.ONE * size_factor, 0.10)
	var highlight := func():
		if not button.disabled:
			Sound.ui_focus()
		animate.call()
	button.mouse_entered.connect(highlight)
	button.mouse_exited.connect(animate)
	button.focus_entered.connect(highlight)
	button.focus_exited.connect(animate)
	button.button_down.connect(animate)
	button.button_up.connect(animate)
	button.pressed.connect(func(): Sound.play("ui_click"))


static func focus_sound(control: Control) -> void:
	control.focus_entered.connect(Sound.ui_focus)


static func button_role(button: Button, primary := false, quiet := false) -> void:
	var style := panel(Color("#29545d") if primary else Color("#14232d"))
	style.border_width_left = 4 if primary else 0
	style.set_content_margin_all(9)
	style.content_margin_left = 16
	style.content_margin_right = 16
	if quiet:
		style.bg_color.a = 0.15
		button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override("normal", style)


static func input_hint(action: String) -> String:
	if Settings.using_gamepad:
		return {"interact":"Y", "use_item":"LB", "ready_up":"BACK", "drop_item":"R3", "pause":"START", "cancel":"B", "vote_1":"LEFT", "vote_2":"RIGHT"}.get(action,"A")
	return {"interact":"E", "use_item":"T", "ready_up":"H", "drop_item":"G", "pause":"ESC", "cancel":"ESC", "vote_1":"1", "vote_2":"2"}.get(action,"ENTER")


static func reveal(control: Control) -> void:
	control.modulate.a = 0.0
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "modulate:a", 1.0, .2)
