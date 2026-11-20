extends Control
## Cold open on the tape loader, then switch to the VCR's playback menu.

const RUN_SCENE := "res://main.tscn"
const LOBBY_SCENE := "res://ui/lobby.tscn"
const BROWSER_SCENE := "res://ui/server_browser.tscn"
const RETRO_SCREEN := preload("res://retro/retro_screen.tscn")
const INSERT := preload("res://assets/audio/sfx/vcr_insert.wav")
const WHIRR := preload("res://assets/audio/sfx/vcr_whirr.wav")
const EJECT := preload("res://assets/audio/sfx/vcr_eject.wav")
const FAST_FORWARD := preload("res://assets/audio/sfx/vcr_ff.wav")
const TRACKING := preload("res://assets/audio/sfx/vhs_glitch.ogg")
const ENGAGE := 0.22
const THREAD := 0.36
const TRACK := 0.72
const PLAY := 0.96
const OSD_COLOR := Color("CCEADB")

var _playback := Control.new()
var _menu := VBoxContainer.new()
var _settings := VBoxContainer.new()
var _suit := VBoxContainer.new()
var _intro := Control.new()
var _deck := VcrDeck.new()
var _snow := ColorRect.new()
var _snow_material := ShaderMaterial.new()
var _transport := AudioStreamPlayer.new()
var _tracking := AudioStreamPlayer.new()
var _backdrop_viewport: SubViewport
var _counter: Label
var _settings_button: Button
var _suit_button: Button
var _suit_picker: SuitPicker
var _host_button: Button
var _t := 0.0
var _menu_ready := false
var _ejecting := false
var _seconds := 0


func _ready() -> void:
	theme = BroadcastUI.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_full_rect(_playback, self)
	_build_street_backdrop()
	_build_playback_menu()
	_build_tape_loader()

	_transport.bus = &"UI"
	_transport.volume_db = -11.0
	if OS.has_feature("web"):
		_transport.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_transport)
	_tracking.bus = &"UI"
	_tracking.volume_db = -19.0
	if OS.has_feature("web"):
		_tracking.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_tracking)

	var retro := RETRO_SCREEN.instantiate() as CanvasLayer
	retro.interface_only = true
	retro.get_node("VHS").hide()
	add_child(retro)


func _build_tape_loader() -> void:
	_add_full_rect(_intro, self)
	var wall := ColorRect.new()
	var wall_material := ShaderMaterial.new()
	var wall_shader := Shader.new()
	wall_shader.code = """shader_type canvas_item;

void fragment() {
	vec2 p = UV - vec2(.5, .54);
	float light = max(0.0, 1.0 - length(p * vec2(1.6, 1.3)));
	float shelf = smoothstep(.894, .909, UV.y);
	vec3 wall = mix(vec3(.022, .021, .033), vec3(.107, .091, .118), light * light);
	COLOR = vec4(wall * (1.0 - shelf * .35), 1.0);
}"""
	wall_material.shader = wall_shader
	wall.material = wall_material
	_add_full_rect(wall, _intro)
	_intro.add_child(_deck)
	_deck.tape_depth = -84.0
	var skip := _label(_intro, "PRESS ANY BUTTON TO SKIP", Vector2(0, 674), 16, Color("8C8B9B"), 960.0)
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_snow_material.shader = _snow_shader()
	_snow_material.set_shader_parameter("steady", Settings.reduced_flash)
	_snow.material = _snow_material
	_snow.hide()
	_add_full_rect(_snow, self)


