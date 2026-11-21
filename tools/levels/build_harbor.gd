extends "res://tools/levels/level_builder.gd"
## Harbor Point. North is the cannery railhead, south is the outer wharf.

func build() -> void:
	district = "harbor"
	if "--props" in OS.get_cmdline_user_args():
		container("freight_box", false)
		container("through_container", true)
		gantry()
		beacon()
		trawler()
	else:
		for id: String in ["freight_box", "through_container", "hammerhead_crane", "harbor_light", "shrimp_boat"]:
			props[id] = load("res://props/harbor/%s.tscn" % id)
	begin_map("HarborPoint",true)
	waterfront()
	canneries()
	freight_yard()
	signal_walk()
	covered_hall("HarborPatrol", Vector3(-38, 0, 4.4), Vector2(10, 8), "#3c91a0", "HARBOR PATROL")
	outer_wharf()
	bait_shop()
	port_authority()
	coastal_pines()
	markers()
	boundary()
	bake_map()


func container(id: String, open: bool) -> void:
	start_scene(id.to_pascal_case())
	var skin := surface("#64a79f" if open else "#cc7152","quay_steel",0.35)
	var frame := paint("#344d52" if open else "#784439")
	for x: float in [-2,2]:
		box(Vector3(x,1.65,0),Vector3(0.14,3.3,10),skin)
		for i in 16:
			box(Vector3(x*1.04,1.65,-4.65+i*0.62),Vector3(0.09,3.12,0.10),frame,false)
		for y: float in [0.12,3.18]:
			box(Vector3(x,y,0),Vector3(0.25,0.22,10.1),frame,false)
	box(Vector3(0,3.28,0),Vector3(4,0.16,10),skin)
	for end: float in [-4.96,4.96]:
		if open:
			box(Vector3(0,3.1,end),Vector3(4,0.26,0.18),frame,false)
		else:
			box(Vector3(0,1.65,end),Vector3(4,3.3,0.18),skin)
			for x: float in [-1.25,-0.23,0.23,1.25]:
				box(Vector3(x,1.6,end*1.026),Vector3(0.07,2.9,0.08),paint("#d7c5a0"),false)
	if open:
		shelter("DryPassage",Vector3(0,1.57,0),Vector3(3.86,3.14,9.96))
	else:
		collider(Vector3(0,1.65,0),Vector3(3.9,3.3,9.9))
	label("H P L   /   87",Vector3(2.14,2.45,0),0.42,"#ffe3b0",90)
	finish_prop(id)


func gantry() -> void:
	start_scene("HammerheadCrane")
	var enamel := surface("#e4a04f","siding")
	var dark := paint("#524b4a")
	var trim := paint("#ffdf98")
	tube(Vector3(0,0.4,0),2.6,0.8,dark,1,true)
	for x: float in [-1.35,1.35]:
		for z: float in [-1.35,1.35]:
			beam(Vector3(x,0,z),Vector3(x,15,z),0.38,enamel,true)
		for i in 4:
			var y := 1+i*3.4
			var side := 1.35 if i%2 == 0 else -1.35
			beam(Vector3(x,y,side), Vector3(x,y+3.4,-side),0.22,enamel)
			beam(Vector3(side,y,x),Vector3(-side,y+3.4,x),0.22,enamel)
	box(Vector3(0,14.8,0),Vector3(4.8,0.55,4.8),dark)
	shelter("CraneBase",Vector3(0,6.9,0),Vector3(4.7,13.8,4.7))
	box(Vector3(-2.8,15.8,0),Vector3(3,2,3.2),enamel)
	box(Vector3(-2.8,16.1,1.62),Vector3(2.48,0.86,0.08),paint("#326c71"),false)
	for z: float in [-0.9,0.9]:
		for y: float in [16.7,18.5]:
			box(Vector3(4.4,y,z),Vector3(23,0.3,0.24),enamel,false)
		for i in 10:
			beam(Vector3(-7+i*2.3,16.7 if i%2==0 else 18.5,z),Vector3(-4.7+i*2.3,18.5 if i%2==0 else 16.7,z),0.22,trim)
	box(Vector3(-6,17.2,0),Vector3(3,2.5,2.8),dark,false)
	for x: float in [12.8,13.3]:
		beam(Vector3(x,17,0),Vector3(x,6.6,0),0.08,dark)
	box(Vector3(13.05,6.5,0),Vector3(1.1,0.65,0.62),enamel,false)
	beam(Vector3(13,6.4,0),Vector3(13.35,5.6,0),0.15,dark)
	beam(Vector3(13.35,5.6,0),Vector3(13.7,6,0),0.15,dark)
	finish_prop("hammerhead_crane")


