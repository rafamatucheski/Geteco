extends RefCounted
## Perseguição de carro no estilo GTA (21/10/2026), sem estado. A avaliação por leitura do código
## mostrou que a perseguição se sabotava: rota que terminava e freava onde o jogador ESTAVA, sensor
## frontal que freava diante do carro dele (nunca encostava), teto de 21/25 m/s e curva a 4 m/s,
## viatura deixada para trás congelada segurando a vaga por 45 s e reforço nascendo no ponto mais
## próximo, quase sempre atrás. Estas regras corrigem isso e acrescentam papéis (PIT, flanco,
## bloqueio de cruzamento, interceptação), área de busca e visão em cone.
## `GETECO_GTA_CHASE=0` volta ao comportamento anterior inteiro (A/B no mesmo export e rollback).

static var enabled := OS.get_environment("GETECO_GTA_CHASE") != "0"

# --- Velocidade -----------------------------------------------------------------
## Teto de cruzeiro na perseguição. A ficha da viatura permite 37,5 m/s; o carro popular do jogador
## chega a ~23 m/s e o esportivo a 30-41 m/s (V1Handling limita a max_speed × 0,8 / 16).
const SPEED_PATROL := 30.0
const SPEED_FAST := 34.0
const SPEED_MOTORCYCLE := 32.0
## Aceleração lateral admitida na curva (v = √(a·R)). O modelo cinemático da viatura não derrapa;
## este valor dá a leitura de "viatura no limite" sem atravessar a esquina.
const LATERAL_ACCEL := 9.0
## Desaceleração usada para planejar a frenagem antes da curva (o Vehicle freia a 14 m/s²).
const CORNER_DECEL := 9.0
const MIN_CORNER_SPEED := 6.0
## Curvatura é amostrada na rota a cada tantos metros, até a distância de frenagem + folga.
const CORNER_STEP := 3.0
const CORNER_SCAN_MIN := 16.0
const CORNER_SCAN_MAX := 90.0
## Recuperação fora da câmera: longe do alvo e sem ser vista, a viatura ganha teto e aceleração.
const BOOST := 1.22
const BOOST_DISTANCE := 45.0
const BOOST_RELEASE_DISTANCE := 25.0

# --- Rota aberta e replanejamento --------------------------------------------------
## Objetivo da rota: tantos segundos à frente do alvo (mais uma folga), para a rota passar por ele
## e continuar; o piloto não freia no fim dela enquanto houver perseguição.
const GOAL_LEAD_SECONDS := 2.2
const GOAL_LEAD_MIN := 30.0
const GOAL_LEAD_MAX := 110.0
## Replanejamento por evento (rota acabando, alvo fora do corredor), com intervalo mínimo
## defasado por viatura e um máximo para não seguir rota velha.
const REPLAN_MIN := 0.9
const REPLAN_STAGGER := 0.12
const REPLAN_MAX := 3.5
const REPLAN_REMAINING := 35.0
const REPLAN_REMAINING_SECONDS := 2.5
const REPLAN_CORRIDOR := 12.0
## Rota aberta: abaixo disto do fim ela volta a frear (beco sem saída de verdade).
const OPEN_ROUTE_BRAKE := 8.0
## Só com o alvo acima disto (m/s) a rota fica aberta; parado ou lento, ela termina nele.
const OPEN_ROUTE_MIN_TARGET_SPEED := 4.0

# --- Guiamento final (contato) -------------------------------------------------------
## Perto do alvo a viatura sai da rota e mira um ponto no carro dele.
const GUIDE_RANGE := 26.0
const GUIDE_CONE := deg_to_rad(75.0)
## Sem força autorizada (1 estrela) ela só cola atrás, a esta distância.
const FOLLOW_GAP := 7.0
## Aproximação para PIT: velocidade relativa no contato.
const PIT_CLOSING_MIN := 2.0
const PIT_CLOSING_MAX := 7.0
## Giro extra do PIT no carro atingido (rad/s, somado ao do StreetPhysics) e seu teto.
const PIT_SPIN_GAIN := 0.32
const PIT_SPIN_MAX := 3.2
const PIT_COOLDOWN := 2.5
const PIT_MIN_TARGET_SPEED := 6.0
## Obstáculo que não é o alvo durante o guiamento: volta à rota por este tempo.
const GUIDE_COOLDOWN := 1.5
## Fora do asfalto: alvo a mais disto da rua mais próxima conta como fora da rua; com ele à vista
## (linha de visão livre) a viatura guia direto até ele de mais longe, em vez de parar na ponta da
## rua mais próxima. A linha de visão e o sensor frontal são a proteção contra prédio e barranco.
const OFFROAD_DISTANCE := 12.0
const OFFROAD_GUIDE_RANGE := 70.0
const OFFROAD_CHECK := 0.5

