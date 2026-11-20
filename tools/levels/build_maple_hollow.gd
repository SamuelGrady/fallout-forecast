extends "res://tools/levels/level_builder.gd"
## Maple Hollow. The school crossing feeds the bulb of Juniper Court.
## Two bridges and a pair of maintenance slopes open the creek route.

func build() -> void:
	district = "maple_hollow"
	water_tower()
	mausoleum()
	church()
	carport()
	play_set()
	october_maple()
	begin_map("MapleHollow",false)
	terrain()
	creek()
	juniper_court()
	churchyard()
	entrance()
	park()
	town_details()
	markers()
	boundary()
	bake_map()


func water_tower() -> void:
	start_scene("MunicipalTank")
	var iron := paint("#555b6b")
	var enamel := surface("#91c4be","siding",0.23)
	var stripe := paint("#e2a47d")
	for x: float in [-1,1]:
		for z: float in [-1,1]:
			beam(Vector3(3.1*x,0,3.1*z),Vector3(2.15*x,12,2.15*z),0.39,iron,true)
			beam(Vector3(2.98*x,1.4,2.98*z),Vector3(-2.55*x,7.3,2.55*z),0.14,iron)
			beam(Vector3(2.98*x,1.4,2.98*z),Vector3(2.55*x,7.3,-2.55*z),0.14,iron)
			box(Vector3(3.1*x,0.24,3.1*z),Vector3(1.05,0.48,1.05),paint("#aaa49f"))
	tube(Vector3(0,5.4,0),0.4,10.8,iron,1,true)
	tube(Vector3(0,12.1,0),1.05,3.5,enamel,4.5)
	tube(Vector3(0,16.15,0),4.72,4.7,enamel)
	collider(Vector3(0,16.15,0),Vector3(9.44,4.7,9.44),Vector3.ZERO,true)
	tube(Vector3(0,14.28,0),4.77,0.56,stripe)
	tube(Vector3(0,18.43,0),4.85,0.2,iron)
	tube(Vector3(0,19.24,0),4.85,1.55,enamel,0.09)
	tube(Vector3(0,20.58,0),0.14,1.35,iron)
	tube(Vector3(0,21.3,0),0.17,0.26,lit("#ff9770"))
	label("MAPLE",Vector3(0,16.75,4.76),1.10,"#304b58")
	label("WATER DEPT.",Vector3(0,15.6,4.78),0.48,"#354459")
	# Utility ladder and hoop-free safety rails.
	for x: float in [-0.34,0.34]:
		box(Vector3(x,8,-4.78),Vector3(0.08,16,0.08),iron,false)
	for i in 30:
		box(Vector3(0,0.4+i*0.51,-4.78),Vector3(0.75,0.06,0.09),iron,false)
	shelter("TankUnderside",Vector3(0,4.9,0),Vector3(6.5,9.8,6.5))
	finish_prop("municipal_tank")


func mausoleum() -> void:
	start_scene("LowellVault")
	var marble := surface("#c2c2ca","sidewalk",0.35)
	var dark := paint("#555264")
	var bronze := paint("#799487")
	box(Vector3(0,2.8,-1.3),Vector3(12.2,5.6,7.8),marble)
	box(Vector3(0,0.38,-1.3),Vector3(12.5,0.76,8.05),dark)
	box(Vector3(0,5.65,0.8),Vector3(13.6,0.65,12.5),dark)
	box(Vector3(0,6.15,0.8),Vector3(13,0.48,12),marble)
	for i in 6:
		box(Vector3(0,6.48+i*0.22,0.8),Vector3(12.2-i*1.9,0.24,11.7),marble,false)
	for x: float in [-5.45,-3.5,3.5,5.45]:
		box(Vector3(x,0.26,5.95),Vector3(1.05,0.52,1.05),dark)
		tube(Vector3(x,2.83,5.95),0.37,4.84,marble,0.84,true)
		box(Vector3(x,5.15,5.95),Vector3(0.98,0.4,0.98),marble,false)
	box(Vector3(0,2.2,2.68),Vector3(3.4,4.4,0.32),dark,false)
	for x: float in [-0.66,0.66]:
		box(Vector3(x,1.75,2.88),Vector3(1.26,3.45,0.18),bronze,false)
		for y: float in [0.95,2.45]:
			box(Vector3(x,y,3),Vector3(0.85,0.85,0.07),dark,false)
	box(Vector3(0,5.65,7.13),Vector3(5.45,0.85,0.15),dark,false)
	label("L O W E L L",Vector3(0,5.68,7.23),0.54,"#dfc9a3")
	shelter("Portico",Vector3(0,2.65,4.8),Vector3(12.7,5.3,4.3))
	finish_prop("lowell_mausoleum")


