class_name Feats
extends RefCounted
## Feats and achievements: one list, one progress store.
## - A feat with "color" or "skin" unlocks that suit look (Cosmetics index).
## - "goal" > 1 counts across runs (progress lives in Settings.feat_progress).
## - "requires" feats complete on their own once every listed feat is done.
## - "hidden" ones read "???" until earned.
## The host confirms every event (game/feat_tracker.gd); each player's own
## machine keeps their progress. See Settings.feat_progress / feats_done.

const LIST: Array[Dictionary] = [
	# ---------------------------------------------------------- suit unlocks
	{"id": "main_street", "name": "MAIN STREET MATINEE", "desc": "Clear the storm over Pinecrest.", "color": 2},
	{"id": "low_tide", "name": "LOW TIDE", "desc": "Clear the storm over Harbor Point.", "color": 5},
	{"id": "sunday_service", "name": "SUNDAY SERVICE", "desc": "Clear the storm over Maple Hollow.", "color": 4},
	{"id": "silver_lining", "name": "SILVER LINING", "desc": "Break Cumulus's core and clear the storm.", "color": 8},
	{"id": "triple_feature", "name": "TRIPLE FEATURE", "desc": "Clear the storm in all three districts.", "color": 9,
		"requires": ["main_street", "low_tide", "sunday_service"]},
	{"id": "cold_shoulder", "name": "COLD SHOULDER", "desc": "Kill 50 Hailstones with hits to the glowing back core.", "goal": 50, "color": 3},
	{"id": "first_responder", "name": "FIRST RESPONDER", "desc": "Revive teammates 25 times.", "goal": 25, "skin": 2},
	{"id": "clean_bill", "name": "CLEAN BILL OF HEALTH", "desc": "Win a run without acid rain ever eating through your suit.", "skin": 3},
	{"id": "late_late_show", "name": "LATE LATE SHOW", "desc": "Reach wave 10 on the endless tape.", "skin": 4},
	# ---------------------------------------------------------- achievements
	{"id": "umbrella_policy", "name": "UMBRELLA POLICY", "desc": "Break Cumulus's core while standing under your own Shield Dome."},
	{"id": "chain_reaction", "name": "CHAIN REACTION", "desc": "Pop a Thunderhead early and take 3 or more infected down with it."},
	{"id": "not_today_undertow", "name": "NOT TODAY, UNDERTOW", "desc": "Get dragged by an Undertow and still be standing when the wave clears."},
	{"id": "wet_work", "name": "WET WORK", "desc": "Revive a teammate while standing in a puddle during a Downpour."},
	{"id": "no_roof", "name": "NO ROOF, NO PROBLEM", "desc": "Clear a wave without stepping under cover once."},
	{"id": "faraday_cage", "name": "FARADAY CAGE", "desc": "Be the last link a Static's chain can find while you stand under a Shield Dome."},
	{"id": "just_a_drizzle", "name": "IT'S JUST A DRIZZLE", "desc": "Clear wave 1 with your suit under 10%."},
	{"id": "brake_check", "name": "BRAKE CHECK", "desc": "Bait a Hailstone into a wall and finish it while it's still seeing stars."},
	{"id": "hail_mary", "name": "HAIL MARY", "desc": "Drop a Hailstone in the middle of its charge."},
	{"id": "be_kind_rewind", "name": "BE KIND, REWIND", "desc": "Revive a teammate with less than a second of bleed-out left."},
	{"id": "uniform_policy", "name": "UNIFORM POLICY", "desc": "Win a run where the whole squad (2+) wears the same skin."},
	{"id": "block_party", "name": "BLOCK PARTY", "desc": "Get the whole squad (2+) under one Shield Dome."},
	{"id": "dry_cleaning", "name": "DRY CLEANING", "desc": "Win a run without using a single decon charge."},
	{"id": "please_stand_by", "name": "PLEASE STAND BY", "desc": "Get Turned, come back at the Clearing, and still win the run."},
	{"id": "last_one_standing", "name": "LAST ONE STANDING", "desc": "Be the only survivor on your feet when a wave clears (2+ players)."},
	{"id": "sweeps_week", "name": "SWEEPS WEEK", "desc": "Score 100 kills in a single run."},
	{"id": "slp_mode", "name": "SLP MODE", "desc": "Keep one tape rolling for 20 minutes."},
	{"id": "stay_tuned", "name": "STAY TUNED", "desc": "Keep the tape rolling after Cumulus falls."},
	{"id": "cable_subscriber", "name": "CABLE SUBSCRIBER", "desc": "See 10 runs through to the end, win or lose.", "goal": 10},
	{"id": "dead_air", "name": "DEAD AIR", "desc": "Go down during the Calm, with no storm in sight.", "hidden": true},
	{"id": "conscientious_objector", "name": "CONSCIENTIOUS OBJECTOR", "desc": "Survive a whole wave without a single kill.", "hidden": true},
	{"id": "late_fee", "name": "LATE FEE", "desc": "Keep the endless tape going to wave 15.", "hidden": true},
]

