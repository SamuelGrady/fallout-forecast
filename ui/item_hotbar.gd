class_name ItemHotbar
extends Control
## Five item slots, bottom centre. No filled boxes: an outline on the selected
## cell, the item icon, the tier as a coloured underline, a count for
## consumables, and scrap as an icon + number at the right end. The Frag
## Grenade and Shield Dome belt pouches sit stacked above the scrap counter.

const FONT := preload("res://assets/fonts/VT323-Regular.ttf")
const CELL := Vector2(68, 64)
const GAP := 5
## Whole hotbar: 5 cells and 4 gaps (360 x 64 px in the 960x720 viewport).
const SIZE := Vector2(CELL.x * 5 + GAP * 4, CELL.y)
const INK := Color(0.047, 0.078, 0.133, 0.9)
## Pouch rows right of the slots: [key] icon count/cap.
const POUCHES := ["frag", "shield_dome"]
const POUCH_COLORS := {"frag": Color("#ff9f6b"), "shield_dome": Color("#7aeeff")}
const POUCH_ROW := 21.0
const POUCH_ICON := 18.0
const MUTED := Color("#728b92")
var _state: Array = []
var _flash := 0.0
var _pouch: Array = []
var _active_pouch := ""
var _pouch_flash: Dictionary = {"frag": 0.0, "shield_dome": 0.0}
var _scrap_icon := GameIcon.new()


func _ready() -> void:
	_scrap_icon.kind = "scrap"
	_scrap_icon.color = Color("#ffc365")
	_scrap_icon.size = Vector2(14, 14)
	_scrap_icon.position = Vector2(SIZE.x + 6, CELL.y - 18)
	add_child(_scrap_icon)


func refresh(holder: WeaponHolder) -> void:
	var data: Array = [holder.current, holder.scrap, holder.active_pouch]
	for item: ItemInstance in holder.slots:
		data.append([item.id, item.tier, item.count] if item else [])
	if _state != data:
		_state = data
		_active_pouch = holder.active_pouch
		queue_redraw()
	var pouch: Array = []
	for id: String in POUCHES:
		pouch.append(holder.pouch_count(id))
	if _pouch != pouch:
		if _pouch.size() == pouch.size():
			for i in POUCHES.size():
				if pouch[i] != _pouch[i]:
					_pouch_flash[POUCHES[i]] = 0.9 if pouch[i] > _pouch[i] else 0.35
		_pouch = pouch
		queue_redraw()


## Belt pouch counts, so the HUD can wake the hotbar when they change.
func pouch_key() -> Array:
	return _pouch


## Slot contents without the selection or scrap, so the HUD can tell a pickup
## or swap apart from ammo ticking down.
func state_key() -> Array:
	return _state.slice(3).map(func(item): return item.slice(0, 2) if item is Array and not item.is_empty() else [])


## Pulse the selected cell (unlocks, pickups).
func flash() -> void:
	_flash = 1.2


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()
	for id: String in POUCHES:
		if _pouch_flash[id] > 0.0:
			_pouch_flash[id] = maxf(0.0, _pouch_flash[id] - delta)
			queue_redraw()


