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
@export var airdrop_weapons: Array[String] = []
@export var airdrop_supplies: Array[String] = []
@export_range(0.0, 1.0, 0.01) var airdrop_cursed_chance := 0.0
@export_range(0.0, 1.0, 0.01) var airdrop_legendary_chance := 0.0

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

func roll_airdrop_weapon() -> String:
	var roll := RNG.rng.randf()
	if roll < airdrop_legendary_chance:
		return "disruptor"
	var weapons := cursed_items if roll < airdrop_legendary_chance + airdrop_cursed_chance else airdrop_weapons
	return weapons[RNG.rng.randi_range(0, weapons.size() - 1)]

func display_name(id: String) -> String:
	var item := ItemCatalog.definition(id)
	if item:
		return item.display_name.to_upper()
	return {"ammo_box": "AMMO BOX", "tarp": "TARP", "decon": "DECON CHARGE"}.get(id, id.to_upper())
