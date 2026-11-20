extends CanvasLayer
var _panel := PanelContainer.new()
var _first: Button
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
	_section(box, "WAVE")
	_button(box, "NEXT PHASE", func(): WeatherManager.next_phase())
	_button(box, "JUMP TO WAVE 5", func(): WeatherManager.set_phase(WeatherManager.Phase.CALM, 5))
	_button(box, "LIGHTNING", func(): WeatherManager.strike_lightning())
	_section(box, "PLAYER")
	_button(box, "HEAL + REPAIR SUIT", func():
		var player := get_tree().get_first_node_in_group("local_player")
		if player:
			player.health = player.max_health
			player.suit_integrity = 100.0)
	_section(box, "SPAWN")
	for kind in ["drip", "gutter", "mister", "sleet", "hailstone", "undertow", "static", "smog", "thunderhead"]:
		var selected: String = kind
		_button(box, "SPAWN " + kind.to_upper(), func():
			var spawner := get_parent().get_node("Enemies")
			spawner.spawn(load("res://enemies/%s/%s.tscn" % [selected, selected])))
	_button(box, "SPAWN CUMULUS", func(): GameManager.spawn_boss())
	_section(box, "MUTATIONS")
	_button(box, "TRIGGER MUTATION ROLL", func(): GameManager.mutations.begin())
	_button(box, "GRANT PLAYER MUTATION", func(): GameManager.mutations.grant_random_player_mutation())
	for mid in ["conductors", "molting", "undertow", "static_charge", "pressure_front", "false_clearing"]:
		var selected_m: String = mid
		_button(box, "FORCE " + mid.replace("_", " ").to_upper(), func(): GameManager.mutations.force_enemy_mutation(selected_m))
	_section(box, "WEAPONS")
	for gun in ["pump_shotgun", "spray_rifle", "flare_gun", "bug_bomb"]:
		var selected: String = gun
		var data := load("res://weapons/%s.tres" % selected) as WeaponData
		var label_name := data.display_name if data and not data.display_name.is_empty() else selected.replace("_", " ")
		_button(box, "GRANT " + label_name.to_upper(), func():
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
	if _first == null:
		_first = button
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
	elif OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		get_viewport().set_input_as_handled()
		if visible:
			_close()
		else:
			MenuState.open(self)

func _close() -> void:
	MenuState.close(self)

func focus_default() -> void:
	_first.grab_focus()

func _section(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", BroadcastUI.CYAN)
	parent.add_child(label)
