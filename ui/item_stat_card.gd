class_name ItemStatCard
extends PanelContainer
## Shared VHS broadcast item stats card: the Field Kit starter picker, the
## Inventory inspector and the HUD vending / ground pickup readout all build
## from this one component and its static helpers, so every screen reads the
## same copy, colors, bar thickness and stat scaling.
##
## Build once with ItemStatCard.new(layout, compact), then call set_item()
## (or configure()) whenever the item changes. Nodes are created up front and
## only their text / values change, so updating never churns the scene tree.
##
## opts / info keys (all optional):
##   badge: String       custom header badge text (starter picker key hint)
##   source: String      "vending", "pickup" or "inventory" footer context
##   count: int          loaded rounds (guns) or stack size (everything else)
##   reserve, reserve_cap: int   carried reserve ammo (inventory guns)
##   price: int, affordable: bool, pouch_full: bool, swap: bool
##   max_power, max_rate, max_mag: float   custom gun bar normalization

enum Layout { TALL, ROW }

const AMMO_BOX := "ammo_box"
const STAT_ROWS := 3
## HUD overlay width (compact mode).
const COMPACT_WIDTH := 236.0
const BAR_HEIGHT := 8
const STAT_FONT := 16
const SUPPLY_TINT := BroadcastUI.CYAN
const CURSED_TINT := Color("#ff8fc8")
const EMPTY_TEXT := "EMPTY SLOT — PICK UP GEAR OR BUY AT A STATION"

const TAGLINES := {
	"service_revolver": "Heavy high-impact sidearm",
	"pump_shotgun": "Close-range buckshot burst",
	"spray_rifle": "Full-auto mid-range spray",
	"nail_driver": "Fast-firing precision nails",
	"hunting_rifle": "Long-range piercing shots",
	"pressure_washer": "Blasts foes, rinses acid",
	"rock_salt": "Twin-shell stagger blast",
	"battery_zapper": "Arcs jump between targets",
	"flare_launcher": "Lobs flares that burn",
	"harpoon": "Spears and reels foes in",
	"leaf_blower": "Gusts the infected back",
	"disruptor": "Charged jammer bolt",
	"leaky_nailgun": "Piercing nails, leaky suit",
	"boombox_launcher": "Rockets that drag foes in",
	"lucky_penny_revolver": "Lucky kills, random jams",
	"frag": "Belt grenade, big blast",
	"shield_dome": "Belt dome shelters squad",
	"umbrella": "Plants a rain canopy",
	"bleach_bomb": "Scours infected in a cloud",
	"bait_radio": "Noise lure pulls the horde",
	"sandbag": "Drops waist-high cover",
	"lightning_rod": "Calls strikes to a spike",
	"med_tin": "Restores health when hurt",
	"suit_patch": "Repairs a torn suit",
	AMMO_BOX: "Refills reserve ammo for all carried weapons",
}

const ROLE_TAGS := {
	"service_revolver": "SIDEARM",
	"pump_shotgun": "SHOTGUN",
	"spray_rifle": "AUTO RIFLE",
	"nail_driver": "AUTO NAILER",
	"hunting_rifle": "RIFLE",
	"pressure_washer": "SPECIAL",
	"rock_salt": "SHOTGUN",
	"battery_zapper": "SPECIAL",
	"flare_launcher": "LAUNCHER",
	"harpoon": "SPECIAL",
	"leaf_blower": "SPECIAL",
	"disruptor": "SPECIAL",
	"leaky_nailgun": "AUTO NAILER",
	"boombox_launcher": "LAUNCHER",
	"lucky_penny_revolver": "SIDEARM",
	AMMO_BOX: "SUPPLY",
}

const MECHANIC_TRAITS := {
	"pin": "WALL PIN",
	"salt": "STAGGER",
	"zap": "CHAIN ARC",
	"reel": "REEL PULL",
	"wash": "CLEARS ACID",
	"gust": "KNOCKBACK",
	"burn": "BURN",
	"suppress": "SUPPRESS",
}

## Non-gun bar maxima (damage, radius in m, duration in s).
const ITEM_MAX_DAMAGE := 150.0
const ITEM_MAX_RADIUS := 8.0
const ITEM_MAX_TIME := 60.0

static var _gun_maxima: Dictionary = {}

var layout := Layout.TALL
var compact := false
var item_id := ""
var item_tier := 0