func beacon() -> void:
	start_scene("HarborLight")
	var bone := surface("#fff0da","siding",0.32)
	var red := surface("#c25b50","siding",0.32)
	var iron := paint("#324955")
	for i in 5:
		var r := 3.15-i*0.28
		tube(Vector3(0,i*3.3+1.65,0),r,3.3,bone if i%2==0 else red,(r-0.28)/r)
	# A compact polygonal tower has no accessible interior.
	collider(Vector3(0,8,0),Vector3(5.7,16,5.7),Vector3.ZERO,true)
	tube(Vector3(0,16.55,0),2.7,0.45,iron)
	for i in 8:
		var a := TAU*i/8.0
		var p := Vector3(cos(a)*2.45,17.15,sin(a)*2.45)
		var q := Vector3(cos(a+TAU/8)*2.45,17.15,sin(a+TAU/8)*2.45)
		beam(p-Vector3.UP*0.55,p+Vector3.UP*0.4,0.09,iron)
		beam(p+Vector3.UP*0.4,q+Vector3.UP*0.4,0.09,iron)
	tube(Vector3(0,18.1,0),1.46,2.8,lit("#ffda84"))
	for i in 8:
		var a := TAU*i/8.0
		box(Vector3(cos(a)*1.47,18.1,sin(a)*1.47),Vector3(0.15,2.8,0.15),iron,false)
	tube(Vector3(0,20.15,0),2.1,1.55,iron,0)
	tube(Vector3(0,21.23,0),0.09,0.8,iron)
	box(Vector3(0,1.3,3),Vector3(1.25,2.6,0.34),iron,false)
	finish_prop("harbor_light")


func trawler() -> void:
	start_scene("ShrimpBoat")
	var hull := paint("#376c71")
	# Tapered bow and transom, cream rubbing strake and a raised wheelhouse.
	box(Vector3(0,0,0),Vector3(3.8,1.25,7),hull)
	for i in 4:
		var w := 3.8-i*0.8
		box(Vector3(0,0,3.5+i*0.58),Vector3(w,1.2,0.75),hull)
		box(Vector3(0,0.63,3.5+i*0.58),Vector3(w,0.12,0.75),paint("#f5d8a2"),false)
	box(Vector3(0,0.67,0),Vector3(3.91,0.17,7.2),surface("#ffecd2","wood"))
	box(Vector3(0,1.45,0.85),Vector3(2.8,1.6,2.6),paint("#f5dcaf"))
	box(Vector3(0,1.85,2.17),Vector3(2.4,0.53,0.06),hull,false)
	for x: float in [-1.41,1.41]:
		box(Vector3(x,1.85,0.85),Vector3(0.06,0.52,2.1),hull,false)
	box(Vector3(0,2.32,0.85),Vector3(3.2,0.18,3),paint("#c06848"),false)
	beam(Vector3(0,0.74,-1.1),Vector3(0,5.3,-1.1),0.17,hull,true)
	for x: float in [-1.65,1.65]:
		beam(Vector3(0,4.9,-1.1),Vector3(x,2.9,-2.8),0.10,paint("#d6b37f"))
	finish_prop("shrimp_boat")


func waterfront() -> void:
	section("TidalBasin")
	var asphalt := surface("#92a8a4", "asphalt")
	var concrete := surface("#aac2b6", "sidewalk")
	box(Vector3(0, -0.95, -26), Vector3(128, 1.9, 76), asphalt)
	box(Vector3(20, -0.95, 48.5), Vector3(88, 1.9, 31), concrete)
	# The basin is walkable below the tide. Solid quay skirts close cavities
	# below the decks, and the marked slipways meet the bed without a lip.
	box(Vector3(0, -2.15, 38), Vector3(128, 0.62, 52), concrete)
	var tide_mat := ShaderMaterial.new()
	tide_mat.shader = load("res://props/harbor/tide.gdshader")
	tide_mat.set_shader_parameter("ripple_pattern", load("res://assets/textures/harbor_tide.png"))
	box(Vector3(0, -1.44, 38), Vector3(128, 0.04, 52), tide_mat, false)
	var tide := add(part, Area3D.new(), "StandingWater") as Area3D
	tide.collision_layer = 16
	tide.collision_mask = 0
	tide.monitoring = false
	var wet := BoxShape3D.new()
	wet.size = Vector3(128, 0.70, 52)
	var hit := add(tide, CollisionShape3D.new(), "Waterline") as CollisionShape3D
	hit.shape = wet
	hit.position = Vector3(0, -1.70, 38)

	for x: float in [-60, -24, 23, 41, 62.5]:
		slipway(Vector3(x, -1.85, 20), Vector3(x, 0, 11.75), "QUAY EXIT")
	for x: float in [-13, 23, 57]:
		slipway(Vector3(x, -1.85, 25), Vector3(x, 0, 33.25), "WHARF EXIT")

	var deck := surface("#dcc496", "wood", 0.45)
	deckway("WestPier", Vector3(-52, 0, 34.5), Vector2(6.5, 45.5), deck)
	deckway("RescuePier", Vector3(-34, 0, 22), Vector2(6, 20.5), deck)
	deckway("WestSeawall", Vector3(-37, 0, 53), Vector2(30.8, 5.5), deck)
	slipway(Vector3(-46.5, -1.85, 42), Vector3(-46.5, 0, 50.4), "PIER EXIT")
	slipway(Vector3(-62.25, -1.85, 41), Vector3(-55.18, 0, 41), "PIER EXIT")
	section("Moorings")
	prop("shrimp_boat", Vector3(-46.5, -1.05, 34), 174)
	prop("shrimp_boat", Vector3(-61.5, -1.05, 29), 6)
	prop("shrimp_boat", Vector3(33, -1.05, 20), 93)
	box(Vector3(0, -2.7, 55), Vector3(1200, 0.12, 1000), tide_mat, false)
	for i in 12:
		box(Vector3(-135 + i * 22, -1, 114 + sin(i * 1.7) * 4), Vector3(22, 2.5, 4), paint("#536f7b"), false)


