extends RefCounted
## Treino na academia Ferro Velho (Harbor). Cada série completa sobe um nível de força ou de fôlego,
## conforme o aparelho. Força aumenta o dano corpo a corpo; fôlego, a velocidade da corrida.
## Mora em `world_state.gym`; o save só aceita níveis que caibam no número de séries feitas.
const KEY := "gym"
const MAX_LEVEL := 20
const MAX_SETS := 100000
## Aparelho → atributo. Os nomes são os clipes de `assets/dante/mixamo/dante_mixamo_gym.res`.
const STATIONS := {
	"punching_bag":"strength", "speedbag":"strength", "bicep_curl":"strength", "push_up":"strength",
	"jump_rope":"stamina", "air_squat":"stamina", "situps":"stamina", "treadmill":"stamina",
}
const LABELS := {
	"punching_bag":"Saco de pancada", "speedbag":"Speedbag", "bicep_curl":"Rosca com halter", "push_up":"Flexão",
	"jump_rope":"Pular corda", "air_squat":"Agachamento", "situps":"Abdominal", "treadmill":"Esteira",
}
## No nível máximo: +30% de dano corpo a corpo e +8% de velocidade correndo.
const STRENGTH_DAMAGE := 0.30
const STAMINA_SPRINT := 0.08

static func fresh() -> Dictionary:
	return {"version":1, "strength":0, "stamina":0, "sets":0}

static func data(world: Dictionary) -> Dictionary:
	var value: Variant = world.get(KEY, fresh())
	return value.duplicate(true) if value is Dictionary else {}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or value.size() != 4: return false
	if not _integer(value.get("strength"), 0, MAX_LEVEL) or not _integer(value.get("stamina"), 0, MAX_LEVEL): return false
	if not _integer(value.get("sets"), 0, MAX_SETS): return false
	return int(value.strength) + int(value.stamina) <= int(value.sets)

static func validate_world(world: Dictionary) -> bool:
	return not world.has(KEY) or valid(world[KEY])

## Conta a série e sobe o atributo do aparelho. Devolve o atributo, o nível novo e se subiu.
static func complete_set(world: Dictionary, station: String) -> Dictionary:
	var saved := data(world)
	if not STATIONS.has(station) or not valid(saved): return {"ok":false}
	var attribute: String = STATIONS[station]
	var raised: bool = int(saved[attribute]) < MAX_LEVEL
	if int(saved.sets) >= MAX_SETS: return {"ok":false}
	saved.sets = int(saved.sets) + 1
	if raised: saved[attribute] = int(saved[attribute]) + 1
	world[KEY] = saved
	return {"ok":true, "attribute":attribute, "level":int(saved[attribute]), "raised":raised}

## Lidas a cada quadro pelo Gameplay: sem `data()` (que duplica o dicionário), só a leitura do nível.
static func melee_damage_scale(world: Dictionary) -> float:
	return 1.0 + STRENGTH_DAMAGE * _level(world, "strength") / MAX_LEVEL

static func sprint_scale(world: Dictionary) -> float:
	return 1.0 + STAMINA_SPRINT * _level(world, "stamina") / MAX_LEVEL

static func _level(world: Dictionary, attribute: String) -> float:
	var saved: Variant = world.get(KEY)
	if not saved is Dictionary: return 0.0
	var value: Variant = saved.get(attribute, 0)
	return clampf(float(value), 0.0, MAX_LEVEL) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else 0.0