func _build_playback_menu() -> void:
	_label(_playback, "PLAY", Vector2(78, 34), 22, OSD_COLOR)
	_label(_playback, ">" if OS.has_feature("web") else "▶", Vector2(51, 36), 17, OSD_COLOR)
	_counter = _label(_playback, "SP   00:00:00", Vector2(702, 34), 22, OSD_COLOR, 206.0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(_playback, "OCT 31 1987", Vector2(52, 658), 19, OSD_COLOR)

	var first := _label(_playback, "FALLOUT", Vector2(96, 91), 99, Color("E6EEE2"))
	var second := _label(_playback, "FORECAST", Vector2(96, 174), 99, Color("A9E9D9"))
	for line in [first, second]:
		line.add_theme_constant_override("shadow_offset_x", 3)
		line.add_theme_constant_override("shadow_offset_y", 3)
		line.add_theme_color_override("font_shadow_color", Color("267E75"))

	_menu.position = Vector2(104, 325)
	_menu.custom_minimum_size.x = 354.0
	_menu.add_theme_constant_override("separation", 5)
	_playback.add_child(_menu)
	_button(_menu, "PLAY SOLO", _on_play)
	# Browsers can join a session, but cannot listen for incoming connections.
	_host_button = _button(_menu, "HOST GAME", _on_host)
	_host_button.visible = Net.can_host()
	_button(_menu, "JOIN GAME", _on_join)
	_suit_button = _button(_menu, "SUIT", _on_suit)
	_settings_button = _button(_menu, "SETTINGS", _on_settings)
	_button(_menu, "QUIT", _on_quit).visible = not OS.has_feature("web")
	for button in _menu.get_children():
		button.disabled = true

	_settings.position = _menu.position
	_settings.custom_minimum_size.x = _menu.custom_minimum_size.x
	_settings.add_theme_constant_override("separation", 5)
	_settings.hide()
	_playback.add_child(_settings)
	_slider(_settings, "MOUSE SENSITIVITY", 0.0005, 0.006, Settings.mouse_sensitivity, func(v): Settings.mouse_sensitivity = v)
	_slider(_settings, "VOLUME", 0.0, 1.0, Settings.master_volume, _set_volume)
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
	# Where JOIN GAME connects. Blank = the public cloud server.
	var server_caption := Label.new()
	server_caption.text = "SERVER (WSS)"
	server_caption.add_theme_font_size_override("font_size", 16)
	_settings.add_child(server_caption)
	var server_edit := LineEdit.new()
	server_edit.text = Settings.server_url
	server_edit.placeholder_text = Net.CLOUD_URL
	server_edit.custom_minimum_size.y = 38
	server_edit.text_changed.connect(func(t): Settings.server_url = t.strip_edges())
	server_edit.text_submitted.connect(func(_t): Settings.save())
	_settings.add_child(server_edit)
	if Net.can_host():
		_button(_settings, "BROWSE LAN GAMES", _on_browse_lan)
	_button(_settings, "BACK", _on_back)

	_suit.position = Vector2(510, 110)
	_suit.custom_minimum_size.x = 362.0
	_suit.add_theme_constant_override("separation", 8)
	_suit.hide()
	_playback.add_child(_suit)
	_suit_picker = SuitPicker.new(Vector2i(280, 280))
	_suit_picker.changed.connect(func(color: int, skin: int):
		Settings.suit_color = color
		Settings.suit_skin = skin)
	_suit.add_child(_suit_picker)
	_button(_suit, "BACK", _on_back)
	_playback.hide()


func _process(delta: float) -> void:
	if _ejecting:
		return
	var previous := _t
	_t += delta
	if _menu_ready:
		var seconds := int(_t - PLAY)
		if seconds != _seconds:
			_seconds = seconds
			_counter.text = "SP   %02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]
		return
	if previous < ENGAGE and _t >= ENGAGE:
		_play_transport(INSERT)
	if previous < THREAD and _t >= THREAD:
		_play_transport(WHIRR)
	if previous < TRACK and _t >= TRACK and not Settings.reduced_flash:
		_tracking.stream = TRACKING
		_tracking.play()
	if _t >= PLAY:
		_finish_intro()
		return
	var approach := smoothstep(0.0, ENGAGE, _t)
	var feed := smoothstep(ENGAGE, 0.62, _t)
	_deck.tape_depth = lerpf(-84.0, 0.0, approach) + VcrDeck.CASSETTE.y * feed
	_deck.reel_angle = maxf(0.0, _t - THREAD) * 18.0
	_deck.shake = 3.0 * sin(TAU * 8.0 * (_t - ENGAGE)) * exp(-11.0 * (_t - ENGAGE)) if _t >= ENGAGE and not Settings.reduced_flash else 0.0
	_deck.display = "--:--" if _t < ENGAGE else ("LOAD" if _t < TRACK else "00:00")
	_deck.play_lit = _t >= TRACK
	if _t >= TRACK:
		var switch := smoothstep(TRACK, PLAY, _t)
		_intro.modulate.a = 1.0 - switch
		_playback.show()
		if _backdrop_viewport:
			_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		_set_tracking(sin(PI * switch) * (0.22 if Settings.reduced_flash else 0.58))


func _input(event: InputEvent) -> void:
	if not _menu_ready and event.is_pressed() and not event.is_echo() and (
		event is InputEventKey or event is InputEventMouseButton
		or event is InputEventJoypadButton or event is InputEventScreenTouch
	):
		_tracking.stop()
		_play_transport(FAST_FORWARD)
		_finish_intro()
		get_viewport().set_input_as_handled()
	elif (_settings.visible or _suit.visible) and event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


func _finish_intro() -> void:
	_t = PLAY
	_menu_ready = true
	_intro.hide()
	_snow.hide()
	_playback.show()
	if _backdrop_viewport:
		_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	for button in _menu.get_children():
		button.disabled = false
	_menu.get_child(0).grab_focus()


func _play_transport(stream: AudioStream) -> void:
	_transport.stream = stream
	_transport.play()


func _set_tracking(strength: float) -> void:
	_snow_material.set_shader_parameter("strength", strength)
	_snow.visible = strength > 0.001


func _add_full_rect(control: Control, parent: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)


func _label(parent: Control, text: String, at: Vector2, font_size: int, color: Color, width := 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size.x = width
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 43
	_style_button(button)
	BroadcastUI.animate_button(button)
	button.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	parent.add_child(button)
	return button


func _style_button(button: Control) -> void:
	button.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var selected: bool = state in ["hover", "pressed", "focus"]
		var fill := Color(0.04, 0.13, 0.16, 0.86) if selected else Color(0.03, 0.06, 0.09, 0.54)
		if state == "focus":
			fill.a = 0.0
		var style := BroadcastUI.panel(fill, OSD_COLOR)
		style.border_width_left = 3 if selected else 0
		style.set_content_margin_all(10)
		style.content_margin_left = 19
		button.add_theme_stylebox_override(state, style)


func _slider(parent: Control, caption: String, lo: float, hi: float, value: float, on_change: Callable) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", OSD_COLOR)
	label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = (hi - lo) / 100.0
	slider.value = value
	slider.custom_minimum_size = Vector2(320, 21)
	slider.value_changed.connect(on_change)
	parent.add_child(slider)


func _set_volume(value: float) -> void:
	Settings.master_volume = value
	Settings.apply()



func _on_play() -> void:
	Settings.save()
	Net.leave()
	SceneLoader.goto(RUN_SCENE)


func _on_host() -> void:
	Settings.save()
	var err := Net.host()
	if err != OK:
		_show_error("Could not open port %d (error %d). Another copy running?" % [Net.PORT, err])
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)


## JOIN GAME goes straight to the cloud server (or the address in Settings).
func _on_join() -> void:
	Settings.save()
	var err := Net.join_cloud()
	if err != OK:
		_show_error("Could not reach %s (error %d)." % [Net.cloud_url(), err])
		return
	_set_menu_enabled(false)
	_join_status("CONNECTING TO %s ..." % Net.cloud_url().trim_prefix("wss://").trim_prefix("ws://").trim_suffix("/").to_upper())
	if not Net.joined_server.is_connected(_on_joined):
		Net.joined_server.connect(_on_joined, CONNECT_ONE_SHOT)
	if not Net.connection_failed.is_connected(_on_join_failed):
		Net.connection_failed.connect(_on_join_failed, CONNECT_ONE_SHOT)


func _on_joined() -> void:
	if Net.connection_failed.is_connected(_on_join_failed):
		Net.connection_failed.disconnect(_on_join_failed)
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_join_failed() -> void:
	if Net.joined_server.is_connected(_on_joined):
		Net.joined_server.disconnect(_on_joined)
	_join_status("")
	_set_menu_enabled(true)
	var why: String = Net.last_error if Net.last_error != "" else "No answer from the server."
	_show_error("Could not join %s. %s" % [Net.cloud_url(), why])


func _on_browse_lan() -> void:
	Settings.save()
	Net.leave()
	get_tree().change_scene_to_file(BROWSER_SCENE)


var _status_label: Label


func _join_status(text: String) -> void:
	if _status_label == null:
		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 20)
		_status_label.add_theme_color_override("font_color", BroadcastUI.CYAN)
		_status_label.position = _menu.position + Vector2(0, -34)
		_playback.add_child(_status_label)
	_status_label.text = text
	_status_label.visible = text != ""