## Surface collision is a filled convex wedge and the visible slab follows its
## top edge. Ends can overlap the adjoining flat slab slightly for a flush join.
func ramp(low: Vector3, high: Vector3, width: float, mat: Material, base_y: float) -> void:
	var rise := high - low
	var side := Vector3(rise.z, 0, -rise.x).normalized() * width * 0.5
	var slope := rad_to_deg(atan2(rise.y, Vector2(rise.x, rise.z).length()))
	var yaw := rad_to_deg(atan2(rise.x, rise.z))
	var rotation := Vector3(-slope, yaw, 0)
	box((low + high) * 0.5 - Vector3.UP * 0.09, Vector3(width, 0.18, rise.length()), mat, false, rotation)
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for corner: Vector3 in [low + side, low - side, high + side, high - side]:
		points.append(corner)
		points.append(Vector3(corner.x, base_y, corner.z))
	shape.points = points
	if not bodies.has(part):
		bodies[part] = add(part, StaticBody3D.new(), "WorldCollision")
	var collision := add(bodies[part], CollisionShape3D.new(), "SlipHull") as CollisionShape3D
	collision.shape = shape


func slipway(low: Vector3, high: Vector3, caption: String) -> void:
	section("MarkedSlipway")
	ramp(low, high, 4.6, surface("#b4bfa5", "sidewalk"), -2.0)
	var heading := (high - low).normalized()
	var side := Vector3(heading.z, 0, -heading.x).normalized()
	var stripe := paint("#ffe087")
	for edge: float in [-2.03, 2.03]:
		beam(low + side * edge + Vector3.UP * 0.035, high + side * edge + Vector3.UP * 0.035, 0.16, stripe)
	var sign_at := high + side * 1.75
	box(sign_at + Vector3.UP * 0.82, Vector3(0.16, 1.64, 0.16), paint("#3b585f"))
	var yaw := rad_to_deg(atan2(-heading.x, -heading.z))
	var face := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	box(sign_at + Vector3.UP * 1.57, Vector3(2.4, 0.50, 0.10), paint("#164450"), false, Vector3(0, yaw, 0))
	label(caption, sign_at + Vector3.UP * 1.57 + face * 0.065, 0.30, "#fff0a8", yaw)


func deckway(title: String, at: Vector3, size: Vector2, mat: Material) -> void:
	section(title)
	box(at - Vector3.UP * 0.96, Vector3(size.x, 1.92, size.y), surface("#75968f", "quay_steel"))
	box(at - Vector3.UP * 0.10, Vector3(size.x, 0.20, size.y), mat, false)


