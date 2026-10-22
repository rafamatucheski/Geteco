extends RefCounted
## One round: two attacks, blocking, jumping and a telegraphed opponent.

const ROUND_TIME := 60.0
var score: int = 0
var finished: bool = false
var status: String = ""
var player_health: int = 100
var enemy_health: int = 100
var player_x: float = 224.0
var enemy_x: float = 574.0
var player_height: float = 0.0
var blocking: bool = false
var elapsed: float = 0.0
var attack_kind: int = 0
var enemy_windup: float = 0.0
var enemy_blocking: bool = false
var sound_events: Array[String] = []
var combo := 0
var _combo_time := 0.0
var _enemy_stun := 0.0
var _player_stun := 0.0
var _hitstop := 0.0
var _enemy_kind := 1
var _queued_attack := 0
var _queue_time := 0.0
var _impact_point := Vector2.ZERO
var _impact_time := 0.0
var _jump_velocity: float = 0.0
var _attack_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _attack_connected: bool = false
var _enemy_cooldown: float = 1.2
var _enemy_attack_pose: float = 0.0
var _player_flash: float = 0.0
var _enemy_flash: float = 0.0
var _rng := RandomNumberGenerator.new()

func title() -> String:
	return "Último Round"

func instructions() -> String:
	return "← → mover  •  ↑ pular  •  ↓ defender  •  Ação: soco  •  Alternativa: chute"

