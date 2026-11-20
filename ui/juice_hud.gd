extends CanvasLayer
## Screen-level juice for the local player (main.gd adds it next to the HUD):
## - trailing white chunk on the health and suit bars after damage
## - SUIT BREACH warning: vignette and beep while suit < 25% and exposed
## - downed view: desaturated, heartbeat
## - rain drips running down the screen while exposed in rain
## - wave intro card ("WAVE 3  -  DOWNPOUR") as each storm starts
## - "+HEADSHOT" / "+KILL" / "+REVIVE" popup ticker (Juice.popup)

const TRAIL_DELAY := 0.35

var _trail := {}  # bar -> {chunk, value, hold}
var _vignette: ColorRect
var _breach_beep := 0.0
var _drips: ColorRect
var _desat: ColorRect
var _heart := AudioStreamPlayer.new()
var _overlay := CanvasLayer.new()
var _card_panel := PanelContainer.new()
var _card_tween: Tween
var _card := Label.new()
var _card_sub := Label.new()
var _ticker := VBoxContainer.new()
var _clock := 0.0
var _warming := false
var _seen_drips := false
var _seen_breach := false
var _seen_downed := false
static var _cached_shaders := {}


func _ready() -> void:
	layer = 2
	_build_screen_layers()
	_overlay.layer = 7
	add_child(_overlay)
	_build_card()
	add_child(preload("res://ui/tape_choice.gd").new())
	_ticker.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_ticker.offset_left = -260
	_ticker.offset_right = -24
	_ticker.offset_top = -40
	_ticker.alignment = BoxContainer.ALIGNMENT_END
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_ticker)
	Juice.popup_requested.connect(_on_popup)
	WeatherManager.phase_changed.connect(_on_phase)
	GameManager.combat_hit.connect(_on_combat_hit)
	_heart.stream = load("res://assets/audio/sfx/heartbeat.wav")
	if _heart.stream is AudioStreamWAV:
		var wav := (_heart.stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
		_heart.stream = wav
	_heart.bus = Sound.bus_for("heartbeat")
	_heart.volume_db = -12.0
	if OS.has_feature("web"):
		_heart.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_heart)