func canneries() -> void:
	var names := ["NORTH STAR  /  ICE","HARBOR POINT CANNING CO.","PIER 3  /  COLD STORE"]
	for i in 3:
		section("CanneryBay"+str(i+1))
		# Leave a service lane beside the ice house.
		part.position = Vector3([-35,-1,39][i],0,-47)
		var wall := surface(["#98c4bd","#dc9b73","#abc7c3"][i],"quay_steel",0.26)
		var steel := paint("#354f59")
		steel.set_meta("storm_wet_surface", true)
		if i == 1:
			for side: float in [-1, 1]:
				box(Vector3(side * 14.8, 4.3, 0), Vector3(0.40, 8.6, 16), wall)
				for end: float in [-7.85, 7.85]:
					box(Vector3(side * 10.15, 4.3, end), Vector3(9.8, 8.6, 0.30), wall)
					box(Vector3(0, 6.54, end), Vector3(10.55, 4.12, 0.30), wall)
				for z: float in [-3.7, 3.7]:
					freight_stack(Vector3(side * 9.5, 0, z))
			shelter("CanneryFloor", Vector3(0, 3.0, 0), Vector3(29.2, 6.0, 15.5))
			label("PACKING FLOOR", Vector3(0, 4.90, 8.18), 0.57, "#ffe1a4")
			label("RAILHEAD", Vector3(0, 4.90, -8.18), 0.57, "#ffe1a4", 180)
		else:
			box(Vector3(0, 4.3, 0), Vector3(30, 8.6, 16), wall)
		if i == 0:
			for z: float in [2.7,4.8]:
				tube(Vector3(-15.32,1.45,z),0.26,2.9,steel,1,true)
				tube(Vector3(-15.32,2.5,z),0.34,0.19,paint("#d7ae73"))
		for side: float in [-1,1]:
			box(Vector3(0,9.28,side*4.25),Vector3(31.2,0.42,8.9),steel,true,Vector3(side*10,0,0))
		box(Vector3(0,8.9,0),Vector3(30,0.75,11),wall)
		box(Vector3(0,7.25,8.18),Vector3(26,1.65,0.32),steel,false)
		label(names[i],Vector3(0,7.3,8.37),0.95,"#ffe1a4")
		for x: float in [-9, 0, 9]:
			if i == 1 and x == 0.0:
				continue
			box(Vector3(x,2.34,8.10),Vector3(6.6,4.68,0.2),paint("#647b7e"),false)
			for j in 9:
				box(Vector3(x,0.4+j*0.48,8.24),Vector3(6.4,0.065,0.09),steel,false)
			box(Vector3(x,5.15,8.15),Vector3(2.5,0.2,0.32),lit("#ffce84"),false)
		box(Vector3(0,4.8,10.9),Vector3(30.6,0.25,6.3),surface("#f2d0a5","diamond_plate"))
		shelter("LoadingApron",Vector3(0,2.33,10.9),Vector3(30,4.65,5.8))
		for x: float in [-14,14]:
			box(Vector3(x,2.36,13.7),Vector3(0.24,4.72,0.24),steel)
		for x: float in [-8,8]:
			tube(Vector3(x,11.2,-3),0.65,3.5,steel)
			tube(Vector3(x,13,-3),0.9,0.45,steel,0.4)
	section("TruckApron")
	for x in range(-56,61,6):
		box(Vector3(x,0.025,-25),Vector3(0.14,0.035,6.4),paint("#d2aa67"),false)
	model("cars","delivery",Vector3(20,0,-22),6.4,65)
	model("roads","dumpster",Vector3(-58,0,-38),2.7)
	lamp(Vector3(-22,4,-33),"#ffac60")
	lamp(Vector3(22,4,-33),"#ffac60")


func freight_yard() -> void:
	section("IntermodalYard")
	for p: Vector3 in [Vector3(-52,0,-12),Vector3(-38,0,-12),Vector3(-45,0,-23),Vector3(-19,0,-10),Vector3(-16,0,4),Vector3(7,0,-12),Vector3(15,0,-12),Vector3(40,0,-12),Vector3(50,0,-8)]:
		var angle := 90 if p.z == -23 or p.x == -16 else 0
		prop("freight_box",p,angle)
		if p.x in [-52.0,15.0,40.0]:
			prop("freight_box",p+Vector3.UP*3.37,angle)
	prop("through_container",Vector3(-45,0,-13))
	prop("freight_box",Vector3(-45,0,-3),90)
	prop("through_container",Vector3(11,0,5),90)
	prop("hammerhead_crane",Vector3(23,0,6),-35)
	for x in range(-60,61,6):
		box(Vector3(x,0.027,-1),Vector3(3,0.03,0.13),paint("#cf9d60"),false)
	for x in range(-61,64,4):
		if abs(x+32)>5 and abs(x)>7 and abs(x-45)>4 and x > -40:
			box(Vector3(x,0.03,11.65),Vector3(2.4,0.045,0.37),paint("#e4ac59"),false)
	model("cars","truck-flat",Vector3(58,0,-25),7.4,-30)
	model("roads","construction-barrier",Vector3(56,0,2),3.5,25)


