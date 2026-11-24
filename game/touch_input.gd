extends Node
## Browser input mode and the shared cursor policy. Godot still emulates a
## single mouse for GUI controls outside the live touch overlay.

signal interrupted
signal layout_changed

var enabled := false
var landscape := true
var foreground := true
var gameplay_active := false
var movement := Vector2.ZERO

var _css_height := 0.0
var _backing_scale := 1.0
var _browser: JavaScriptObject
var _browser_callback: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_browser = JavaScriptBridge.get_interface("falloutTouch")
	if _browser == null:
		return
	_browser_callback = JavaScriptBridge.create_callback(_on_browser_change)
	_browser.subscribe(_browser_callback)
	get_window().focus_exited.connect(interrupt)
	get_viewport().size_changed.connect(layout_changed.emit)


func _on_browser_change(args: Array) -> void:
	interrupt()
	enabled = bool(args[0])
	landscape = bool(args[1])
	foreground = bool(args[2])
	_css_height = float(args[3])
	_backing_scale = maxf(float(args[4]), 1.0)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if enabled else Window.CONTENT_SCALE_ASPECT_KEEP
	if enabled:
		release_pointer()
	layout_changed.emit()


func set_run_visible(value: bool) -> void:
	if _browser != null:
		_browser.setRunVisible(value)


func interrupt() -> void:
	movement = Vector2.ZERO
	interrupted.emit()


func set_gameplay_active(value: bool) -> void:
	if gameplay_active == value:
		return
	gameplay_active = value
	if not value:
		interrupt()
	Input.emulate_mouse_from_touch = not value


func units_per_css_pixel() -> float:
	return get_viewport().get_visible_rect().size.y / maxf(_css_height, 1.0) if _css_height > 0.0 else 1.0


func look_delta(screen_relative: Vector2) -> Vector2:
	return screen_relative * (3.0 * Settings.mouse_sensitivity / _backing_scale)


func capture_pointer() -> void:
	if not enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_pointer() -> void:
	set_gameplay_active(false)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func combat_pointer_active() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or gameplay_active