func church() -> void:
	start_scene("WaysideChapel")
	var wall := surface("#f0d5b6","siding",0.38)
	var roof := surface("#847897","diamond_plate",0.25)
	var frame := paint("#584f5c")
	box(Vector3(0,3.3,0),Vector3(11,6.6,17),wall)
	for side: float in [-1,1]:
		box(Vector3(side*2.92,7.75,0),Vector3(6.64,0.38,17.7),roof,true,Vector3(0,0,-side*25))
		for z: float in [-5.7,-1.9,1.9,5.7]:
			box(Vector3(side*5.51,3.7,z),Vector3(0.15,3.2,1.65),frame,false)
			box(Vector3(side*5.62,3.7,z),Vector3(0.07,2.7,1.27),lit("#d9a783"),false)
			box(Vector3(side*5.71,3.75,z),Vector3(0.08,2.8,0.11),frame,false)
			box(Vector3(side*5.71,3.75,z),Vector3(0.08,0.1,1.32),frame,false)
	for i in 7:
		box(Vector3(0,6.67+i*0.33,0),Vector3(10.55-i*1.45,0.35,16.98),wall,false)
	box(Vector3(0,5.15,7.4),Vector3(4.6,10.3,4.8),wall)
	box(Vector3(0,10.25,7.4),Vector3(5,0.35,5.2),frame)
	for x: float in [-1.65,1.65]:
		for z: float in [5.75,9.05]:
			box(Vector3(x,11.65,z),Vector3(0.45,2.65,0.45),wall,false)
	tube(Vector3(0,11.24,7.4),0.84,0.95,paint("#8d775d"),0.43)
	box(Vector3(0,13,7.4),Vector3(4.6,0.4,4.6),frame,false)
	tube(Vector3(0,15.5,7.4),2.45,5.0,roof,0.035)
	box(Vector3(0,18.65,7.4),Vector3(0.17,1.8,0.17),wall,false)
	box(Vector3(0,18.93,7.4),Vector3(1.18,0.16,0.16),wall,false)
	box(Vector3(0,1.76,9.88),Vector3(2.4,3.52,0.22),frame,false)
	# Clock face and hands overlook the cemetery entrance.
	tube(Vector3(0,7.65,9.89),1.16,0.20,frame,1,false,Vector3(90,0,0))
	tube(Vector3(0,7.65,10.02),1.02,0.07,lit("#e9c49c"),1,false,Vector3(90,0,0))
	beam(Vector3(0,7.65,10.10),Vector3(-0.44,8.21,10.10),0.12,frame)
	beam(Vector3(0,7.65,10.10),Vector3(0.54,7.92,10.10),0.11,frame)
	box(Vector3(0,3.95,11.1),Vector3(5.35,0.38,3.2),roof)
	for x: float in [-2.4,2.4]:
		box(Vector3(x,1.9,12.45),Vector3(0.22,3.8,0.22),wall)
	shelter("ChapelPorch",Vector3(0,1.84,11.25),Vector3(5.2,3.68,2.85))
	finish_prop("wayside_chapel")


func carport() -> void:
	start_scene("Breezeway")
	var posts := surface("#ebddba","siding")
	box(Vector3(0,3.18,0),Vector3(4.7,0.32,7),surface("#bda5b4","diamond_plate"))
	for x: float in [-2.13,2.13]:
		for z: float in [-3.16,3.16]:
			box(Vector3(x,1.52,z),Vector3(0.18,3.04,0.18),posts)
	box(Vector3(0,1.4,-3.32),Vector3(4.42,2.8,0.19),posts)
	box(Vector3(0,1.26,-3.18),Vector3(3.55,2.5,0.12),paint("#acabba"),false)
	for i in 5:
		box(Vector3(0,0.36+i*0.46,-3.08),Vector3(3.42,0.052,0.08),paint("#747888"),false)
	box(Vector3(0,2.92,3.39),Vector3(1.4,0.14,0.12),lit("#ffcb85"),false)
	shelter("DryBay",Vector3(0,1.49,0),Vector3(4.5,2.98,6.8))
	finish_prop("breezeway")