func signal_walk() -> void:
	section("SignalWalk")
	var cap := surface("#455f6d", "diamond_plate", 0.45)
	var iron := paint("#28444c")
	var rails := paint("#e0af65")
	var z := 0.0
	var y := 2.85
	ramp(Vector3(-8, 0, z), Vector3(2.2, y, z), 5.0, cap, -0.18)
	ramp(Vector3(34, 0, z), Vector3(23.8, y, z), 5.0, cap, -0.18)
	box(Vector3(13, y - 0.20, z), Vector3(22, 0.40, 5.0), cap)
	for x: float in [2.6, 12.8, 23.4]:
		for side: float in [-2.32, 2.32]:
			box(Vector3(x, 1.25, z + side), Vector3(0.28, 2.5, 0.32), iron)
	for side: float in [-2.41, 2.41]:
		box(Vector3(13, y + 0.86, z + side), Vector3(22, 0.18, 0.17), rails, false)
		box(Vector3(13, y + 0.43, z + side), Vector3(22, 0.86, 0.16), iron, true)
		for x: float in [2.4, 5.8, 9.3, 12.8, 16.3, 19.8, 23.6]:
			box(Vector3(x, y + 0.58, z + side), Vector3(0.13, 1.16, 0.15), rails, false)
		for ends: Array in [[-8, 2.2], [34, 23.8]]:
			beam(Vector3(ends[0], 0.38, z + side), Vector3(ends[1], y + 0.38, z + side), 0.43, rails, true)
	box(Vector3(12.7, y + 3.0, z), Vector3(8, 0.23, 5.1), surface("#bf7754", "quay_steel"))
	for x: float in [9.1, 16.4]:
		for side: float in [-2.36, 2.36]:
			box(Vector3(x, y + 1.54, z + side), Vector3(0.22, 3.08, 0.22), iron)
	shelter("SignalWalkRoof", Vector3(12.7, y + 1.43, z), Vector3(7.9, 2.86, 4.8))
	label("SIGNAL WALK", Vector3(12.7, y + 3.0, z - 2.66), 0.40, "#ffe8ac", 180)
	label("SIGNAL WALK", Vector3(12.7, y + 3.0, z + 2.66), 0.40, "#ffe8ac")


func outer_wharf() -> void:
	var iron := paint("#24444e")
	var ochre := paint("#ebb45e")
	var deck := surface("#c3aa7c", "wood", 0.45)
	var plate := surface("#96bbb5", "diamond_plate", 0.35)
	deckway("FishExchangeIsland", Vector3(2, 0, 25), Vector2(22, 13), deck)
	deckway("LiftBridge", Vector3(2.25, 0, 16.2), Vector2(12.5, 9.4), plate)
	deckway("SouthBridge", Vector3(6, 0, 32.5), Vector2(9, 3.6), plate)
	deckway("ExchangeApron", Vector3(-9.85, 0, 29.65), Vector2(2.65, 7.1), plate)
	deckway("NetWalk", Vector3(-21, 0, 24.5), Vector2(27, 5.5), deck)
	deckway("CustomsWalk", Vector3(29.7, 0, 24.5), Vector2(35.5, 5.6), deck)
	deckway("PilotsWalk", Vector3(47, 0, 22.5), Vector2(7.1, 21.5), plate)
	slipway(Vector3(-6.5, -1.85, 12.8), Vector3(-6.5, 0, 18.58), "MARKET EXIT")
	slipway(Vector3(19.3, -1.85, 29.0), Vector3(12.93, 0, 29.0), "MARKET EXIT")
	slipway(Vector3(35, -1.85, 27.83), Vector3(35, 0, 33.05), "WHARF EXIT")
	section("LiftBridgePortal")
	for x: float in [-3.75, 3.75]:
		for z: float in [12.6, 18.1]:
			box(Vector3(x, 3.15, z), Vector3(0.46, 6.3, 0.46), iron)
			beam(Vector3(x, 5.6, z), Vector3(x, 0.7, 15.4), 0.17, ochre)
		for z: float in [13.6, 17.1]:
			box(Vector3(x, 0.55, z), Vector3(0.23, 1.1, 0.23), iron)
	for z: float in [12.6, 18.1]:
		box(Vector3(0, 6.22, z), Vector3(8.4, 0.42, 0.52), iron)
	label("02  /  FISH EXCHANGE", Vector3(0, 5.99, 12.24), 0.40, "#ffe8ac", 180)

	covered_hall("FishExchange", Vector3(0, 0, 24.9), Vector2(14, 8.4), "#de785a", "FISH EXCHANGE")
	covered_hall("RescueBay", Vector3(-34, 0, 20.0), Vector2(5.6, 9.6), "#4d92a0", "RESCUE BAY")
	covered_hall("NetLoft", Vector3(-52, 0, 47), Vector2(6.3, 9.4), "#ba7456", "NET LOFT")
	covered_hall("CustomsShed", Vector3(47, 0, 29), Vector2(7, 7.4), "#6ca496", "CUSTOMS")
	covered_hall("IceMarket", Vector3(24, 0, 44), Vector2(14.0, 11.8), "#c87852", "ICE MARKET")

	section("WharfCover")
	prop("harbor_light", Vector3(53, 0, 49))
	prop("hammerhead_crane", Vector3(-17, 0, 49), 115)
	prop("freight_box", Vector3(-8, 0, 57), 90)
	prop("through_container", Vector3(41, 0, 45), 90)
	prop("freight_box", Vector3(34, 0, 55), 90)
	for at: Vector3 in [Vector3(-48, 0, 54.6), Vector3(8.9, 0, 22.6), Vector3(5, 0, 39),
			Vector3(14, 0, 53), Vector3(35, 0, 40), Vector3(44, 0, 35), Vector3(55, 0, 37)]:
		freight_stack(at)
	for p: Vector3 in [Vector3(-52, 0, 32), Vector3(-34, 0, 27), Vector3(0, 0, 29),
			Vector3(46, 0, 19), Vector3(53, 0, 44)]:
		for side: float in [-2.4, 2.4]:
			tube(p + Vector3(side, 0.44, 0), 0.32, 0.90, iron, 1, true)
			tube(p + Vector3(side, 0.90, 0), 0.39, 0.13, ochre)


