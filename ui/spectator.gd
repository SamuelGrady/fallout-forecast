class_name SpectatorView
extends Node3D
## Spectator camera: while the local player is OUT (bled out in a session,
## waiting for Clearing), follow a teammate over the shoulder instead of
## staring at the floor. Left click / fire cycles teammates. Hands the view
## back to the player's own camera as soon as they are back in.

const DISTANCE := 3.6
const HEIGHT := 2.3

var _camera := Camera3D.new()
var _label := Label.new()
var _layer := CanvasLayer.new()
var _index := 0
var _active := false


func _ready() -> void:
	_camera.fov = 70.0
	_camera.cull_mask = 0xFFFFF
	add_child(_camera)
	_layer.layer = 7
	add_child(_layer)
	BroadcastUI.text(_label, roundi(24 * Settings.hud_scale), BroadcastUI.CYAN)
	BroadcastUI.back_label(_label)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -220
	_label.offset_right = 220
	# Above the vitals/armory panels (even at Large HUD) and the bottom-center hotbar.
	_label.offset_top = -176
	_label.offset_bottom = -176
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.visible = false
	_layer.add_child(_label)


static func targets(tree: SceneTree, me: Node) -> Array[Node]:
	return tree.get_nodes_in_group("players").filter(func(p: Node):
		return p != me and p is Node3D and str(p.get("state")) in ["ok", "downed"])


static func has_target(tree: SceneTree, me: Node) -> bool:
	return not targets(tree, me).is_empty()


func _process(delta: float) -> void:
	var me := get_tree().get_first_node_in_group("local_player")
	var spectating := me != null and str(me.get("state")) == "out"
	var available: Array[Node] = []
	if spectating:
		available = targets(get_tree(), me)
	if not spectating or available.is_empty():
		if _active:
			_active = false
			_label.visible = false
			var own := me.get_node_or_null("Head/Camera3D") as Camera3D if me else null
			if own:
				own.current = true
		return
	if available.size() > 1 and (Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("weapon_next")):
		_index += 1
		Sound.play("ui_click")
	_index = posmod(_index, available.size())
	var target := available[_index] as Node3D
	if not _active:
		_active = true
		_camera.current = true
		_camera.global_position = target.global_position + Vector3.UP * HEIGHT
	var behind := target.global_basis.z
	behind.y = 0.0
	behind = behind.normalized() if behind.length_squared() > 0.01 else Vector3.BACK
	var want := target.global_position + behind * DISTANCE + Vector3.UP * HEIGHT
	# Keep the camera out of walls: pull it in front of whatever is behind them.
	var head := target.global_position + Vector3.UP * 1.6
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(head, want, 1))
	if not hit.is_empty():
		want = hit.position + (head - want).normalized() * 0.3
	_camera.global_position = _camera.global_position.lerp(want, 1.0 - exp(-8.0 * delta))
	_camera.look_at(head, Vector3.UP)
	var callsign := str(target.get("display_name")) if target.get("display_name") != null else "TEAMMATE"
	_label.text = "SPECTATING  /  %s\nBACK AT CLEARING" % callsign.to_upper()
	if available.size() > 1:
		_label.text += "   [%s] NEXT" % ("RT" if Settings.using_gamepad else "LMB")
	_label.visible = true
