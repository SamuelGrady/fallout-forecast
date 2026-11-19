extends CanvasLayer
## RetroScreen (design doc "Art and audio direction"). Local to each client,
## never networked.
## - Post effect on the 3D view (retro_screen.gdshader): 240-line pixelation,
##   colour bleed, ordered dither, scanlines, vignette.
## - PS1 materials: every opaque StandardMaterial3D in the scene, including
##   ones spawned later, is swapped for ps1.gdshader (vertex snapping).
## - VHS overlay: blinking REC, and a timestamp counting from OCT 31 1987 11:47 PM.
## - Tracking glitch on lightning strikes and while the local player is downed.
## F8 toggles the whole effect.

const PS1 := preload("res://retro/ps1.gdshader")
const MONTH := "OCT"
const START_SECONDS := 23 * 3600 + 47 * 60  # 11:47 PM

@export var enabled := true
@export var vertex_snap := 120.0
@export var lightning_glitch := 1.0
@export var downed_glitch := 0.45

var _glitch := 0.0
var _clock := 0.0
var _converted := {}  # original material -> ShaderMaterial
var _ps1_materials: Array[ShaderMaterial] = []

@onready var screen: ColorRect = $Screen
@onready var rec: Label = %Rec
@onready var stamp: Label = %Stamp


func _ready() -> void:
	enabled = Settings.retro_enabled
	WeatherManager.lightning_struck.connect(func(_p, _s): _glitch = maxf(_glitch, lightning_glitch))
	get_tree().node_added.connect(_on_node_added)
	_convert_tree.call_deferred(get_tree().root)
	_apply_enabled()
	rec.add_theme_font_override("font", BroadcastUI.FONT)
	stamp.add_theme_font_override("font", BroadcastUI.FONT)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		enabled = not enabled
		_apply_enabled()


func _process(delta: float) -> void:
	_clock += delta
	var target := 0.0
	var player := get_tree().get_first_node_in_group("local_player")
	if player and player.get("state") == "downed":
		target = downed_glitch
	_glitch = maxf(move_toward(_glitch, 0.0, delta * 1.6), target)
	(screen.material as ShaderMaterial).set_shader_parameter("glitch", _glitch)

	rec.text = ("● REC" if fmod(_clock, 1.0) < 0.6 else "   REC") + "  ▶"
	var s := START_SECONDS + int(_clock)
	var day := 31 + s / 86400
	s %= 86400
	var hour := s / 3600
	var ampm := "PM" if hour >= 12 else "AM"
	var h12 := hour % 12
	if h12 == 0:
		h12 = 12
	var month := MONTH if day <= 31 else "NOV"
	if day > 31:
		day -= 31
	stamp.text = "%s %02d 1987\n%2d:%02d:%02d %s" % [month, day, h12, (s / 60) % 60, s % 60, ampm]


func _apply_enabled() -> void:
	screen.visible = enabled
	rec.visible = enabled
	stamp.visible = enabled
	for m in _ps1_materials:
		m.set_shader_parameter("snap", vertex_snap if enabled else 0.0)


func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D or node is CSGShape3D:
		_convert_node.call_deferred(node)


func _convert_tree(node: Node) -> void:
	for n in node.find_children("*", "GeometryInstance3D", true, false):
		_convert_node(n)


func _convert_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override:
			var o := _convert(mi.material_override)
			if o:
				mi.material_override = o
			return
		if mi.mesh == null:
			return
		for i in mi.mesh.get_surface_count():
			var c := _convert(mi.get_active_material(i))
			if c:
				mi.set_surface_override_material(i, c)
	elif node is CSGPrimitive3D:
		var csg := node as CSGPrimitive3D
		var c := _convert(csg.material)
		if c:
			csg.material = c


func _convert(material: Material) -> ShaderMaterial:
	if material == null or not (material is StandardMaterial3D):
		return null
	if _converted.has(material):
		return _converted[material]
	var m := material as StandardMaterial3D
	# Leave anything special alone: glass, puddles, glows, unshaded effects.
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED \
			or m.emission_enabled or m.grow or m.no_depth_test:
		return null
	var s := ShaderMaterial.new()
	s.shader = PS1
	s.set_shader_parameter("albedo", m.albedo_color)
	if m.albedo_texture:
		s.set_shader_parameter("albedo_texture", m.albedo_texture)
		s.set_shader_parameter("use_texture", true)
	s.set_shader_parameter("triplanar", m.uv1_triplanar)
	s.set_shader_parameter("uv_scale", m.uv1_scale)
	s.set_shader_parameter("uv_offset", m.uv1_offset)
	s.set_shader_parameter("snap", vertex_snap if enabled else 0.0)
	_converted[material] = s
	_ps1_materials.append(s)
	return s