func _exit_tree() -> void:
	for pair in [[Juice.popup_requested, _on_popup], [WeatherManager.phase_changed, _on_phase], [GameManager.combat_hit, _on_combat_hit]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _shader_rect(key: String, code: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _cached_shaders.has(key):
		var shader := Shader.new()
		shader.code = code
		_cached_shaders[key] = shader
	var mat := ShaderMaterial.new()
	mat.shader = _cached_shaders[key]
	rect.material = mat
	rect.visible = false
	add_child(rect)
	return rect


## Briefly draw full-screen overlays with amount=0 behind the loading card so
## ANGLE/WebGL2 compiles their shaders during warm-up rather than mid-combat.
func warm_shaders(active: bool) -> void:
	_warming = active
	for rect in [_drips, _desat, _vignette]:
		if rect == null:
			continue
		(rect.material as ShaderMaterial).set_shader_parameter("amount", 0.0)
		rect.visible = active


func _build_screen_layers() -> void:
	_drips = _shader_rect("drips", """shader_type canvas_item;
uniform float amount = 0.0;
float h(float x){ return fract(sin(x * 91.7) * 43758.5); }
void fragment(){
	float col = floor(UV.x * 34.0);
	float speed = 0.15 + h(col) * 0.35;
	float y = fract(UV.y * 0.6 - TIME * speed + h(col + 3.0));
	float streak = smoothstep(0.0, 0.02, y) * (1.0 - smoothstep(0.02, 0.22, y));
	float lane = 1.0 - smoothstep(0.0, 0.08, abs(fract(UV.x * 34.0) - 0.5) - 0.02);
	COLOR = vec4(0.75, 0.9, 1.0, streak * lane * amount * step(0.55, h(col + 7.0)) * 0.35);
}""")
	if OS.has_feature("web"):
		# Zero screen-copy downed vignette on WebGL2 (matches RetroScreen).
		_desat = _shader_rect("desat_web", """shader_type canvas_item;
uniform float amount = 0.0;
void fragment(){
	float r = length(UV - 0.5);
	float vig = smoothstep(0.18, 0.72, r);
	COLOR = vec4(0.08, 0.03, 0.04, (0.28 + 0.52 * vig) * amount);
}""")
	else:
		_desat = _shader_rect("desat", """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment(){
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec2 d = UV - 0.5;
	float vig = 1.0 - smoothstep(0.25, 0.75, length(d));
	COLOR = vec4(mix(c, vec3(g) * vec3(1.0, 0.85, 0.85), amount) * mix(1.0, vig, amount * 0.7), 1.0);
}""")
	_vignette = _shader_rect("vignette", """shader_type canvas_item;
uniform float amount = 0.0;
void fragment(){
	float r = length(UV - 0.5);
	COLOR = vec4(1.0, 0.15, 0.1, smoothstep(0.35, 0.75, r) * amount);
}""")


func _build_card() -> void:
	_card_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card_panel.offset_left = -228
	_card_panel.offset_right = 228
	_card_panel.offset_top = -78
	_card_panel.offset_bottom = -78
	_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := BroadcastUI.panel(BroadcastUI.OVERLAY)
	style.set_content_margin_all(12)
	_card_panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(_card_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_panel.add_child(column)
	for label in [_card, _card_sub]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	_card_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BroadcastUI.text(_card, roundi(52 * Settings.hud_scale))
	BroadcastUI.text(_card_sub, roundi(23 * Settings.hud_scale), BroadcastUI.CYAN)
	_card_panel.hide()


func _on_phase(phase: int, wave: int) -> void:
	if phase != WeatherManager.Phase.DRIZZLE:
		return
	var subtitle: String = "THE ACID STORM" if wave == WeatherManager.FINAL_WAVE else ["", "FIRST RAIN", "DOWNPOUR WARNING", "FLOOD WATCH", "SEVERE STORM"][clampi(wave, 0, 4)]
	var modifier := WeatherManager.wave_modifier()
	if not modifier.is_empty():
		subtitle = "%s  /  %s" % [modifier, WeatherManager.WavePlan.FORECAST[modifier]]
	_card.text = "ENDLESS %d" % (wave - WeatherManager.FINAL_WAVE) if GameManager.endless else "WAVE %d" % wave
	_card_sub.text = subtitle
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	_card_panel.modulate.a = 0.0
	_card_panel.show()
	_card_tween = create_tween()
	_card_tween.tween_property(_card_panel, "modulate:a", 1.0, 0.18)
	_card_tween.tween_interval(1.30)
	_card_tween.tween_property(_card_panel, "modulate:a", 0.0, 0.36)
	_card_tween.tween_callback(_card_panel.hide)


var _kill_times: Array = []


func _on_combat_hit(killed: bool, critical: bool) -> void:
	if not killed:
		return
	var now := _clock
	_kill_times.append(now)
	_kill_times = _kill_times.filter(func(t): return now - float(t) < 1.5)
	if _kill_times.size() >= 3:
		Juice.popup("+MULTIKILL x%d" % _kill_times.size(), Color("#ffd56a"))
		Sound.play("multikill", -8.0)
	else:
		Sound.play("kill_confirm", -10.0)
	Juice.popup("+HEADSHOT KILL" if critical else "+KILL", Color("#ff6a6a") if critical else BroadcastUI.PAPER)
	Juice.hit_stop(45.0 if critical else 25.0)


func _on_popup(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	_ticker.add_child(label)
	while _ticker.get_child_count() > 5:
		_ticker.get_child(0).queue_free()
		_ticker.remove_child(_ticker.get_child(0))
	var tween := label.create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


func _process(delta: float) -> void:
	_clock += delta
	var me := get_tree().get_first_node_in_group("local_player")
	if me == null:
		return
	var hud := get_parent().get_node_or_null("HUD")
	if hud:
		for bar_name in ["SuitBar", "HealthBar"]:
			var bar := hud.find_child(bar_name, true, false) as ProgressBar
			if bar:
				_update_trail(bar, delta)
	var state := str(me.get("state"))
	var suit := float(me.get("suit_integrity")) if me.get("suit_integrity") != null else 100.0
	var exposed: bool = me.get("exposed") != false and WeatherManager.is_raining()
	if _warming:
		return
	# Suit breach.
	var breach := state == "ok" and suit < 25.0 and exposed
	_vignette.visible = breach
	if breach:
		if not _seen_breach:
			_seen_breach = true
			Perf.mark("hud first suit breach")
		(_vignette.material as ShaderMaterial).set_shader_parameter("amount", 0.12 if Settings.reduced_flash else 0.28 + 0.08 * sin(_clock * 6.0))
		_breach_beep -= delta
		if _breach_beep <= 0.0:
			_breach_beep = 0.8
			Sound.play("suit_beep", -10.0)
	# Rain drips while exposed.
	var drip := WeatherManager.storm_intensity if exposed and state == "ok" else 0.0
	_drips.visible = drip > 0.05
	if _drips.visible:
		if not _seen_drips:
			_seen_drips = true
			Perf.mark("hud first rain drips")
		(_drips.material as ShaderMaterial).set_shader_parameter("amount", drip * (0.5 if Settings.reduced_flash else 1.0))
	# Downed view.
	var downed := state == "downed"
	_desat.visible = downed
	if downed:
		if not _seen_downed:
			_seen_downed = true
			Perf.mark("hud first downed overlay")
		(_desat.material as ShaderMaterial).set_shader_parameter("amount", 0.50 if Settings.reduced_flash else 0.80)
		if not _heart.playing:
			_heart.play()
	elif _heart.playing:
		_heart.stop()


func _update_trail(bar: ProgressBar, delta: float) -> void:
	if not _trail.has(bar):
		var chunk := ColorRect.new()
		chunk.color = Color(BroadcastUI.PAPER, 0.50 if Settings.reduced_flash else 0.80)
		chunk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(chunk)
		_trail[bar] = {"chunk": chunk, "value": bar.value, "hold": 0.0}
	var t: Dictionary = _trail[bar]
	if bar.value >= t.value:
		t.value = bar.value
		t.hold = TRAIL_DELAY
	else:
		t.hold -= delta
		if t.hold <= 0.0:
			t.value = move_toward(t.value, bar.value, delta * 60.0)
	var chunk: ColorRect = t.chunk
	var w := bar.size.x
	var from := bar.value / maxf(bar.max_value, 1.0) * w
	var to: float = float(t.value) / maxf(bar.max_value, 1.0) * w
	chunk.position = Vector2(from, 0)
	chunk.size = Vector2(maxf(0.0, to - from), bar.size.y)
	chunk.visible = to - from > 0.5
