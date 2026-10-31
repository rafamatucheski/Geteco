extends RefCounted
## Prática de nove dardos e sinuca de dez tacadas. Sem dinheiro, inventário nem mudança na campanha.
const SEGMENTS := [20,1,18,4,13,6,10,15,2,17,3,19,7,16,8,11,14,9,12,5]
const SCRATCH_PENALTY := 50
const POCKETS := [Vector2(0,0),Vector2(320,0),Vector2(640,0),Vector2(0,320),Vector2(320,320),Vector2(640,320)]
var kind := "bar_darts"
var score := 0
var shots := 0
var finished := false
var aim := Vector2.ZERO
var angle := 0.0
var strength := .55
var marks: Array[Vector2] = []
var balls: Array[Dictionary] = []
var sunk := 0
var scratches := 0
var moving := false
var status := ""

func reset(game_kind: String) -> void:
	kind = game_kind
	score = 0
	shots = 0
	finished = false
	aim = Vector2.ZERO
	angle = 0.0
	strength = .55
	marks.clear()
	balls.clear()
	sunk = 0
	scratches = 0
	moving = false
	status = ""
	balls.append({"position":Vector2(170,160),"velocity":Vector2.ZERO,"sunk":false})
	# Triângulo encostado (fileiras a 17.5 de distância, 20.2 na largura) para a quebra espalhar o conjunto.
	for point in [Vector2(410,160),Vector2(427.5,149.9),Vector2(427.5,170.1),Vector2(445,139.8),Vector2(445,160),Vector2(445,180.2)]:
		balls.append({"position":point,"velocity":Vector2.ZERO,"sunk":false})

static func dart_score(point: Vector2) -> int:
	var radius := point.length()
	if radius > 1.0: return 0
	if radius <= .037: return 50
	if radius <= .094: return 25
	var sector := int(floor(fposmod(atan2(point.x,-point.y)+PI/20.0,TAU)/(TAU/20.0)))
	var multiplier := 3 if radius >= .56 and radius <= .63 else (2 if radius >= .92 else 1)
	return SEGMENTS[sector]*multiplier

func shoot() -> bool:
	if finished or moving: return false
	shots += 1
	if kind == "bar_darts":
		# Crosshair includes the visible power-dependent vertical drop.
		var point := aim+Vector2(0,(.55-strength)*.65)
		marks.append(point)
		var points := dart_score(point)
		score += points
		status = "+%d"%points
		finished = shots >= 9
	else:
		balls[0].velocity = Vector2.from_angle(angle)*lerpf(140.0,650.0,strength)
		moving = true
		status = ""
	return true

func step(delta: float) -> void:
	if not moving: return
	# Subpassos limitados de 240 Hz evitam tunelamento na tacada mais forte.
	var steps := maxi(1,int(ceil(minf(delta,.1)*240)))
	var dt := minf(delta,.1)/steps
	for substep in steps:
		for i in balls.size():
			if balls[i].sunk: continue
			var p: Vector2 = balls[i].position
			var v: Vector2 = balls[i].velocity
			p += v*dt
			var pocketed := false
			for pocket in POCKETS:
				if p.distance_to(pocket) < 21.0:
					pocketed = true
					break
			if pocketed:
				balls[i].sunk = true
				balls[i].velocity = Vector2.ZERO
				if i == 0:
					scratches += 1
					score = maxi(0,score-SCRATCH_PENALTY)
					status = "Branca na caçapa · falta −%d"%SCRATCH_PENALTY
				else:
					sunk += 1
					score += 100
					status = "+100"
				continue
			if p.x < 10 or p.x > 630:
				v.x *= -.88
				p.x = clampf(p.x,10,630)
			if p.y < 10 or p.y > 310:
				v.y *= -.88
				p.y = clampf(p.y,10,310)
			balls[i].position = p
			balls[i].velocity = v.move_toward(Vector2.ZERO,58.0*dt)
		for i in balls.size():
			for j in range(i+1,balls.size()):
				if balls[i].sunk or balls[j].sunk: continue
				var diff: Vector2 = balls[j].position-balls[i].position
				var distance := diff.length()
				if distance >= 20: continue
				var normal := diff/maxf(distance,.001) if distance > .001 else Vector2.RIGHT
				var correction := normal*(20-distance)*.5
				balls[i].position -= correction
				balls[j].position += correction
				var closing: float = (balls[i].velocity-balls[j].velocity).dot(normal)
				if closing > 0:
					balls[i].velocity -= normal*closing*.96
					balls[j].velocity += normal*closing*.96
	moving = false
	for ball in balls:
		if not ball.sunk and ball.velocity.length() > 1.0: moving = true
	if not moving:
		for ball in balls: ball.velocity = Vector2.ZERO
		if balls[0].sunk:
			balls[0].sunk = false
			# Bola na mão: escolhe um ponto livre na linha de saída.
			for y in [160,60,260,110,210]:
				var free := true
				for index in range(1,balls.size()):
					if not balls[index].sunk and Vector2(100,y).distance_to(balls[index].position) < 22: free = false
				if free:
					balls[0].position = Vector2(100,y)
					break
		finished = sunk == 6 or shots >= 10
