extends RefCounted
## IDs index both these weighted mixes and the spawner's wire roster.
enum Kind { DRIP, GUTTER, MISTER, SLEET, HAILSTONE, UNDERTOW, STATIC, SMOG, THUNDERHEAD }

const BLACKOUT := "BLACKOUT"
const FLOOD := "FLOOD"
const SWARM := "SWARM"
const HEAVY_WEATHER := "HEAVY WEATHER"

const MODIFIERS := ["", BLACKOUT, FLOOD, SWARM, HEAVY_WEATHER]
const ENDLESS_MODIFIERS := [HEAVY_WEATHER, FLOOD, BLACKOUT, SWARM]
const FORECAST := {
	BLACKOUT: "LOW LIGHT / DENSE FOG",
	FLOOD: "RISING WATER / UNDERTOW",
	SWARM: "DENSE INFECTED PACKS",
	HEAVY_WEATHER: "FREQUENT LIGHTNING",
}
const NORMAL_OPEN := [Kind.DRIP, Kind.GUTTER, Kind.DRIP]
const FLOOD_OPEN := [Kind.DRIP, Kind.UNDERTOW, Kind.DRIP]
const FORECAST_SPECIAL := {BLACKOUT: Kind.STATIC, SWARM: Kind.SLEET, HEAVY_WEATHER: Kind.THUNDERHEAD}
const DRAFT_COUNTERS := {
	BLACKOUT: ["reflex_tendons", "chitin_suit", "adrenaline_glands"],
	FLOOD: ["hydro_skin", "adrenaline_glands", "chitin_suit"],
	SWARM: ["bone_piercer", "reflex_tendons", "vampiric_siphon"],
	HEAVY_WEATHER: ["chitin_suit", "voltaic_veins", "adrenaline_glands"],
}
const FORECAST_MUTATION := {FLOOD: "undertow", SWARM: "swarm", HEAVY_WEATHER: "conductors"}

static func modifier(wave: int) -> String:
	if wave <= MODIFIERS.size():
		return MODIFIERS[maxi(0, wave - 1)]
	return ENDLESS_MODIFIERS[(wave - MODIFIERS.size() - 1) % ENDLESS_MODIFIERS.size()]


static func opener(wave: int, downpour: bool) -> Array:
	var forecast := modifier(wave)
	var group := (FLOOD_OPEN if forecast == FLOOD else NORMAL_OPEN).duplicate()
	if wave >= 2 and downpour:
		group.insert(1, Kind.HAILSTONE)
		if FORECAST_SPECIAL.has(forecast):
			group.append(FORECAST_SPECIAL[forecast])
	if wave >= 2:
		group.append(Kind.MISTER)
	return group


static func weights(wave: int, downpour: bool) -> Array:
	var forecast := modifier(wave)
	var flood := forecast == FLOOD
	var weights := [11 if forecast == SWARM else 8, 0 if flood else 3,
		2 if wave >= 2 else 0, 0, 0, 3 if flood else 0, 0, 0, 0]
	if wave >= 2 and downpour:
		weights[Kind.HAILSTONE] = 2 if wave == 2 else 3
	elif wave >= 3:
		weights[Kind.HAILSTONE] = 1
	if FORECAST_SPECIAL.has(forecast):
		weights[FORECAST_SPECIAL[forecast]] = 2 if downpour else 1
	if wave >= 4 and downpour:
		weights[Kind.SMOG] = 1
	return weights
