extends "res://tools/levels/level_builder.gd"
## Harbor Point. North is the cannery railhead, south is the outer wharf.

func build() -> void:
	district = "harbor"
	container("freight_box", false)
	container("through_container", true)
	gantry()
	beacon()
	trawler()
	begin_map("HarborPoint",true)
	waterfront()
	canneries()
	freight_yard()
	outer_wharf()
	bait_shop()
	port_authority()
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
	var concrete := surface("#afbebb","sidewalk")
	box(Vector3(0,-0.95,-26),Vector3(128,1.9,76),surface("#d0d6d6","asphalt"))
	box(Vector3(18,-0.95,46),Vector3(92,1.9,36),concrete)
	# A walkable tidal bed and two sloped slipways let players recover from
	# either side of the docks. The water volume ends below the decking.
	box(Vector3(0,-2.45,0),Vector3(128,0.6,128),concrete)
	box(Vector3(0,-1.83,46),Vector3(128,0.06,36),surface("#bed9cf","harbor_tide",0.06),false)
	box(Vector3(0,-1.83,20),Vector3(128,0.06,16),surface("#bed9cf","harbor_tide",0.06),false)
	var tide := add(part,Area3D.new(),"StandingWater") as Area3D
	tide.collision_layer = 16
	tide.collision_mask = 0
	tide.monitoring = false
	var wet := BoxShape3D.new()
	wet.size = Vector3(128,1.0,53)
	var hit := add(tide,CollisionShape3D.new(),"Waterline") as CollisionShape3D
	hit.shape = wet
	hit.position = Vector3(0,-1.98,38)
	for p in [Vector3(-32,-1.15,18),Vector3(-12,-1.15,22)]:
		var tilt := 10.4 if p.x < -20 else -10.4
		box(p,Vector3(7,0.3,13.6),concrete,true,Vector3(tilt,0,0))
	for x: float in [-56,-43]:
		box(Vector3(x,-0.34,34),Vector3(3.8,0.68,44),surface("#e6c997","wood",0.45))
		for z in range(15,57,7):
			for edge: float in [-1.85,1.85]:
				tube(Vector3(x+edge,-0.6,z),0.22,3.3,paint("#5f5050"),1,true)
	box(Vector3(-42.3,-0.34,54),Vector3(31.5,0.68,4),surface("#e6c997","wood",0.45))
	# Tide gauge and hazard stripes identify the drivable concrete slip.
	box(Vector3(-36.2,1.05,11.5),Vector3(0.24,2.1,0.24),paint("#645947"))
	box(Vector3(-36.2,2.1,11.5),Vector3(3.4,0.86,0.14),paint("#345866"))
	label("BOAT RAMP",Vector3(-36.2,2.12,11.41),0.35,"#ffe4ac",180)
	for x: float in [-35,-29]:
		box(Vector3(x,0.021,8.1),Vector3(0.18,0.04,6.7),paint("#d8a858"),false)
	prop("shrimp_boat",Vector3(-50,-1.27,37),174)
	prop("shrimp_boat",Vector3(-60,-1.27,22),6)
	# Sea beyond the map and distant breakwater silhouettes.
	box(Vector3(0,-2.7,55),Vector3(1200,0.12,1000),surface("#a9bfca","harbor_tide",0.035),false)
	for i in 12:
		box(Vector3(-135+i*22,-1,114+sin(i*1.7)*4),Vector3(22,2.5,4),paint("#758989"),false)


func canneries() -> void:
	var names := ["NORTH STAR  /  ICE","HARBOR POINT CANNING CO.","PIER 3  /  COLD STORE"]
	for i in 3:
		section("CanneryBay"+str(i+1))
		part.position = Vector3(-41+i*40,0,-47)
		var wall := surface(["#98c4bd","#dc9b73","#abc7c3"][i],"quay_steel",0.26)
		var steel := paint("#354f59")
		box(Vector3(0,4.3,0),Vector3(30,8.6,16),wall)
		for side: float in [-1,1]:
			box(Vector3(0,9.28,side*4.25),Vector3(31.2,0.42,8.9),steel,true,Vector3(side*10,0,0))
		box(Vector3(0,8.9,0),Vector3(30,0.75,11),wall)
		box(Vector3(0,7.25,8.18),Vector3(26,1.65,0.32),steel,false)
		label(names[i],Vector3(0,7.3,8.37),0.95,"#ffe1a4")
		for x: float in [-9,0,9]:
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


