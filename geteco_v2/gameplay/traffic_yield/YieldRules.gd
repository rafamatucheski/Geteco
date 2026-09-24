extends RefCounted
## Constantes e testes geométricos puros do módulo de cessão de passagem.
## Não há equivalente numérico na V1 (o tráfego 2D dela abria caminho por
## `EmergencyLaneRouter`, que não existe na V2); os valores abaixo são escolhas
## novas, todas em metros/segundos, e precisam de calibração em jogo.

## A viatura é ameaça quando chega ao ambiente em `DETECT_SECONDS` s à velocidade atual,
## limitado a [DETECT_MIN, DETECT_MAX] m.
const DETECT_MIN := 35.0
const DETECT_MAX := 60.0
const DETECT_SECONDS := 3.5
## Meia-largura do corredor da viatura (além da meia-largura do veículo ambiente).
const CORRIDOR := 4.5
## Parada com sirene não cede passagem: só viatura em movimento.
const MIN_EMERGENCY_SPEED := 2.5
## cos do ângulo máximo entre as direções para contar como "mesmo sentido".
const SAME_DIRECTION := 0.45
## Viatura já passou quando o ambiente está tanto atrás dela.
const PASSED_MARGIN := 7.0
## Comprimentos de tentativa da manobra lateral, do mais curto ao mais longo.
const PULL_LENGTHS: Array[float] = [10.0, 16.0, 24.0, 34.0]
const MERGE_LENGTH := 14.0
const SAMPLE_STEP := 2.0
## Folga mantida entre a lateral do veículo e o limite da pista.
const EDGE_MARGIN := 0.35
const MAX_SHIFT := 3.0
const MIN_SHIFT := 0.3
## Velocidade máxima enquanto cede (o Vehicle ambiente já não passa de 5,5 m/s).
const YIELD_SPEED := 3.5
const SLOW_ONLY_SPEED := 2.0
## Só volta à rota depois de ficar sem ameaça por este tempo.
const RESUME_DELAY := 1.2
const CLEAR_BEHIND := 10.0
## Viatura ao lado (ultrapassando) também impede o carro que cedeu de voltar à faixa.
const PASSING_ZONE := 7.0
## Teto de espera parado; depois disso volta assim que o espaço estiver livre.
const HOLD_MAX := 30.0
const PROGRESS_TIMEOUT := 4.0
const COOLDOWN := 3.0
const MAX_YIELDERS := 10
const SCAN_INTERVAL := 0.2
const MAX_STARTS_PER_SCAN := 2
## Cruzamento: raio somado à meia-largura da pista onde não se para.
const JUNCTION_MARGIN := 3.0

static func detection_range(emergency_speed: float) -> float:
	return clampf(emergency_speed * DETECT_SECONDS, DETECT_MIN, DETECT_MAX)

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

## Distância do ambiente à frente da viatura (`along`) e desvio lateral (`lateral`, em módulo).
static func relative(e_position: Vector3, e_forward: Vector3, point: Vector3) -> Vector2:
	var forward := _flat(e_forward).normalized()
	var rel := _flat(point - e_position)
	var right := forward.cross(Vector3.UP)
	return Vector2(rel.dot(forward), absf(rel.dot(right)))

static func threatens(e_position: Vector3, e_forward: Vector3, e_speed: float, a_position: Vector3, a_forward: Vector3, a_half_width: float) -> bool:
	if e_speed < MIN_EMERGENCY_SPEED: return false
	if _flat(a_forward).normalized().dot(_flat(e_forward).normalized()) < SAME_DIRECTION: return false
	var rel := relative(e_position, e_forward, a_position)
	return rel.x >= 1.0 and rel.x <= detection_range(e_speed) and rel.y <= CORRIDOR + a_half_width

## A viatura já está à frente do ambiente (ou longe demais para importar).
static func passed(e_position: Vector3, e_forward: Vector3, e_speed: float, a_position: Vector3) -> bool:
	var rel := relative(e_position, e_forward, a_position)
	return rel.x < -PASSED_MARGIN or rel.x > detection_range(maxf(e_speed, MIN_EMERGENCY_SPEED)) + 15.0

## Viatura logo atrás do ambiente, perto o bastante para a volta à pista ser insegura.
static func close_behind(e_position: Vector3, e_forward: Vector3, e_speed: float, a_position: Vector3, a_half_width: float) -> bool:
	if e_speed < MIN_EMERGENCY_SPEED: return false
	var rel := relative(e_position, e_forward, a_position)
	return rel.x > -PASSING_ZONE and rel.x < CLEAR_BEHIND and rel.y <= CORRIDOR + a_half_width