# --- Papéis ------------------------------------------------------------------------
const ROLE_CHASER := 0
const ROLE_FLANK_LEFT := 1
const ROLE_FLANK_RIGHT := 2
const ROLE_BLOCKER := 3
const ROLE_INTERCEPTOR := 4
## Ordem em que os papéis são preenchidos pelas viaturas ativas: a primeira persegue (PIT).
const ROLE_PRIORITY: Array[int] = [0, 1, 3, 2, 4]
## Bloqueador: só vai a um cruzamento previsto se chega antes do alvo, com folga.
const BLOCK_MIN_DISTANCE := 35.0
const BLOCK_MAX_DISTANCE := 240.0
const BLOCK_ETA_MARGIN := 1.0
const BLOCK_HOLD_MAX := 14.0
const BLOCK_RELEASE_DISTANCE := 18.0
const BLOCK_RETRY := 2.0
## Interceptor: entra no caminho previsto do alvo, vindo de frente.
const INTERCEPT_LEAD := 110.0

# --- Recicla e nascimento à frente ------------------------------------------------------
## Viatura deixada para trás (longe e fora da vista) com contato recente: some e libera a vaga
## para uma nova nascer à frente, em vez de congelar segurando a vaga por até 45 s.
const RECYCLE_CONTACT_AGE := 8.0
const SPAWN_LEAD_SECONDS := 2.5
const SPAWN_AHEAD_MAX := 120.0
const SPAWN_MOVING_SPEED := 5.0

# --- Busca ---------------------------------------------------------------------------
## Raio da área de busca por estrela, em volta da última posição conhecida.
const SEARCH_RADIUS: Array[float] = [0.0, 70.0, 90.0, 110.0, 140.0, 170.0, 200.0]
## Dentro da área a fuga anda a esta fração (fora dela, normal): sair do círculo é o que despista.
const EVASION_INSIDE_RATE := 0.4
## Visão da viatura: cone frontal longo e, em volta, o mesmo círculo de antes (650 px = 40,6 m),
## para nunca enxergar menos que a regra antiga.
const VISION_FRONT := 70.0
const VISION_HALF_ANGLE := deg_to_rad(40.0)
const VISION_NEAR := 650.0 / 16.0
## Nos primeiros segundos sem contato a viatura segue por estimativa (última posição + direção e
## velocidade vistas), como quem dobra a esquina atrás do suspeito; depois, busca em leque.
const SEARCH_PURSUE_SECONDS := 6.0
const SEARCH_PURSUE_LEAD := 25.0
const SEARCH_PURSUE_MAX := 150.0
## Busca em leque: pontos de rua dentro da área, um por viatura.
const SEARCH_POINT_SPACING := 16.0
const SEARCH_POINT_REACHED := 9.0

# --- Bloqueio com pregos ----------------------------------------------------------------
const ROADBLOCK_MIN_STARS := 3
const ROADBLOCK_AHEAD_MIN := 70.0
const ROADBLOCK_AHEAD_MAX := 150.0
const ROADBLOCK_AHEAD_STEP := 15.0

# --- Prisão no carro ------------------------------------------------------------------
## Carro parado e cercado com 1-2 estrelas sem força autorizada: o policial a pé prende (GTA "busted").
const BUST_MAX_STARS := 2

static func speed_cap(variant: String) -> float:
	match variant:
		"tank": return 10.0
		"motorcycle": return SPEED_MOTORCYCLE
		"interceptor", "tactical": return SPEED_FAST
	return SPEED_PATROL

## Velocidade máxima numa curva de curvatura `curvature` (1/m).
static func corner_speed(curvature: float) -> float:
	if curvature <= 0.0001: return INF
	return sqrt(LATERAL_ACCEL / curvature)

## Velocidade com que ainda se freia até `allowed` em `distance` metros.
static func brake_window(allowed: float, distance: float) -> float:
	return sqrt(allowed * allowed + 2.0 * CORNER_DECEL * maxf(0.0, distance))

## Objetivo de rota à frente do alvo: a rota passa por ele e continua.
static func chase_goal(target_position: Vector3, target_velocity: Vector3) -> Vector3:
	var planar := Vector3(target_velocity.x, 0.0, target_velocity.z)
	if planar.length() < 1.0: return target_position
	var lead := clampf(planar.length() * GOAL_LEAD_SECONDS + 20.0, GOAL_LEAD_MIN, GOAL_LEAD_MAX)
	return target_position + planar.normalized() * lead

static func replan_remaining(speed: float) -> float:
	return maxf(REPLAN_REMAINING, absf(speed) * REPLAN_REMAINING_SECONDS)

## Contato com força: a partir de 2 estrelas ou com força autorizada; nunca rendido nem onde
## armas são proibidas (garagem do Maciota).
static func ram_allowed(gameplay: Node) -> bool:
	if gameplay == null or gameplay.stars <= 0: return false
	if gameplay.has_method("police_surrendering") and gameplay.police_surrendering(): return false
	if gameplay.get("state") != null and not gameplay.state.weapons_allowed(): return false
	var authorized: bool = gameplay.police_force_authorized() if gameplay.has_method("police_force_authorized") else false
	return gameplay.stars >= 2 or authorized

static func next_role(active_roles: Array) -> int:
	for role in ROLE_PRIORITY:
		if not active_roles.has(role): return role
	return ROLE_CHASER