func outer_wharf() -> void:
	section("LiftBridge")
	var iron := paint("#395a60")
	box(Vector3(0,-0.32,20),Vector3(10,0.64,16.3),surface("#c2d3cb","diamond_plate"))
	for x: float in [-4.9,4.9]:
		box(Vector3(x,1.05,20),Vector3(0.2,0.18,16),iron)
		for z in [12.5,16.5,20.5,24.5,27.5]:
			box(Vector3(x,0.6,z),Vector3(0.22,1.2,0.22),iron)
		for z: float in [14,26]:
			box(Vector3(x,3.6,z),Vector3(0.48,7.2,0.48),iron)
			beam(Vector3(x,6.9,z),Vector3(x,1,20),0.18,paint("#cc9353"))
	for z: float in [14,26]:
		box(Vector3(0,7.1,z),Vector3(10.5,0.45,0.54),iron)
	section("PilotsWalk")
	box(Vector3(45,-0.25,20),Vector3(3.4,0.5,16.3),surface("#f0cfab","wood"))
	for z in [14,19,24,27]:
		tube(Vector3(46.5,-0.45,z),0.2,2.8,iron,1,true)
	section("BuoyYard")
	prop("harbor_light",Vector3(54,0,48))
	prop("hammerhead_crane",Vector3(-19,0,35),145)
	prop("through_container",Vector3(-16,0,51),90)
	prop("freight_box",Vector3(-16,0,58),90)
	for x in range(8,43,5):
		for z: float in [29.8,62]:
			box(Vector3(x,0.03,z),Vector3(2.7,0.035,0.22),paint("#ae754f"),false)
	for x: float in [-25,-4,18,40,60]:
		tube(Vector3(x,0.48,28.7),0.42,0.96,iron,1,true)
		tube(Vector3(x,0.99,28.7),0.55,0.14,paint("#e5ab66"))
	lamp(Vector3(-18,4,35),"#ffb66c")


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
	section("BridgeTender")
	box(Vector3(9,-0.36,17),Vector3(5.5,0.72,11.2),surface("#c6b293","wood"))
	box(Vector3(9,1.4,14.3),Vector3(4.1,2.8,3.6),surface("#8ba69b","quay_steel"))
	box(Vector3(9,2.03,16.15),Vector3(3.55,0.77,0.12),iron,false)
	box(Vector3(9,2.93,14.45),Vector3(4.7,0.24,4.15),ochre)
	# Leave an access walkway along the east side of the control booth.
	box(Vector3(12,-0.36,17),Vector3(2.4,0.72,11.2),surface("#c6b293","wood"))
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


func markers() -> void:
	points("PlayerSpawns","player_spawn",[Vector2(-45.85,-14.8),Vector2(-44.15,-14.8),Vector2(-45.85,-12.3),Vector2(-44.15,-12.3)])
	points("EnemySpawns","enemy_spawn",[Vector2(-59,-52),Vector2(-43,-59),Vector2(-5,-60),Vector2(37,-59),Vector2(59,-46),Vector2(60,-13),Vector2(61,32),Vector2(62,58),Vector2(4,61),Vector2(-24,58),Vector2(-56,50),Vector2(-60,-24)])
	points("CrateSpawns","crate_spawn",[Vector2(-57,-28),Vector2(-23,-28),Vector2(11,-28),Vector2(48,-32),Vector2(-29,-7),Vector2(27,0),Vector2(-43,40),Vector2(0,22),Vector2(32,47),Vector2(-5,53),Vector2(45,25),Vector2(50,39)])
	for p: Vector2 in [Vector2(-54,-29),Vector2(-26,-28),Vector2(0,-28),Vector2(32,-28),Vector2(-30,5),Vector2(35,8),Vector2(17,34),Vector2(49,40)]:
		drain(Vector3(p.x,0.02,p.y))
	shower("IceHouse",Vector3(-48,0,-35))
	shower("PilotsStore",Vector3(56,0,11))
	shower("BuoyShed",Vector3(-15,0,51))
	marker("","boss_anchor","BossAnchor",Vector3(27,18,46))
	puddles([Vector3(-57,3,-20),Vector3(-33,3,-30),Vector3(-10,3.2,-23),Vector3(2,2,-32),Vector3(30,3,-25),Vector3(55,3,-33),Vector3(-26,3,-3),Vector3(-4,2.5,5),Vector3(34,2.8,0),Vector3(48,2.4,6),Vector3(0,2.5,18),Vector3(12,3.2,34),Vector3(32,3.5,48),Vector3(-1,2,52),Vector3(50,2.5,57),Vector3(-50,2,5)])
