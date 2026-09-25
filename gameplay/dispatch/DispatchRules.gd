extends RefCounted
## Regras de despacho portadas da V1, sem estado. Fontes:
##   police/WantedManager.gd        patamares, limites, intervalos, orçamento de despacho
##   emergency/EmergencyVehicle.gd  raios de parada, formação, tempos de travamento
##   emergency/ServiceIncidents.gd  capacidade e raio de agrupamento de ocorrências
##   emergency/NPCMedicalCare.gd    prazos de resgate, raio de resposta
##   police/PoliceVehicleCombat.gd  tiro a partir da viatura
## A V1 mede em pixels; 16 px = 1 m (mesma escala do restante da V2).

const PX := 16.0

# --- Polícia (WantedManager) -------------------------------------------------
const MAX_ACTIVE: Array[int] = [0, 2, 3, 4, 5, 6, 8]
const DEPLOYMENT: Array[int] = [0, 4, 6, 10, 18, 26, 40]
const INITIAL_DELAY: Array[float] = [0.0, 6.0, 3.0, 1.0, 1.0, 1.0, 1.0]
const INTERVAL: Array[float] = [0.0, 10.0, 8.0, 6.0, 4.0, 3.0, 2.0]
const SPAWN_MIN := 520.0 / PX
const SPAWN_MAX := 1800.0 / PX
const SIGHT_RANGE := 650.0 / PX
const STOP_BASE := 140.0 / PX
const STOP_STEP := 36.0 / PX
const TARGET_STOPPED_SECONDS := 1.5
const SHOT_RANGE := 300.0 / PX
const SHOT_AIM_SECONDS := 0.9
const SHOT_COOLDOWN := 0.8
const SHOT_BURST_COOLDOWN := 3.0
const SHOT_DAMAGE := 5.0
const SPEED_PATROL := 235.0 / PX
const SPEED_FAST := 255.0 / PX
const FORMATION_SPACING: Array[float] = [130.0 / PX, 175.0 / PX, 175.0 / PX, 260.0 / PX, 360.0 / PX]
const FORMATION_LEAD: Array[float] = [0.22, 0.42, 0.42, 0.70, 0.95]
const FORMATION_FLANK := 32.0 / PX
const OFFICERS_PER_CAR := 2
const OFFICERS_PER_VAN := 6
const FOOT_LIMIT: Array[int] = [0, 4, 6, 8, 10, 12, 16]

# --- Emergência ---------------------------------------------------------------
const MAX_INCIDENTS := 24
const RESPONSE_RADIUS := 1100.0 / PX
const DISPATCH_COOLDOWN := 10.0
const MAX_CREWS := 3
const UNANSWERED_SECONDS := 120.0
const MAX_INCIDENT_SECONDS := 300.0
const MERGE_RADIUS := 550.0 / PX
const FOOT_RANGE := 360.0 / PX
const ARRIVAL_MEDIC := 75.0 / PX
const ARRIVAL_FIRE := 120.0 / PX
const STUCK_POLICE := 2.0
const STUCK_SERVICE := 0.45
const RECYCLE_DISTANCE := 1000.0 / PX
const RECYCLE_STUCK_SECONDS := 24.0

