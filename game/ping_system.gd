class_name PingSystem
extends Node
## Pings: there is no voice chat, so players mark things for each other.
## main.gd adds this as "Pings" under Main on every peer (same path for RPCs);
## ui/ping_hud.gd is the input, the radial wheel and the markers.
##
## Flow: the owner calls send(). Solo and the host accept it straight away; a
## client asks the host (_request_ping), which validates it (rate limit, range,
## roughly in view, REVIVE ME only while downed) and relays it to every peer in
## the run (_show_ping). Enemy pings carry the enemy's net_id, so every peer
## can make the marker follow its own copy of that enemy.

signal pinged(ping: Dictionary)

const LIFETIME := 6.0
const REVIVE_LIFETIME := 15.0
## A player's fourth ping replaces their oldest one.
const MAX_PER_PLAYER := 3
## Host-side flood guard: at most RATE_MAX pings per player per second.
const RATE_MAX := 4
const MAX_RANGE := 120.0
const AIM_MASK := Player.WORLD_LAYER | Player.ENEMY_LAYER

## kind -> marker label, GameIcon kind, cue (assets/audio/sfx/<cue>.wav).
## The first six are the wheel's slices; the rest come from a quick tap.
const KINDS := {
	"enemy": {"label": "ENEMY", "icon": "enemy", "cue": "ping_enemy"},
	"go": {"label": "GO HERE", "icon": "go", "cue": "ping_go"},
	"revive": {"label": "REVIVE ME", "icon": "health", "cue": "ping_revive"},
	"shelter": {"label": "SHELTER", "icon": "shelter", "cue": "ping_shelter"},
	"danger": {"label": "LOOK OUT", "icon": "danger", "cue": "ping_danger"},
	"crate": {"label": "CRATE", "icon": "crate", "cue": "ping_item"},
	"decon": {"label": "DECON", "icon": "shower", "cue": "ping_item"},
	"objective": {"label": "OBJECTIVE", "icon": "objective", "cue": "ping_item"},
	"ammo": {"label": "AMMO", "icon": "ammo", "cue": "ping_item"},
	"health": {"label": "MEDKIT", "icon": "health", "cue": "ping_item"},
	"suit": {"label": "SUIT PATCH", "icon": "suit", "cue": "ping_item"},
	"supply": {"label": "SUPPLIES", "icon": "ammo", "cue": "ping_item"},
	"ammo_box": {"label": "AMMO BOX", "icon": "ammo", "cue": "ping_item"},
	"tarp": {"label": "TARP", "icon": "shelter", "cue": "ping_item"},
}
## Live pings, oldest first: {owner, kind, pos, enemy_id, age, life, color,
## name, marker}. ui/ping_hud.gd draws these.
var pings: Array[Dictionary] = []
## Host: peer -> recent ping times (msec), for the rate limit.
var _recent := {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer: int): _recent.erase(peer))


func _process(delta: float) -> void:
	for ping in pings.duplicate():
		ping.age += delta
		_follow(ping)
		var marker := ping.marker as Node3D
		if is_instance_valid(marker):
			marker.global_position = ping.pos
			var fade := clampf((ping.life - ping.age) / 0.8, 0.0, 1.0) * minf(ping.age / 0.15, 1.0)
			marker.scale = Vector3(1.0, maxf(fade, 0.01), 1.0)
		if ping.age >= ping.life:
			_remove(ping)


## Enemy pings track the enemy while it lives; REVIVE ME tracks the pinger.
## When the target is gone the marker lingers a moment, then fades.
func _follow(ping: Dictionary) -> void:
	if int(ping.enemy_id) > 0:
		var enemy := find_enemy(int(ping.enemy_id))
		if enemy and enemy.health > 0.0:
			ping.pos = enemy.global_position
		else:
			ping.enemy_id = 0
			ping.life = minf(ping.life, ping.age + 1.0)
	elif ping.kind == "revive":
		var player := GameManager.player_for_peer(int(ping.owner)) as Player
		if player == null:
			ping.life = minf(ping.life, ping.age)
			return
		ping.pos = player.global_position
		if player.state != "downed":
			ping.life = minf(ping.life, ping.age + 0.5)


