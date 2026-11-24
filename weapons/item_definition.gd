class_name ItemDefinition
extends Resource
## Immutable catalog entry. The host stores mutable state in ItemInstance.

enum Kind { GUN, THROWABLE, CONSUMABLE, DEPLOYABLE }

@export var id: String
@export var display_name: String
@export var kind: Kind
@export var icon: Texture2D
@export var pickup_visual: PackedScene
## Empty for items that are consumed after their last use, including disposable launchers.
@export var ammo_type: String
@export var stack_cap := 1
@export var spawn_count := 1
@export var weapon: WeaponData
@export var legendary := false

func is_cursed() -> bool:
	return weapon != null and weapon.cursed
