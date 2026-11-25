extends SceneTree
## Capture harness for Open Protocol transcripts (tools/open_protocol/capture_transcripts.py).
##
## Starts the real dedicated server (Net sees `--server` in the user args and
## mounts game/dedicated_server.gd exactly as in production) and only shortens
## the session so a full connect -> lobby -> run -> combat -> mutation draft ->
## results -> lobby cycle fits in about two minutes:
##   - Drizzle and Clearing timers are clamped (DRIZZLE_MAX / CLEARING_MAX s).
##   - Infected that survive STRAGGLER_SECONDS in Downpour take lethal damage
##     through EnemyBase.take_damage, so kills/despawns use the normal RPCs.
##   - Living players are kept at >= FLOOR health/suit until the run ends.
##   - FINISH_AFTER seconds into wave 2 Drizzle the run ends through
##     GameManager.finish(false), the same path a squad wipe takes.
## Every frame a client receives is still produced by unmodified server code.
##
##   godot --headless --path . --audio-driver Dummy -s tools/open_protocol/capture_harness.gd \
##       -- --server --port=17777 --thin-port=17780 --thin-tcp-port=17781 --map pinecrest

const DRIZZLE_MAX := 8.0
const CLEARING_MAX := 4.0
const STRAGGLER_SECONDS := 9.0
const FLOOR := 45.0
const FINISH_AFTER := 6.0

var _ages := {}
var _wave2_drizzle := 0.0


func _initialize() -> void:
	print("[capture-harness] active: storm timers shortened for transcript capture")


func _process(delta: float) -> bool:
	var gm := root.get_node_or_null("GameManager")
	var wm := root.get_node_or_null("WeatherManager")
	if gm == null or wm == null or not gm.run_active or gm.finished:
		_ages.clear()
		_wave2_drizzle = 0.0
		return false
	for p: Node in gm.players():
		if p.get("state") == "ok":
			p.set("health", maxf(float(p.get("health")), FLOOR))
			p.set("suit_integrity", maxf(float(p.get("suit_integrity")), FLOOR))
	match int(wm.phase):
		2:  # DRIZZLE
			wm.phase_time_left = minf(wm.phase_time_left, DRIZZLE_MAX)
			if wm.wave >= 2:
				_wave2_drizzle += delta
				if _wave2_drizzle >= FINISH_AFTER:
					print("[capture-harness] ending the run (GameManager.finish(false))")
					gm.finish(false)
		3:  # DOWNPOUR
			var live := {}
			for enemy: Node in get_nodes_in_group("enemies"):
				var id := enemy.get_instance_id()
				live[id] = float(_ages.get(id, 0.0)) + delta
				if live[id] >= STRAGGLER_SECONDS and float(enemy.get("health")) > 0.0:
					enemy.take_damage(999999.0)
			_ages = live
		4:  # CLEARING
			wm.phase_time_left = minf(wm.phase_time_left, CLEARING_MAX)
	return false