# ------------------------------------------------------------------ sending
## Owner: ping `kind` at `pos` (enemy_id = the enemy's net_id, or 0).
func send(kind: String, pos: Vector3, enemy_id := 0) -> void:
	if not Net.can_send_run_rpc():
		return
	if Net.is_host():
		_accept(multiplayer.get_unique_id(), kind, pos, enemy_id)
	elif Net.is_online():
		_request_ping.rpc_id(1, kind, pos, enemy_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_ping(kind: String, pos: Vector3, enemy_id: int) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if Net.run_peers.has(sender):
		_accept(sender, kind, pos, enemy_id)


## Host: check a ping, then show it here and on every peer in the run.
func _accept(peer: int, kind: String, pos: Vector3, enemy_id: int) -> void:
	var player := GameManager.player_for_peer(peer) as Player
	if player == null or not GameManager.run_active or GameManager.finished or get_tree().paused:
		return
	if not KINDS.has(kind) or not pos.is_finite() or player.state not in ["ok", "downed"]:
		return
	if kind == "revive" and player.state != "downed":
		return
	var now := Time.get_ticks_msec()
	var times: Array = (_recent.get(peer, []) as Array).filter(func(t): return now - int(t) < 1000)
	if times.size() >= RATE_MAX:
		return
	times.append(now)
	_recent[peer] = times
	if kind == "revive":
		pos = player.global_position
		enemy_id = 0
	else:
		var enemy := find_enemy(enemy_id) if kind == "enemy" and enemy_id > 0 else null
		if enemy and enemy.health > 0.0 and enemy.global_position.distance_to(pos) < 8.0:
			pos = enemy.global_position
		else:
			enemy_id = 0
		var offset := pos - player.camera.global_position
		var distance := offset.length()
		if distance > MAX_RANGE + 6.0:
			return
		# Allow for the host's interpolated view of the sender to lag behind.
		if distance > 4.0 and (-player.camera.global_basis.z).dot(offset / distance) < -0.4:
			return
	if Net.is_online():
		Net.rpc_to_run(_show_ping, [peer, kind, pos, enemy_id])
	if not Net.dedicated:
		_show(peer, kind, pos, enemy_id)


@rpc("authority", "call_remote", "reliable")
func _show_ping(peer: int, kind: String, pos: Vector3, enemy_id: int) -> void:
	_show(peer, kind, pos, enemy_id)


func _show(peer: int, kind: String, pos: Vector3, enemy_id: int) -> void:
	if not KINDS.has(kind):
		return
	var player := GameManager.player_for_peer(peer)
	var who := "PLAYER"
	if peer == multiplayer.get_unique_id() and not Net.dedicated:
		who = "YOU"
	elif player:
		who = str(player.get("display_name")).to_upper()
	var ping := {"owner": peer, "kind": kind, "pos": pos, "enemy_id": enemy_id, "age": 0.0,
		"life": REVIVE_LIFETIME if kind == "revive" else LIFETIME,
		"color": color_of(player), "name": who, "marker": null}
	# One live REVIVE ME per player, and re-pinging the same enemy refreshes it.
	for old in pings.duplicate():
		if int(old.owner) == peer and (kind == "revive" and old.kind == "revive" or enemy_id > 0 and int(old.enemy_id) == enemy_id):
			_remove(old)
	pings.append(ping)
	var own := pings.filter(func(p): return int(p.owner) == peer)
	while own.size() > MAX_PER_PLAYER:
		_remove(own.pop_front())
	if kind != "revive" or peer != multiplayer.get_unique_id():
		ping.marker = _make_marker(ping.color, kind)
		ping.marker.global_position = pos
	Sound.play(KINDS[kind].cue, -4.0 if kind in ["revive", "danger"] else -7.0)
	pinged.emit(ping)


func _remove(ping: Dictionary) -> void:
	if is_instance_valid(ping.marker):
		(ping.marker as Node).queue_free()
	pings.erase(ping)


## The 3D half of a marker: a thin light column and a ground ring in the
## pinger's colour, so the spot reads in the world. The icon, label and
## distance are drawn by the HUD (sharp, through walls, clamped to the edge).
func _make_marker(color: Color, kind: String) -> Node3D:
	var root := Node3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.55)
	material.disable_fog = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.55
	torus.rings = 20
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = material
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	if kind != "enemy":
		var beam := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.04
		cylinder.bottom_radius = 0.08
		cylinder.height = 3.0
		cylinder.radial_segments = 8
		cylinder.rings = 0
		beam.mesh = cylinder
		beam.material_override = material
		beam.position.y = 1.5
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
	add_child(root)
	return root


