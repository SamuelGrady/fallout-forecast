extends CanvasLayer
const SPIN_STEP := 0.12
var _panel := PanelContainer.new()
var _title := Label.new()
var _cards: Array[MutationCard] = []
var _lever := Button.new()
var _handle := GameIcon.new()
var _countdown := ProgressBar.new()
var _table: MutationTable
var _targets: Array = []
var _spinning := [false,false,false]
var _stop_at := [0.0,0.0,0.0]
var _clock := 0.0
var _spin_t := 0.0
var _hide_at := -1.0
var _options: Array = []
## How the roll works, then the result: the wave's mutation and your perk.
var _info := Label.new()
var _pull_wait := 0.0

func _ready() -> void:
	layer = 2
	_table = load("res://game/mutation_table.tres")
	_panel.theme = BroadcastUI.theme()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -370
	_panel.offset_right = 370
	_panel.offset_top = -270
	_panel.offset_bottom = 270
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	_panel.add_child(box)
	_title.text = "MUTATION"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size",32)
	box.add_child(_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation",14)
	box.add_child(row)
	for i in 3:
		var card := MutationCard.new()
		row.add_child(card)
		var index := i
		card.pressed.connect(func(): _vote(index))
		_cards.append(card)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 19)
	box.add_child(_info)
	_lever.custom_minimum_size = Vector2(260,65)
	_lever.text = "PULL"
	_lever.pressed.connect(GameManager.pull_lever)
	box.add_child(_lever)
	_handle.kind = "lever"
	_handle.position = Vector2(20,4)
	_handle.size = Vector2(56,56)
	_lever.add_child(_handle)
	_countdown.show_percentage = false
	_countdown.custom_minimum_size.y = 6
	_countdown.max_value = 1
	BroadcastUI.bar(_countdown,BroadcastUI.CYAN)
	box.add_child(_countdown)
	_panel.visible = false
	var roll := GameManager.mutations
	roll.roll_started.connect(_on_started)
	roll.pulls_changed.connect(_on_pulls)
	roll.roll_result.connect(_on_result)
	roll.vote_started.connect(_on_vote)
	roll.vote_cast.connect(_on_vote_cast)
	roll.mutations_changed.connect(_on_final)


func _exit_tree() -> void:
	var roll := GameManager.mutations
	if roll == null:
		return
	for pair in [
		[roll.roll_started, _on_started],
		[roll.pulls_changed, _on_pulls],
		[roll.roll_result, _on_result],
		[roll.vote_started, _on_vote],
		[roll.vote_cast, _on_vote_cast],
		[roll.mutations_changed, _on_final],
	]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])

func _input(event: InputEvent) -> void:
	if not _panel.visible or get_tree().paused:
		return
	if GameManager.mutations.stage == "pulling" and event.is_action_pressed("interact"):
		GameManager.pull_lever()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_clock += delta
	if _hide_at > 0 and _clock >= _hide_at:
		_panel.visible = false
		_hide_at = -1
	if not _panel.visible:
		return
	var roll := GameManager.mutations
	_countdown.value = roll._timer / (roll.VOTE_TIME if roll.stage == "voting" else roll.PULL_TIME)
	_countdown.visible = roll.stage in ["pulling","voting"]
	_lever.text = "[%s] PULL" % BroadcastUI.input_hint("interact")
	# Solo: one pull, made for you after a beat, so the roll just happens.
	if roll.stage == "pulling" and GameManager.is_solo() and not _lever.disabled:
		_pull_wait += delta
		if _pull_wait >= 0.9:
			GameManager.pull_lever()
	_spin_t += delta
	if _spin_t >= SPIN_STEP:
		_spin_t = 0
		if _spinning.has(true):
			Sound.play("reel_tick",-22)
		for i in 3:
			if _spinning[i]:
				if not _targets.is_empty() and _clock >= _stop_at[i]:
					_spinning[i] = false
					_cards[i].show_entry(_table.get_entry(_targets[i]),true)
					Sound.play("reel_land")
				else:
					_cards[i].show_entry(_table.entries.pick_random(),false)

func _on_started() -> void:
	_panel.visible = true
	BroadcastUI.reveal(_panel)
	_title.text = "MUTATION ROLL"
	_info.text = "Enemies mutate this wave - and YOUR SQUAD mutates permanently! Match 3 for a JACKPOT (2 player mutations, vote off 1 enemy mutation)."
	_pull_wait = 0.0
	_targets.clear()
	_options.clear()
	_spinning = [true,true,true]
	_hide_at = -1
	_handle.value = 0
	_lever.visible = true
	_lever.disabled = false
	for card in _cards:
		card.visible = true
		card.disabled = true
		card.canceled = false
		card.modulate = Color.WHITE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_lever.grab_focus()

func _on_pulls(pulled: int, _needed: int) -> void:
	if pulled > 0:
		Sound.play("lever")
		_handle.value = 1.0
		_lever.disabled = true

func _on_result(symbols: Array, _mutations: Array, jackpot: bool) -> void:
	_targets = symbols.duplicate()
	_spinning = [true,true,true]
	for i in 3:
		_stop_at[i] = _clock + .5 + i*.65
	_lever.visible = false
	_title.text = "JACKPOT" if jackpot else "MUTATION"

func _on_vote(options: Array) -> void:
	_panel.visible = true
	_lever.visible = false
	_spinning = [false,false,false]
	_options = options.duplicate()
	_title.text = "CANCEL ONE"
	_info.text = "JACKPOT: two enemy mutations landed. Vote which one to cancel (you keep 2 player mutations!)."
	_cards[2].visible = false
	for i in 2:
		_cards[i].show_entry(_table.get_entry(options[i]),true,BroadcastUI.input_hint("vote_%d" % (i+1)))
		_cards[i].disabled = false
	_cards[0].grab_focus()

func _vote(index: int) -> void:
	GameManager.mutations.vote(index)


func _on_vote_cast(index: int) -> void:
	if index >= 0 and index < _cards.size():
		_cards[index].cross_out()
	for card in _cards:
		card.disabled = true

func _on_final(active: Array) -> void:
	if active.is_empty():
		_panel.visible = false
		return
	_spinning = [false,false,false]
	_title.text = "MUTATION"
	if not _options.is_empty():
		for i in 2:
			if _options[i] not in active:
				_cards[i].cross_out()
	else:
		for i in 3:
			_cards[i].visible = i < active.size()
			if i < active.size():
				_cards[i].show_entry(_table.get_entry(active[i]),true)
	var lines := []
	for id in active:
		var entry := _table.get_entry(id)
		if entry:
			lines.append("ENEMIES: %s - %s" % [entry.display_name.to_upper(), entry.description])
	for pid in GameManager.mutations.last_player_mutations:
		if GameManager.PLAYER_MUTATIONS.has(pid):
			var info: Dictionary = GameManager.PLAYER_MUTATIONS[pid]
			lines.append("YOUR MUTATION: %s - %s" % [str(info.name), str(info.desc)])
	_info.text = "\n".join(PackedStringArray(lines))
	_hide_at = _clock + 4.5
	if MenuState.stack.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
