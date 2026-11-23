extends Control
## Fortnite-style dynamic spread crosshair plus status rings:
## - Dynamic angular spread ticks (firearms), corner spread box (shotguns),
##   curved cone arcs (pressure washer / leaf blower), launcher reticle, and
##   converging charge ring (Weather-Radio Disruptor).
## - Hold-to-interact arc, reload ring, jam tint, hit/crit/kill markers, and
##   downed bleed-out countdown.

enum Style { CROSS, SHOTGUN, STREAM, LAUNCHER, CHARGE }

var progress := 0.0
var targeted := false
var hit_left := 0.0
var critical := false
var killed := false
var reload := 0.0
var jammed := false
var downed := false
var bleed := 0.0
var bleed_seconds := 0

var style := Style.CROSS
var target_spread := 6.0
var spread_px := 6.0
var charge := 0.0
var charging := false
var ads_tight := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit(is_kill: bool, is_critical: bool) -> void:
	hit_left = 0.28 if is_kill else 0.13
	critical = is_critical
	killed = is_kill


func _process(delta: float) -> void:
	hit_left = maxf(0.0, hit_left - delta)
	# Snappy Fortnite bloom: expands almost instantly on shot/move, settles crisply.
	var speed := 26.0 if target_spread > spread_px else 16.0
	spread_px = lerpf(spread_px, target_spread, 1.0 - exp(-speed * delta))
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	if downed:
		_draw_bleed(center)
	else:
		var color := BroadcastUI.CYAN if targeted else Color(1, 1, 1, 0.92 if ads_tight else 0.80)
		if jammed:
			color = BroadcastUI.PINK
		elif charging and charge >= 1.0:
			color = BroadcastUI.AMBER
		elif charging:
			color = BroadcastUI.CYAN.lerp(BroadcastUI.PINK, charge)
		_draw_reticle(center, color)
	if progress > 0.0:
		draw_arc(center, 22, -PI / 2, -PI / 2 + TAU * progress, 40, BroadcastUI.CYAN, 4, true)
	elif charging:
		var ring_r := 18.0
		var ring_col := BroadcastUI.AMBER if charge >= 1.0 else BroadcastUI.CYAN.lerp(BroadcastUI.PINK, charge)
		draw_arc(center, ring_r, 0, TAU, 36, Color(BroadcastUI.INK, 0.55), 4, true)
		draw_arc(center, ring_r, -PI / 2, -PI / 2 + TAU * clampf(charge, 0.0, 1.0), 36, ring_col, 2.6, true)
		if charge >= 1.0:
			var font := BroadcastUI.FONT
			var txt := "READY"
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string_outline(font, center + Vector2(-tw * 0.5, 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, BroadcastUI.INK)
			draw_string(font, center + Vector2(-tw * 0.5, 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, BroadcastUI.AMBER)
	elif reload > 0.0:
		draw_arc(center, 16, 0, TAU, 32, Color(BroadcastUI.INK, 0.6), 3, true)
		draw_arc(center, 16, -PI / 2, -PI / 2 + TAU * reload, 32, BroadcastUI.PAPER, 2, true)
	if hit_left > 0.0:
		var hit_color := Color("#ffd56a") if critical else (BroadcastUI.PINK if killed else Color.WHITE)
		var duration := 0.28 if killed else 0.13
		var pulse := 0.0 if Settings.reduced_flash else (hit_left / duration) * (6.0 if critical or killed else 3.0)
		var inner := (13.0 if killed else 10.0) + pulse
		var outer := inner + (9.0 if critical or killed else 6.0)
		for i in 4:
			var direction := Vector2.from_angle(PI / 4 + i * PI / 2)
			draw_line(center + direction * inner, center + direction * outer, Color.BLACK, 5, true)
			draw_line(center + direction * inner, center + direction * outer, hit_color, 3, true)


func _draw_reticle(center: Vector2, color: Color) -> void:
	var outline := Color(0, 0, 0, 0.82)
	# Crisp center dot (classic Fortnite anchor point).
	draw_circle(center, 2.7, outline)
	draw_circle(center, 1.6, color)
	match style:
		Style.SHOTGUN:
			# Fortnite-style shotgun spread brackets enclosing the pellet cone.
			var r := clampf(spread_px, 14.0, 92.0)
			var arm := clampf(r * 0.38, 7.0, 16.0)
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner := center + Vector2(sx * r, sy * r)
					var h_end := corner + Vector2(-sx * arm, 0.0)
					var v_end := corner + Vector2(0.0, -sy * arm)
					draw_line(h_end, corner, outline, 4.4, true)
					draw_line(corner, v_end, outline, 4.4, true)
					draw_line(h_end, corner, color, 2.2, true)
					draw_line(corner, v_end, color, 2.2, true)
		Style.STREAM:
			# Wide curved parenthesis arcs matching water jet / leaf blower cone width.
			var r := clampf(spread_px, 16.0, 84.0)
			var span := 0.58
			for base_angle in [0.0, PI]:
				draw_arc(center, r, base_angle - span, base_angle + span, 16, outline, 4.2, true)
				draw_arc(center, r, base_angle - span, base_angle + span, 16, color, 2.2, true)
		Style.LAUNCHER:
			# Curved arc reticle for lobbed flares, rockets, throwables & deployables.
			var r := clampf(spread_px, 13.0, 32.0)
			draw_arc(center, r, PI * 0.16, PI * 0.84, 20, outline, 4.0, true)
			draw_arc(center, r, PI * 0.16, PI * 0.84, 20, color, 2.0, true)
			for side in [-1.0, 1.0]:
				var p0 := center + Vector2(side * (r + 3.0), 0.0)
				var p1 := center + Vector2(side * (r + 9.0), 0.0)
				draw_line(p0, p1, outline, 4.0, true)
				draw_line(p0, p1, color, 2.0, true)
		Style.CHARGE:
			# Converging ticks tighten as charge builds toward 100%.
			var gap := lerpf(clampf(spread_px, 12.0, 26.0), 5.0, charge) if charging else clampf(spread_px, 8.0, 26.0)
			var tick_len := 7.0 if charging else 6.0
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(center + direction * gap, center + direction * (gap + tick_len), outline, 4.0, true)
				draw_line(center + direction * gap, center + direction * (gap + tick_len), color, 2.0, true)
		_:
			# Standard Fortnite 4-tick dynamic spread crosshair.
			var gap := clampf(spread_px, 4.5, 76.0)
			var tick_len := 6.0 if ads_tight else 7.5
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(center + direction * gap, center + direction * (gap + tick_len), outline, 4.0, true)
				draw_line(center + direction * gap, center + direction * (gap + tick_len), color, 2.0, true)


func _draw_bleed(center: Vector2) -> void:
	var radius := 30.0
	draw_arc(center, radius, 0, TAU, 48, Color(BroadcastUI.INK, 0.65), 6, true)
	draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * clampf(bleed, 0.0, 1.0), 48, BroadcastUI.PINK, 4, true)
	var text := str(bleed_seconds)
	var font := BroadcastUI.FONT
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string_outline(font, center + Vector2(-width * 0.5, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 3, BroadcastUI.INK)
	draw_string(font, center + Vector2(-width * 0.5, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, BroadcastUI.PINK)