func play_set() -> void:
	start_scene("RocketYard")
	var red := paint("#c26c69")
	var blue := paint("#608d9b")
	var gold := paint("#e7b763")
	for x: float in [-3.4,3.4]:
		for z: float in [-1.9,1.9]:
			beam(Vector3(x,0,z),Vector3(x,3.7,0),0.17,red,true)
	box(Vector3(0,3.62,0),Vector3(7.25,0.21,0.21),gold)
	for x: float in [-1.6,1.6]:
		for off: float in [-0.5,0.5]:
			beam(Vector3(x+off,3.6,0),Vector3(x+off,0.68,0.15),0.047,blue)
		box(Vector3(x,0.65,0.15),Vector3(1.23,0.12,0.5),blue,true)
	# A rocket-shaped climbing slide with a faceted nose and three fins.
	for x: float in [5.5,7.5]:
		for z: float in [-1,1]:
			box(Vector3(x,1.15,z),Vector3(0.18,2.3,0.18),red)
	tube(Vector3(6.5,2.28,0),1.5,0.27,gold,1,true)
	for i in 5:
		var a := TAU*i/5.0
		box(Vector3(6.5+1.24*cos(a),3.48,1.24*sin(a)),Vector3(0.13,2.4,0.13),blue,false)
	tube(Vector3(6.5,5.42,0),1.6,1.6,red,0.04)
	collider(Vector3(6.5,4.69,0),Vector3(3.2,0.14,3.2),Vector3.ZERO,true)
	box(Vector3(6.5,1.2,3.15),Vector3(1.05,0.16,5.05),gold,true,Vector3(27,0,0))
	shelter("RocketPlatform",Vector3(6.5,1.03,0),Vector3(2.05,2.06,2.05))
	shelter("Capsule",Vector3(6.5,3.48,0),Vector3(2.2,2.18,2.2))
	finish_prop("rocket_playground")


func terrain() -> void:
	section("Lawns")
	var lawn := surface("#cad0a0","grass",0.19)
	box(Vector3(10.5,-1.55,0),Vector3(107,3.1,128),lawn)
	box(Vector3(-57.5,-1.55,0),Vector3(13,3.1,128),lawn)
	section("JuniperPavement")
	var walk := surface("#dfcdd0","sidewalk",0.35)
	var road := surface("#ccc7d5","asphalt",0.35)
	# The sidewalk is also the road's collision bed.
	box(Vector3(6,0.025,32),Vector3(116,0.05,12),walk)
	box(Vector3(6,0.053,32),Vector3(116,0.045,9.4),road,false)
	box(Vector3(-9,0.029,6.4),Vector3(12.8,0.056,41),walk)
	box(Vector3(-9,0.061,6.4),Vector3(9.4,0.055,41),road,false)
	tube(Vector3(-9,0.057,-16),16.7,0.08,walk,1,true)
	tube(Vector3(-9,0.106,-16),14.8,0.032,road)
	tube(Vector3(-9,0.155,-16),4.1,0.14,walk,1,true)
	tube(Vector3(-9,0.234,-16),3.66,0.04,lawn)
	prop("october_maple",Vector3(-9,0.25,-16),27)
	for x in range(-39,64,7):
		if abs(x+9)>6:
			box(Vector3(x,0.098,32),Vector3(3.1,0.025,0.13),paint("#d8bb79"),false)
	for z in range(3,26,6):
		box(Vector3(-9,0.108,z),Vector3(0.13,0.02,2.6),paint("#dcc78a"),false)
	for x in range(-14,-3,2):
		box(Vector3(x,0.105,24.5),Vector3(0.72,0.025,2.2),paint("#e4ddc8"),false)


