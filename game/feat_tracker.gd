extends Node
## GameManager/Feats: watches the run on the host and confirms feat and
## achievement events (game/feats.gd) for each player.
## - The host decides; the player's own machine saves (Settings.feat_progress).
##   A remote player gets their event through _feat_event, nobody else does,
##   and the dedicated server never saves anything for players.
## - Most conditions are polled off plain player properties (state, sheltered,
##   exposed, in_puddle, suit_integrity). Enemy/weapon code reports the rest
##   with GameManager.achievement_event(event, player, value).

signal feat_completed(id: String)

const Projectile := preload("res://weapons/projectile.gd")
const AchievementToast := preload("res://ui/achievement_toast.gd")
const LONG_PLAY_MS := 20 * 60 * 1000
const HOST_TICK := 0.25
const CRASH_WINDOW_MS := 2500

## Local: feats this machine completed during the current run (results screen).
var earned_this_run: Array[String] = []

## Host: peer id -> this run's flags for that player (see _flags).
var _run := {}
## Host: peer id -> {feat id: true} for one-shot feats already sent this run.
var _sent := {}
var _tick := 0.0
var _toast: CanvasLayer


func _ready() -> void:
	Net.run_started.connect(func(): earned_this_run.clear())
	get_tree().node_added.connect(_on_node_added)
	if not Net.dedicated:
		_toast = AchievementToast.new()
		_toast.name = "AchievementToast"
		add_child(_toast)


# ------------------------------------------------------------------ host: run
## Host: a new run started (GameManager.start_run).
func reset_run() -> void:
	_run.clear()
	_sent.clear()
	earned_this_run.clear()
	for p in GameManager.players():
		_flags(p)


func _flags(player: Node) -> Dictionary:
	var peer := player.get_multiplayer_authority()
	if not _run.has(peer):
		_run[peer] = {
			# Joined before the first storm: eligible for the "whole run" feats.
			"full_run": WeatherManager.wave <= 1 and WeatherManager.phase != WeatherManager.Phase.DOWNPOUR and not GameManager.endless,
			"in_wave": false, "roofed": false, "dragged": false, "wave_kills": 0,
			"acid": false, "decon": false, "turned": false, "kills": 0,
			"state": str(player.get("state")),
		}
	return _run[peer]


func _active() -> bool:
	return Net.is_host() and GameManager.run_active and not GameManager.finished


func _process(delta: float) -> void:
	if not _active():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = HOST_TICK
	var players := GameManager.players()
	var phase := WeatherManager.phase
	var storm := phase == WeatherManager.Phase.DRIZZLE or phase == WeatherManager.Phase.DOWNPOUR
	var draining := WeatherManager.suit_loss_per_second() > 0.0
	for p: Node3D in players:
		var f := _flags(p)
		var state := str(p.get("state"))
		if state != f.state:
			if state == "downed" and phase == WeatherManager.Phase.CALM:
				award(p, "dead_air")
			f.state = state
		if state != "ok":
			continue
		if storm and bool(p.get("sheltered")):
			f.roofed = true
		if draining and bool(p.get("exposed")) and float(p.get("suit_integrity")) <= 0.0 \
				and not Projectile.protects(p.global_position + Vector3.UP, get_tree()):
			f.acid = true
	if players.size() >= 2:
		for dome: Node3D in get_tree().get_nodes_in_group("active_flares"):
			var inside := 0
			for p: Node3D in players:
				if str(p.get("state")) == "ok" and _under(dome, p):
					inside += 1
			if inside == players.size():
				_award_all("block_party")
				break
	var started: int = GameManager._run_started_ms
	if started > 0 and Time.get_ticks_msec() - started >= LONG_PLAY_MS:
		_award_all("slp_mode")


## True if `player` stands inside this Shield Dome (umbrellas share the group).
func _under(dome: Node3D, player: Node3D) -> bool:
	var kind: Variant = dome.get("id")
	if kind != null and str(kind) != "shield_dome":
		return false
	var data: Variant = dome.get("data")
	var radius := float(data.effect_radius) if data else 0.0
	return not dome.is_queued_for_deletion() and dome.global_position.distance_to(player.global_position + Vector3.UP) <= radius


## Host: GameManager._on_phase_changed, before players come back at Clearing.
func on_phase(phase: int, wave: int) -> void:
	if not _active():
		return
	var players := GameManager.players()
	match phase:
		WeatherManager.Phase.DRIZZLE:
			for p in players:
				var f := _flags(p)
				f.in_wave = str(p.get("state")) == "ok"
				f.roofed = false
				f.dragged = false
				f.wave_kills = 0
			if GameManager.endless and wave >= 10:
				_award_all("late_late_show")
			if GameManager.endless and wave >= 15:
				_award_all("late_fee")
		WeatherManager.Phase.CLEARING:
			var standing: Array = []
			for p in players:
				var f := _flags(p)
				if str(p.get("state")) == "ok":
					standing.append(p)
					if f.in_wave:
						if not f.roofed:
							award(p, "no_roof")
						if f.dragged:
							award(p, "not_today_undertow")
						if int(f.wave_kills) == 0:
							award(p, "conscientious_objector")
						if wave == 1 and float(p.get("suit_integrity")) < 10.0:
							award(p, "just_a_drizzle")
				f.in_wave = false
			if players.size() >= 2 and standing.size() == 1:
				award(standing[0], "last_one_standing")


