extends RefCounted
## Deterministic pinball table. ArcadeScreen calls render from its drawing pass.

const BUMPERS := [Vector2(337, 148), Vector2(465, 148), Vector2(401, 246)]
const BALL_RADIUS := 7.0
const LAUNCH_RAIL_TOP := Vector2(540, 280)
const LAUNCH_RAIL_BOTTOM := Vector2(540, 456)
const RIGHT_GUIDE_START := Vector2(535, 350)
var score: int = 0
var finished: bool = false
var status: String = ""
var lives: int = 3
var ball := Vector2.ZERO
var velocity := Vector2.ZERO
var waiting: bool = true
var left_flipper: bool = false
var right_flipper: bool = false
var _glow := PackedFloat32Array([0.0, 0.0, 0.0])
var _rng := RandomNumberGenerator.new()

func title() -> String:
	return "Bola de Aço"

func instructions() -> String:
	return "← → pás  •  Ação: lançar bola  •  3 bolas"

func reset(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	score = 0
	lives = 3
	finished = false
	left_flipper = false
	right_flipper = false
	_glow.fill(0.0)
	_prepare_ball()

func _prepare_ball() -> void:
	ball = Vector2(553, 395)
	velocity = Vector2.ZERO
	waiting = true
	status = "LANCE A BOLA"

func step(delta: float, controls: Dictionary) -> void:
	if finished:
		return
	var dt := clampf(delta, 0.0, 0.1)
	left_flipper = bool(controls.get("left", false))
	right_flipper = bool(controls.get("right", false))
	for i in range(_glow.size()):
		_glow[i] = maxf(0.0, _glow[i] - dt)
	if waiting:
		if bool(controls.get("action_pressed", false)) or bool(controls.get("up_pressed", false)):
			waiting = false
			# A real right-side launch lane clears the lower guide. The upper
			# chamfer then rebounds the ball left into the bumper field.
			velocity = Vector2(_rng.randf_range(-8.0, 8.0), -620.0)
			status = "BOLA %d / 3" % (4 - lives)
		return
	var count := maxi(1, ceili(dt / (1.0 / 240.0)))
	for substep in range(count):
		_simulate(dt / float(count))
		if waiting or finished:
			break

func _simulate(dt: float) -> void:
	velocity.y += 345.0 * dt
	velocity = velocity.limit_length(760.0)
	ball += velocity * dt
	if ball.x < 238.0:
		ball.x = 238.0
		velocity.x = absf(velocity.x) * 0.93
	elif ball.x > 562.0:
		ball.x = 562.0
		velocity.x = -absf(velocity.x) * 0.93
	if ball.y < 51.0:
		ball.y = 51.0
		velocity.y = absf(velocity.y) * 0.94
	_bounce_segment(Vector2(231, 90), Vector2(278, 44), false)
	_bounce_segment(Vector2(522, 44), Vector2(569, 90), false)
	_bounce_segment(Vector2(231, 316), Vector2(314, 399), false)
	_bounce_segment(RIGHT_GUIDE_START, Vector2(486, 399), false)
	_bounce_segment(LAUNCH_RAIL_TOP, LAUNCH_RAIL_BOTTOM, false)
	for i in range(BUMPERS.size()):
		var offset: Vector2 = ball - BUMPERS[i]
		if offset.length_squared() < 34.0 * 34.0:
			var normal := offset.normalized() if offset.length_squared() > 0.01 else Vector2.UP
			ball = BUMPERS[i] + normal * 34.0
			if velocity.dot(normal) < 0.0:
				velocity = velocity.bounce(normal) * 1.04 + normal * 115.0
				if _glow[i] <= 0.0:
					score += 100
					_glow[i] = 0.2
	_bounce_segment(Vector2(309, 410), Vector2(388, 377 if left_flipper else 434), left_flipper)
	_bounce_segment(Vector2(491, 410), Vector2(412, 377 if right_flipper else 434), right_flipper)
	if ball.y > 478.0:
		lives -= 1
		if lives <= 0:
			finished = true
			status = "FIM DE JOGO"
		else:
			_prepare_ball()

func _bounce_segment(start: Vector2, end: Vector2, powered: bool) -> void:
	var closest := Geometry2D.get_closest_point_to_segment(ball, start, end)
	var offset := ball - closest
	var radius := BALL_RADIUS + 6.0
	if offset.length_squared() >= radius * radius:
		return
	var normal := offset.normalized() if offset.length_squared() > 0.01 else Vector2.UP
	ball = closest + normal * radius
	if velocity.dot(normal) < 0.0:
		velocity = velocity.bounce(normal) * 0.92
		if powered and ball.y < start.y + 12.0:
			velocity.y = -maxf(470.0, absf(velocity.y))
			velocity.x += (400.0 - ball.x) * 2.1

func render(canvas: Control, area: Rect2) -> void:
	canvas.draw_set_transform(area.position, 0.0, area.size / Vector2(800, 480))
	canvas.draw_rect(Rect2(0, 0, 800, 480), Color("080f22"))
	for x in range(0, 800, 32):
		canvas.draw_line(Vector2(x, 0), Vector2(x, 480), Color("101e35"))
	for y in range(0, 480, 32):
		canvas.draw_line(Vector2(0, y), Vector2(800, y), Color("101e35"))
	canvas.draw_rect(Rect2(221, 31, 358, 445), Color("12233b"))
	canvas.draw_rect(Rect2(229, 39, 342, 430), Color("091824"))
	canvas.draw_polyline(PackedVector2Array([Vector2(231, 464), Vector2(231, 90), Vector2(278, 44), Vector2(522, 44), Vector2(569, 90), Vector2(569, 464)]), Color("45decd"), 4.0, true)
	canvas.draw_arc(Vector2(400, 226), 122.0, 0.0, TAU, 60, Color("164b59"), 2.0, true)
	canvas.draw_arc(Vector2(400, 226), 114.0, 0.0, TAU, 60, Color("164b59"), 1.0, true)
	for i in range(BUMPERS.size()):
		var color := Color("ffda6c") if _glow[i] > 0.0 else Color("f45f86")
		canvas.draw_circle(BUMPERS[i], 34.0, Color(color, 0.12))
		canvas.draw_circle(BUMPERS[i], 27.0, color)
		canvas.draw_circle(BUMPERS[i], 20.0, Color("263052"))
		canvas.draw_arc(BUMPERS[i], 14.0, 0.0, TAU, 24, color, 2.0, true)
		_text(canvas, BUMPERS[i] + Vector2(-13, 5), "100", 13, Color.WHITE)
	for mirrored in [false, true]:
		var a := RIGHT_GUIDE_START if mirrored else Vector2(231, 316)
		var b := Vector2(486 if mirrored else 314, 399)
		canvas.draw_line(a, b, Color("3bcbbb"), 9.0, true)
	canvas.draw_line(LAUNCH_RAIL_TOP, LAUNCH_RAIL_BOTTOM, Color("45decd"), 5.0, true)
	canvas.draw_line(Vector2(547, 438), Vector2(560, 438), Color("fcca68"), 4.0)
	for spring in range(4):
		var y := 443.0 + spring * 5.0
		canvas.draw_line(Vector2(548, y), Vector2(559, y + 3), Color("719aa4"), 1.5, true)
	var left_end := Vector2(388, 377 if left_flipper else 434)
	var right_end := Vector2(412, 377 if right_flipper else 434)
	canvas.draw_line(Vector2(309, 410), left_end, Color("fcca68"), 13.0, true)
	canvas.draw_line(Vector2(491, 410), right_end, Color("fcca68"), 13.0, true)
	canvas.draw_circle(Vector2(309, 410), 8.0, Color("e87752"))
	canvas.draw_circle(Vector2(491, 410), 8.0, Color("e87752"))
	if not finished:
		canvas.draw_circle(ball + Vector2(2, 4), 8.0, Color(0, 0, 0, 0.45))
		canvas.draw_circle(ball, BALL_RADIUS, Color("b9dfed"))
		canvas.draw_circle(ball + Vector2(-2, -2), 3.0, Color.WHITE)
	_text(canvas, Vector2(30, 68), "PONTOS", 17, Color("7a98b2"))
	_text(canvas, Vector2(30, 106), "%06d" % score, 30, Color("f8d575"))
	_text(canvas, Vector2(30, 175), "BOLAS", 17, Color("7a98b2"))
	for i in range(lives):
		canvas.draw_circle(Vector2(40 + i * 28, 202), 7.0, Color("c9e9f2"))
	_text(canvas, Vector2(610, 83), "←     →", 28, Color("f8d575"))
	_text(canvas, Vector2(610, 115), "PÁS", 17, Color("7a98b2"))
	if waiting:
		_text(canvas, Vector2(310, 328), "AÇÃO: LANÇAR", 21, Color("f8d575"))
	canvas.draw_set_transform(Vector2.ZERO)

func _text(canvas: Control, point: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(ThemeDB.fallback_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
