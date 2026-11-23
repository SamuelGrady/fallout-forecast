class_name LootTable
extends Resource

@export var common_weight := 69.0
@export var rare_weight := 25.0
@export var cursed_weight := 5.0
@export var legendary_weight := 1.0
@export var common_items: Array[String] = ["ammo_box", "med_tin", "suit_patch", "sandbag", "nail_driver", "rock_salt", "pump_shotgun"]
@export var rare_items: Array[String] = ["tarp", "decon", "hunting_rifle", "pressure_washer", "battery_zapper",
	"flare_launcher", "harpoon", "leaf_blower", "umbrella", "lightning_rod", "bleach_bomb", "bait_radio"]
@export var cursed_items: Array[String] = ["leaky_nailgun", "boombox_launcher", "lucky_penny_revolver"]
## Between-wave airdrops scale by the wave they land before:
## 0 Surplus (wave 2), 1 Tuned (wave 3), 2 Overclocked (wave 4), 3 Apex (wave 5+ / Endless).
@export var airdrop_basic_weapons: Array[String] = []
@export var airdrop_weapons: Array[String] = []
@export var airdrop_supplies_surplus: Array[String] = []
@export var airdrop_supplies_tuned: Array[String] = []
@export var airdrop_supplies_overclocked: Array[String] = []
@export var airdrop_supplies_apex: Array[String] = []
@export var airdrop_cursed_chances: PackedFloat32Array = PackedFloat32Array([0.0, 0.1, 0.22, 0.35])
@export var airdrop_legendary_chances: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.1, 0.25])

static func airdrop_grade(wave: int) -> int:
	return clampi(wave - 2, 0, 3)

func airdrop_tier(wave: int) -> int:
	return [ItemCatalog.STANDARD, ItemCatalog.TUNED, ItemCatalog.OVERCLOCKED, ItemCatalog.OVERCLOCKED][airdrop_grade(wave)]

## Squad-wide bonus weapons on top of one per player.
func airdrop_bonus_weapons(wave: int) -> int:
	return 1 if airdrop_grade(wave) >= 3 else 0

func airdrop_supplies(wave: int) -> Array[String]:
	var lists: Array = [airdrop_supplies_surplus, airdrop_supplies_tuned, airdrop_supplies_overclocked, airdrop_supplies_apex]
	var result: Array[String] = []
	result.assign(lists[airdrop_grade(wave)])
	return result

func pool(tier: int, wave: int) -> Array[String]:
	var items: Array[String] = []
	match tier:
		0:
			items.assign(common_items)
			if wave >= 2:
				items.append("spray_rifle")
		1:
			items.assign(rare_items)
			if wave >= 3:
				items.append_array(["shield_dome", "frag"])
		2:
			items.assign(cursed_items)
		3:
			items.append("disruptor")
	return items

func roll_airdrop_weapon(wave: int) -> String:
	var grade := airdrop_grade(wave)
	var legendary: float = airdrop_legendary_chances[grade] if grade < airdrop_legendary_chances.size() else 0.0
	var cursed: float = airdrop_cursed_chances[grade] if grade < airdrop_cursed_chances.size() else 0.0
	var roll := RNG.rng.randf()
	if roll < legendary:
		return "disruptor"
	var weapons := airdrop_basic_weapons if grade == 0 else airdrop_weapons
	if roll < legendary + cursed:
		weapons = cursed_items
	return weapons[RNG.rng.randi_range(0, weapons.size() - 1)]

func display_name(id: String) -> String:
	var item := ItemCatalog.definition(id)
	if item:
		return item.display_name.to_upper()
	return {"ammo_box": "AMMO BOX", "tarp": "TARP", "decon": "DECON CHARGE"}.get(id, id.to_upper())
