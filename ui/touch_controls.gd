extends Control
## Each index keeps its role until lift/cancel, even if it crosses another pad.

const STICK_RADIUS := 36.0
const LOOK_DEADZONE := 6.0
const MAX_LOOK_STEP := 80.0
const HELD_ACTIONS := [&"fire", &"reload", &"interact", &"jump"]
const ACTION_CAPTIONS := {
	&"fire": "FIRE", &"reload": "RELOAD", &"interact": "USE", &"jump": "JUMP",
	&"loadout": "LOADOUT", &"pause": "PAUSE", &"ready_up": "READY",
}

var pause_menu: CanvasLayer
var inventory: InventoryMenu
var starter_picker: Control
var hotbar: ItemHotbar

var _contacts: Dictionary = {}
var _start_pos: Dictionary = {}
var _last_pos: Dictionary = {}
var _look_dragging: Dictionary = {}
var _actions: Dictionary = {}
var _pending_releases: Array[StringName] = []
var _buttons: Dictionary = {}
var _player: Player
var _player_state := ""
var _active := false
var _stick_home := Vector2.ZERO
var _stick_center := Vector2.ZERO
var _stick_tip := Vector2.ZERO
var _unit := 1.0


func _ready() -> void:
	TouchInput.interrupted.connect(_cancel_contacts)
	TouchInput.layout_changed.connect(_layout)
	resized.connect(_layout)
	TouchInput.set_run_visible(true)
	_layout()
	hide()


func _exit_tree() -> void:
	_cancel_contacts()
	TouchInput.set_gameplay_active(false)
	TouchInput.set_run_visible(false)


func _view_size() -> Vector2:
	var rect_size := get_viewport_rect().size
	return rect_size if rect_size.x > 0.0 and rect_size.y > 0.0 else size


func _layout() -> void:
	var view_size := _view_size()
	_unit = TouchInput.units_per_css_pixel()
	var prev_home := _stick_home
	_stick_home = Vector2(76.0 * _unit, view_size.y - 106.0 * _unit)
	if not (&"move" in _contacts.values()) or _stick_center.is_equal_approx(prev_home):
		_stick_center = _stick_home
		_stick_tip = _stick_home
	var right := view_size.x / maxf(_unit, 0.001)
	var bottom := view_size.y / maxf(_unit, 0.001)
	_buttons = {
		&"pause": Rect2(right - 68, 26, 60, 44),
		&"loadout": Rect2(right - 149, 26, 74, 44),
		&"ready_up": Rect2(right - 230, 26, 74, 44),
		&"fire": Rect2(right - 83, bottom - 175, 74, 58),
		&"reload": Rect2(right - 83, bottom - 110, 74, 44),
		&"interact": Rect2(right - 155, bottom - 175, 64, 58),
		&"jump": Rect2(right - 155, bottom - 110, 64, 44),
	}
	queue_redraw()


func _refresh() -> bool:
	var player := get_tree().get_first_node_in_group("local_player") as Player
	var state := player.state if player else ""
	if player != _player or state != _player_state:
		_cancel_contacts()
		_player = player
		_player_state = state
	var muts_busy: bool = GameManager.mutations != null and str(GameManager.mutations.get("stage")) != ""
	var active: bool = TouchInput.enabled and TouchInput.landscape and TouchInput.foreground and is_instance_valid(_player) \
		and GameManager.run_active and not GameManager.finished and Net.can_send_run_rpc() \
		and not get_tree().paused and not InventoryMenu.blocks_gameplay_actions() \
		and not (starter_picker != null and starter_picker.visible) and not GameManager.is_voting() \
		and not muts_busy and not GameManager.awaiting_tape_choice
	if active != _active:
		_active = active
		visible = active
	TouchInput.set_gameplay_active(active)
	return active


func _process(_delta: float) -> void:
	if not _refresh():
		return
	for action in _pending_releases.duplicate():
		if _action_sampled(action):
			_release_action(action)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag) or not _refresh():
		return
	get_viewport().set_input_as_handled()
	if event is InputEventScreenDrag:
		var role: Variant = _contacts.get(event.index)
		if role == &"move":
			_move_stick(event.position)
		elif role == &"look" or (role == &"fire" and not (&"look" in _contacts.values())):
			_drag_look(event.index, event.position)
		return
	if event.is_canceled():
		_end_contact(event.index, event.position)
	elif event.pressed:
		Settings.using_gamepad = false
		_begin_contact(event.index, event.position)
	else:
		_end_contact(event.index, event.position)


func _button_visible(action: StringName) -> bool:
	match action:
		&"pause":
			return true
		&"loadout":
			return InventoryMenu.can_open()
		&"ready_up":
			return _player_state == "ok" and GameManager.can_ready_up()
		&"interact":
			return _player_state in ["ok", "downed"]
		&"fire", &"jump":
			return _player_state in ["ok", "turned"]
		_:
			return _player_state == "ok"


func _target(at: Vector2, pad := 4.0) -> Variant:
	var at_css := at / maxf(_unit, 0.001)
	for action: StringName in _buttons:
		var box: Rect2 = _buttons[action]
		if _button_visible(action) and box.grow(pad).has_point(at_css):
			return action
	return hotbar.touch_cell_at(at) if hotbar != null and _player_state == "ok" else -1


func _drag_look(index: int, at: Vector2) -> void:
	if not bool(_look_dragging.get(index, false)):
		var start_at: Vector2 = _start_pos.get(index, at)
		if at.distance_to(start_at) < LOOK_DEADZONE * _unit:
			return
		_look_dragging[index] = true
		_last_pos[index] = at
		return
	var prev_at: Vector2 = _last_pos.get(index, at)
	_last_pos[index] = at
	var css_delta := ((at - prev_at) / maxf(_unit, 0.001)).limit_length(MAX_LOOK_STEP)
	if css_delta != Vector2.ZERO and is_instance_valid(_player):
		_player.touch_look(css_delta)