## Exposed so the starter picker can restyle focus / confirm states.
var content: VBoxContainer
var badge: PanelContainer
var badge_label: Label
var role_label: Label
var icon_well: PanelContainer
var name_label: Label
var tagline_label: Label
var trait_label: Label

var _header: HBoxContainer
var _icon_tex: TextureRect
var _icon_glyph: GameIcon
var _icon_fallback: Label
var _divider: ColorRect
var _rows: Array[Dictionary] = []
var _footer: HBoxContainer
var _meta_label: Label
var _price_pill: PanelContainer
var _price_label: Label
var _empty_label: Label
var _item_nodes: Array[Control] = []


func _init(card_layout := Layout.TALL, is_compact := false) -> void:
	layout = card_layout
	compact = is_compact
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if compact:
		custom_minimum_size.x = COMPACT_WIDTH
	_build()
	clear()


# ------------------------------------------------------------------ static metadata
static func tagline(id: String) -> String:
	return str(TAGLINES.get(id, ""))


static func role_tag(id: String) -> String:
	if ROLE_TAGS.has(id):
		return str(ROLE_TAGS[id])
	var definition := ItemCatalog.definition(id)
	if definition == null:
		return "ITEM"
	match definition.kind:
		ItemDefinition.Kind.THROWABLE:
			return "THROWABLE"
		ItemDefinition.Kind.DEPLOYABLE:
			return "DEPLOYABLE"
		ItemDefinition.Kind.CONSUMABLE:
			return "CONSUMABLE"
	return "WEAPON"


static func display_name(id: String) -> String:
	if id == AMMO_BOX:
		return "AMMO REFILL"
	var definition := ItemCatalog.definition(id)
	return (definition.display_name if definition else id.replace("_", " ")).to_upper()


static func badge_text(id: String, tier: int) -> String:
	if id == AMMO_BOX or ItemCatalog.definition(id) == null:
		return "SUPPLY"
	return ItemCatalog.tier_name(id, clampi(tier, 0, ItemCatalog.TIER_NAMES.size() - 1))


## Trim / badge color: tier tint, amber for legendary, cyan for supplies.
static func accent_color(id: String, tier: int) -> Color:
	var definition := ItemCatalog.definition(id)
	if definition == null:
		return SUPPLY_TINT
	if definition.legendary:
		return BroadcastUI.AMBER
	return ItemCatalog.tier_color(id, clampi(tier, 0, ItemCatalog.TIER_COLORS.size() - 1))


## Name tint: paper for standard gear, the tier tint for anything rarer.
static func name_color(id: String, tier: int) -> Color:
	var definition := ItemCatalog.definition(id)
	if definition == null or (tier <= 0 and not definition.is_cursed() and not definition.legendary):
		return BroadcastUI.PAPER
	return accent_color(id, tier)


## Raw gun numbers with the tier damage scale applied.
static func gun_numbers(data: WeaponData, tier := 0) -> Dictionary:
	var scale := float(ItemCatalog.DAMAGE_SCALE[clampi(tier, 0, ItemCatalog.DAMAGE_SCALE.size() - 1)])
	var pellets := maxi(1, data.pellets)
	var damage := data.damage * scale
	return {
		"damage": damage,
		"pellets": pellets,
		"power": damage * float(pellets),
		"rate": 1.0 / maxf(data.fire_interval, 0.01),
		"mag": maxi(1, data.mag_size),
	}


## Bar maxima across `ids` (all guns by default, at the top tier) so cards
## compare apples to apples. The starter picker passes its three kits.
static func gun_maxima(ids: Array = [], tier := -1) -> Dictionary:
	var everything := ids.is_empty()
	if everything and not _gun_maxima.is_empty():
		return _gun_maxima
	if everything:
		ids = ItemCatalog.GUNS.keys()
	var top := ItemCatalog.DAMAGE_SCALE.size() - 1 if tier < 0 else tier
	var result := {"max_power": 1.0, "max_rate": 0.1, "max_mag": 1.0}
	for id in ids:
		var definition := ItemCatalog.definition(str(id))
		if definition == null or definition.weapon == null or definition.kind != ItemDefinition.Kind.GUN:
			continue
		var numbers := gun_numbers(definition.weapon, top)
		result.max_power = maxf(result.max_power, numbers.power)
		result.max_rate = maxf(result.max_rate, numbers.rate)
		result.max_mag = maxf(result.max_mag, float(numbers.mag))
	if everything:
		_gun_maxima = result
	return result