# ------------------------------------------------------------------ aiming
## What `player` is pointing at: {point, enemy (EnemyBase or null), boss}.
func aim(player: Player) -> Dictionary:
	var camera := player.camera
	var from := camera.global_position
	var direction := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * MAX_RANGE, AIM_MASK, [player.get_rid()])
	query.collide_with_areas = false
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var result := {"point": from + direction * 40.0, "enemy": null, "boss": false}
	if hit.is_empty():
		return result
	result.point = hit.position
	var node := hit.collider as Node
	while node and not node is EnemyBase:
		if node.is_in_group("boss_parts") or node.is_in_group("boss"):
			result.boss = true
		node = node.get_parent()
	result.enemy = node
	return result


## A quick tap: the most useful thing near the crosshair. Enemy under the
## crosshair, then an enemy just off it, then a crate, decon shower, active
## objective or pickup, then the spot itself (GO HERE).
func context_ping(player: Player, only_kind := "") -> Dictionary:
	var looked := aim(player)
	if only_kind in ["", "enemy"]:
		if looked.enemy and looked.enemy.health > 0.0:
			return {"kind": "enemy", "pos": looked.enemy.global_position, "enemy_id": looked.enemy.net_id}
		if looked.boss:
			return {"kind": "enemy", "pos": looked.point, "enemy_id": 0}
	var camera := player.camera
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var best := {}
	var best_score := INF
	var candidates: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase and enemy.health > 0.0:
			candidates.append([enemy, "enemy", 0.995, enemy.global_position + Vector3.UP])
	for crate in get_tree().get_nodes_in_group("crates"):
		if crate.can_ping():
			candidates.append([crate, "crate", 0.985, crate.global_position + Vector3.UP * 0.5])
	for shower in get_tree().get_nodes_in_group("decon_shower"):
		candidates.append([shower, "decon", 0.985, shower.global_position + Vector3.UP])
	for objective in get_tree().get_nodes_in_group("district_objectives"):
		if objective.get("active"):
			candidates.append([objective, "objective", 0.985, objective.global_position])
	for drop in get_tree().get_nodes_in_group("ammo_drops"):
		var drop_kind := str(drop.get("flavor") if drop.get("flavor") != null else drop.get("kind"))
		if KINDS.has(drop_kind):
			candidates.append([drop, drop_kind, 0.98, drop.global_position + Vector3.UP * 0.3])
	for entry in candidates:
		if only_kind != "" and entry[1] != only_kind:
			continue
		var node := entry[0] as Node3D
		var at: Vector3 = entry[3]
		var offset := at - eye
		var distance := offset.length()
		if distance > 60.0 or not node.is_visible_in_tree():
			continue
		var facing := forward.dot(offset / maxf(distance, 0.01))
		# Near the hit point counts too, so pinging the floor by a crate works.
		var near_hit: bool = at.distance_to(looked.point) < 1.6
		if facing < entry[2] and not near_hit:
			continue
		if not _visible(player, eye, at, node):
			continue
		var score := (1.0 - facing) * 10.0 + distance * 0.01 + (0.0 if entry[1] == "enemy" else 0.05)
		if score < best_score:
			best_score = score
			best = {"kind": entry[1], "pos": node.global_position,
				"enemy_id": node.net_id if node is EnemyBase else 0}
	if not best.is_empty() and KINDS.has(best.kind):
		return best
	return {"kind": "go" if only_kind == "" else only_kind, "pos": looked.point, "enemy_id": 0}


## Wheel slice `kind`, aimed where the player is looking.
func wheel_ping(player: Player, kind: String) -> Dictionary:
	if kind == "revive":
		return {"kind": kind, "pos": player.global_position, "enemy_id": 0}
	if kind in ["crate", "enemy"]:
		return context_ping(player, kind)
	return {"kind": kind, "pos": aim(player).point, "enemy_id": 0}


func _visible(player: Player, eye: Vector3, at: Vector3, node: Node) -> bool:
	var exclude: Array[RID] = [player.get_rid()]
	if node is CollisionObject3D:
		exclude.append(node.get_rid())
	var query := PhysicsRayQueryParameters3D.create(eye, at, Player.WORLD_LAYER, exclude)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit.position as Vector3).distance_to(at) < 1.0


func find_enemy(net_id: int) -> EnemyBase:
	for node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyBase and node.net_id == net_id and node.is_inside_tree():
			return node
	return null


## The pinger's suit colour, as their body model shows it.
static func color_of(player: Node) -> Color:
	if player == null:
		return BroadcastUI.CYAN
	var body := player.get_node_or_null("BodyModel")
	if body and body.get("suit_color") is Color:
		return body.suit_color
	var suit = player.get("suit_color")
	return suit if suit is Color else BroadcastUI.CYAN
