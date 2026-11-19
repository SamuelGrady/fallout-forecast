extends CanvasLayer
var _panel := PanelContainer.new()
var _was_paused := false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_panel.theme = BroadcastUI.theme()
	_panel.position = Vector2(30, 30)
	_panel.size = Vector2(430, 650)
	add_child(_panel)
	var scroll := ScrollContainer.new()
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 370
	scroll.add_child(box)
	var title := Label.new()
	title.text = "DEVELOPER TOOLS  /  F10"
	box.add_child(title)
	_button(box, "NEXT PHASE", func(): WeatherManager.next_phase())
	_button(box, "JUMP TO WAVE 5", func(): WeatherManager.set_phase(WeatherManager.Phase.CALM, 5))
	_button(box, "LIGHTNING", func(): WeatherManager.strike_lightning())
	_button(box, "HEAL + REPAIR SUIT", func():
		var player := get_tree().get_first_node_in_group("local_player")
		if player:
			player.health = player.max_health
			player.suit_integrity = 100.0)
	for kind in ["drip", "gutter", "mister"]:
		var selected: String = kind
		_button(box, "SPAWN " + kind.to_upper(), func():
			var spawner := get_parent().get_node("Enemies")
			spawner.spawn(load("res://enemies/%s/%s.tscn" % [selected, selected])))
	_button(box, "SPAWN CUMULUS", func(): GameManager.spawn_boss())
	for gun in ["pump_shotgun", "spray_rifle", "flare_gun", "bug_bomb"]:
		var selected: String = gun
		_button(box, "GRANT " + gun.replace("_", " ").to_upper(), func():
			var player := get_tree().get_first_node_in_group("local_player")
			if player:
				player.grant("weapon:res://weapons/%s.tres" % selected))
	_button(box, "TOGGLE DEBUG HUD", func(): get_parent().get_node("DebugHUD").visible = not get_parent().get_node("DebugHUD").visible)
	_button(box, "CLOSE", _close)
	visible = false
func _button(box: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	BroadcastUI.animate_button(button)
	button.pressed.connect(action)
	box.add_child(button)
func _input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		if visible:
			_close()
		else:
			_was_paused = get_tree().paused
			get_tree().paused = true
			visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
func _close() -> void:
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _was_paused else Input.MOUSE_MODE_CAPTURED
