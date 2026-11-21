class_name GameIcon
extends Control
## Small geometric pictograms shared by cards, HUD and world signage.

@export var kind := "health":
	set(v):
		if kind != v:
			kind = v
			queue_redraw()
@export var color := Color("#e8e9d5"):
	set(v):
		if color != v:
			color = v
			queue_redraw()
var value := 1.0:
	set(v):
		if not is_equal_approx(value, v):
			value = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 64.0
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * scale_factor)
	match kind:
		"health", "regen":
			draw_rect(Rect2(-6, -22, 12, 44), color)
			draw_rect(Rect2(-22, -6, 44, 12), color)
			if kind == "regen":
				draw_line(Vector2(-25, 25), Vector2(25, -25), Color("#ff5689"), 6, true)
		"suit", "armor", "department":
			var shield := PackedVector2Array([Vector2(-23,-23),Vector2(23,-23),Vector2(20,9),Vector2(0,27),Vector2(-20,9)])
			draw_colored_polygon(shield, color * Color(1,1,1,0.2))
			shield.append(shield[0])
			draw_polyline(shield, color, 4, true)
			draw_line(Vector2(0,-15), Vector2(0,14), color, 4, true)
		"spores":
			for i in 7:
				var direction := Vector2.from_angle(i * TAU / 7.0)
				draw_line(direction * 9, direction * 24, color, 3, true)
				draw_circle(direction * 24, 4, color)
			draw_circle(Vector2.ZERO, 11, color)
		"swarm", "enemy":
			var count := 3 if kind == "swarm" else 1
			for i in count:
				var center := Vector2((i - (count - 1)*0.5)*19, -6 if i % 2 == 0 else 6)
				draw_circle(center, 8, color)
				draw_line(center + Vector2(-8,18), center + Vector2(8,18), color, 8, true)
		"runners":
			draw_circle(Vector2(8,-22), 6, color)
			_line([Vector2(0,-12), Vector2(-6,5), Vector2(-22,21)], 6)
			_line([Vector2(-6,5), Vector2(12,10), Vector2(18,24)], 6)
			_line([Vector2(-12,-5), Vector2(0,-12), Vector2(14,-3), Vector2(25,-7)], 4)
		"splitters":
			_line([Vector2(0,-26),Vector2(0,-5),Vector2(-20,20)], 6)
			_line([Vector2(0,-5),Vector2(20,20)], 6)
			draw_circle(Vector2(-20,20), 7, color)
			draw_circle(Vector2(20,20), 7, color)
		"ammo":
			for x in [-16, 0, 16]:
				draw_rect(Rect2(x-5,-12,10,33), color)
				draw_colored_polygon(PackedVector2Array([Vector2(x-5,-12),Vector2(x,-23),Vector2(x+5,-12)]), color)
		"shower":
			_line([Vector2(-20,25),Vector2(-20,-20),Vector2(4,-20),Vector2(15,-8)], 4)
			draw_line(Vector2(3,-7),Vector2(24,-7),color,5,true)
			for x in [6,14,22]:
				draw_line(Vector2(x,1),Vector2(x-4,19),color,3,true)
		"tarp":
			var spread := lerpf(7,26,value)
			_line([Vector2(-spread,17),Vector2(0,-22),Vector2(spread,17),Vector2(-spread,17)], 4)
		"weather":
			for i in 3:
				draw_circle(Vector2(-16+i*16,-12), 10, color)
			for i in ceili(value * 5):
				var x := -22+i*10
				draw_line(Vector2(x,5),Vector2(x-6,23),color,3,true)
		"lever":
			draw_rect(Rect2(-25,12,50,15), color)
			var end := Vector2(18,-23).lerp(Vector2(-18,7),value)
			draw_line(Vector2(0,12),end,color,6,true)
			draw_circle(end,9,Color("#ff5689"))
		"unlock":
			draw_rect(Rect2(-20,-2,40,28),color)
			draw_arc(Vector2(0,-4),15,PI,TAU,20,color,4,true)
		"bus":
			draw_rect(Rect2(-23,-23,46,40),color,false,4)
			draw_rect(Rect2(-15,-15,30,13),color)
			for x in [-15,15]:
				draw_circle(Vector2(x,22),5,color)
		"park":
			draw_colored_polygon(PackedVector2Array([Vector2(0,-27),Vector2(25,12),Vector2(-25,12)]),color)
			draw_rect(Rect2(-4,12,8,17),color)
		# Ping wheel (ui/ping_hud.gd).
		"go":
			draw_arc(Vector2(0,-8), 15, 0, TAU, 24, color, 5, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-13,0),Vector2(13,0),Vector2(0,27)]), color)
			draw_circle(Vector2(0,-8), 5, color)
		"danger":
			var triangle := PackedVector2Array([Vector2(0,-26),Vector2(26,22),Vector2(-26,22)])
			draw_colored_polygon(triangle, color * Color(1,1,1,0.2))
			triangle.append(triangle[0])
			draw_polyline(triangle, color, 5, true)
			draw_line(Vector2(0,-10), Vector2(0,7), color, 6, true)
			draw_circle(Vector2(0,15), 3.5, color)
		"crate":
			draw_rect(Rect2(-22,-18,44,38), color, false, 5)
			draw_line(Vector2(-22,-6), Vector2(22,-6), color, 4, true)
			draw_rect(Rect2(-5,-10,10,9), color)
		"shelter":
			_line([Vector2(-27,4),Vector2(0,-17),Vector2(27,4)], 6)
			draw_line(Vector2(-19,4), Vector2(-19,27), color, 4, true)
			draw_line(Vector2(19,4), Vector2(19,27), color, 4, true)
			for x in [-12, 0, 12]:
				draw_line(Vector2(x+3,-31), Vector2(x,-24), color * Color(1,1,1,0.6), 3, true)
		"objective":
			var diamond := PackedVector2Array([Vector2(0,-26),Vector2(26,0),Vector2(0,26),Vector2(-26,0),Vector2(0,-26)])
			draw_polyline(diamond, color, 5, true)
			draw_circle(Vector2.ZERO, 7, color)
		# HUD status glyphs (ui/hud.gd).
		"rain":
			draw_colored_polygon(PackedVector2Array([Vector2(0,-27),Vector2(15,4),Vector2(10,18),
				Vector2(0,23),Vector2(-10,18),Vector2(-15,4)]), color)
		"skull":
			draw_circle(Vector2(0,-5), 21, color)
			draw_rect(Rect2(-12,8,24,17), color)
			draw_circle(Vector2(-8,-5), 6, Color(0.05,0.08,0.12))
			draw_circle(Vector2(8,-5), 6, Color(0.05,0.08,0.12))
			for x in [-6, 0, 6]:
				draw_line(Vector2(x,15), Vector2(x,25), Color(0.05,0.08,0.12), 2)
		"scrap":
			_line([Vector2(-20,-12),Vector2(4,-24),Vector2(24,-6),Vector2(16,20),Vector2(-14,22),Vector2(-24,4),Vector2(-20,-12)], 5)
			draw_circle(Vector2(0,0), 7, color)
		"check":
			_line([Vector2(-22,0),Vector2(-6,16),Vector2(22,-16)], 7)
		# Extra enemy mutations.
		"conductors":
			_line([Vector2(6,-26), Vector2(-10,-2), Vector2(4,-2), Vector2(-8,26)], 6)
			draw_circle(Vector2(6,-26), 4, color)
			draw_circle(Vector2(-8,26), 4, color)
		"molting":
			_line([Vector2(-22,12), Vector2(0,-22), Vector2(22,12)], 5)
			_line([Vector2(-14,22), Vector2(0,-4), Vector2(14,22)], 4)
			draw_line(Vector2(0,-22), Vector2(0,22), color * Color(1,1,1,0.5), 3, true)
		"undertow":
			draw_arc(Vector2.ZERO, 22, 0.2, PI * 1.4, 20, color, 5, true)
			draw_arc(Vector2.ZERO, 12, PI, TAU + 0.6, 16, color, 4, true)
			draw_circle(Vector2.ZERO, 4, color)
		"static_charge":
			draw_circle(Vector2.ZERO, 16, color, false, 4, true)
			_line([Vector2(3,-12), Vector2(-5,0), Vector2(3,0), Vector2(-3,12)], 4)
			for i in 6:
				var d := Vector2.from_angle(i * TAU / 6.0)
				draw_line(d * 20, d * 27, color, 3, true)
		"pressure_front":
			_line([Vector2(-26,0), Vector2(-9,0)], 5)
			_line([Vector2(-15,-8), Vector2(-8,0), Vector2(-15,8)], 4)
			_line([Vector2(26,0), Vector2(9,0)], 5)
			_line([Vector2(15,-8), Vector2(8,0), Vector2(15,8)], 4)
			draw_rect(Rect2(-5, -20, 10, 40), color)
		"false_clearing":
			draw_arc(Vector2(-8,-8), 11, 0, TAU, 18, color, 4, true)
			draw_circle(Vector2(6,4), 10, color)
			draw_circle(Vector2(-6,8), 9, color)
			draw_circle(Vector2(14,10), 8, color)
			draw_line(Vector2(-20,24), Vector2(22,-18), Color("#ff5689"), 4, true)
		# Player bio-mutations.
		"acid_blood":
			var drop := PackedVector2Array([Vector2(0,-25), Vector2(16,4), Vector2(10,20), Vector2(-10,20), Vector2(-16,4)])
			draw_colored_polygon(drop, color * Color(1,1,1,0.3))
			drop.append(drop[0])
			draw_polyline(drop, color, 4, true)
			draw_circle(Vector2(-22,-6), 4, color)
			draw_circle(Vector2(22,-4), 3.5, color)
		"chitin_suit":
			var hex := PackedVector2Array([Vector2(0,-25), Vector2(22,-12), Vector2(22,12), Vector2(0,25), Vector2(-22,12), Vector2(-22,-12)])
			draw_colored_polygon(hex, color * Color(1,1,1,0.22))
			hex.append(hex[0])
			draw_polyline(hex, color, 4, true)
			draw_line(Vector2(-14,0), Vector2(14,0), color, 4, true)
			draw_line(Vector2(0,-14), Vector2(0,14), color, 4, true)
		"adrenaline_glands":
			_line([Vector2(-20,16), Vector2(0,-4), Vector2(20,16)], 6)
			_line([Vector2(-20,-2), Vector2(0,-22), Vector2(20,-2)], 6)
		"bone_piercer":
			draw_circle(Vector2.ZERO, 15, color, false, 4, true)
			draw_line(Vector2(-26,18), Vector2(24,-18), color, 5, true)
			_line([Vector2(12,-20), Vector2(25,-19), Vector2(21,-6)], 4)
		"reflex_tendons":
			_line([Vector2(-22,-16), Vector2(-4,0), Vector2(-22,16)], 6)
			_line([Vector2(0,-16), Vector2(18,0), Vector2(0,16)], 6)
		"magnet_hands":
			draw_arc(Vector2(0,-2), 18, PI, TAU, 20, color, 6, true)
			draw_line(Vector2(-18,-2), Vector2(-18,18), color, 6, true)
			draw_line(Vector2(18,-2), Vector2(18,18), color, 6, true)
			draw_rect(Rect2(-22, 14, 8, 8), Color("#ff5689"))
			draw_rect(Rect2(14, 14, 8, 8), Color("#5ce8ff"))
		"voltaic_veins":
			_line([Vector2(-22,-16), Vector2(-4,-4), Vector2(-10,8), Vector2(22,18)], 5)
			_line([Vector2(-4,-4), Vector2(18,-18)], 4)
			draw_circle(Vector2(-22,-16), 5, color)
			draw_circle(Vector2(18,-18), 5, color)
			draw_circle(Vector2(22,18), 5, color)
		"vampiric_siphon":
			var siphon := PackedVector2Array([Vector2(0,-24), Vector2(18,4), Vector2(0,24), Vector2(-18,4)])
			draw_colored_polygon(siphon, color * Color(1,1,1,0.28))
			siphon.append(siphon[0])
			draw_polyline(siphon, color, 4, true)
			draw_line(Vector2(-8,2), Vector2(8,2), color, 4, true)
			draw_line(Vector2(0,-6), Vector2(0,10), color, 4, true)
		"blast_glands":
			for i in 8:
				var d := Vector2.from_angle(i * TAU / 8.0)
				draw_line(d * 6, d * (26 if i % 2 == 0 else 17), color, 4, true)
			draw_circle(Vector2.ZERO, 7, color)
		"hydro_skin":
			draw_arc(Vector2.ZERO, 22, 0, TAU, 24, color, 4, true)
			var droplet := PackedVector2Array([Vector2(0,-14), Vector2(10,4), Vector2(0,13), Vector2(-10,4)])
			draw_colored_polygon(droplet, color)
		"hyper_focus":
			draw_circle(Vector2.ZERO, 17, color, false, 4, true)
			draw_circle(Vector2.ZERO, 4, color)
			draw_line(Vector2(0,-26), Vector2(0,-11), color, 4, true)
			draw_line(Vector2(0,11), Vector2(0,26), color, 4, true)
			draw_line(Vector2(-26,0), Vector2(-11,0), color, 4, true)
			draw_line(Vector2(11,0), Vector2(26,0), color, 4, true)
		_:
			draw_circle(Vector2.ZERO, 20, color, false, 4, true)


func _line(points: Array, width: float) -> void:
	draw_polyline(PackedVector2Array(points), color, width, true)
