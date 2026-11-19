class_name BroadcastUI
extends RefCounted

const FONT := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const INK := Color("#0c1422")
const PAPER := Color("#e8e9d5")
const CYAN := Color("#66dfda")
const PINK := Color("#ff5689")

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
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := panel(Color("#182837") if state == "normal" else Color("#274452"))
		style.border_width_left = 4
		result.set_stylebox(state, "Button", style)
	result.set_color("font_color", "Button", PAPER)
	result.set_color("font_hover_color", "Button", CYAN)
	result.set_font_size("font_size", "Button", 26)
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_stylebox("slider", "HSlider", panel(Color("#263747"), Color("#263747")))
	result.set_stylebox("grabber_area", "HSlider", panel(CYAN, CYAN))
	return result

static func apply(node: Node) -> void:
	if node is Control:
		node.theme = theme()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE if node is Label else node.mouse_filter
	for child in node.get_children():
		apply(child)
	if node is Label:
		node.add_theme_constant_override("outline_size", 0)
		node.add_theme_font_override("font", FONT)
	if node is ProgressBar:
		bar(node, CYAN)

static func bar(control: ProgressBar, color: Color) -> void:
	var background := panel(Color("#142331"), Color("#314655"))
	background.border_width_left = 0
	background.set_content_margin_all(0)
	var fill := background.duplicate()
	fill.bg_color = color
	control.add_theme_stylebox_override("background", background)
	control.add_theme_stylebox_override("fill", fill)

static func backdrop(parent: Control) -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
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
	material.shader = shader
	background.material = material
	parent.add_child(background)
	parent.move_child(background, 0)

static func animate_button(button: Button) -> void:
	button.pivot_offset = button.size * 0.5
	var active := [null]
	var animate := func(amount: float):
		if active[0] is Tween and active[0].is_valid():
			active[0].kill()
		var tween := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		active[0] = tween
		tween.tween_property(button, "scale", Vector2.ONE * amount, .12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	button.mouse_entered.connect(func(): animate.call(1.025))
	button.mouse_exited.connect(func(): animate.call(1.0))
	button.focus_entered.connect(func(): animate.call(1.025))
	button.focus_exited.connect(func(): animate.call(1.0))
	button.button_down.connect(func(): animate.call(.97))
	button.button_up.connect(func(): animate.call(1.0))

static func reveal(control: Control) -> void:
	control.modulate.a = 0.0
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "modulate:a", 1.0, .2)