func covered_hall(title: String, at: Vector3, size: Vector2, color: String, caption: String) -> void:
	section(title)
	part.position = at
	var frame := paint("#254350")
	var roof := surface(color, "quay_steel", 0.36)
	var border := Vector3(size.x, 0.0, size.y)
	var floor := surface("#adc3af", "sidewalk")
	box(Vector3(0, 0.018, 0), Vector3(size.x - 0.10, 0.028, size.y - 0.10), floor, false)
	var half_width := size.x * 0.5
	for ridge: float in [-1, 1]:
		box(Vector3(ridge * size.x * 0.25, 3.46, 0), Vector3(size.x * 0.51, 0.23, size.y + 0.25),
			roof, true, Vector3(0, 0, -ridge * 8))
	for x: float in [-half_width + 0.36, half_width - 0.36]:
		for z: float in [-size.y * 0.5 + 0.36, size.y * 0.5 - 0.36]:
			box(Vector3(x, 1.60, z), Vector3(0.30, 3.2, 0.30), frame)
			beam(Vector3(x, 2.3, z), Vector3(x * 0.71, 3.12, z), 0.19, frame)
		box(Vector3(x, 0.55, 0), Vector3(0.24, 1.1, size.y * 0.43), frame)
		for z: float in [-size.y * 0.28, size.y * 0.28]:
			box(Vector3(x, 3.03, z), Vector3(0.30, 0.12, 0.64), lit("#fff0ad"), false)
	for z: float in [-size.y * 0.5, size.y * 0.5]:
		box(Vector3(0, 3.20, z), Vector3(size.x - 0.35, 0.46, 0.18), frame, false)
		label(caption, Vector3(0, 3.18, z + signf(z) * 0.102), 0.32, "#ffe8ac", 0 if z > 0.0 else 180)
	shelter(title + "Roof", Vector3(0, 1.48, 0), border + Vector3(-0.15, 2.96, -0.15))
	freight_stack(Vector3(size.x * 0.31, 0, 0), true)


func freight_stack(at: Vector3, low := false) -> void:
	var frame := paint("#34525d")
	var wood := surface("#bb825a", "wood", 0.42)
	var h := 0.8 if low else 1.30
	box(at + Vector3.UP * h * 0.5, Vector3(1.9, h, 1.44), wood)
	for x: float in [-0.68, 0.68]:
		box(at + Vector3(x, h * 0.5, 0), Vector3(0.13, h + 0.045, 1.48), frame, false)
	box(at + Vector3(0, 0.065, 0), Vector3(2.1, 0.12, 1.64), frame, false)


func bait_shop() -> void:
	section("BaitAndTackle")
	part.position = Vector3(56,0,6.5)
	box(Vector3(0,-0.22,5.2),Vector3(10,0.44,4),surface("#efcfab","wood"))
	box(Vector3(0,2.2,0),Vector3(9,4.4,6),surface("#e4ad95","siding",0.55))
	box(Vector3(0,4.5,0),Vector3(10,0.38,7.1),surface("#a4c9b6","shingles_teal"))
	box(Vector3(0,3.1,4.8),Vector3(9.8,0.24,3.8),surface("#ffecb4","awning_cyan"))
	shelter("TackleCounter",Vector3(0,1.48,4.8),Vector3(9.5,2.96,3.6))
	for x: float in [-4.55,4.55]:
		box(Vector3(x,1.5,6.45),Vector3(0.18,3,0.18),paint("#394e55"))
	box(Vector3(-1.15,1.9,3.05),Vector3(5,1.4,0.15),paint("#325767"),false)
	box(Vector3(2.6,1.3,3.05),Vector3(1.55,2.6,0.2),paint("#356868"),false)
	box(Vector3(0,4.2,3.65),Vector3(9.4,1.45,0.18),paint("#284e55"),false)
	label("LIVE BAIT",Vector3(0,4.25,3.77),0.98,"#ffcf94")