## The bar rows for an item: [[name, ratio, value_text, color], ...].
static func stat_rows(id: String, tier := 0, opts := {}) -> Array:
	if id == AMMO_BOX:
		return [["FILL", 1.0, "100%", BroadcastUI.AMBER], ["SCOPE", 1.0, "ALL", BroadcastUI.CYAN]]
	var definition := ItemCatalog.definition(id)
	if definition == null or definition.weapon == null:
		return []
	var data := definition.weapon
	if definition.kind == ItemDefinition.Kind.GUN:
		var maxima := gun_maxima()
		var max_power := float(opts.get("max_power", maxima.max_power))
		var max_rate := float(opts.get("max_rate", maxima.max_rate))
		var max_mag := float(opts.get("max_mag", maxima.max_mag))
		var n := gun_numbers(data, tier)
		var dmg_text := "%dx%d" % [roundi(n.damage), n.pellets] if n.pellets > 1 else "%d" % roundi(n.damage)
		return [
			["DMG", clampf(sqrt(n.power / maxf(max_power, 0.01)), 0.14, 1.0), dmg_text, BroadcastUI.AMBER],
			["RATE", clampf(sqrt(n.rate / maxf(max_rate, 0.01)), 0.14, 1.0), "%.1f/S" % n.rate, BroadcastUI.CYAN],
			["MAG", clampf(float(n.mag) / maxf(max_mag, 1.0), 0.14, 1.0), "%d" % n.mag, BroadcastUI.ACID],
		]
	var rows: Array = []
	match id:
		"med_tin":
			rows.append(["HEAL", clampf(data.damage / 100.0, 0.14, 1.0), "%d" % roundi(data.damage), BroadcastUI.PINK])
		"suit_patch":
			rows.append(["SUIT", clampf(data.damage / 100.0, 0.14, 1.0), "%d%%" % roundi(data.damage), BroadcastUI.CYAN])
		"shield_dome", "umbrella", "sandbag":
			var cover := data.effect_radius
			rows.append(["COVER", clampf(cover / ITEM_MAX_RADIUS, 0.14, 1.0) if cover > 0.0 else 0.5,
				"%.1fM" % cover if cover > 0.0 else "WALL", BroadcastUI.CYAN])
			rows.append(["DUR", clampf(data.effect_time / ITEM_MAX_TIME, 0.14, 1.0), "%dS" % roundi(data.effect_time), BroadcastUI.AMBER])
		"bait_radio":
			rows.append(["LURE", clampf(data.effect_radius / ITEM_MAX_RADIUS, 0.14, 1.0), "%dM" % roundi(data.effect_radius), BroadcastUI.CYAN])
			rows.append(["DUR", clampf(data.effect_time / ITEM_MAX_TIME, 0.14, 1.0), "%dS" % roundi(data.effect_time), BroadcastUI.AMBER])
		_:
			rows.append(["DMG", clampf(sqrt(data.damage / ITEM_MAX_DAMAGE), 0.14, 1.0), "%d" % roundi(data.damage), BroadcastUI.AMBER])
			rows.append(["RAD", clampf(data.effect_radius / ITEM_MAX_RADIUS, 0.14, 1.0), "%.1fM" % data.effect_radius, BroadcastUI.CYAN])
	var cap := ItemCatalog.pouch_cap(id) if ItemCatalog.is_pouch(id) else definition.stack_cap
	var count := int(opts.get("count", definition.spawn_count))
	rows.append(["STACK", clampf(float(count) / maxf(float(cap), 1.0), 0.14, 1.0), "%d/%d" % [count, cap], BroadcastUI.ACID])
	return rows.slice(0, STAT_ROWS)


