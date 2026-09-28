extends RefCounted
## Desvio local de UM pedestre (Actor não-jogador). Só ajusta a direção desejada; quem move é o Actor.
## Três camadas, todas sem raycast extra — usam só as colisões que o move_and_slide já calculou:
##   faixa  -> anda ~0,4 m à DIREITA do próprio rumo. Dois civis em sentidos opostos na mesma calçada
##             ocupam faixas diferentes e se cruzam em vez de bater de frente (antes travavam nariz com nariz).
##   passo  -> encostou em outro corpo que está à frente: desvia para a direita por um instante. Como os dois
##             aplicam a mesma regra relativa ao próprio rumo, os desvios se somam em vez de se anularem.
##   travado-> quase não saiu do lugar por STUCK_TIME querendo andar: tenta o outro lado; persistindo, desiste
##             do ponto atual (o Actor avança o waypoint ou quem controla recebe `stuck`).
const LANE_OFFSET := 0.4
const SIDESTEP_TIME := 0.7
const SIDESTEP_WEIGHT := 1.1
const STUCK_TIME := 1.2
const STUCK_DISTANCE := 0.25
const GIVE_UP_TIME := 3.0

var sidestep_clock := 0.0
var sidestep_sign := 1.0
var stuck_clock := 0.0
var blocked_time := 0.0
var anchor := Vector3.ZERO
var stuck := false ## lido pelo Actor: pular o waypoint atual

## Ponto de rota deslocado para a faixa da direita do trecho `from -> to`.
static func lane_point(from: Vector3, to: Vector3) -> Vector3:
	var along := to - from
	along.y = 0.0
	if along.length_squared() < 0.01: return to
	return to + along.normalized().cross(Vector3.UP) * LANE_OFFSET

func steer(body: CharacterBody3D, desired: Vector3, delta: float) -> Vector3:
	stuck = false
	if desired.length_squared() < 0.01:
		stuck_clock = 0.0
		blocked_time = 0.0
		anchor = body.global_position
		return desired
	var right := desired.cross(Vector3.UP).normalized()
	# Colisões do quadro anterior: outro corpo na frente dispara o passo lateral. Contra parede quase perpendicular
	# o move_and_slide zera o movimento e a lista de colisões pode trazer só a normal do chão; a normal de parede
	# agregada é o sinal confiável nesse caso.
	var paving_contact := false
	for index in body.get_slide_collision_count():
		var other := body.get_slide_collision(index).get_collider() as StaticBody3D
		if other != null and other.get_meta("pedestrian_step", false): paving_contact = true
	if body.is_on_wall() and not paving_contact:
		var wall := body.get_wall_normal()
		wall.y = 0.0
		if wall.dot(desired) < -0.35:
			if sidestep_clock <= 0.0: sidestep_sign = 1.0
			sidestep_clock = SIDESTEP_TIME
	for index in body.get_slide_collision_count():
		if sidestep_clock >= SIDESTEP_TIME: break
		var collision := body.get_slide_collision(index)
		var other := collision.get_collider()
		if not other is PhysicsBody3D: continue
		if other.get_meta("pedestrian_step", false): continue
		var push := -collision.get_normal()
		push.y = 0.0
		if push.dot(desired) > 0.35:
			if sidestep_clock <= 0.0: sidestep_sign = 1.0
			sidestep_clock = SIDESTEP_TIME
			break
	# Travamento: o deslocamento real é o único juiz (parede, poste, carro ou gente).
	# Avaliado uma vez por janela, não a cada quadro, para o lado não oscilar.
	stuck_clock += delta
	if stuck_clock >= STUCK_TIME:
		stuck_clock = 0.0
		var moved := body.global_position - anchor
		moved.y = 0.0
		anchor = body.global_position
		if moved.length() < STUCK_DISTANCE:
			blocked_time += STUCK_TIME
			sidestep_sign = -sidestep_sign
			sidestep_clock = SIDESTEP_TIME * 1.5
			if blocked_time >= GIVE_UP_TIME:
				stuck = true
				blocked_time = 0.0
		else: blocked_time = 0.0
	if sidestep_clock > 0.0:
		sidestep_clock -= delta
		return (desired + right * sidestep_sign * SIDESTEP_WEIGHT).normalized()
	return desired
