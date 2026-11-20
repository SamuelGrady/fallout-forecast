class_name ItemInstance
extends RefCounted

var serial: int
var id: String
var tier: int
var count: int
## Host clock only. It follows the gun when it changes hands.
var jam_until := 0.0

func _init(instance_id: int, definition_id: String, rarity: int, rounds_or_stack: int) -> void:
	serial = instance_id
	id = definition_id
	tier = rarity
	count = rounds_or_stack

func encode() -> Array:
	return [serial, id, tier, count]

static func decode(row: Array) -> ItemInstance:
	return null if row.is_empty() else ItemInstance.new(row[0], row[1], row[2], row[3])
