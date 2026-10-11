extends RefCounted
## Corpos do Meshy para os escalões da polícia (`PoliceModel`). Cada entrada serve a alguns escalões e a um
## sexo/corpulência; entradas sem arquivo são ignoradas, e sem nenhuma entrada compatível o policial segue com o
## corpo procedural do kit. O equipamento tático (colete, cinto, joelheiras, luvas, trilhos do capacete) continua
## procedural e é anexado às juntas pelo próprio `PoliceModel`.
const FOLDER := "res://assets/civilians/meshy/police/"
## `tiers`: valores de `PoliceModel.UnitTier` atendidos; `build`: 0 magro, 1 médio, 2 robusto.
const ENTRIES := []
## Testes podem forçar um corpo por escalão: {tier: "res://….glb"}.
static var override: Dictionary = {}
static var enabled := OS.get_environment("GETECO_NO_MESHY_BODIES").is_empty()
static var _available: Array = []
static var _scanned := false

static func _entries() -> Array:
	if not _scanned:
		_scanned = true
		for entry in ENTRIES:
			if ResourceLoader.exists(FOLDER + String(entry.file)): _available.append(entry)
	return _available

## Devolve {"path": …, "tint": {…}} ou {} quando não há corpo importado para este policial.
static func pick(tier: int, look: Dictionary, appearance_index: int) -> Dictionary:
	if not enabled: return {}
	if override.has(tier): return {"path": String(override[tier]), "tint": {}}
	var best: Array = []
	var best_distance := 99
	for entry in _entries():
		if not (tier in entry.tiers): continue
		if bool(entry.female) != bool(look.get("female", false)): continue
		var distance := absi(int(entry.build) - int(look.get("build", 1)))
		if distance < best_distance:
			best_distance = distance
			best = [entry]
		elif distance == best_distance:
			best.append(entry)
	if best.is_empty(): return {}
	var entry: Dictionary = best[posmod(appearance_index, best.size())]
	return {"path": FOLDER + String(entry.file), "tint": entry.get("tint", {})}