func port_authority() -> void:
	var iron := paint("#344a52")
	var cream := paint("#dcc5a3")
	var ochre := paint("#c68b53")
	deckway("BridgeTenderPier", Vector3(10.25, 0, 17), Vector2(8.05, 11.2), surface("#c6b293", "wood"))
	section("BridgeTender")
	box(Vector3(9,1.4,14.3),Vector3(4.1,2.8,3.6),surface("#8ba69b","quay_steel"))
	box(Vector3(9,2.03,16.15),Vector3(3.55,0.77,0.12),iron,false)
	box(Vector3(9,2.93,14.45),Vector3(4.7,0.24,4.15),ochre)
	for x: float in [6.5,12.95]:
		tube(Vector3(x,-0.66,22.4),0.28,2.9,iron,1,true)
	section("HarborMastersOffice")
	part.position = Vector3(55,0,58)
	box(Vector3(0,2.1,0),Vector3(10.5,4.2,6),surface("#e9cdad","siding"))
	for side: float in [-1,1]:
		box(Vector3(0,4.55,side*1.7),Vector3(11.3,0.36,3.75),iron,true,Vector3(side*15,0,0))
	box(Vector3(0,4.37,0),Vector3(10.5,0.6,4.1),cream,false)
	for x: float in [-3.6,-1.35,1]:
		box(Vector3(x,2.5,-3.1),Vector3(1.65,1.28,0.2),iron,false)
	box(Vector3(3.6,1.32,-3.1),Vector3(1.65,2.64,0.2),ochre,false)
	box(Vector3(-6.9,3,0),Vector3(3.6,0.25,7),surface("#aec0b0","quay_steel"))
	for z: float in [-3.2,3.2]:
		box(Vector3(-8.42,1.43,z),Vector3(0.2,2.86,0.2),iron)
	shelter("KeepersVeranda",Vector3(-6.92,1.4,0),Vector3(3.36,2.8,6.85))
	section("WharfLivery")
	# Paint and mooring fixtures frame the open turning apron.
	for x: float in [9,44]:
		box(Vector3(x,0.035,45),Vector3(0.18,0.035,27),ochre,false)
	for i in 8:
		box(Vector3(11+i*4,0.035,32),Vector3(2.8,0.035,0.3),ochre,false)
	var lettering := add(part,Label3D.new(),"BerthNumber") as Label3D
	lettering.font = FONT
	lettering.text = "04  /  OUTER WHARF"
	lettering.modulate = Color("#ad7953")
	lettering.font_size = 96
	lettering.pixel_size = 0.041
	lettering.outline_size = 0
	lettering.position = Vector3(27,0.045,56)
	lettering.rotation_degrees.x = -90
	for p: Vector2 in [Vector2(6,59),Vector2(43,60),Vector2(60,30)]:
		box(Vector3(p.x,2.6,p.y),Vector3(0.23,5.2,0.23),iron)
		box(Vector3(p.x,5.15,p.y-0.57),Vector3(0.82,0.3,1.4),iron,false)
		box(Vector3(p.x,4.95,p.y-0.82),Vector3(0.67,0.14,0.76),lit("#ffcb83"),false)
	for p: Vector2 in [Vector2(-22,42),Vector2(-19,43),Vector2(-23,46),Vector2(50,32),Vector2(53,32)]:
		var foot := Vector3(p.x,0,p.y)
		tube(foot+Vector3.UP*0.5,0.93,1,ochre,0.68,true)
		tube(foot+Vector3.UP*1.25,0.64,0.72,iron,0.47)
		tube(foot+Vector3.UP*1.75,0.18,0.4,ochre)
	section("RefinerySkyline")
	box(Vector3(0,-2.15,-153),Vector3(360,4.1,179),surface("#c9c4bf","asphalt",0.15),false)
	for i in 9:
		var x := -93+i*22
		var h := 8+(i*7)%12
		tube(Vector3(x,h*0.5,-84-i%3*4),4.5,h,paint("#778185"),1,false)
		tube(Vector3(x,h+0.75,-84-i%3*4),4.7,1.6,paint("#586675"),0.45)
		box(Vector3(x-6,2.7,-82-i%3*4),Vector3(9,5.4,9),paint("#65777b"),false)
		for y: float in [2.2,5.7]:
			tube(Vector3(x,y,-84-i%3*4),4.57,0.15,iron)
		if i%3 == 0:
			tube(Vector3(x+7,12,-88),0.8,24,paint("#7c706e"))
			tube(Vector3(x+7,23,-88),0.84,0.95,ochre)
	box(Vector3(-112,1.3,-46),Vector3(48,5.8,108),paint("#64787a"),false)
	for i in 6:
		box(Vector3(-98,4.2,-86+i*14),Vector3(12,6+i%3*2,11),paint("#73848a"),false)


