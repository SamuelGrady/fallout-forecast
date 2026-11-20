extends Control
## Cold open on the tape loader, then switch to the VCR's playback menu.

const LOBBY_SCENE := "res://ui/lobby.tscn"
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
var _content := Control.new()
var _menu := VBoxContainer.new()
var _settings_panel := PanelContainer.new()
var _settings := VBoxContainer.new()
var _settings_initial: HSlider
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
	if OS.has_feature("web"):
		_transport.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_transport)
	_tracking.bus = &"UI"
	_tracking.volume_db = Sound.cue_gain("vhs_glitch", -19.0)
	if OS.has_feature("web"):
		_tracking.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_tracking)

	var retro := RETRO_SCREEN.instantiate() as CanvasLayer
	retro.interface_only = true
	retro.get_node("VHS").hide()
	add_child(retro)
	if MenuState.title_played:
		_finish_intro()


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
	var skip := _label(_intro, "PRESS ANY BUTTON TO SKIP", Vector2(0, 674), 16, BroadcastUI.MUTED, 960.0)
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	skip.offset_top = -45
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_snow_material.shader = _snow_shader()
	_snow_material.set_shader_parameter("steady", Settings.reduced_flash)
	_snow.material = _snow_material
	_snow.hide()
	_add_full_rect(_snow, self)