func _begin_contact(index: int, at: Vector2) -> void:
	if _contacts.has(index):
		_end_contact(index, at)
	var view_size := _view_size()
	var role: Variant = _target(at)
	if role is int and role == -1 and _player_state != "out":
		if at.x < view_size.x * 0.36 and at.y >= view_size.y * 0.28:
			role = &"move"
		elif at.x >= view_size.x * 0.36:
			role = &"look"
	if (role is int and role == -1) or role in _contacts.values():
		return
	_contacts[index] = role
	_start_pos[index] = at
	_last_pos[index] = at
	_look_dragging[index] = false
	if role == &"move":
		var margin := (STICK_RADIUS + 12.0) * _unit
		_stick_center = Vector2(
			clampf(at.x, margin, maxf(margin, view_size.x * 0.36 - margin * 0.5)),
			clampf(at.y, maxf(margin, view_size.y * 0.32), maxf(margin, view_size.y - margin))
		)
		_stick_tip = _stick_center
		TouchInput.movement = Vector2.ZERO
	elif role in HELD_ACTIONS:
		if _actions.has(role):
			_release_action(role)
		_actions[role] = Vector2i(Engine.get_process_frames(), Engine.get_physics_frames())
		Input.action_press(role)
	elif role is int and hotbar != null:
		hotbar.select_touch_cell(role, _holder())


func _end_contact(index: int, at: Vector2) -> void:
	var role: Variant = _contacts.get(index)
	var start_at: Vector2 = _start_pos.get(index, at)
	_start_pos.erase(index)
	_last_pos.erase(index)
	_look_dragging.erase(index)
	if not _contacts.erase(index):
		return
	if role == &"move":
		_stick_center = _stick_home
		_stick_tip = _stick_home
		TouchInput.movement = Vector2.ZERO
	elif role in HELD_ACTIONS:
		# Even a down/up pair delivered during one slow Web frame needs to
		# reach the same gameplay polls as a longer button press.
		if _action_sampled(role):
			_release_action(role)
		else:
			_pending_releases.append(role)
	elif role is StringName:
		var box: Rect2 = _buttons.get(role, Rect2())
		var release_target: Variant = _target(at, 16.0)
		var same_target: bool = release_target is StringName and release_target == role
		if same_target or (at.distance_to(start_at) <= 32.0 * _unit and box.grow(16.0).has_point(at / maxf(_unit, 0.001))):
			match role:
				&"pause":
					if pause_menu:
						pause_menu.toggle_pause()
				&"loadout":
					if inventory:
						inventory.toggle()
				&"ready_up":
					GameManager.ready_up()


func _action_sampled(action: StringName) -> bool:
	var start: Vector2i = _actions[action]
	return Engine.get_process_frames() > start.x and Engine.get_physics_frames() > start.y


func _release_action(action: StringName) -> void:
	Input.action_release(action)
	_actions.erase(action)
	_pending_releases.erase(action)


func _cancel_contacts() -> void:
	if _actions.has(&"fire"):
		var holder := _holder()
		if holder:
			holder.cancel_touch_fire()
	for action: StringName in _actions:
		Input.action_release(action)
	_actions.clear()
	_pending_releases.clear()
	_contacts.clear()
	_start_pos.clear()
	_last_pos.clear()
	_look_dragging.clear()
	_stick_center = _stick_home
	_stick_tip = _stick_home
	TouchInput.movement = Vector2.ZERO


func _holder() -> WeaponHolder:
	return _player.get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponHolder if is_instance_valid(_player) else null


func _move_stick(at: Vector2) -> void:
	var step := ((at - _stick_center) / (STICK_RADIUS * _unit)).limit_length()
	_stick_tip = _stick_center + step * STICK_RADIUS * _unit
	TouchInput.movement = step.normalized() * remap(maxf(step.length(), 0.12), 0.12, 1.0, 0.0, 1.0)


func _draw() -> void:
	if not _active:
		return
	var ink := Color(BroadcastUI.INK, 0.67)
	var edge := Color(BroadcastUI.CYAN, 0.65)
	if _player_state != "out":
		draw_circle(_stick_center, STICK_RADIUS * _unit, ink, true, -1.0, true)
		draw_arc(_stick_center, STICK_RADIUS * _unit, 0, TAU, 40, edge, _unit, true)
		draw_circle(_stick_tip, 15.0 * _unit, Color(BroadcastUI.CYAN, 0.46), true, -1.0, true)
	for action: StringName in _buttons:
		if not _button_visible(action):
			continue
		var box: Rect2 = _buttons[action]
		box = Rect2(box.position * _unit, box.size * _unit)
		var accent := BroadcastUI.PINK if action == &"fire" else BroadcastUI.CYAN
		draw_rect(box, Color(accent, 0.52) if action in _contacts.values() else ink)
		draw_rect(box, Color(accent, 0.76), false, _unit)
		var caption: String = ACTION_CAPTIONS[action]
		if action == &"ready_up":
			caption = "READY %d/%d" % [GameManager.ready_count, GameManager.player_count()] if Net.is_online() else "SKIP"
		elif action == &"fire" and _player_state == "turned":
			caption = "BITE"
		draw_string(BroadcastUI.FONT, box.position + Vector2(0, box.size.y * 0.5 + 5.0 * _unit),
			caption, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, roundi(16.0 * _unit), BroadcastUI.PAPER)
