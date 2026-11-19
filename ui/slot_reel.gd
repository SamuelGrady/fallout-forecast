extends CanvasLayer
## SlotReelUI: the Mutation Roll on screen. Three reels idle-spin while
## players pull the lever, then whip round and stop one by one on the host's
## result. A jackpot shows the cancel vote. Built in code; restyle freely.

const SPIN_STEP := 0.06

var _panel := PanelContainer.new()
var _title := Label.new()
var _reels: Array[Label] = []
var _status := Label.new()
var _table: MutationTable
var _spinning := [false, false, false]
var _targets := ["", "", ""]
var _spin_t := 0.0
var _stop_at := [0.0, 0.0, 0.0]
var _clock := 0.0
var _hide_at := -1.0


func _ready() -> void:
	layer = 2
	_table = load("res://game/mutation_table.tres")
	_build()
	_panel.visible = false
	var roll: Node = GameManager.mutations
	roll.roll_started.connect(_on_started)
	roll.pulls_changed.connect(_on_pulls)
	roll.roll_result.connect(_on_result)
	roll.vote_started.connect(_on_vote)
	roll.mutations_changed.connect(_on_final)


func _build() -> void:
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.15, 0.85)
	sb.border_color = Color("FF3EA5")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	_title.text = "MUTATION ROLL"
	_style(_title, 34, Color("2EE6E6"))
	v.add_child(_title)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	for i in 3:
		var cell := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.95, 0.92, 0.85)
		cs.set_corner_radius_all(6)
		cs.set_content_margin_all(10)
		cell.add_theme_stylebox_override("panel", cs)
		cell.custom_minimum_size = Vector2(170, 70)
		var reel := Label.new()
		reel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		reel.add_theme_font_size_override("font_size", 26)
		cell.add_child(reel)
		h.add_child(cell)
		_reels.append(reel)
	_style(_status, 20, Color(1, 1, 0.85))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	v.add_child(_status)


func _style(l: Label, size: int, color: Color) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)


func _process(delta: float) -> void:
	_clock += delta
	if _hide_at > 0.0 and _clock >= _hide_at:
		_panel.visible = false
		_hide_at = -1.0
	if not _panel.visible:
		return
	_spin_t += delta
	if _spin_t >= SPIN_STEP:
		_spin_t = 0.0
		for i in 3:
			if _spinning[i]:
				if _targets[i] != "" and _clock >= _stop_at[i]:
					_spinning[i] = false
					_show(i, _targets[i])
				else:
					_show(i, _table.entries[randi() % _table.entries.size()].id)


func _show(i: int, id: String) -> void:
	var e := _table.get_entry(id)
	_reels[i].text = e.display_name.to_upper()
	_reels[i].add_theme_color_override("font_color", e.color.darkened(0.35))


func _on_started() -> void:
	_panel.visible = true
	_hide_at = -1.0
	_title.text = "MUTATION ROLL"
	_targets = ["", "", ""]
	_spinning = [true, true, true]


func _on_pulls(pulled: int, needed: int) -> void:
	_status.text = "PULL THE LEVER [E]   %d / %d" % [pulled, needed]


func _on_result(symbols: Array, _mutations: Array, jackpot: bool) -> void:
	_targets = symbols.duplicate()
	_spinning = [true, true, true]
	for i in 3:
		_stop_at[i] = _clock + 0.8 + i * 0.7
	_status.text = "..."
	if jackpot:
		_title.text = "JACKPOT!"


func _on_vote(options: Array) -> void:
	var a := _table.get_entry(options[0])
	var b := _table.get_entry(options[1])
	_status.text = "Two mutations stack! Vote to CANCEL one:\n[1] %s    [2] %s" % [a.display_name.to_upper(), b.display_name.to_upper()]


func _on_final(active: Array) -> void:
	if active.is_empty():
		_panel.visible = false
		return
	var lines := active.map(func(id): var e := _table.get_entry(id); return "%s: %s" % [e.display_name.to_upper(), e.description])
	_status.text = "\n".join(lines)
	_hide_at = _clock + 3.0
