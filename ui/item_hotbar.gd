class_name ItemHotbar
extends Control

const FONT := preload("res://assets/fonts/VT323-Regular.ttf")
const CELL := Vector2(61, 66)
const GAP := 5
var _state: Array = []

func refresh(holder: WeaponHolder) -> void:
	var data: Array = [holder.current, holder.scrap]
	for item: ItemInstance in holder.slots:
		data.append([item.id, item.tier, item.count] if item else [])
	if _state != data:
		_state = data
		queue_redraw()

func _draw() -> void:
	if _state.is_empty():
		return
	var scrap_text := "%d SCRAP" % _state[1]
	draw_string(FONT, Vector2(0, -5), scrap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#ffc365"))
	for i in WeaponHolder.SLOT_COUNT:
		var at := Vector2(i * (CELL.x + GAP), 0)
		var selected: bool = _state[0] == i
		var item: Array = _state[i + 2]
		var color := Color("#728b92") if item.is_empty() else ItemCatalog.tier_color(item[0], item[1])
		draw_rect(Rect2(at, CELL), Color("#203647f5") if selected else Color("#101c25de"))
		draw_rect(Rect2(at, CELL), Color("#c7faff") if selected else Color("#6d899089"), false, 2.0 if selected else 1.0)
		draw_rect(Rect2(at + Vector2(2, CELL.y - 4), Vector2(CELL.x - 4, 3)), color)
		draw_string(FONT, at + Vector2(5, 16), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
		if item.is_empty():
			draw_rect(Rect2(at + Vector2(25, 29), Vector2(11, 2)), color)
			continue
		var definition := ItemCatalog.definition(item[0])
		if definition.icon:
			draw_texture_rect(definition.icon, Rect2(at + Vector2(13, 6), Vector2(36, 36)), false)
		else:
			var initials := ""
			for word in definition.display_name.split(" "):
				initials += word.left(1)
			draw_rect(Rect2(at + Vector2(17, 12), Vector2(29, 25)), Color(color, 0.15))
			draw_string(FONT, at + Vector2(12, 31), initials.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 37, 20, color)
		if definition.kind != ItemDefinition.Kind.GUN:
			draw_string(FONT, at + Vector2(37, 35), str(item[2]), HORIZONTAL_ALIGNMENT_RIGHT, 20, 18, color)
		draw_string(FONT, at + Vector2(2, 55), ItemCatalog.tier_name(item[0], item[1]),
			HORIZONTAL_ALIGNMENT_CENTER, CELL.x - 4, 11, color)
