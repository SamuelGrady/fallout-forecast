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
## In-game type scale (multiplied by Settings.hud_scale where it applies).
const T_META := 16
const T_BODY := 22
const T_NUM := 34
const T_HEAD := 56

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
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = CYAN
	focus.set_border_width_all(2)
	focus.set_content_margin_all(0)
	for type: String in ["Button", "CheckButton"]:
		var is_check := type == "CheckButton"
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var color := PANEL
			var accent := CYAN if is_check else MUTED.darkened(0.2)
			if state in ["hover", "hover_pressed"]:
				color = Color("#24424f")
				accent = CYAN
			elif state == "pressed":
				color = Color("#1d3844")
				accent = CYAN
			elif state == "disabled":
				color = INK
				accent = MUTED.darkened(0.45)
			var style := _button_box(color, accent, 3 if is_check else 2, 5 if is_check else 7, 12 if is_check else 14)
			result.set_stylebox(state, type, style)
		result.set_stylebox("focus", type, focus)
		result.set_color("font_color", type, PAPER)
		result.set_color("font_focus_color", type, PAPER)
		result.set_color("font_hover_color", type, CYAN)
		result.set_color("font_pressed_color", type, CYAN)
		result.set_color("font_hover_pressed_color", type, CYAN)
		result.set_color("font_disabled_color", type, MUTED.darkened(0.25))
		result.set_font_size("font_size", type, 22 if is_check else 24)
	var edit_normal := _edit_box(Color("#0e1a26"), MUTED.darkened(0.15), 1, 3)
	var edit_focus := _edit_box(Color("#132331"), CYAN, 2, 3)
	var edit_readonly := _edit_box(INK, MUTED.darkened(0.4), 1, 3)
	result.set_stylebox("normal", "LineEdit", edit_normal)
	result.set_stylebox("focus", "LineEdit", edit_focus)
	result.set_stylebox("read_only", "LineEdit", edit_readonly)
	result.set_font_size("font_size", "LineEdit", 22)
	result.set_color("font_color", "LineEdit", PAPER)
	result.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.15))
	result.set_color("caret_color", "LineEdit", CYAN)
	result.set_font("normal_font", "RichTextLabel", FONT)
	result.set_font("bold_font", "RichTextLabel", FONT)
	result.set_font_size("normal_font_size", "RichTextLabel", 20)
	result.set_color("default_color", "RichTextLabel", PAPER)
	result.set_stylebox("focus", "HSlider", focus)
	var scroll_track := StyleBoxFlat.new()
	scroll_track.bg_color = Color(PANEL, 0.6)
	scroll_track.content_margin_left = 3
	scroll_track.content_margin_right = 3
	result.set_stylebox("scroll", "VScrollBar", scroll_track)
	result.set_stylebox("scroll_focus", "VScrollBar", scroll_track)
	for spec: Array in [["grabber", MUTED.darkened(0.35)], ["grabber_highlight", CYAN], ["grabber_pressed", PAPER]]:
		var grab := StyleBoxFlat.new()
		grab.bg_color = spec[1]
		grab.content_margin_left = 3
		grab.content_margin_right = 3
		result.set_stylebox(spec[0], "VScrollBar", grab)
	result.set_stylebox("panel", "PanelContainer", panel())
	for spec in [["slider", PANEL], ["grabber_area", CYAN], ["grabber_area_highlight", PAPER]]:
		var track := panel(spec[1], spec[1])
		track.set_content_margin_all(3)
		result.set_stylebox(spec[0], "HSlider", track)
	return result


