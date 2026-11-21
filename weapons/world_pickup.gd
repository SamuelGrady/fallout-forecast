class_name WorldPickup
extends Interactable

var registry: Node
var pickup_id: int
var item: ItemInstance
var flavor: String
var claim_peer := 0
var visual: Node3D
var _clock := 0.0

func _ready() -> void:
	if item:
		radius = 2.55
		hold_time = 0.0
		if not Net.dedicated:
			visual = ItemCatalog.model(item.id, true)
			add_child(visual)
			var marker := Label3D.new()
			marker.text = ItemCatalog.tier_name(item.id, item.tier)
			marker.modulate = ItemCatalog.tier_color(item.id, item.tier)
			marker.font = preload("res://assets/fonts/VT323-Regular.ttf")
			marker.font_size = 32
			marker.pixel_size = 0.003
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.position.y = 0.65
			add_child(marker)
		add_to_group("interactables")
	else:
		add_to_group("ammo_drops")
		if flavor == "supply":
			add_to_group("street_supplies")
		if not Net.dedicated:
			var pack := Node3D.new()
			pack.set_script(preload("res://weapons/ammo_drop.gd"))
			pack.set("kind", flavor)
			add_child(pack)

func _process(delta: float) -> void:
	if visual:
		_clock += delta
		visual.position.y = 0.25 + sin(_clock * 3.0) * 0.06
		visual.rotation.y += delta * 1.4

func can_interact(player: Node) -> bool:
	return not is_queued_for_deletion() and item != null and player.state == "ok" \
			and (claim_peer == 0 or claim_peer == player.get_multiplayer_authority())

func get_prompt(player: Node) -> String:
	var holder := player.get_node("Head/Camera3D/WeaponHolder") as WeaponHolder
	var action := "Swap for" if holder.needs_swap(item) else "Take"
	return "%s %s" % [action, ItemCatalog.definition(item.id).display_name]

func request(player: Node) -> void:
	var holder := player.get_node("Head/Camera3D/WeaponHolder") as WeaponHolder
	registry.request_claim(pickup_id, holder.selected_serial(), holder.current, player)