func coastal_pines() -> void:
	var bark := surface("#69564b", "wood", 0.64)
	var needlebeds: Array[Material] = [
		paint("#2c5551"), paint("#386963"), paint("#477863"),
	]
	var sites := [
		Vector3(-52, 0, -31), Vector3(-44, 0, 4.5),
		Vector3(39, 0, 6.5), Vector3(59, 0, -17),
		Vector3(7, 0, 51), Vector3(57, 0, 41),
	]
	for index in sites.size():
		section("WindbreakPine%d" % (index + 1))
		part.position = sites[index]
		var height := 4.8 + float(index % 3) * 0.34
		tube(Vector3(0, 2.1, 0), 0.44, 4.2, bark, 0.73, true)
		tube(Vector3(0, 0.17, 0), 0.78, 0.34, surface("#807d68", "sidewalk", 0.7), 0.96)
		var foliage := section("Needles", part)
		foliage.position.y = 2.8
		foliage.add_to_group("wind_sway", true)
		var lean := -1.0 if index % 2 else 1.0
		tube(Vector3(lean * 0.13, 0.50, 0), 2.01, 1.18, needlebeds[0], 0.72, false, Vector3(2, 0, -7 * lean))
		tube(Vector3(lean * 0.30, 1.30, 0), 1.68, 1.33, needlebeds[1], 0.44, false, Vector3(1, 0, -9 * lean))
		tube(Vector3(lean * 0.42, height - 3.5, 0), 1.03, 1.55, needlebeds[2], 0.1, false, Vector3(0, 0, -12 * lean))
		part = foliage.get_parent_node_3d()
		var canopy := add(part, Area3D.new(), "CanopyShelter") as Area3D
		canopy.add_to_group("shelter", true)
		canopy.collision_layer = 8
		canopy.collision_mask = 0
		canopy.monitoring = false
		var cover := CylinderShape3D.new()
		cover.radius = 1.65
		cover.height = 2.95
		var hit := add(canopy, CollisionShape3D.new(), "CanopyShape") as CollisionShape3D
		hit.shape = cover
		hit.position = Vector3(0, 1.475, 0)


func markers() -> void:
	points("PlayerSpawns", "player_spawn", [Vector2(-39.3, 3.7), Vector2(-36.8, 3.7),
		Vector2(-39.3, 6.0), Vector2(-36.8, 6.0)])
	points("EnemySpawns", "enemy_spawn", [Vector2(-59, -52), Vector2(-43, -59), Vector2(-5, -60),
		Vector2(37, -59), Vector2(59, -46), Vector2(60, -13), Vector2(61, 32), Vector2(62, 58),
		Vector2(4, 61), Vector2(-21, 58), Vector2(-52, 38), Vector2(-60, -24), Vector2(10, 41),
		Vector2(35, 36), Vector2(-20, 25)])
	points("CrateSpawns", "crate_spawn", [Vector2(-57, -28), Vector2(-23, -28), Vector2(11, -28),
		Vector2(48, -32), Vector2(-26, -1), Vector2(-14, 5), Vector2(-21, 24), Vector2(8.9, 23),
		Vector2(32, 24.5), Vector2(9, 38), Vector2(50, 39), Vector2(14, 51), Vector2(-49, 53)])
	for p: Vector2 in [Vector2(-54, -29), Vector2(-26, -28), Vector2(0, -28), Vector2(32, -28),
			Vector2(-30, 5), Vector2(35, 8), Vector2(17, 34), Vector2(49, 40),
			Vector2(-29, 23), Vector2(10, 28)]:
		drain(Vector3(p.x, 0.02, p.y))
	shower("IceHouse", Vector3(-48, 0, -35))
	shower("FishExchange", Vector3(-5.5, 0, 26))
	shower("IceMarket", Vector3(19.5, 0, 44))
	shower("RescueBay", Vector3(-34.8, 0, 19))
	points("StreetSupplySpawns", "street_supply_spawn", [Vector2(-38, -24), Vector2(36, -19),
		Vector2(20, 35), Vector2(44, 46)], 0.06)
	directories["CrateStations"] = add(scene, Node3D.new(), "CrateStations")
	marker("CrateStations", "crate_station", "CanneryStation", Vector3(-5, 0, -35)).rotation_degrees.y = 180
	marker("CrateStations", "crate_station", "BaitShopStation", Vector3(50, 0, 10)).rotation_degrees.y = 90
	marker("CrateStations", "crate_station", "FishExchangeStation", Vector3(4.5, 0, 24.5))
	marker("CrateStations", "crate_station", "RescueStation", Vector3(-34.8, 0, 16.6))
	marker("", "boss_anchor", "BossAnchor", Vector3(36, 16, 49))
	puddles([Vector3(-57, 3, -20), Vector3(-33, 3, -30), Vector3(-10, 3.2, -23),
		Vector3(2, 2, -32), Vector3(30, 3, -25), Vector3(55, 3, -33), Vector3(-26, 3, -3),
		Vector3(-4, 2.5, 5), Vector3(34, 2.8, 0), Vector3(48, 2.4, 6), Vector3(0, 2.2, 15),
		Vector3(12, 2.5, 35), Vector3(32, 3.5, 48), Vector3(-1, 2, 52), Vector3(44, 2.5, 54),
		Vector3(-50, 2, 5), Vector3(32, 2, 24.5)])