static func _button_box(bg: Color, accent: Color, left_width: int, pad_y: int, pad_x: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = accent
	style.border_width_left = left_width
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	return style


static func _edit_box(bg: Color, border: Color, border_all: int, border_left: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_all)
	style.border_width_left = border_left
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func text(label: Label, font_size: int, color := PAPER, outline := 0) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", outline)


## HUD text: outlined, no backing box.
static func hud_text(label: Label, font_size: int, color := PAPER) -> void:
	text(label, font_size, color, 3)
	label.add_theme_color_override("font_outline_color", Color(INK, 0.9))


## Thin HUD bar: dim track, solid fill, no borders.
static func thin_bar(control: ProgressBar, color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(INK, 0.55)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	control.add_theme_stylebox_override("background", background)
	control.add_theme_stylebox_override("fill", fill)
	control.show_percentage = false


## Draw a small key cap ("E", "LMB") at `at` (top-left). Returns its width.
static func draw_key_cap(canvas: CanvasItem, at: Vector2, glyph: String, font_size := T_META, color := PAPER) -> float:
	var width := maxf(FONT.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 10.0, font_size + 2.0)
	var rect := Rect2(at, Vector2(width, font_size + 2.0))
	canvas.draw_rect(rect, Color(INK, 0.7))
	canvas.draw_rect(rect, color, false, 1.0)
	canvas.draw_string(FONT, at + Vector2(0, font_size - 1.0), glyph, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)
	return width


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
	var pad_y := 5 if quiet else 7
	var pad_x := 11 if quiet else 14
	var left_w := 4 if primary else (2 if quiet else 3)
	var normal_bg := Color("#244d57") if primary else (Color(PANEL, 0.55) if quiet else PANEL)
	var hover_bg := Color("#2f626e") if primary else Color("#24424f", 0.95 if quiet else 1.0)
	var press_bg := Color("#1c3e47") if primary else Color("#1d3844")
	var normal_border := CYAN if primary else MUTED.darkened(0.35 if quiet else 0.2)
	button.add_theme_stylebox_override("normal", _button_box(normal_bg, normal_border, left_w, pad_y, pad_x))
	button.add_theme_stylebox_override("hover", _button_box(hover_bg, CYAN, left_w, pad_y, pad_x))
	button.add_theme_stylebox_override("pressed", _button_box(press_bg, CYAN, left_w, pad_y, pad_x))
	button.add_theme_stylebox_override("disabled", _button_box(Color(INK, 0.65 if quiet else 1.0), MUTED.darkened(0.45), left_w, pad_y, pad_x))
	button.add_theme_font_size_override("font_size", 20 if quiet else 24)


static func button_accent(button: Button, accent: Color, quiet := false) -> void:
	var pad_y := 5 if quiet else 7
	var pad_x := 11 if quiet else 14
	var base := accent.darkened(0.76)
	button.add_theme_stylebox_override("normal", _button_box(base, accent, 3, pad_y, pad_x))
	button.add_theme_stylebox_override("hover", _button_box(accent.darkened(0.66), accent, 3, pad_y, pad_x))
	button.add_theme_stylebox_override("pressed", _button_box(accent.darkened(0.82), accent, 3, pad_y, pad_x))
	button.add_theme_stylebox_override("disabled", _button_box(INK, MUTED.darkened(0.45), 3, pad_y, pad_x))
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_font_size_override("font_size", 20 if quiet else 24)


static func input_hint(action: String) -> String:
	if Settings.using_gamepad:
		return {"interact":"Y", "use_item":"LB", "ready_up":"BACK", "drop_item":"R3", "fire":"RT", "reload":"X", "ping":"D-PAD", "pause":"START", "cancel":"B", "vote_1":"LEFT", "vote_2":"RIGHT", "throw_grenade":"D-L", "throw_dome":"D-R"}.get(action,"A")
	return {"interact":"E", "use_item":"T", "ready_up":"H", "drop_item":"G", "fire":"LMB", "reload":"R", "ping":"Z", "pause":"ESC", "cancel":"ESC", "vote_1":"1", "vote_2":"2", "throw_grenade":"Q", "throw_dome":"F"}.get(action,"ENTER")


static func reveal(control: Control) -> void:
	control.modulate.a = 0.0
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "modulate:a", 1.0, .2)