## Compact mechanics line under the bars ("PIERCE 3  /  REEL PULL").
static func traits(id: String) -> String:
	var definition := ItemCatalog.definition(id)
	if definition == null or definition.weapon == null:
		return ""
	var data := definition.weapon
	var parts := PackedStringArray()
	if definition.is_cursed():
		parts.append("CURSED")
	if definition.kind == ItemDefinition.Kind.GUN:
		if data.charge_time > 0.0:
			parts.append("CHARGE")
		if MECHANIC_TRAITS.has(data.mechanic):
			parts.append(MECHANIC_TRAITS[data.mechanic])
		if data.pierce > 0:
			parts.append("PIERCE %d" % data.pierce)
		if data.critical_bonus > 1.0:
			parts.append("CRIT x%.1f" % data.critical_bonus)
		if data.pull_radius > 0.0:
			parts.append("PULL")
		if data.held_suit_drain > 0.0:
			parts.append("SUIT DRAIN")
		if data.lucky_kill_chance > 0.0:
			parts.append("%d%% LUCKY" % roundi(data.lucky_kill_chance * 100.0))
		if data.jam_chance > 0.0:
			parts.append("%d%% JAM" % roundi(data.jam_chance * 100.0))
		if data.shell_reload:
			parts.append("SHELL LOAD")
		elif data.automatic and parts.size() < 2:
			parts.append("FULL AUTO")
	elif ItemCatalog.is_pouch(id):
		parts.append("BELT POUCH [%s]" % BroadcastUI.input_hint(str(ItemCatalog.POUCH_ACTIONS.get(id, "use_item"))))
	return "  /  ".join(parts.slice(0, 3))


## One labelled thin bar row, identical on every screen.
static func build_stat_row(parent: Control, stat_name: String, ratio: float, value_text: String, color: Color, font_size := STAT_FONT) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = stat_name
	lbl.custom_minimum_size = Vector2(40, 0)
	BroadcastUI.text(lbl, font_size, BroadcastUI.MUTED)
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = ratio
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BroadcastUI.thin_bar(bar, color)
	row.add_child(bar)

	var val := Label.new()
	val.text = value_text
	val.custom_minimum_size = Vector2(42, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	BroadcastUI.text(val, font_size, BroadcastUI.PAPER)
	row.add_child(val)
	return {"row": row, "label": lbl, "bar": bar, "value": val}


static func apply_stat_row(parts: Dictionary, stat_name: String, ratio: float, value_text: String, color: Color) -> void:
	parts.label.text = stat_name
	parts.bar.value = ratio
	parts.value.text = value_text
	var fill := parts.bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill == null or fill.bg_color != color:
		BroadcastUI.thin_bar(parts.bar, color)
	parts.row.visible = true


static func card_style(accent: Color, is_compact := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.055, 0.09, 0.9) if is_compact else Color(0.05, 0.085, 0.135, 0.92)
	style.border_color = accent
	style.border_width_left = 3
	style.border_width_top = 3
	var pad := 8 if is_compact else 10
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad - 3
	style.content_margin_bottom = pad - 2
	return style


static func badge_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


static func icon_well_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.07, 0.78)
	style.border_color = Color(BroadcastUI.MUTED, 0.18)
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	return style


# ------------------------------------------------------------------ public API
## Accepts a targeted_item_info()-style dictionary ({id, tier, ...opts}).
func configure(info: Dictionary) -> void:
	var id := str(info.get("id", ""))
	if id.is_empty():
		clear()
		return
	set_item(id, int(info.get("tier", 0)), info)


func set_item(id: String, tier := 0, opts := {}) -> void:
	item_id = id
	item_tier = tier
	var definition := ItemCatalog.definition(id)
	if definition == null and id != AMMO_BOX:
		clear("UNKNOWN ITEM")
		return
	for node in _item_nodes:
		node.visible = true
	_empty_label.visible = false
	var accent := accent_color(id, tier)
	add_theme_stylebox_override("panel", card_style(accent, compact))

	badge_label.text = str(opts.get("badge", badge_text(id, tier)))
	badge.add_theme_stylebox_override("panel", badge_style(accent))
	role_label.text = role_tag(id)
	role_label.add_theme_color_override("font_color", BroadcastUI.MUTED)

	_icon_tex.visible = false
	_icon_glyph.visible = false
	_icon_fallback.visible = false
	if id == AMMO_BOX:
		_icon_glyph.kind = "ammo"
		_icon_glyph.color = BroadcastUI.AMBER
		_icon_glyph.visible = true
	elif definition.icon:
		_icon_tex.texture = definition.icon
		_icon_tex.visible = true
	else:
		_icon_fallback.text = id.left(3).to_upper()
		_icon_fallback.visible = true

	name_label.text = display_name(id)
	name_label.add_theme_color_override("font_color", name_color(id, tier))
	tagline_label.text = tagline(id)
	tagline_label.add_theme_color_override("font_color", BroadcastUI.MUTED)

	var rows := stat_rows(id, tier, opts)
	for i in _rows.size():
		if i < rows.size():
			var spec: Array = rows[i]
			apply_stat_row(_rows[i], spec[0], spec[1], spec[2], spec[3])
		else:
			_rows[i].row.visible = false

	trait_label.text = traits(id)
	trait_label.add_theme_color_override("font_color", CURSED_TINT if definition and definition.is_cursed() else Color(BroadcastUI.MUTED, 0.9))
	trait_label.visible = not trait_label.text.is_empty()
	_apply_footer(id, definition, opts)


