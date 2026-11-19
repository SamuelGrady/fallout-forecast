extends Control
## Results screen after a run: won or lost, waves survived, and per player
## kills, revives, times Turned and best cursed weapon roll.

const RUN_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://ui/title.tscn"


func _ready() -> void:
	theme = BroadcastUI.theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("100A1E")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	BroadcastUI.backdrop(self)
	bg.queue_free()
	var r: Dictionary = GameManager.last_results
	var won: bool = r.get("won", false)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	box.offset_left = -440
	box.offset_right = 440
	box.offset_top = -210
	add_child(box)
	_label(box, "PINECREST IS SAFE" if won else "PINECREST IS LOST", 60, Color("8FD65A") if won else Color("FF3EA5"))
	_label(box, "WAVES SURVIVED: %d / %d" % [int(r.get("waves", 0)), WeatherManager.FINAL_WAVE], 28, Color("F2E3C6"))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for h in ["PLAYER", "KILLS", "REVIVES", "TURNED", "BEST CURSED ROLL"]:
		_label(grid, h, 18, Color("2EE6E6"))
	var players: Dictionary = r.get("players", {})
	for id in players:
		var p: Dictionary = players[id]
		_label(grid, str(p.get("name", "?")).to_upper(), 22, Color("F2E3C6"))
		_label(grid, str(p.get("kills", 0)), 22, Color("F2E3C6"))
		_label(grid, str(p.get("revives", 0)), 22, Color("F2E3C6"))
		_label(grid, str(p.get("turned", 0)), 22, Color("F2E3C6"))
		var cursed := str(p.get("cursed", ""))
		_label(grid, cursed.to_upper() if cursed != "" else "-", 22, Color("FF3EA5") if cursed != "" else Color("F2E3C6"))
	_label(box, "STAY DRY, STAY ALIVE.  PINECREST HEALTH DEPT.", 16, Color("8FD65A"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	_button(row, "PLAY AGAIN", func(): get_tree().change_scene_to_file(RUN_SCENE))
	_button(row, "TITLE", func(): get_tree().change_scene_to_file(TITLE_SCENE))


func _label(parent: Control, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 0)
	parent.add_child(l)


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 52)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func():
		Sound.play("ui_click")
		action.call())
	parent.add_child(b)
