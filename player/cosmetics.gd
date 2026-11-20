class_name Cosmetics
extends RefCounted
## The survivor's look: a suit colour and a skin, both stored as small ints so
## they travel cheaply in Net.roster ({"color": int, "skin": int}).
## PlayerModel draws them; the lobby and title pickers choose them.

## Curated 80s palette, picked to read against the wet, dark map.
const COLORS := [
	Color(1.0, 0.85, 0.2),  # hazmat yellow (the old default)
	Color("#2ec9c9"),  # teal
	Color("#ff4fa3"),  # hot pink
	Color("#9be04a"),  # lime
	Color("#ff8a2a"),  # orange
	Color("#9a6bff"),  # purple
	Color("#e6e9ec"),  # white
	Color("#e8423a"),  # red
	Color("#3d7bff"),  # storm blue (feat: Silver Lining)
	Color("#b5653a"),  # rust (feat: Triple Feature)
]
const COLOR_NAMES := ["HAZMAT YELLOW", "TEAL", "HOT PINK", "LIME", "ORANGE", "PURPLE", "WHITE", "RED", "STORM BLUE", "RUST"]

const SKINS := ["STANDARD", "GAS MASK", "FIREFIGHTER", "BIO-TECH", "ION RIG"]


static func color(index: int) -> Color:
	return COLORS[posmod(index, COLORS.size())]


static func skin_name(index: int) -> String:
	return SKINS[wrap_skin(index)]


static func wrap_skin(index: int) -> int:
	return posmod(index, SKINS.size())


## The wanted colour if nobody else wears it, else the next free one along the
## palette. `taken` holds colour indices other players already wear. A
## non-empty `allowed` limits the pick to colours that player has unlocked
## (Feats); the four free colours guarantee a full squad always fits.
static func free_color(wanted: int, taken: Array, allowed: Array = []) -> int:
	wanted = posmod(wanted, COLORS.size())
	for step in COLORS.size():
		var index := (wanted + step) % COLORS.size()
		if index not in taken and (allowed.is_empty() or index in allowed):
			return index
	return wanted
