extends RefCounted
## A short pseudo-3D sprint against six cars. Distances are in race metres.

const RACE_LENGTH := 6500.0
const TIME_LIMIT := 48.0
const RIVAL_COLORS := [Color("f1b568"), Color("d387dc"), Color("72ddb7"), Color("8fa3ee"), Color("f08884"), Color("d5dae9")]
var score: int = 0
var finished: bool = false
var status: String = ""
var distance: float = 0.0
var speed: float = 0.0
var lane: float = 0.0
var elapsed: float = 0.0
var nitro: float = 5.0
var rank: int = 7
var rivals: Array[Dictionary] = []
var collisions: int = 0
var boosting: bool = false
var sound_events: Array[String] = []
var near_misses := 0
var _boost_was_active := false
var _impact_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func title() -> String:
	return "Pista Neon"

func instructions() -> String:
	return "← → dirigir  •  ↑ / Ação: acelerar  •  ↓ frear  •  Alternativa: nitro"

func reset(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	score = 0
	finished = false
	status = "PÉ NO ACELERADOR"
	distance = 0.0
	speed = 0.0
	lane = 0.0
	elapsed = 0.0
	nitro = 5.0
	rank = 7
	collisions = 0
	boosting = false
	sound_events.clear()
	near_misses = 0
	_boost_was_active = false
	_impact_timer = 0.0
	rivals.clear()
	for i in range(6):
		rivals.append({"distance": 120.0 + i * 125.0, "lane": [-0.62, 0.0, 0.62][i % 3], "speed": 172.0 + i * 4.5, "phase": _rng.randf_range(0.0, TAU), "passed":false})

func step(delta: float, controls: Dictionary) -> void:
	if finished:
		return
	var dt := clampf(delta, 0.0, 0.1)
	elapsed += dt
	_impact_timer = maxf(0.0, _impact_timer - dt)
	var accelerating := bool(controls.get("up", false)) or bool(controls.get("action", false))
	var braking := bool(controls.get("down", false))
	boosting = bool(controls.get("action_alt", false)) and nitro > 0.0 and accelerating and not braking
	if boosting and not _boost_was_active: sound_events.append("nitro")
	_boost_was_active = boosting
	var top_speed := 315.0 if boosting else 248.0
	if boosting:
		nitro = maxf(0.0, nitro - dt)
	elif absf(lane) <= 1.0 and speed > 130.0:
		nitro = minf(5.0,nitro + dt*.14)
	if braking:
		speed = move_toward(speed, 0.0, 190.0 * dt)
	elif accelerating:
		speed = move_toward(speed, top_speed, (150.0 if boosting else 95.0) * dt)
	else:
		speed = move_toward(speed, 0.0, 42.0 * dt)
	var digital := float(bool(controls.get("right", false))) - float(bool(controls.get("left", false)))
	var steering := clampf(float(controls.get("steering",digital)),-1.0,1.0)
	lane += steering * dt * (0.7 + speed / 200.0)
	lane -= sin(distance / 760.0) * speed / 320.0 * dt * 0.45
	lane = clampf(lane, -1.4, 1.4)
	if absf(lane) > 1.0:
		speed = move_toward(speed, 92.0, 210.0 * dt)
	distance += speed * dt
	for rival in rivals:
		var old_gap := float(rival["distance"]) - distance + speed * dt
		var target_lane := sin(elapsed*.65+float(rival["phase"]))*.64
		# Opponents change line smoothly; close encounters remain readable.
		if absf(float(rival["distance"])-distance) > 110.0:
			rival["lane"] = move_toward(float(rival["lane"]),target_lane,dt*.22)
		rival["distance"] = minf(RACE_LENGTH + 40.0, float(rival["distance"]) + float(rival["speed"]) * dt)
		var new_gap := float(rival["distance"]) - distance
		if old_gap > 0.0 and new_gap <= 0.0 and not bool(rival["passed"]):
			rival["passed"] = true
			if absf(float(rival["lane"])-lane) >= .24 and absf(float(rival["lane"])-lane) < .5:
				near_misses += 1
				nitro = minf(5.0,nitro+.7)
				sound_events.append("line")
		if _impact_timer <= 0.0 and absf(float(rival["distance"]) - distance) < 32.0:
			if absf(float(rival["lane"]) - lane) < 0.24:
				speed *= 0.38
				_impact_timer = 1.1
				collisions += 1
				sound_events.append("hit")
				lane = clampf(lane + (0.25 if lane >= float(rival["lane"]) else -0.25), -1.4, 1.4)
	rank = 1
	for rival in rivals:
		if float(rival["distance"]) > distance:
			rank += 1
	score = int(distance / 5.0) + (7 - rank) * 200 + near_misses * 150
	status = "%d / 7  •  %d%%" % [rank, mini(100, int(distance / RACE_LENGTH * 100.0))]
	if distance >= RACE_LENGTH:
		distance = RACE_LENGTH
		finished = true
		score += int(maxf(0.0, TIME_LIMIT - elapsed) * 50.0) + (1200 if rank == 1 else 0)
		status = String(TranslationServer.translate("CHEGADA  •  %dº LUGAR")) % rank
	elif elapsed >= TIME_LIMIT:
		finished = true
		status = "TEMPO ESGOTADO"

func _road_center(t: float) -> float:
	var ahead := 1600.0 * pow(1.0 - t, 2.0)
	return 400.0 + (sin((distance + ahead) / 760.0) - sin(distance / 760.0)) * 130.0 * (1.0 - t) - lane * 140.0 * t

func render(canvas: Control, area: Rect2) -> void:
	canvas.draw_set_transform(area.position, 0.0, area.size / Vector2(800, 480))
	canvas.draw_rect(Rect2(0, 0, 800, 480), Color("11152b"))
	for band in range(9):
		canvas.draw_rect(Rect2(0,band*20,800,20),Color("11152b").lerp(Color("533855"),float(band)/9.0))
	canvas.draw_rect(Rect2(0, 108, 800, 100), Color("393052"))
	canvas.draw_circle(Vector2(591, 112), 48.0, Color("f79d83"))
	for y in range(92, 156, 10):
		canvas.draw_rect(Rect2(540, y, 104, 4), Color("393052"))
	for i in range(18):
		var h := 21.0 + float((i * 73) % 67)
		canvas.draw_rect(Rect2(i * 48 - 20, 181 - h, 39, h), Color("1c203a"))
		for window in range(3):
			canvas.draw_rect(Rect2(i * 48 - 12 + window * 10, 185 - h, 3, 7), Color("705875"))
	for strip in range(36):
		var t0 := float(strip) / 36.0
		var t1 := float(strip + 1) / 36.0
		var y0 := 178.0 + t0 * 302.0
		var y1 := 178.0 + t1 * 302.0
		var center0 := _road_center(t0)
		var center1 := _road_center(t1)
		var width0 := 22.0 + t0 * 308.0
		var width1 := 22.0 + t1 * 308.0
		var stripe := posmod(int(distance / 34.0) + strip, 2) == 0
		canvas.draw_rect(Rect2(0, y0, 800, y1 - y0 + 1), Color("233b41") if stripe else Color("20353c"))
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(center0 - width0 - 9 * t0, y0), Vector2(center0 + width0 + 9 * t0, y0), Vector2(center1 + width1 + 9 * t1, y1 + 1), Vector2(center1 - width1 - 9 * t1, y1 + 1)]), Color("e4ddc3") if stripe else Color("ec6e79"))
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(center0 - width0, y0), Vector2(center0 + width0, y0), Vector2(center1 + width1, y1 + 1), Vector2(center1 - width1, y1 + 1)]), Color("292d40") if stripe else Color("2c3043"))
		if stripe:
			for side in [-1.0, 1.0]:
				canvas.draw_line(Vector2(center0 + side * width0 / 3.0, y0), Vector2(center1 + side * width1 / 3.0, y1), Color("d9d4c4"), maxf(1.0, t1 * 4.0))
		for side in [-1.0,1.0]:
			canvas.draw_line(Vector2(center0+side*(width0+12*t0),y0),Vector2(center1+side*(width1+12*t1),y1),Color("58d9df"),maxf(1,t1*3))
		if strip%6 == 0:
			for side in [-1.0,1.0]:
				var base := Vector2(center1+side*(width1+38*t1),y1)
				canvas.draw_line(base,base-Vector2(0,65*t1),Color("8792ae"),maxf(1,t1*4))
				canvas.draw_line(base-Vector2(0,65*t1),base+Vector2(-side*26*t1,-65*t1),Color("ffceab"),maxf(1,t1*4))
	# Sort only six references, far to near, for correct car overlap.
	var ordered: Array[Dictionary] = rivals.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) > float(b["distance"]))
	for rival in ordered:
		var ahead := float(rival["distance"]) - distance
		if ahead < -20.0 or ahead > 1500.0:
			continue
		var t := 1.0 - sqrt(clampf(ahead / 1600.0, 0.0, 1.0))
		var p := Vector2(_road_center(t) + float(rival["lane"]) * (22.0 + t * 308.0), 178.0 + t * 302.0)
		var color_index := rivals.find(rival)
		_draw_car(canvas, p, 0.18 + t * 0.86, RIVAL_COLORS[color_index], false)
	var shake := sin(elapsed * 65.0) * 3.0 if _impact_timer > 0.7 else 0.0
	var player_t := 0.95
	var player_point := Vector2(_road_center(player_t) + lane * (22.0 + player_t * 308.0) + shake, 178.0 + player_t * 302.0)
	_draw_car(canvas, player_point, 1.15, Color("55d5e4"), boosting)
	canvas.draw_rect(Rect2(20, 20, 164, 66), Color(0.035, 0.05, 0.11, 0.88))
	_text(canvas, Vector2(31, 46), "%d / 7" % rank, 23, Color("f9df93"))
	_text(canvas, Vector2(31, 71), "%03d km/h" % int(speed), 18, Color("d3e8ec"))
	_text(canvas, Vector2(650, 48), "%02d s" % ceili(maxf(0, TIME_LIMIT - elapsed)), 28, Color("f9df93"))
	canvas.draw_rect(Rect2(229, 26, 342, 9), Color("263b51"))
	canvas.draw_rect(Rect2(229, 26, 342 * clampf(distance / RACE_LENGTH, 0.0, 1.0), 9), Color("51d5c2"))
	_text(canvas, Vector2(31, 463), "NITRO", 15, Color("a5d8ed"))
	canvas.draw_rect(Rect2(95, 449, 111, 13), Color("24364a"))
	canvas.draw_rect(Rect2(97, 451, nitro / 5.0 * 107, 9), Color("5fe0e5"))
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_car(canvas: Control, point: Vector2, scale: float, color: Color, flame: bool) -> void:
	canvas.draw_rect(Rect2(point + Vector2(-34, -5) * scale, Vector2(68, 13) * scale), Color(0, 0, 0, 0.4))
	canvas.draw_rect(Rect2(point + Vector2(-32, -36) * scale, Vector2(12, 36) * scale), Color("10131d"))
	canvas.draw_rect(Rect2(point + Vector2(20, -36) * scale, Vector2(12, 36) * scale), Color("10131d"))
	canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(-27, 0) * scale, point + Vector2(-25, -30) * scale, point + Vector2(-15, -51) * scale, point + Vector2(15, -51) * scale, point + Vector2(25, -30) * scale, point + Vector2(27, 0) * scale]), color)
	canvas.draw_rect(Rect2(point + Vector2(-16, -42) * scale, Vector2(32, 15) * scale), Color("193847"))
	canvas.draw_line(point+Vector2(-13,-40)*scale,point+Vector2(6,-40)*scale,Color("91c9da"),2*scale,true)
	canvas.draw_line(point+Vector2(-23,-24)*scale,point+Vector2(-18,-44)*scale,color.lightened(.45),2*scale,true)
	canvas.draw_rect(Rect2(point+Vector2(-25,-24)*scale,Vector2(50,5)*scale),color.darkened(.28))
	canvas.draw_rect(Rect2(point+Vector2(-29,-27)*scale,Vector2(58,3)*scale),color.lightened(.25))
	canvas.draw_rect(Rect2(point+Vector2(-8,-9)*scale,Vector2(16,5)*scale),Color("dbe4ed"))
	canvas.draw_line(point + Vector2(-23, -10) * scale, point + Vector2(23, -10) * scale, color.darkened(0.3), 5.0 * scale)
	canvas.draw_rect(Rect2(point + Vector2(-23, -9) * scale, Vector2(11, 4) * scale), Color("f68391"))
	canvas.draw_rect(Rect2(point + Vector2(12, -9) * scale, Vector2(11, 4) * scale), Color("f68391"))
	if flame:
		for side in [-1.0, 1.0]:
			canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(side * 12 - 4, 0) * scale, point + Vector2(side * 12 + 4, 0) * scale, point + Vector2(side * 12, 17 + sin(elapsed * 40) * 5) * scale]), Color("acf9fa"))

func _text(canvas: Control, point: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(ThemeDB.fallback_font, point, String(TranslationServer.translate(text)), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
