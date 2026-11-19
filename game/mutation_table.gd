class_name MutationTable
extends Resource
## MutationTable.tres: every mutation the slot reel can land on, with weights.

@export var entries: Array[MutationData] = []


func get_entry(id: String) -> MutationData:
	for e in entries:
		if e.id == id:
			return e
	return null


func weights() -> Array:
	return entries.map(func(e): return e.weight)
