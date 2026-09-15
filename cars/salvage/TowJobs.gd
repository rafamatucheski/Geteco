extends RefCounted
## A sequência avança só na entrega e volta ao começo para continuar rendendo.
const JOBS := [
	{"title":"Primeiro reboque", "en":"First haul", "reward":1800, "duration":360.0, "kind":"local"},
	{"title":"Esportivo do outro lado", "en":"Across-town sports car", "reward":3200, "duration":540.0, "kind":"special"},
	{"title":"Viatura fora de serviço", "en":"Off-duty cruiser", "reward":4200, "duration":600.0, "kind":"police"},
	{"title":"Colecionador sem sorte", "en":"Unlucky collector", "reward":4800, "duration":540.0, "kind":"rare"},
	{"title":"Encomenda da madrugada", "en":"Midnight order", "reward":6000, "duration":600.0, "kind":"police"},
]

static func next_job(data: Dictionary) -> Dictionary:
	var index := int(data.get("tow_completed",0)) % JOBS.size()
	var spec: Dictionary = JOBS[index].duplicate(true)
	spec["stage"] = index + 1
	return spec

static func is_night(time: float) -> bool:
	return time >= 20.0/24.0 or time < 0.25