func creek() -> void:
	section("MillCreek")
	var stone := surface("#b9afba","sidewalk")
	box(Vector3(-47,-3.05,0),Vector3(8.3,0.4,128),stone)
	box(Vector3(-47,-2.58,0),Vector3(8.2,0.06,128),surface("#a1c8bd","water",0.17),false)
	var water := add(part,Area3D.new(),"CreekWater") as Area3D
	water.collision_layer = 16
	water.collision_mask = 0
	water.monitoring = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(8,0.88,128)
	var hit := add(water,CollisionShape3D.new(),"Waterline") as CollisionShape3D
	hit.shape = shape
	hit.position = Vector3(-47,-2.72,0)
	for z: float in [-35,3,32]:
		box(Vector3(-47,-0.15,z),Vector3(8.6,0.35,8),stone)
		for s: float in [-1,1]:
			box(Vector3(-47,0.46,z+s*3.85),Vector3(8.8,0.88,0.32),stone)
			for x: float in [-49.3,-44.7]:
				# Headwall jambs frame the open culvert under the crossing.
				box(Vector3(x,-1.47,z+s*3.87),Vector3(0.58,2.65,0.5),stone)
		shelter("Culvert",Vector3(-47,-1.61,z),Vector3(8,2.42,7.85))
	for z: float in [-15,48]:
		box(Vector3(-44.9,-1.51,z),Vector3(3.4,0.22,14.7),stone,true,Vector3(11,0,0))
		box(Vector3(-45.4,-0.18,z-7.4),Vector3(5.4,0.32,1.3),stone)
	# West bank footpath with a maintenance gate at the tower.
	box(Vector3(-57,0.015,0),Vector3(4,0.03,127),surface("#adb7a4","sidewalk"),false)
	for z in range(-57,64,14):
		if abs(z+43)>8:
			model("graveyard","pine-crooked",Vector3(-61,0,z),4.7,z*4,false)
			collider(Vector3(-61,1.6,z),Vector3(0.65,3.2,0.65))
	prop("municipal_tank",Vector3(-56,0,-44))


func house(id: String, at: Vector3, yaw: float, porch_light: bool) -> void:
	section("Juniper"+id.to_upper())
	part.position = at
	part.rotation_degrees.y = yaw
	var house_tints := {"a":"#e7af8b","f":"#d2c09b","h":"#a0b1be","k":"#c6a2aa","p":"#acc3aa","c":"#e4c696"}
	model("suburban","building-type-"+id,Vector3.ZERO,12,0,true,house_tints[id])
	var posts := paint("#e3d0b0")
	var roof := surface("#acc4c2","shingles_teal")
	box(Vector3(0,0.035,7.6),Vector3(6.8,0.07,3.8),surface("#decfae","wood"))
	box(Vector3(0,3.0,7.2),Vector3(6.9,0.27,4.9),roof)
	for x: float in [-3.15,3.15]:
		box(Vector3(x,1.44,9.32),Vector3(0.19,2.88,0.19),posts)
		box(Vector3(x*0.79,0.8,9.32),Vector3(1.6,0.13,0.14),posts,false)
	shelter("FrontPorch",Vector3(0,1.4,7.78),Vector3(6.6,2.8,3.55))
	prop("breezeway",Vector3(8.7,0,0))
	box(Vector3(8.7,0.025,6.9),Vector3(4.8,0.05,7.5),surface("#c8c5bf","sidewalk"),false)
	box(Vector3(-2.7,2.68,9.42),Vector3(0.36,0.32,0.22),lit("#ffd394"),false)
	if porch_light:
		lamp(Vector3(-2.6,2.48,9.35),"#ffb071")
	box(Vector3(3.9,0.62,10.2),Vector3(0.13,1.24,0.13),posts)
	box(Vector3(3.9,1.24,10.2),Vector3(0.48,0.38,0.65),paint("#606e75"))
	box(Vector3(4.16,1.43,10.2),Vector3(0.06,0.25,0.19),paint("#bd685d"),false)


