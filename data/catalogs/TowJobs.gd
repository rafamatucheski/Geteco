extends RefCounted
## A sequência avança só na entrega e volta ao começo para continuar rendendo.
## Valores e liberação por missão vêm de EconomyBalance.TOW_TIERS: o serviço abre desde o
## começo, mas só com o reboque simples; as faixas que pagam mais chegam com a história.
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const JOBS := [
	{"title":"Primeiro reboque", "en":"First haul", "reward":BALANCE.TOW_TIERS[0].reward, "duration":360.0, "kind":"local"},
	{"title":"Esportivo do outro lado", "en":"Across-town sports car", "reward":BALANCE.TOW_TIERS[1].reward, "duration":540.0, "kind":"special"},
	{"title":"Viatura fora de serviço", "en":"Off-duty cruiser", "reward":BALANCE.TOW_TIERS[2].reward, "duration":600.0, "kind":"police"},
	{"title":"Colecionador sem sorte", "en":"Unlucky collector", "reward":BALANCE.TOW_TIERS[3].reward, "duration":540.0, "kind":"rare"},
	{"title":"Encomenda da madrugada", "en":"Midnight order", "reward":BALANCE.TOW_TIERS[4].reward, "duration":600.0, "kind":"police"},
]

## Faixas liberadas pelas missões concluídas (a primeira está sempre aberta).
static func unlocked(completed: Array) -> Array[int]:
	var result: Array[int] = []
	for index in JOBS.size():
		var requires := str(BALANCE.TOW_TIERS[index].requires)
		if requires.is_empty() or completed.has(requires): result.append(index)
	return result

## Próxima faixa da rodada, girando só pelas liberadas.
static func next_index(tow_completed: int, completed: Array) -> int:
	var open := unlocked(completed)
	return open[posmod(tow_completed, open.size())]

static func next_job(data: Dictionary, completed: Array = []) -> Dictionary:
	var index := next_index(int(data.get("tow_completed",0)), completed)
	var spec: Dictionary = JOBS[index].duplicate(true)
	spec["stage"] = index + 1
	return spec

## Contrato gravado antes da mudança de valores continua válido com o valor antigo.
static func reward_accepted(index: int, reward: Variant) -> bool:
	if index < 0 or index >= JOBS.size() or typeof(reward) not in [TYPE_INT, TYPE_FLOAT]: return false
	return float(reward) == float(JOBS[index].reward) or float(reward) == float(BALANCE.TOW_LEGACY_REWARDS[index])

static func is_night(time: float) -> bool:
	return time >= 20.0/24.0 or time < 0.25