## Ponto e velocidade do guiamento final. `side` (-1/+1) é o lado do alvo em que a viatura está.
## Devolve {"point": Vector3, "speed": float, "mode": String}.
static func guide(role: int, ram: bool, police_position: Vector3, target_position: Vector3, target_forward: Vector3, target_velocity: Vector3, target_half_width: float, target_half_length: float, police_half_width: float) -> Dictionary:
	var forward := Vector3(target_forward.x, 0.0, target_forward.z)
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	var planar := Vector3(target_velocity.x, 0.0, target_velocity.z)
	var target_speed := planar.length()
	var relative := police_position - target_position
	relative.y = 0.0
	var distance := relative.length()
	var side := -1.0 if relative.dot(right) < 0.0 else 1.0
	var behind := -relative.dot(forward)
	if not ram:
		# Cola atrás sem encostar: mantém FOLLOW_GAP e iguala a velocidade.
		var follow := target_position - forward * (target_half_length + FOLLOW_GAP) + planar * 0.3
		var gap := (follow - police_position).dot(forward)
		return {"point": follow, "speed": maxf(0.0, target_speed + clampf(gap * 0.6, -6.0, 6.0)), "mode": "follow"}
	if role == ROLE_FLANK_LEFT or role == ROLE_FLANK_RIGHT:
		var flank_side := -1.0 if role == ROLE_FLANK_LEFT else 1.0
		var beside := target_position + right * flank_side * (target_half_width + police_half_width + 0.4) + planar * 0.35
		var longitudinal := (beside - police_position).dot(forward)
		# Emparelhado: fecha no carro do alvo (raspão lateral).
		if absf(longitudinal) < 2.0 and absf(relative.dot(right)) < target_half_width + police_half_width + 2.5:
			return {"point": target_position + planar * 0.25, "speed": target_speed + 1.5, "mode": "swipe"}
		return {"point": beside, "speed": maxf(0.0, target_speed + clampf(longitudinal * 0.8, -4.0, 6.0)), "mode": "flank"}
	# Perseguidor (e qualquer outro papel colado no alvo): PIT na traseira lateral do lado em que está.
	var closing := clampf(distance * 0.5, PIT_CLOSING_MIN, PIT_CLOSING_MAX)
	var lead := clampf(distance / maxf(1.0, closing + 1.0), 0.0, 0.5)
	var quarter := target_position + forward * (-target_half_length * 0.6) + right * side * (target_half_width * 0.75) + planar * lead
	# Ainda bem atrás: primeiro alinha na traseira, depois puxa para o canto.
	if behind > target_half_length + 6.0: quarter = target_position - forward * (target_half_length + 1.0) + right * side * target_half_width * 0.4 + planar * lead
	return {"point": quarter, "speed": target_speed + closing, "mode": "pit"}

## Giro extra (rad/s) de um PIT: contato da viatura na traseira lateral do alvo.
## `local_point` é o ponto de contato no espaço do alvo (frente = -Z); `push` é a velocidade
## relativa da viatura (planar, mundo) e `target_basis` a base do alvo.
static func pit_spin(local_point: Vector3, push: Vector3, target_basis: Basis, target_half_width: float, target_half_length: float) -> float:
	if local_point.z < target_half_length * 0.2 or absf(local_point.x) < target_half_width * 0.25: return 0.0
	var lever := target_basis * Vector3(local_point.x, 0.0, local_point.z)
	lever.y = 0.0
	var force := Vector3(push.x, 0.0, push.z)
	return clampf(lever.cross(force).y * PIT_SPIN_GAIN, -PIT_SPIN_MAX, PIT_SPIN_MAX)

## Nota de nascimento à frente (menor é melhor): perto do ponto onde o alvo estará em
## SPAWN_LEAD_SECONDS, de preferência virada para ele; atrás do alvo é penalizado.
static func spawn_score(point: Vector3, yaw: float, anchor: Vector3, direction: Vector3, speed: float) -> float:
	var relative := point - anchor
	relative.y = 0.0
	var ahead := relative.dot(direction)
	var lateral := (relative - direction * ahead).length()
	var heading := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var facing := heading.dot(-direction)
	var score := absf(ahead - speed * SPAWN_LEAD_SECONDS) * 0.6 + lateral * 0.8 - facing * 12.0
	if ahead < 10.0: score += 120.0
	return score

static func search_radius(stars: int) -> float:
	return SEARCH_RADIUS[clampi(stars, 0, SEARCH_RADIUS.size() - 1)]

## A viatura vê o ponto? Só geometria (cone/raio); a linha de visão é do chamador.
static func in_vision(police_position: Vector3, police_forward: Vector3, point: Vector3) -> bool:
	var relative := point - police_position
	relative.y = 0.0
	var distance := relative.length()
	if distance <= VISION_NEAR: return true
	if distance > VISION_FRONT: return false
	var forward := Vector3(police_forward.x, 0.0, police_forward.z)
	if forward.length_squared() < 0.0001: return false
	return forward.normalized().angle_to(relative / distance) <= VISION_HALF_ANGLE