func fence(a: Vector3,b: Vector3) -> void:
	var wood := surface("#bba186","wood",0.35)
	var pale := paint("#cbb6a2")
	var count := ceili(a.distance_to(b)/1.1)
	var delta := (b-a)/count
	for i in count+1:
		var p := a+delta*i
		box(p+Vector3.UP*0.77,Vector3(0.13,1.54,0.13),pale,false)
	var rot := Vector3(0,rad_to_deg(atan2((b-a).x,(b-a).z)),0)
	for y: float in [0.42,1.12]:
		box((a+b)*0.5+Vector3.UP*y,Vector3(0.12,0.15,a.distance_to(b)),wood,false,rot)
	collider((a+b)*0.5+Vector3.UP*0.74,Vector3(0.18,1.48,a.distance_to(b)),rot)


func juniper_court() -> void:
	house("a",Vector3(-32,0,-24),90,true)
	house("f",Vector3(-20,0,-42),12,false)
	house("h",Vector3(1,0,-44),-14,true)
	house("k",Vector3(9,0,-16),-90,false)
	house("p",Vector3(-31,0,10),90,false)
	house("c",Vector3(10,0,9),-90,false)
	section("BackyardCuts")
	for x: float in [-40,17]:
		for span: Vector2 in [Vector2(-48,-34),Vector2(-29,-8),Vector2(-3,13)]:
			fence(Vector3(x,0,span.x),Vector3(x,0,span.y))
	for x in range(-38,15,20):
		fence(Vector3(x,0,-54),Vector3(x+15,0,-54))
	model("cars","sedan",Vector3(-24,0,18),4.65,-20)
	model("cars","hatchback-sports",Vector3(1,0,-30),4.3,55)


func churchyard() -> void:
	section("WaysideGrounds")
	prop("wayside_chapel",Vector3(32,0,-48))
	prop("lowell_mausoleum",Vector3(47,0,-10),180)
	# Open processional lawn centered on (46,-31), framed by burial rows.
	var gravel := surface("#c7b1b7","sidewalk",0.3)
	box(Vector3(46,0.022,-32),Vector3(3,0.044,30),gravel,false)
	box(Vector3(43,0.022,-47.5),Vector3(20,0.044,2.6),gravel,false)
	box(Vector3(29,0.022,-28),Vector3(2.6,0.044,15),gravel,false)
	var stones := ["gravestone-round","gravestone-cross","gravestone-wide","gravestone-bevel","gravestone-roof"]
	for i in 7:
		for x: float in [24,61]:
			var z := -49+i*5.5
			model("graveyard",stones[(i+int(x))%stones.size()],Vector3(x,0,z),1.45,i*3)
	for i in 5:
		model("graveyard",stones[i],Vector3(40+i*4.5,0,-53),1.55,(i-2)*6)
	for x: float in [21,60]:
		for z: float in [-57,-6]:
			model("graveyard","pine-fall-crooked",Vector3(x,0,z),4.9,z*2,false)
			collider(Vector3(x,1.7,z),Vector3(0.7,3.4,0.7))
	# Sectional iron rail and gate piers leave three passages into the yard.
	for x in [24,30,48,54,60]:
		model("graveyard","iron-fence-border",Vector3(x,0,-2),5.9)
	for x: float in [33,45]:
		model("graveyard","pillar-square",Vector3(x,0,-2),1.2)
	model("graveyard","bench",Vector3(36,0,-16),2.8,90)