## Dim placeholder state (an empty inventory slot, nothing targeted).
func clear(message := EMPTY_TEXT) -> void:
	item_id = ""
	item_tier = 0
	for node in _item_nodes:
		node.visible = false
	_empty_label.text = message
	_empty_label.visible = true
	var style := card_style(Color(BroadcastUI.MUTED, 0.35), compact)
	style.bg_color = Color(BroadcastUI.INK, 0.6)
	add_theme_stylebox_override("panel", style)


# ------------------------------------------------------------------ internals
func _apply_footer(id: String, definition: ItemDefinition, opts: Dictionary) -> void:
	var source := str(opts.get("source", ""))
	var meta := ""
	var meta_color := BroadcastUI.MUTED
	var is_gun := definition != null and definition.kind == ItemDefinition.Kind.GUN
	_price_pill.visible = false
	match source:
		"vending":
			var price := int(opts.get("price", 0))
			var affordable := bool(opts.get("affordable", true))
			_price_label.text = "%d SCRAP" % price
			var tint := BroadcastUI.AMBER if affordable else BroadcastUI.PINK
			_price_label.add_theme_color_override("font_color", BroadcastUI.INK)
			_price_pill.add_theme_stylebox_override("panel", badge_style(tint))
			_price_pill.visible = true
			if bool(opts.get("pouch_full", false)):
				meta = "POUCH FULL"
				meta_color = BroadcastUI.PINK
			elif not affordable:
				meta = "NEED %d MORE" % maxi(0, price - int(opts.get("scrap", 0))) if opts.has("scrap") else "SHORT ON SCRAP"
				meta_color = BroadcastUI.PINK
			elif bool(opts.get("swap", false)):
				meta = "SWAP"
				meta_color = BroadcastUI.AMBER
			elif definition and definition.spawn_count > 1 and not is_gun:
				meta = "BUY x%d" % definition.spawn_count
		"pickup":
			if bool(opts.get("pouch_full", false)):
				meta = "POUCH FULL"
				meta_color = BroadcastUI.PINK
			else:
				var verb := "SWAP" if bool(opts.get("swap", false)) else "TAKE"
				meta_color = BroadcastUI.AMBER if verb == "SWAP" else BroadcastUI.ACID
				if is_gun:
					meta = "%s  /  %d RDS LOADED" % [verb, int(opts.get("count", 0))]
				else:
					meta = "%s x%d" % [verb, int(opts.get("count", 1))]
		"inventory":
			if is_gun:
				var reserve := int(opts.get("reserve", 0))
				var cap := int(opts.get("reserve_cap", ItemCatalog.CAPS.get(definition.ammo_type, 0)))
				var loaded := int(opts.get("count", 0))
				meta = "RESERVE: %d / %d   MAG %d/%d" % [reserve, cap, loaded, maxi(1, definition.weapon.mag_size)]
				meta_color = BroadcastUI.PINK if reserve <= 0 and loaded <= 0 else BroadcastUI.PAPER
			elif definition:
				meta = "x%d" % int(opts.get("count", 1))
				meta_color = BroadcastUI.PAPER
	_meta_label.text = meta
	_meta_label.add_theme_color_override("font_color", meta_color)
	_footer.visible = not meta.is_empty() or _price_pill.visible


func _ignore(control: Control) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