# --- Limites próprios da V2 (nenhum tem equivalente na V1) ---------------------
## Teto absoluto de veículos de despacho vivos, somando todos os serviços.
const MAX_UNITS := 11
## Absolute cap; FOOT_LIMIT scales the actual response with wanted level.
const MAX_FOOT_OFFICERS := 16
## ProductionWorld remove veículos ambiente além de 145 m; suspendemos um pouco antes.
const SUSPEND_DISTANCE := 130.0
const RESUME_DISTANCE := 115.0
const SUSPEND_RECYCLE_SECONDS := 45.0
## Recuperação de ultrapassagem sem progresso (`overtake.episode_age`): a unidade
## ENCERRA O ATENDIMENTO (solta a ocorrência, sirene off, parte). O veículo segue
## recuperando fisicamente; nada é forçado por causa deste prazo.
const RECOVERY_GIVE_UP_SECONDS := 60.0
## Mesmo prazo quando o piloto já declarou `unresolved`.
const RECOVERY_GIVE_UP_UNRESOLVED_SECONDS := 25.0
## Partindo com recuperação física ainda pendente: só depois disto e FORA DA VISTA
## a unidade é removida (remoção imediata, distinta da recuperação).
const STRANDED_REMOVAL_SECONDS := 45.0
## Orçamento CUMULATIVO de recuperação física por atendimento (`unit.recovery_total`):
## soma de todos os episódios curtos. Esgotado, o próximo momento em recuperação encerra
## o atendimento (`assignment_released`, `cause = recovery_cumulative`). NÃO CALIBRADO.
const RECOVERY_CUMULATIVE_SECONDS := 90.0
## Partindo com recuperação física há tanto tempo: a unidade é "encalhada" e o
## controlador pode liberar a vaga de MAX_ACTIVE/MAX_CREWS dela (não a de MAX_UNITS). NÃO CALIBRADO.
const STRANDED_SLOT_SECONDS := 20.0
## No máximo tantas unidades encalhadas têm a vaga de perfil liberada ao mesmo tempo
## (as mais antigas primeiro); as demais continuam contando. MAX_UNITS não é afetado. NÃO CALIBRADO.
const MAX_STRANDED_RELEASED := 2

const ARCHETYPES := {"police": "police_cruiser", "medic": "medic_box", "fire": "rescue_pumper", "mortician": "station_wagon"}

static func archetype_for(service: String) -> String:
	return ARCHETYPES.get(service, "")

static func stop_radius(serial: int) -> float:
	return STOP_BASE + float(posmod(serial, 3)) * STOP_STEP

static func arrival_radius(service: String) -> float:
	match service:
		"police": return STOP_BASE
		"fire": return ARRIVAL_FIRE
		_: return ARRIVAL_MEDIC

static func variant_for(level: int, elite: bool) -> String:
	if level >= 5: return "tactical" if elite else "interceptor"
	if level >= 4: return "tactical" if elite else "patrol"
	return "interceptor" if level == 3 else "patrol"

## O equipamento pertence à equipe despachada, não às estrelas no instante
## do desembarque. Patrulhas enviadas antes da escalada mantêm seu equipamento.
## PoliceModel.UnitTier: REGULAR, DETECTIVE, SWAT, FBI, ARMY.
static func officer_tier_for(level: int, variant: String) -> int:
	match variant:
		"interceptor": return 1
		"tactical": return clampi(level - 2, 2, 4)
		_: return 0

static func speed_cap(variant: String) -> float:
	return SPEED_FAST if variant == "interceptor" else SPEED_PATROL

static func pursuit_role(serial: int) -> int:
	return posmod(serial, 5)

static func stars_index(stars: int) -> int:
	return clampi(stars, 0, MAX_ACTIVE.size() - 1)

## Ponto de interceptação da formação (EmergencyVehicle._police_dynamic_pursuit_goal).
## `forward` é a direção de referência do alvo; parado, o espaçamento encolhe
## para caber no raio de parada, como na V1.
static func formation_goal(role: int, target_position: Vector3, target_velocity: Vector3, forward: Vector3, stop_distance: float) -> Vector3:
	forward.y = 0
	var heading: Vector3 = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var lateral: Vector3 = Vector3(-heading.z, 0, heading.x)
	var planar: Vector3 = Vector3(target_velocity.x, 0, target_velocity.z)
	var lead: float = FORMATION_LEAD[role]
	var goal: Vector3 = target_position + heading * (planar.length() * lead)
	var spacing: float = FORMATION_SPACING[role]
	if planar.length() <= 12.0 / PX: spacing = minf(spacing, stop_distance * 0.65)
	match role:
		0: goal -= heading * spacing
		1: goal += lateral * FORMATION_FLANK - heading * spacing
		2: goal -= lateral * FORMATION_FLANK + heading * spacing
		_: goal += heading * spacing
	return goal