func entrance() -> void:
	for i in 2:
		section("CornerMarket" if i==0 else "VideoRental")
		part.position = Vector3(-16+25*i,0,52)
		var face := paint("#415459" if i==0 else "#6d4d65")
		box(Vector3(0,2.8,0),Vector3(19,5.6,10),surface("#e1c8b0","siding"))
		box(Vector3(0,5.65,0),Vector3(19.45,0.4,10.4),face)
		box(Vector3(0,4.6,-5.14),Vector3(18.65,1.62,0.3),face,false)
		label("CLOVER  FOODS" if i==0 else "NIGHT OWL VIDEO",Vector3(0,4.62,-5.32),0.94,"#ffe3ae" if i==0 else "#ffc7ca",180)
		for x: float in [-6,0,6]:
			box(Vector3(x,1.98,-5.10),Vector3(4.8,1.72,0.19),paint("#476975"),false)
			box(Vector3(x,1.98,-5.23),Vector3(0.12,1.74,0.12),face,false)
		box(Vector3(0,3.48,-6.65),Vector3(19.75,0.27,3.6),surface("#f5ddc1","awning_cyan" if i==0 else "awning_pink"))
		shelter("ShopAwning",Vector3(0,1.64,-6.77),Vector3(19.4,3.28,3.37))
	section("ShoppingParade")
	box(Vector3(-3.5,0.025,48),Vector3(48,0.05,22),surface("#c4b8bd","asphalt"))
	# Delivery passage between shops. A rear wall and parked bread van
	# screen all four arrivals, with room to peel off to either sidewalk.
	box(Vector3(-3.5,1.8,56.7),Vector3(6.6,3.6,0.32),surface("#d3bbaa","siding"))
	model("cars","delivery",Vector3(-4,0,42.5),6.4,90)
	for x in range(-27,24,4):
		box(Vector3(x,0.072,40.4),Vector3(0.1,0.028,3.9),paint("#cdbba8"),false)
	model("roads","dumpster",Vector3(18,0,58),2.6,25)
	model("cars","van",Vector3(-26,0,39),5.1,64)
	section("SchoolCrossing")
	for x: float in [-18,33]:
		model("roads","light-curved",Vector3(x,0,37),2.1)
	lamp(Vector3(32.7,4.3,36.5),"#ffb678")


func park() -> void:
	section("RocketPark")
	box(Vector3(42,0.035,16),Vector3(22,0.07,12),surface("#ce9768","pavers"),false)
	prop("rocket_playground",Vector3(40,0.08,15))
	model("graveyard","bench",Vector3(29,0,15),3.1,-85)
	model("graveyard","bench",Vector3(52.5,0,20),3.1,88)
	for p: Vector2 in [Vector2(26,8),Vector2(58,10),Vector2(55,25),Vector2(-37,49),Vector2(-33,-5),Vector2(-1,61),Vector2(28,57),Vector2(56,54),Vector2(53,40),Vector2(23,45)]:
		prop("october_maple",Vector3(p.x,0,p.y),p.x*4)
	fence(Vector3(29,0,24),Vector3(42,0,24))
	fence(Vector3(47,0,24),Vector3(57,0,24))


func october_maple() -> void:
	start_scene("OctoberMaple")
	var bark := surface("#705b59","wood",0.45)
	tube(Vector3(0,1.95,0),0.44,3.9,bark,0.56,true)
	for i in 5:
		var a := i*TAU/5.0+0.4
		var tip := Vector3(2.1*cos(a),3.96+0.48*(i%3),2.1*sin(a))
		beam(Vector3(0,1.85+0.23*i,0),tip,0.28,bark)
		var leaf := paint(["#c17956","#b66b5e","#ce8f5f","#ac6158","#d69d68"][i])
		tube(tip+Vector3.UP*0.63,0.97,1.6,leaf,2.12)
		tube(tip+Vector3.UP*2.24,2.06,1.65,leaf,0.34)
	tube(Vector3(0,5.8,0),2.1,2.3,paint("#cf9165"),0.54)
	finish_prop("october_maple")