## Host: Cumulus's core broke (GameManager.boss_defeated).
func on_boss_defeated() -> void:
	if not Net.is_host():
		return
	var players := GameManager.players()
	var map_feat := str(Feats.MAP_FEATS.get(GameManager.map_id, ""))
	for p in players:
		var f := _flags(p)
		award(p, "silver_lining")
		if map_feat != "":
			award(p, map_feat)
		if f.full_run:
			if not f.acid:
				award(p, "clean_bill")
			if not f.decon:
				award(p, "dry_cleaning")
			if f.turned and str(p.get("state")) == "ok":
				award(p, "please_stand_by")
	if Net.is_online() and players.size() >= 2:
		var skins := {}
		for p in players:
			var info: Dictionary = Net.roster.get(p.get_multiplayer_authority(), {})
			skins[int(info.get("skin", 0))] = true
		if skins.size() == 1:
			_award_all("uniform_policy")


func on_finish() -> void:
	if Net.is_host():
		_award_all("cable_subscriber")


func on_tape_choice(keep_playing: bool) -> void:
	if keep_playing and Net.is_host():
		_award_all("stay_tuned")


func on_revive(reviver: Node, revived: Node) -> void:
	if not _active() or not is_instance_valid(reviver) or not reviver.is_in_group("players"):
		return
	award(reviver, "first_responder")
	if bool(reviver.get("in_puddle")) and WeatherManager.phase == WeatherManager.Phase.DOWNPOUR:
		award(reviver, "wet_work")
	if is_instance_valid(revived) and float(revived.get("bleed_left")) < 1.0:
		award(reviver, "be_kind_rewind")


func on_turned(player: Node) -> void:
	if _active() and player:
		_flags(player).turned = true


func on_decon(player: Node) -> void:
	if _active() and player:
		_flags(player).decon = true


## Host: small hooks from enemy and weapon code (GameManager.achievement_event).
func on_event(event: String, player: Node, value: int) -> void:
	if not _active() or not is_instance_valid(player) or not player.is_in_group("players"):
		return
	match event:
		"boss_core":
			for dome: Node3D in get_tree().get_nodes_in_group("active_flares"):
				if dome.get("shooter") == player and _under(dome, player as Node3D):
					award(player, "umbrella_policy")
		"thunderhead_chain":
			if value >= 3:
				award(player, "chain_reaction")
		"undertow_drag":
			_flags(player).dragged = true
		"static_chain":
			if value <= 1 and Projectile.protects((player as Node3D).global_position + Vector3.UP, get_tree()):
				award(player, "faraday_cage")


func _on_node_added(node: Node) -> void:
	if node is EnemyBase and Net.is_host():
		(node as EnemyBase).died.connect(_on_enemy_died)


## Host: read the kill off the enemy before it frees (EnemyBase.died fires
## inside the killing take_damage, so the shot's critical flag still holds).
func _on_enemy_died(enemy: EnemyBase) -> void:
	if not _active() or GameManager.victory_locked:
		return
	var killer: Variant = enemy.get("_last_hit_by")
	if not (killer is Node and is_instance_valid(killer) and (killer as Node).is_in_group("players")):
		return
	var f := _flags(killer)
	f.kills = int(f.kills) + 1
	f.wave_kills = int(f.wave_kills) + 1
	if int(f.kills) >= 100:
		award(killer, "sweeps_week")
	if enemy.data == null or enemy.data.display_name != "Hailstone":
		return
	var now := Time.get_ticks_msec()
	if bool(enemy.get("_bullet_critical")):
		award(killer, "cold_shoulder")
	var crashed := enemy.has_meta("crashed_ms") and now - int(enemy.get_meta("crashed_ms")) <= CRASH_WINDOW_MS
	if crashed:
		award(killer, "brake_check")
	elif float(enemy.get("_charge_left")) > 0.0 or (enemy.has_meta("charge_cut_ms") and now - int(enemy.get_meta("charge_cut_ms")) <= 100):
		award(killer, "hail_mary")


# ------------------------------------------------------------------ host: send
func _award_all(id: String) -> void:
	for p in GameManager.players():
		award(p, id)


## Host: confirm `amount` progress on `id` for this player. A one-shot is sent
## once per run. The player's own machine applies and saves it.
func award(player: Node, id: String, amount := 1) -> void:
	if not Net.is_host() or not is_instance_valid(player) or not Feats.exists(id):
		return
	var peer := player.get_multiplayer_authority()
	if Feats.goal(id) == 1:
		var sent: Dictionary = _sent.get_or_add(peer, {})
		if sent.has(id):
			return
		sent[id] = true
	if Net.is_online() and peer != multiplayer.get_unique_id():
		if Net._is_peer_open(peer):
			_feat_event.rpc_id(peer, id, amount)
	elif not Net.dedicated:
		_apply(id, amount)


## Host -> one client: your own feat progress. Authority is the host (this
## node sits under the GameManager autoload), so only peer 1 can send it.
@rpc("authority", "call_remote", "reliable")
func _feat_event(id: String, amount: int) -> void:
	if Net.dedicated or Net.is_host() or not Feats.exists(id):
		return
	_apply(id, clampi(amount, 1, 100))


func _apply(id: String, amount: int) -> void:
	for done: String in Feats.add_progress(id, amount):
		earned_this_run.append(done)
		feat_completed.emit(done)
		if Feats.is_suit_unlock(done):
			Juice.popup("SUIT UNLOCKED: " + Feats.reward_name(done), BroadcastUI.ACID)
		if _toast:
			_toast.show_feat(done)
