class_name LootTable
extends Resource
## LootTable.tres: what a mystery crate can hold. A crate rolls a tier by
## weight, then an item in that tier. Item ids are what Player.grant() takes:
## ammo, medkit, suit_patch, base_ammo, flares, tarp, decon, or
## "weapon:<res path to a WeaponData>".

@export var common_weight := 70.0
@export var rare_weight := 25.0
@export var cursed_weight := 5.0
@export var common_items: Array[String] = ["ammo", "medkit", "suit_patch", "base_ammo"]
@export var rare_items: Array[String] = ["flares", "tarp", "decon"]
@export var cursed_items: Array[String] = []
## Names shown on the crate's spin.
@export var display_names := {
	"ammo": "AMMO", "medkit": "MED KIT", "suit_patch": "SUIT PATCH", "base_ammo": "EXTRA SHELLS",
	"flares": "FLARE PACK", "tarp": "TARP", "decon": "DECON CHARGE",
}


func display_name(item: String) -> String:
	if item.begins_with("weapon:"):
		var w := load(item.trim_prefix("weapon:")) as WeaponData
		return w.display_name.to_upper() if w else "???"
	return display_names.get(item, item.to_upper())


func tier_of(item: String) -> String:
	if item in cursed_items:
		return "cursed"
	if item in rare_items:
		return "rare"
	return "common"