## Map id -> the feat for clearing its storm.
const MAP_FEATS := {"pinecrest": "main_street", "harbor": "low_tide", "maple_hollow": "sunday_service"}

static var _by_id := {}


static func entry(id: String) -> Dictionary:
	if _by_id.is_empty():
		for feat in LIST:
			_by_id[feat.id] = feat
	return _by_id.get(id, {})


static func exists(id: String) -> bool:
	return not entry(id).is_empty()


static func goal(id: String) -> int:
	var feat := entry(id)
	if feat.has("requires"):
		return (feat.requires as Array).size()
	return maxi(1, int(feat.get("goal", 1)))


static func is_done(id: String) -> bool:
	return id in Settings.feats_done


## Progress toward the goal (requires-feats count their finished parts).
static func progress(id: String) -> int:
	if is_done(id):
		return goal(id)
	var feat := entry(id)
	if feat.has("requires"):
		var count := 0
		for part: String in feat.requires:
			if is_done(part):
				count += 1
		return count
	return mini(int(Settings.feat_progress.get(id, 0)), goal(id))


static func is_suit_unlock(id: String) -> bool:
	var feat := entry(id)
	return feat.has("color") or feat.has("skin")


## What a feat unlocks, e.g. "HOT PINK SUIT" / "FIREFIGHTER SKIN", or "".
static func reward_name(id: String) -> String:
	var feat := entry(id)
	if feat.has("color"):
		return Cosmetics.COLOR_NAMES[int(feat.color)] + " SUIT"
	if feat.has("skin"):
		return Cosmetics.SKINS[int(feat.skin)] + " SKIN"
	return ""


## The feat that unlocks this colour/skin, or {} when it is free from the start.
static func color_feat(index: int) -> Dictionary:
	for feat in LIST:
		if int(feat.get("color", -1)) == index:
			return feat
	return {}


static func skin_feat(index: int) -> Dictionary:
	for feat in LIST:
		if int(feat.get("skin", -1)) == index:
			return feat
	return {}


static func color_unlocked(index: int) -> bool:
	var feat := color_feat(posmod(index, Cosmetics.COLORS.size()))
	return feat.is_empty() or is_done(feat.id)


static func skin_unlocked(index: int) -> bool:
	var feat := skin_feat(Cosmetics.wrap_skin(index))
	return feat.is_empty() or is_done(feat.id)


static func unlocked_colors() -> Array:
	var out := []
	for i in Cosmetics.COLORS.size():
		if color_unlocked(i):
			out.append(i)
	return out


## "LOCKED / FIRST RESPONDER: Revive teammates 25 times. (7/25)"
static func lock_text(feat: Dictionary) -> String:
	var id := str(feat.id)
	var text := "%s: %s" % [feat.name, feat.desc]
	if goal(id) > 1:
		text += " (%d/%d)" % [progress(id), goal(id)]
	return text


static func done_count() -> int:
	var count := 0
	for feat in LIST:
		if is_done(feat.id):
			count += 1
	return count


## Local: add progress on this machine. Returns the feats that just completed
## (the feat itself and any "requires" feat it finished), in order.
static func add_progress(id: String, amount := 1) -> Array[String]:
	var completed: Array[String] = []
	if not exists(id) or is_done(id) or entry(id).has("requires") or amount <= 0:
		return completed
	var count := int(Settings.feat_progress.get(id, 0)) + amount
	Settings.feat_progress[id] = mini(count, goal(id))
	if count >= goal(id):
		Settings.feats_done.append(id)
		completed.append(id)
		for feat in LIST:
			if feat.has("requires") and not is_done(feat.id) and progress(feat.id) >= goal(feat.id):
				Settings.feats_done.append(feat.id)
				completed.append(str(feat.id))
	Settings.queue_save()
	return completed