func _set_menu_enabled(enabled: bool) -> void:
	for button in _menu.get_children():
		if button is Button:
			button.disabled = not enabled


func _on_quit() -> void:
	_ejecting = true
	_playback.hide()
	_intro.modulate.a = 1.0
	_intro.show()
	_deck.display = "EJECT"
	_deck.play_lit = false
	_deck.shake = 0.0
	_play_transport(EJECT)
	var eject := create_tween()
	eject.tween_property(_deck, "tape_depth", -45.0, 0.78).from(VcrDeck.CASSETTE.y).set_trans(Tween.TRANS_CUBIC)
	eject.tween_interval(0.16)
	eject.tween_callback(_finish_eject)


func _finish_eject() -> void:
	_transport.stop()
	_transport.stream = null
	await get_tree().process_frame
	get_tree().quit()


## A failed host attempt keeps the error and its Back action in the menu area.
func _show_error(text: String) -> void:
	_menu.hide()
	var row := VBoxContainer.new()
	row.position = _menu.position
	row.custom_minimum_size.x = _menu.custom_minimum_size.x
	row.add_theme_constant_override("separation", 12)
	_playback.add_child(row)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", BroadcastUI.PINK)
	row.add_child(label)
	var back := _button(row, "BACK", func():
		row.queue_free()
		_menu.show()
		_host_button.grab_focus())
	back.grab_focus()
	BroadcastUI.reveal(row)


