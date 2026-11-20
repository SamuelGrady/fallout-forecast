extends RefCounted
## Reuses the authored transforms and collision dimensions. Only the visual
## child is replaced. Collision, garages, awnings and navigation stay in scene.

const SHOPS := {
	"VideoVault": "video_vault",
	"Arcade": "arcade",
	"Laundromat": "laundromat",
	"Diner": "diner",
	"Pharmacy": "pharmacy",
	"Hardware": "hardware",
}
const HOUSES := {
	"HouseWest": "house_west",
	"HouseNorthWest": "house_north_west",
	"HouseNorth": "house_north",
	"HouseNorthEast": "house_north_east",
	"HouseEast": "house_east",
	"LaneWest": "lane_west",
	"LaneEast": "lane_east",
	"MainNorthEast1": "main_north_east_one",
	"MainNorthEast2": "main_north_east_two",
	"BackNorthEast": "back_north_east",
}


static func apply(level: Node3D) -> void:
	var downtown := level.get_node("Geometry/Downtown")
	for shop: String in SHOPS:
		var body: StaticBody3D = downtown.get_node(shop)
		var kit := PinecrestShops.new(_dimensions(body))
		kit.call(SHOPS[shop])
		var model := _install(body, kit)
		var label: Label3D = downtown.get_node(shop + "Sign")
		label.global_transform = model.global_transform.translated_local(kit.sign_mount)
		label.set_meta("facade_mount", true)
	for house: String in HOUSES:
		var body: StaticBody3D = level.get_node("Geometry/Houses/%s/Building" % house)
		var kit := PinecrestHouses.new(_dimensions(body))
		kit.call(HOUSES[house])
		_install(body, kit)
	var kiosk: StaticBody3D = level.get_node("Geometry/GasStation/Kiosk")
	var booth := PinecrestShops.new(_dimensions(kiosk))
	booth.kiosk()
	_install(kiosk, booth)


static func _dimensions(body: StaticBody3D) -> Vector3:
	return (body.get_node("Collision").shape as BoxShape3D).size


static func _install(body: StaticBody3D, kit: BuildingKit) -> MeshInstance3D:
	var model := kit.finish()
	var collision: CollisionShape3D = body.get_node("Collision")
	model.transform = collision.transform.translated_local(Vector3.DOWN * kit.size.y / 2)
	body.get_node("Model").queue_free()
	body.add_child(model)
	return model