func _build() -> void:
	var tall := layout == Layout.TALL
	var meta_size := 15 if compact else 16
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 7 if tall else 3)
	add_child(_ignore(content))

	# Header strip: tier / key badge on the left, role tag on the right.
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	badge = PanelContainer.new()
	badge.custom_minimum_size = Vector2(32, 0)
	_header.add_child(_ignore(badge))
	badge_label = Label.new()
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(badge_label, 18 if tall else meta_size, BroadcastUI.INK)
	badge.add_child(badge_label)
	role_label = Label.new()
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_label.clip_text = true
	BroadcastUI.text(role_label, meta_size, BroadcastUI.MUTED)
	_header.add_child(role_label)

	# Icon well: item icon, the ammo glyph, or a 3-letter fallback.
	icon_well = PanelContainer.new()
	icon_well.add_theme_stylebox_override("panel", icon_well_style())
	var icon_side := 64.0 if tall else (44.0 if compact else 52.0)
	var icon_center := CenterContainer.new()
	icon_well.add_child(_ignore(icon_center))
	_icon_tex = TextureRect.new()
	_icon_tex.custom_minimum_size = Vector2(icon_side, icon_side)
	_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_center.add_child(_ignore(_icon_tex))
	_icon_glyph = GameIcon.new()
	_icon_glyph.custom_minimum_size = Vector2(icon_side, icon_side) * 0.8
	icon_center.add_child(_ignore(_icon_glyph))
	_icon_fallback = Label.new()
	BroadcastUI.text(_icon_fallback, 28 if tall else 22, BroadcastUI.CYAN)
	icon_center.add_child(_icon_fallback)

	name_label = Label.new()
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tagline_label = Label.new()
	tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline_label.max_lines_visible = 2
	var top: Control
	if tall:
		# Starter picker card: header, big centered icon well, name, tagline.
		content.add_child(_ignore(_header))
		icon_well.custom_minimum_size = Vector2(0, 84)
		content.add_child(_ignore(icon_well))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		BroadcastUI.text(name_label, 26, BroadcastUI.PAPER, 2)
		content.add_child(name_label)
		tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tagline_label.custom_minimum_size = Vector2(10, 38)
		BroadcastUI.text(tagline_label, 18, BroadcastUI.MUTED)
		content.add_child(tagline_label)
	else:
		# Inventory / HUD card: icon well beside the header strip, name, tagline.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(_ignore(row))
		top = row
		icon_well.custom_minimum_size = Vector2(icon_side + 8.0, icon_side + 8.0)
		icon_well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(_ignore(icon_well))
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_ignore(words))
		words.add_child(_ignore(_header))
		BroadcastUI.text(name_label, 20 if compact else 22, BroadcastUI.PAPER, 2)
		words.add_child(name_label)
		tagline_label.custom_minimum_size = Vector2(10, 0)
		BroadcastUI.text(tagline_label, meta_size, BroadcastUI.MUTED)
		words.add_child(tagline_label)

	_divider = ColorRect.new()
	_divider.custom_minimum_size = Vector2(0, 1)
	_divider.color = Color(BroadcastUI.MUTED, 0.22)
	content.add_child(_ignore(_divider))

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 5 if tall else 1)
	content.add_child(_ignore(stats))
	for i in STAT_ROWS:
		_rows.append(build_stat_row(stats, "-", 0.5, "-", BroadcastUI.CYAN, meta_size))

	trait_label = Label.new()
	trait_label.clip_text = true
	trait_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if tall else HORIZONTAL_ALIGNMENT_LEFT
	BroadcastUI.text(trait_label, meta_size - 1, BroadcastUI.MUTED)
	content.add_child(trait_label)

	_footer = HBoxContainer.new()
	_footer.add_theme_constant_override("separation", 6)
	content.add_child(_ignore(_footer))
	_meta_label = Label.new()
	_meta_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meta_label.clip_text = true
	_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_meta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BroadcastUI.text(_meta_label, meta_size, BroadcastUI.MUTED)
	_footer.add_child(_meta_label)
	_price_pill = PanelContainer.new()
	_footer.add_child(_ignore(_price_pill))
	_price_label = Label.new()
	BroadcastUI.text(_price_label, meta_size, BroadcastUI.INK)
	_price_pill.add_child(_price_label)

	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A real minimum width keeps the wrapped height sane before first layout.
	_empty_label.custom_minimum_size = Vector2(COMPACT_WIDTH - 40.0, 0)
	BroadcastUI.text(_empty_label, 18, Color(BroadcastUI.MUTED, 0.6))
	content.add_child(_empty_label)

	if tall:
		_item_nodes = [_header, icon_well, name_label, tagline_label, _divider, stats, trait_label, _footer]
	else:
		# The divider is a TALL-only flourish; ROW cards stay tight.
		_divider.visible = false
		_item_nodes = [top, stats, trait_label, _footer]