func _on_settings() -> void:
	_menu.hide()
	_settings.show()
	BroadcastUI.reveal(_settings)
	_settings.get_child(1).grab_focus()


func _on_suit() -> void:
	_menu.hide()
	_suit.show()
	BroadcastUI.reveal(_suit)
	_suit_picker.focus_selected()


func _on_back() -> void:
	Settings.save()
	var button := _suit_button if _suit.visible else _settings_button
	_settings.hide()
	_suit.hide()
	_menu.show()
	button.grab_focus()


func _snow_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;

uniform float strength = 0.0;
uniform bool steady = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(13.37, 78.233))) * 43758.5453);
}

void fragment() {
	if (steady) {
		COLOR = vec4(.09, .18, .34, strength);
	} else {
		float time = floor(TIME * 23.0);
		float line = floor(UV.y * 240.0);
		float slip = (hash(vec2(line, time)) - .5) * 30.0;
		vec2 cell = vec2(floor(UV.x * 320.0 + slip), line);
		float grain = hash(cell + time);
		float band = 1.0 - smoothstep(.04, .23, abs(fract(UV.y + TIME * 1.7) - .5));
		vec3 snow = vec3(.10, .19, .31) + vec3(grain * .55 + band * .15);
		COLOR = vec4(snow, strength);
	}
}"""
	return shader


func _build_street_3d(viewport: SubViewport) -> void:
	var level := (load("res://levels/pinecrest/level_pinecrest.tscn") as PackedScene).instantiate() as Node3D
	viewport.add_child(level)
	preload("res://props/building_restyle.gd").apply(level)
	var signs := Node.new()
	signs.set_script(preload("res://props/map_signs.gd"))
	level.add_child(signs)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(-28, 2.2, -2)
	camera.look_at(Vector3(-5, 1.5, 1))


func _build_street_backdrop() -> void:
	if OS.has_feature("web"):
		# Building the whole map just for a backdrop froze the browser on the
		# VHS screen; web shows a pre-rendered still of the same view instead
		# (assets/ui/title_street.png, re-bake if the street changes).
		var still := TextureRect.new()
		still.texture = preload("res://assets/ui/title_street.png")
		still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		still.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playback.add_child(still)
	else:
		var container := SubViewportContainer.new()
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playback.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 720)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		container.add_child(viewport)
		_backdrop_viewport = viewport
		# Build the 3D street after the first frame so the screen shows at once.
		_build_street_3d.call_deferred(viewport)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade_material := ShaderMaterial.new()
	var shade_shader := Shader.new()
	shade_shader.code = """shader_type canvas_item;

void fragment() {
	float left = 1.0 - smoothstep(.28, .80, UV.x);
	float rim = 2.0 * abs(UV.y - .5);
	float opacity = .48 + .31 * left + .14 * pow(rim, 4.0);
	COLOR = vec4(.014, .027, .052, opacity);
}"""
	shade_material.shader = shade_shader
	shade.material = shade_material
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_playback.add_child(shade)
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
	_playback.add_child(rain)