func _draw() -> void:
	if _state.is_empty():
		return
	var scrap_text := str(_state[1])
	draw_string_outline(FONT, Vector2(SIZE.x + 24, CELL.y - 5), scrap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 3, INK)
	draw_string(FONT, Vector2(SIZE.x + 24, CELL.y - 5), scrap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#ffc365"))
	_draw_pouches()
	for i in WeaponHolder.SLOT_COUNT:
		var selected: bool = _active_pouch.is_empty() and _state[0] == i
		var at := Vector2(i * (CELL.x + GAP), -4.0 if selected else 0.0)
		var item: Array = _state[i + 3]
		var color := Color("#728b92") if item.is_empty() else ItemCatalog.tier_color(item[0], item[1])
		if selected:
			draw_rect(Rect2(at, CELL), Color(color, 0.14))
			var outline := Color("#ffc365").lerp(Color("#c7faff"), 1.0 - _flash / 1.2) if _flash > 0.0 else Color("#c7faff")
			draw_rect(Rect2(at, CELL), outline, false, 2.0)
		else:
			draw_rect(Rect2(at, CELL), Color(0.43, 0.54, 0.56, 0.28), false, 1.0)
		draw_string_outline(FONT, at + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, INK)
		draw_string(FONT, at + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.91, 0.91, 0.84, 0.75 if selected else 0.4))
		if item.is_empty():
			draw_rect(Rect2(at + Vector2(28, 30), Vector2(12, 2)), Color(color, 0.5))
			continue
		draw_rect(Rect2(at + Vector2(6, CELL.y - 5), Vector2(CELL.x - 12, 2)), color)
		var definition := ItemCatalog.definition(item[0])
		var alpha := 1.0 if selected else 0.7
		if selected:
			var hint := "%s DROP" % BroadcastUI.input_hint("drop_item")
			var hint_at := at + Vector2(0, -5)
			draw_string_outline(FONT, hint_at, hint, HORIZONTAL_ALIGNMENT_CENTER, CELL.x, 15, 3, INK)
			draw_string(FONT, hint_at, hint, HORIZONTAL_ALIGNMENT_CENTER, CELL.x, 15, Color("#c7faff"))
		if definition.icon:
			draw_texture_rect(definition.icon, Rect2(at + Vector2(14, 8), Vector2(40, 40)), false, Color(1, 1, 1, alpha))
		else:
			var initials := ""
			for word in definition.display_name.split(" "):
				initials += word.left(1)
			draw_string(FONT, at + Vector2(15, 36), initials.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 38, 22, Color(color, alpha))
		if definition.kind != ItemDefinition.Kind.GUN:
			draw_string_outline(FONT, at + Vector2(CELL.x - 28, CELL.y - 10), str(item[2]), HORIZONTAL_ALIGNMENT_RIGHT, 22, 18, 3, INK)
			draw_string(FONT, at + Vector2(CELL.x - 28, CELL.y - 10), str(item[2]), HORIZONTAL_ALIGNMENT_RIGHT, 22, 18, color)


func _draw_pouches() -> void:
	if _pouch.size() != POUCHES.size():
		return
	for i in POUCHES.size():
		var id: String = POUCHES[i]
		var count: int = _pouch[i]
		var cap := ItemCatalog.pouch_cap(id)
		var stocked := count > 0
		var held := _active_pouch == id
		var pulse: float = _pouch_flash[id]
		var accent: Color = POUCH_COLORS[id]
		var color := accent.lerp(Color.WHITE, clampf(pulse, 0.0, 1.0) * 0.6) if stocked else MUTED
		var alpha := 1.0 if stocked else 0.45
		var x := SIZE.x + 6.0
		var y := i * POUCH_ROW
		if held:
			var row_rect := Rect2(Vector2(x - 3.0, y), Vector2(78.0, POUCH_ROW - 1.0))
			draw_rect(row_rect, Color(accent, 0.18))
			draw_rect(row_rect, Color("#c7faff"), false, 1.5)
		var key := BroadcastUI.input_hint(ItemCatalog.POUCH_ACTIONS[id])
		var key_w := FONT.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(FONT, Vector2(x, y + 15), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, INK)
		draw_string(FONT, Vector2(x, y + 15), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#c7faff") if held else Color(0.91, 0.91, 0.84, 0.85 if stocked else 0.4))
		x += key_w + 3.0
		var icon_rect := Rect2(Vector2(x, y + (POUCH_ROW - POUCH_ICON) * 0.5 - 1.0), Vector2.ONE * POUCH_ICON)
		if pulse > 0.0:
			draw_rect(icon_rect.grow(2.0), Color(accent, 0.35 * clampf(pulse, 0.0, 1.0)), false, 1.5)
		var definition := ItemCatalog.definition(id)
		if definition and definition.icon:
			draw_texture_rect(definition.icon, icon_rect, false, Color(1, 1, 1, alpha) if stocked else Color(0.6, 0.66, 0.68, alpha))
		else:
			draw_rect(icon_rect.grow(-4.0), Color(color, alpha))
		x += POUCH_ICON + 3.0
		var count_text := str(count)
		draw_string_outline(FONT, Vector2(x, y + 16), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, INK)
		draw_string(FONT, Vector2(x, y + 16), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
		x += FONT.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var cap_text := "/%d" % cap
		draw_string_outline(FONT, Vector2(x, y + 16), cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, INK)
		draw_string(FONT, Vector2(x, y + 16), cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(MUTED, 0.9 if stocked else 0.5))