func _build_playback_menu() -> void:
	_add_full_rect(_content, _playback)
	_content.anchor_left = 0.5
	_content.anchor_right = 0.5
	_content.offset_left = -480
	_content.offset_right = 480
	_label(_content, "PLAY", Vector2(78, 34), 22, OSD_COLOR)
	_label(_content, ">" if OS.has_feature("web") else "▶", Vector2(51, 36), 17, OSD_COLOR)
	_counter = _label(_content, "SP   00:00:00", Vector2(702, 34), 22, OSD_COLOR, 206.0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(_content, "OCT 31 1987", Vector2(52, 658), 19, OSD_COLOR)

	var first := _label(_content, "FALLOUT", Vector2(96, 91), 99, Color("E6EEE2"))
	var second := _label(_content, "FORECAST", Vector2(96, 174), 99, Color("A9E9D9"))
	for line in [first, second]:
		line.add_theme_constant_override("shadow_offset_x", 3)
		line.add_theme_constant_override("shadow_offset_y", 3)
		line.add_theme_color_override("font_shadow_color", Color("267E75"))

	_menu.position = Vector2(104, 325)
	_menu.custom_minimum_size.x = 354.0
	_menu.add_theme_constant_override("separation", 5)
	_content.add_child(_menu)
	if OS.has_feature("web"):
		# Web: PLAY SOLO shares its row with a DOWNLOAD button for the desktop build.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		_menu.add_child(row)
		var play := _button(row, "PLAY SOLO", _on_play)
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		BroadcastUI.button_role(play, true)
		var download := _button(row, "DOWNLOAD", _on_download)
		download.alignment = HORIZONTAL_ALIGNMENT_CENTER
		download.custom_minimum_size.x = 150
		download.tooltip_text = "Get the desktop build (Windows / Linux)"
	else:
		BroadcastUI.button_role(_button(_menu, "PLAY SOLO", _on_play), true)
	_button(_menu, "CLOUD PLAY", _on_join)
	_suit_button = _button(_menu, "SUIT", _on_suit)
	_settings_button = _button(_menu, "SETTINGS", _on_settings)
	_button(_menu, "QUIT", _on_quit).visible = not OS.has_feature("web")
	_set_menu_enabled(false)

	_settings_panel.position = Vector2(495, 87)
	_settings_panel.custom_minimum_size.x = 376.0
	_settings_panel.hide()
	_content.add_child(_settings_panel)
	_settings.add_theme_constant_override("separation", 5)
	_settings_panel.add_child(_settings)
	var heading := Label.new()
	heading.text = "SETTINGS"
	BroadcastUI.text(heading, 38, BroadcastUI.CYAN)
	_settings.add_child(heading)
	_settings_initial = _slider(_settings, "MOUSE SENSITIVITY", 0.0005, 0.006, Settings.mouse_sensitivity, func(v: float): Settings.mouse_sensitivity = v)
	_slider(_settings, "VOLUME", 0.0, 1.0, Settings.master_volume, _set_volume)
	_toggle("RETRO VHS EFFECT", Settings.retro_enabled, Settings.set_retro)
	_toggle("REDUCED FLASHING", Settings.reduced_flash, Settings.set_reduced_flash)
	_toggle("LARGE HUD", Settings.hud_scale > 1.0, Settings.set_large_hud)
	_toggle("PERFORMANCE OVERLAY", Settings.perf_overlay, func(on: bool):
		Settings.perf_overlay = on
		Settings.save())
	_toggle("SEND TELEMETRY", Settings.telemetry_enabled, func(on: bool):
		Settings.telemetry_enabled = on
		Settings.save())
	var server_caption := Label.new()
	server_caption.text = "SERVER (WSS)"
	BroadcastUI.text(server_caption, 19, BroadcastUI.CYAN)
	_settings.add_child(server_caption)
	var server_edit := LineEdit.new()
	server_edit.text = Settings.server_url
	server_edit.placeholder_text = Net.CLOUD_URL
	server_edit.custom_minimum_size.y = 38
	server_edit.text_changed.connect(func(t: String): Settings.server_url = t.strip_edges())
	server_edit.text_submitted.connect(func(_t: String):
		Sound.play("ui_click")
		Settings.save())
	BroadcastUI.focus_sound(server_edit)
	_settings.add_child(server_edit)
	var export := _button(_settings, "EXPORT PERF REPORT", func(): pass)
	export.pressed.connect(func():
		Perf.export_report()
		export.text = "PERF REPORT DOWNLOADED" if OS.has_feature("web") else "PERF REPORT SAVED")
	_button(_settings, "BACK", _on_back)

	_suit.position = Vector2(510, 110)
	_suit.custom_minimum_size.x = 362.0
	_suit.add_theme_constant_override("separation", 8)
	_suit.hide()
	_content.add_child(_suit)
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
	elif (_settings_panel.visible or _suit.visible) and event.is_action_pressed("ui_cancel"):
		Sound.play("ui_click")
		_on_back()
		get_viewport().set_input_as_handled()


func _finish_intro() -> void:
	MenuState.title_played = true
	_t = PLAY
	_menu_ready = true
	_intro.hide()
	_snow.hide()
	_playback.show()
	if _backdrop_viewport:
		_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_set_menu_enabled(true)
	_menu_buttons()[0].grab_focus()


func _play_transport(stream: AudioStream) -> void:
	_transport.stream = stream
	_transport.volume_db = Sound.cue_gain(stream.resource_path.get_file().get_basename(), -11.0)
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
	BroadcastUI.text(label, font_size, color, 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 43
	BroadcastUI.button_role(button)
	BroadcastUI.animate_button(button)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _toggle(caption: String, checked: bool, action: Callable) -> void:
	var toggle := CheckButton.new()
	toggle.text = caption
	toggle.button_pressed = checked
	toggle.toggled.connect(action)
	BroadcastUI.animate_button(toggle)
	_settings.add_child(toggle)


func _slider(parent: Control, caption: String, lo: float, hi: float, value: float, on_change: Callable) -> HSlider:
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
	slider.value_changed.connect(func(_value: float): Sound.ui_focus())
	BroadcastUI.focus_sound(slider)
	parent.add_child(slider)
	return slider


func _set_volume(value: float) -> void:
	Settings.master_volume = value
	Settings.apply()



func _on_play() -> void:
	Settings.save()
	Net.leave()
	SceneLoader.cut_to(Maps.SELECT_SCENE)


## CLOUD PLAY goes straight to the cloud server (or the address in Settings).
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
	SceneLoader.cut_to(LOBBY_SCENE)


func _on_join_failed() -> void:
	if Net.joined_server.is_connected(_on_joined):
		Net.joined_server.disconnect(_on_joined)
	_join_status("")
	_set_menu_enabled(true)
	var why: String = Net.last_error if Net.last_error != "" else "No answer from the server."
	_show_error("Could not join %s. %s" % [Net.cloud_url(), why])


var _status_label: Label


func _join_status(text: String) -> void:
	if _status_label == null:
		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 20)
		_status_label.add_theme_color_override("font_color", BroadcastUI.CYAN)
		_status_label.position = _menu.position + Vector2(0, -34)
		_content.add_child(_status_label)
	_status_label.text = text
	_status_label.visible = text != ""


func _set_menu_enabled(enabled: bool) -> void:
	for button in _menu_buttons():
		button.disabled = not enabled


## Every menu button, including the ones inside the web PLAY / DOWNLOAD row.
func _menu_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in _menu.get_children():
		if child is Button:
			out.append(child)
		elif child is HBoxContainer:
			for inner in child.get_children():
				if inner is Button:
					out.append(inner)
	return out


const RELEASES := "https://github.com/kickofline/fallout-forecast/releases"


## Web only: download the desktop build that matches the visitor's OS (the
## rolling "nightly" release CI refreshes on every master push).
func _on_download() -> void:
	var file := ""
	if OS.has_feature("web"):
		var agent := str(JavaScriptBridge.eval("navigator.userAgent", true)).to_lower()
		if "windows" in agent:
			file = "FalloutForecast-windows-x86_64.zip"
		elif "linux" in agent and not "android" in agent:
			file = "FalloutForecast-linux-x86_64.tar.gz"
	OS.shell_open(RELEASES + ("/download/nightly/" + file if file != "" else "/tag/nightly"))


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
	_content.add_child(row)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", BroadcastUI.PINK)
	row.add_child(label)
	var back := _button(row, "BACK", func():
		row.queue_free()
		_menu.show()
		_menu_buttons()[0].grab_focus())
	back.grab_focus()
	BroadcastUI.reveal(row)


func _on_settings() -> void:
	_menu.hide()
	_settings_panel.show()
	_settings_initial.grab_focus()
	SceneLoader.tracking_wipe()


func _on_suit() -> void:
	_menu.hide()
	_suit.show()
	_suit_picker.focus_selected()
	SceneLoader.tracking_wipe()


func _on_back() -> void:
	Settings.save()
	var button := _suit_button if _suit.visible else _settings_button
	_settings_panel.hide()
	_suit.hide()
	_menu.show()
	button.grab_focus()
	SceneLoader.tracking_wipe()


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
	# The VCR cover always depicts Pinecrest, independently of the run map.
	var scene := load(Maps.entry(Maps.DEFAULT_ID).scene) as PackedScene
	var level := scene.instantiate() as Node3D
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
	if OS.has_feature("web") or Net.dedicated:
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
