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
	SWARM: "SLEET PACKS",
	HEAVY_WEATHER: "LIGHTNING / THUNDERHEADS",
}
## First group in each combat phase. Remaining groups draw from the mixes.
const DRIZZLE_OPENERS := [
	[Kind.DRIP, Kind.DRIP, Kind.GUTTER, Kind.DRIP],
	[Kind.MISTER, Kind.DRIP, Kind.GUTTER, Kind.DRIP],
	[Kind.HAILSTONE, Kind.DRIP, Kind.DRIP, Kind.MISTER],
	[Kind.STATIC, Kind.DRIP, Kind.MISTER, Kind.DRIP],
	[Kind.THUNDERHEAD, Kind.DRIP, Kind.STATIC, Kind.DRIP],
	[Kind.HAILSTONE, Kind.THUNDERHEAD, Kind.STATIC, Kind.SMOG],
]
const DOWNPOUR_OPENERS := [
	[Kind.SLEET, Kind.SLEET, Kind.SLEET, Kind.GUTTER],
	[Kind.HAILSTONE, Kind.GUTTER, Kind.DRIP, Kind.MISTER],
	[Kind.UNDERTOW, Kind.UNDERTOW, Kind.GUTTER, Kind.HAILSTONE],
	[Kind.SMOG, Kind.SLEET, Kind.SLEET, Kind.SLEET, Kind.SLEET, Kind.STATIC],
	[Kind.THUNDERHEAD, Kind.HAILSTONE, Kind.SMOG, Kind.UNDERTOW, Kind.STATIC],
	[Kind.THUNDERHEAD, Kind.UNDERTOW, Kind.SMOG, Kind.SLEET, Kind.SLEET, Kind.SLEET, Kind.STATIC],
]
const DRIZZLE_MIX := [
	[9, 3, 0, 0, 0, 0, 0, 0, 0],
	[8, 3, 2, 2, 0, 0, 0, 0, 0],
	[7, 2, 2, 2, 2, 0, 0, 0, 0],
	[6, 2, 2, 4, 2, 1, 2, 0, 0],
	[6, 2, 2, 3, 2, 1, 2, 2, 3],
	[5, 2, 2, 3, 3, 3, 3, 3, 3],
]
const DOWNPOUR_MIX := [
	[8, 3, 0, 3, 0, 0, 0, 0, 0],
	[7, 3, 2, 3, 3, 0, 0, 0, 0],
	[6, 3, 2, 2, 3, 5, 0, 0, 0],
	[5, 2, 2, 5, 2, 2, 3, 3, 0],
	[5, 2, 2, 3, 2, 2, 3, 3, 5],
	[4, 2, 2, 4, 3, 3, 4, 4, 5],
]


static func modifier(wave: int) -> String:
	if wave <= MODIFIERS.size():
		return MODIFIERS[maxi(0, wave - 1)]
	return ENDLESS_MODIFIERS[(wave - MODIFIERS.size() - 1) % ENDLESS_MODIFIERS.size()]


static func opener(wave: int, downpour: bool) -> Array:
	var groups := DOWNPOUR_OPENERS if downpour else DRIZZLE_OPENERS
	return groups[clampi(wave - 1, 0, groups.size() - 1)].duplicate()


static func weights(wave: int, downpour: bool) -> Array:
	var mixes := DOWNPOUR_MIX if downpour else DRIZZLE_MIX
	var mix: Array = mixes[clampi(wave - 1, 0, mixes.size() - 1)].duplicate()
	match modifier(wave):
		SWARM:
			mix[Kind.SLEET] += 6
		FLOOD:
			if downpour or wave > 5:
				mix[Kind.UNDERTOW] += 4
		HEAVY_WEATHER:
			mix[Kind.THUNDERHEAD] += 3
	return mix