func town_details() -> void:
	section("TownLimits")
	var timber := paint("#6b5b62")
	for x: float in [19.1,25.1]:
		box(Vector3(x,1.5,21.5),Vector3(0.26,3,0.26),timber)
	box(Vector3(22.1,2.1,21.5),Vector3(7.6,2.35,0.32),paint("#475b61"))
	box(Vector3(22.1,3.32,21.5),Vector3(7.9,0.17,0.49),paint("#e1c89d"))
	label("MAPLE HOLLOW",Vector3(22.1,2.39,21.69),0.68,"#f5d3a6")
	label("EST.  1891",Vector3(22.1,1.60,21.69),0.40,"#e6bc8f")
	section("TelephoneLine")
	for x in [-36,-8,20,48]:
		box(Vector3(x,3.9,37.6),Vector3(0.27,7.8,0.27),timber)
		box(Vector3(x,7.36,37.6),Vector3(0.24,0.18,2.3),timber,false)
		for z: float in [36.75,38.45]:
			tube(Vector3(x,7.61,z),0.12,0.27,paint("#8d9b9a"))
			if x < 48:
				beam(Vector3(x,7.73,z),Vector3(x+14,6.88,z),0.055,timber)
				beam(Vector3(x+14,6.88,z),Vector3(x+28,7.73,z),0.055,timber)
	section("OutlyingWoodland")
	var verge := surface("#b4bea2","grass",0.12)
	for side: int in [-1,1]:
		box(Vector3(side*124,-0.16,0),Vector3(120,0.3,128),verge,false)
		for span: Vector2 in [Vector2(-184,-51),Vector2(-43,184)]:
			box(Vector3((span.x+span.y)/2,-0.16,side*125),Vector3(span.y-span.x,0.3,122),verge,false)
		box(Vector3(-47,-2.6,side*125),Vector3(8,0.12,122),surface("#a1c8bd","water",0.17),false)
		box(Vector3(side*109,0.025,32),Vector3(90,0.06,9.4),surface("#ccc7d5","asphalt"),false)
		model("roads","construction-barrier",Vector3(side*62,0.08,31.2),4.1,86)
		model("roads","construction-barrier",Vector3(side*61,0.08,35.5),3.8,96)
	# Irregular stands of two-tier evergreens enclose the horizon. Keep the
	# verge clear beside the road and leave the open creek visible from shore.
	for i in 112:
		var a := i*2.39996
		var direction := Vector3(cos(a),0,sin(a))
		var p := direction*(72+fmod(i*5.23,32.0))/maxf(absf(direction.x),absf(direction.z))
		if absf(p.z-32)<6 or absf(p.x+47)<4: continue
		var h := 4.8+fmod(i*3.7,5.0)
		var crown := paint(["#495c5d","#526969","#5b6460","#685d67"][i%4])
		tube(p+Vector3.UP*(h*0.18),0.24,h*0.36,timber)
		tube(p+Vector3.UP*(h*0.48),h*0.31,h*0.55,crown,0.13)
		tube(p+Vector3.UP*(h*0.78),h*0.22,h*0.48,crown,0.025)


func markers() -> void:
	points("PlayerSpawns","player_spawn",[Vector2(-4.8,51),Vector2(-2.6,51),Vector2(-4.8,53.2),Vector2(-2.6,53.2)])
	points("EnemySpawns","enemy_spawn",[Vector2(-61,53),Vector2(-59,8),Vector2(-59,-32),Vector2(-37,-60),Vector2(-6,-60),Vector2(18,-58),Vector2(55,-59),Vector2(61,-39),Vector2(59,-10),Vector2(60,46),Vector2(34,59),Vector2(-30,60)])
	points("CrateSpawns","crate_spawn",[Vector2(-57,35),Vector2(-38,3),Vector2(-27,-6),Vector2(-11,-29),Vector2(-35,-43),Vector2(8,-32),Vector2(33,-22),Vector2(48,-42),Vector2(52,9),Vector2(23,30),Vector2(-10,39),Vector2(27,53)])
	for p: Vector2 in [Vector2(-39,-35),Vector2(-37,3),Vector2(-38,30),Vector2(-16,22),Vector2(-19,-25),Vector2(6,30)]:
		drain(Vector3(p.x,0.09,p.y))
	drain(Vector3(-47,-2.81,-30))
	drain(Vector3(-47,-2.81,7.8))
	shower("CloverFoods",Vector3(-21,0.06,45.5))
	shower("ChapelPorch",Vector3(31,0,-36.5))
	shower("JuniperPorch",Vector3(-24,0,-24))
	marker("","boss_anchor","BossAnchor",Vector3(46,18,-32))
	puddles([Vector3(-37,2.7,32),Vector3(-27,2,40),Vector3(11,2.4,40),Vector3(25,3.2,31),Vector3(-9,2.4,15),Vector3(-12,2,-5),Vector3(-21,2.2,-20),Vector3(-3,2.2,-28),Vector3(-37,2,-34),Vector3(-57,2.2,-12),Vector3(38,3,-27),Vector3(56,2.5,-39),Vector3(25,2.2,5),Vector3(50,2,19)])
	for pool: Area3D in directories.Puddles.get_children():
		if Vector2(pool.position.x+9,pool.position.z+16).length() < 14.8:
			pool.position.y = 0.12