func reset(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	score = 0
	finished = false
	status = "LUTE!"
	player_health = 100
	enemy_health = 100
	player_x = 224.0
	enemy_x = 574.0
	player_height = 0.0
	_jump_velocity = 0.0
	blocking = false
	elapsed = 0.0
	attack_kind = 0
	_attack_timer = 0.0
	_attack_cooldown = 0.0
	_attack_connected = false
	enemy_windup = 0.0
	enemy_blocking = false
	_enemy_cooldown = 1.2
	_enemy_attack_pose = 0.0
	_player_flash = 0.0
	_enemy_flash = 0.0
	sound_events.clear()
	combo = 0
	_combo_time = 0.0
	_enemy_stun = 0.0
	_player_stun = 0.0
	_hitstop = 0.0
	_enemy_kind = 1
	_queued_attack = 0
	_queue_time = 0.0
	_impact_time = 0.0

func step(delta: float, controls: Dictionary) -> void:
	if finished:
		return
	var dt := clampf(delta, 0.0, 0.1)
	if _hitstop > 0.0:
		_hitstop = maxf(0.0,_hitstop-dt)
		return
	elapsed += dt
	_combo_time = maxf(0.0,_combo_time-dt)
	if _combo_time <= 0.0: combo = 0
	_enemy_stun = maxf(0.0,_enemy_stun-dt)
	_player_stun = maxf(0.0,_player_stun-dt)
	_impact_time = maxf(0.0,_impact_time-dt)
	_queue_time = maxf(0.0,_queue_time-dt)
	if _queue_time <= 0.0: _queued_attack = 0
	if bool(controls.get("action_alt_pressed",false)):
		_queued_attack = 2
		_queue_time = .22
	elif bool(controls.get("action_pressed",false)):
		_queued_attack = 1
		_queue_time = .22
	_attack_cooldown = maxf(0.0, _attack_cooldown - dt)
	_player_flash = maxf(0.0, _player_flash - dt)
	_enemy_flash = maxf(0.0, _enemy_flash - dt)
	_enemy_attack_pose = maxf(0.0, _enemy_attack_pose - dt)
	blocking = bool(controls.get("down", false)) and player_height <= 0.0 and _attack_timer <= 0.0
	var direction := float(bool(controls.get("right", false))) - float(bool(controls.get("left", false)))
	player_x = clampf(player_x + direction * dt * (0.0 if _player_stun > 0.0 else 65.0 if blocking else 190.0), 62.0, 738.0)
	if bool(controls.get("up_pressed", false)) and player_height <= 0.0 and not blocking:
		_jump_velocity = 620.0
	if player_height > 0.0 or _jump_velocity > 0.0:
		_jump_velocity -= 1700.0 * dt
		player_height = maxf(0.0, player_height + _jump_velocity * dt)
		if player_height <= 0.0:
			_jump_velocity = 0.0
	if _attack_cooldown <= 0.0 and not blocking and _player_stun <= 0.0 and _queued_attack != 0:
		_begin_attack(_queued_attack)
		_queued_attack = 0
	if _attack_timer > 0.0:
		_attack_timer = maxf(0.0, _attack_timer - dt)
		if not _attack_connected and _attack_timer <= (0.25 if attack_kind == 2 else 0.16):
			_attack_connected = true
			_player_hit()
		if _attack_timer <= 0.0:
			attack_kind = 0
	if enemy_health > 0:
		_step_enemy(dt)
	if absf(enemy_x - player_x) < 45.0 and player_height < 30.0:
		player_x = clampf(enemy_x + (-45.0 if player_x < enemy_x else 45.0), 62.0, 738.0)
	if enemy_health <= 0 or player_health <= 0 or elapsed >= ROUND_TIME:
		finished = true
		if player_health > enemy_health:
			score += 1000 + player_health * 10 + int(maxf(0.0, ROUND_TIME - elapsed) * 10.0)
			status = "VITÓRIA!"
		elif player_health == enemy_health:
			status = "EMPATE"
		else:
			status = "DERROTA"

func _begin_attack(kind: int) -> void:
	attack_kind = kind
	sound_events.append("swing")
	_attack_timer = 0.38 if kind == 2 else 0.25
	_attack_cooldown = 0.46 if kind == 2 else 0.28
	_attack_connected = false

func _player_hit() -> void:
	var reach := 139.0 if attack_kind == 2 else 105.0
	if absf(enemy_x - player_x) > reach or player_height > 82.0:
		return
	var damage := 17 if attack_kind == 2 else 10
	if enemy_blocking:
		damage = 3
		sound_events.append("guard")
	else:
		combo += 1
		_combo_time = 1.0
		damage += mini(6,combo-1)*2
		_enemy_stun = .2 if attack_kind == 2 else .12
		enemy_windup = 0.0
		_enemy_cooldown = maxf(_enemy_cooldown,.35)
		sound_events.append("hit")
	_hitstop = .055
	_impact_time = .18
	_impact_point = Vector2(enemy_x,285-player_height*.4)
	enemy_health = maxi(0, enemy_health - damage)
	score += damage * 12
	_enemy_flash = 0.16
	enemy_x = clampf(enemy_x + signf(enemy_x - player_x) * (15.0 if attack_kind == 2 else 8.0), 62.0, 738.0)

func _step_enemy(dt: float) -> void:
	_enemy_cooldown = maxf(0.0, _enemy_cooldown - dt)
	if _enemy_stun > 0.0:
		enemy_blocking = false
		return
	var gap := absf(enemy_x - player_x)
	enemy_blocking = enemy_windup <= 0.0 and _enemy_cooldown > 0.35 and sin(elapsed * 2.4) > 0.53
	if enemy_windup > 0.0:
		enemy_windup = maxf(0.0, enemy_windup - dt)
		if enemy_windup <= 0.0:
			_enemy_attack_pose = 0.22
			sound_events.append("swing")
			_enemy_cooldown = _rng.randf_range(0.72, 1.18)
			if gap < (145.0 if _enemy_kind == 2 else 113.0) and player_height < (45.0 if _enemy_kind == 2 else 70.0):
				player_health = maxi(0, player_health - (2 if blocking else 17 if _enemy_kind == 2 else 11))
				sound_events.append("guard" if blocking else "hit")
				_player_stun = .05 if blocking else .2
				_hitstop = .045
				_impact_time = .18
				_impact_point = Vector2(player_x,285-player_height)
				combo = 0
				_player_flash = 0.16
				player_x = clampf(player_x + signf(player_x - enemy_x) * (5.0 if blocking else 20.0), 62.0, 738.0)
	elif gap > 89.0:
		enemy_x += signf(player_x - enemy_x) * (52.0 if enemy_blocking else 105.0) * dt
	elif _enemy_cooldown <= 0.0:
		enemy_blocking = false
		_enemy_kind = 2 if _rng.randf() > .55 else 1
		enemy_windup = .5 if _enemy_kind == 2 else .32
	enemy_x = clampf(enemy_x, 62.0, 738.0)

func render(canvas: Control, area: Rect2) -> void:
	canvas.draw_set_transform(area.position, 0.0, area.size / Vector2(800, 480))
	canvas.draw_rect(Rect2(0, 0, 800, 480), Color("151d32"))
	canvas.draw_rect(Rect2(0, 138, 800, 204), Color("25263c"))
	for row in range(6):
		var y := 152.0 + row * 31.0
		canvas.draw_line(Vector2(0, y), Vector2(800, y), Color("363346"), 2.0)
		for column in range(11):
			var x := column * 82.0 + (41.0 if row % 2 else 0.0)
			canvas.draw_line(Vector2(x, y), Vector2(x, y + 31), Color("363346"), 2.0)
	for side in [0, 1]:
		var x: float = 84.0 + float(side) * 510.0
		canvas.draw_rect(Rect2(x, 143, 122, 122), Color("111b2d"))
		canvas.draw_rect(Rect2(x + 5, 148, 112, 3), Color("61d2d4"))
		for bar in range(5):
			canvas.draw_line(Vector2(x + 20 + bar * 22, 152), Vector2(x + 20 + bar * 22, 266), Color("384b5f"), 4.0)
	canvas.draw_rect(Rect2(0, 343, 800, 137), Color("333344"))
	for i in range(11):
		canvas.draw_line(Vector2(400 + (i - 5) * 59, 343), Vector2(400 + (i - 5) * 130, 480), Color("494151"), 2.0)
	for y in [364, 401, 452]:
		canvas.draw_line(Vector2(0, y), Vector2(800, y), Color("494151"), 2.0)
	_draw_fighter(canvas, Vector2(player_x, 377 - player_height), signf(enemy_x - player_x), Color("65c9dc"), blocking, attack_kind, _player_flash, false)
	_draw_fighter(canvas, Vector2(enemy_x, 377), signf(player_x - enemy_x), Color("e88883"), enemy_blocking, _enemy_kind if _enemy_attack_pose > 0 else 0, _enemy_flash, enemy_windup > 0)
	if _impact_time > 0.0:
		for ray in range(8):
			var normal := Vector2.from_angle(ray*TAU/8.0)
			var radius := (1.0-_impact_time/.18)*38.0
			canvas.draw_line(_impact_point+normal*radius*.35,_impact_point+normal*radius,Color("ffdf78"),3.0,true)
	if combo > 1:
		_text(canvas,Vector2(310,115),String(TranslationServer.translate("%d ACERTOS")) % combo,24,Color("ffdf78"))
	_draw_health(canvas, Rect2(31, 37, 292, 22), player_health, Color("67d4d0"))
	_draw_health(canvas, Rect2(477, 37, 292, 22), enemy_health, Color("eb888b"))
	_text(canvas, Vector2(31, 29), "VOCÊ", 18, Color("c8e4ea"))
	_text(canvas, Vector2(645, 29), "DESAFIANTE", 18, Color("e9bdc4"))
	_text(canvas, Vector2(373, 58), "%02d" % ceili(maxf(0.0, ROUND_TIME - elapsed)), 35, Color("f5d9a5"))
	_text(canvas, Vector2(32, 453), "%06d" % score, 24, Color("e9d9b5"))
	if enemy_windup > 0.0:
		_text(canvas, Vector2(enemy_x - 6, 203), "!", 29, Color("ffdf78"))
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_health(canvas: Control, rectangle: Rect2, health: int, color: Color) -> void:
	canvas.draw_rect(rectangle.grow(3), Color("576078"))
	canvas.draw_rect(rectangle, Color("302538"))
	canvas.draw_rect(Rect2(rectangle.position, Vector2(rectangle.size.x * health / 100.0, rectangle.size.y)), color)

func _draw_fighter(canvas: Control, point: Vector2, facing: float, color: Color, guard: bool, attack: int, flash: float, windup: bool) -> void:
	var ink := Color("1a2235")
	var skin := Color("c6957c")
	if flash > 0.0:
		color = Color("fff3ce")
	canvas.draw_circle(Vector2(point.x, 378), 33, Color(0, 0, 0, 0.22))
	var hip := point + Vector2(0, -52)
	var chest := point + Vector2(0, -98)
	var bounce := sin(elapsed*9.0+point.x*.01)*2.5
	hip.y += bounce
	chest.y += bounce
	var extension := 1.0
	if attack != 0:
		var is_player := absf(point.x-player_x) < .1
		var timer := _attack_timer if is_player else _enemy_attack_pose
		var duration := (.38 if attack == 2 else .25) if is_player else .22
		extension = sin(clampf(1.0-timer/duration,0.0,1.0)*PI)
	var rear_foot := point + Vector2(-facing * 24, 0)
	var front_foot := point + Vector2(facing * 27, 0)
	if attack == 2:
		front_foot = point + Vector2(facing * lerpf(27,112,extension),-63*extension)
	canvas.draw_line(hip, rear_foot, ink, 18.0, true)
	canvas.draw_line(hip, front_foot, ink, 18.0, true)
	canvas.draw_line(rear_foot - Vector2(5, 0), rear_foot + Vector2(12, 0), Color("9db5c6"), 10.0)
	canvas.draw_line(front_foot - Vector2(5, 0), front_foot + Vector2(12, 0), Color("9db5c6"), 10.0)
	canvas.draw_line(hip, chest, color, 35.0, true)
	canvas.draw_line(hip + Vector2(-15, -1), hip + Vector2(15, -1), ink, 7.0)
	canvas.draw_circle(chest + Vector2(0, -30), 18, skin)
	canvas.draw_rect(Rect2(chest + Vector2(-18, -48), Vector2(36, 12)), ink)
	canvas.draw_rect(Rect2(chest + Vector2(facing * 8 - 2, -34), Vector2(4, 4)), ink)
	var hand := chest + Vector2(facing * 30, -7)
	if guard:
		hand = chest + Vector2(facing * 24, -33)
	elif windup:
		hand = chest + Vector2(-facing * 29, -16)
	elif attack == 1:
		hand = chest + Vector2(facing * lerpf(30,100,extension), -7)
	canvas.draw_line(chest + Vector2(-facing * 11, 4), chest + Vector2(-facing * 27, 28), color.darkened(0.18), 13.0, true)
	canvas.draw_circle(chest + Vector2(-facing * 27, 28), 8, skin)
	var shoulder := chest + Vector2(facing * 7,0)
	var elbow := shoulder.lerp(hand,.5)+Vector2(-facing*8,14*(1.0-extension) if attack == 1 else 14)
	canvas.draw_line(shoulder,elbow,color.lightened(.1),14.0,true)
	canvas.draw_line(elbow,hand,color.lightened(.1),12.0,true)
	canvas.draw_circle(hand, 9, skin)
	if guard:
		canvas.draw_arc(chest + Vector2(facing * 17, -20), 31.0, -PI / 2 if facing > 0 else PI / 2, PI / 2 if facing > 0 else PI * 1.5, 16, Color("91d9e8"), 2.0, true)

func _text(canvas: Control, point: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(ThemeDB.fallback_font, point, String(TranslationServer.translate(text)), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
