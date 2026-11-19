extends Node
## Autoload "RNG": the host's weighted rolls (loot, mutations). Every roll goes
## through here so results come from one place and can be shown to everyone.

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


## Index of the picked weight.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1


func chance(p: float) -> bool:
	return rng.randf() < p
