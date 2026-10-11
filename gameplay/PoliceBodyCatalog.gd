extends RefCounted
## Corpos do Meshy para os escalões da polícia (`PoliceModel`). Cada entrada serve a alguns escalões e a um
## sexo/corpulência; entradas sem arquivo são ignoradas, e sem nenhuma entrada compatível o policial segue com o
## corpo procedural do kit. O equipamento tático (colete, cinto, joelheiras, luvas, trilhos do capacete) continua
## procedural e é anexado às juntas pelo próprio `PoliceModel`.
const FOLDER := "res://assets/civilians/meshy/police/"
## `tiers`: valores de `PoliceModel.UnitTier` atendidos (0 patrulha, 1 detetive, 2 SWAT, 3 FBI, 4 Exército);
## `build`: 0 magro, 1 médio, 2 robusto; `tint.tone` escurece/colore as roupas sem mexer na pele (o terno cinza
## vira marrom de detetive ou preto de FBI, o tático cinza vira oliva do Exército). Escalões táticos femininos e o
## biotipo magro ainda não têm corpo próprio e seguem com o corpo procedural (ou o médio mais próximo). O FBI usa
## o terno sem o colete procedural: o tronco do terno é raso e o colete do kit ficava flutuando sobre ele.
const ENTRIES := [
	{"id": "patrol_m", "file": "patrol_m.glb", "tiers": [0], "female": false, "build": 1, "skin": 0.62},
	{"id": "patrol_heavy", "file": "patrol_heavy.glb", "tiers": [0], "female": false, "build": 2, "skin": 0.25},
	{"id": "patrol_f", "file": "patrol_f.glb", "tiers": [0], "female": true, "build": 1, "skin": 0.45},
	{"id": "detective_m", "file": "suit_m.glb", "tiers": [1], "female": false, "build": 1, "skin": 0.62, "tint": {"tone": Color(1.0, 0.82, 0.62)}, "accessories": [{"kind": "fedora", "chance": 0.55, "color": Color("3b342d"), "band": Color("141210")}]},
	{"id": "detective_f", "file": "suit_f.glb", "tiers": [1], "female": true, "build": 1, "skin": 0.22, "tint": {"tone": Color(1.0, 0.82, 0.62)}, "accessories": [{"kind": "fedora", "chance": 0.35, "color": Color("3b342d"), "band": Color("141210")}]},
	{"id": "fbi_m", "file": "suit_m.glb", "tiers": [3], "female": false, "build": 1, "skin": 0.62, "baked_equipment": true, "tint": {"tone": Color(0.42, 0.42, 0.46)}, "accessories": [{"kind": "sunglasses", "chance": 0.85}]},
	{"id": "fbi_f", "file": "suit_f.glb", "tiers": [3], "female": true, "build": 1, "skin": 0.22, "baked_equipment": true, "tint": {"tone": Color(0.42, 0.42, 0.46)}, "accessories": [{"kind": "sunglasses", "chance": 0.85}]},
	{"id": "swat_gray", "file": "tactical_gray.glb", "tiers": [2], "female": false, "build": 1, "skin": 0.62, "baked_equipment": true, "tint": {"tone": Color(0.5, 0.52, 0.56)}},
	{"id": "swat_black", "file": "tactical_black.glb", "tiers": [2], "female": false, "build": 1, "skin": 0.25, "baked_equipment": true},
	{"id": "army_gray", "file": "tactical_gray.glb", "tiers": [4], "female": false, "build": 1, "skin": 0.62, "baked_equipment": true, "tint": {"tone": Color(0.62, 0.72, 0.45)}},
	{"id": "army_black", "file": "tactical_black.glb", "tiers": [4], "female": false, "build": 1, "skin": 0.25, "baked_equipment": true, "tint": {"tone": Color(0.9, 1.0, 0.62)}},
]
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

## Devolve {"path": …, "tint": {…}, "baked_equipment": bool} ou {} quando não há corpo importado para este policial.
## `baked_equipment`: capacete, colete e joelheiras já fazem parte da malha (escalões táticos do Meshy); o
## `PoliceModel` então não anexa o equipamento procedural por cima, que ficaria duplicado.
static func pick(tier: int, look: Dictionary, appearance_index: int) -> Dictionary:
	if not enabled: return {}
	if override.has(tier): return {"path": String(override[tier]), "tint": {}, "baked_equipment": false, "accessories": []}
	# Pontuação: biotipo (0/1/2) e luminância da pele do policial contra a da entrada; empates rodam pelo
	# `appearance_index`, para o mesmo policial manter o mesmo corpo e policiais diferentes variarem.
	var skin_luminance := Color(look.get("skin", Color(0.7, 0.55, 0.42))).get_luminance()
	var scored: Array = []
	var best_score := 99.0
	for entry in _entries():
		if not (tier in entry.tiers): continue
		if bool(entry.female) != bool(look.get("female", false)): continue
		var score := float(absi(int(entry.build) - int(look.get("build", 1)))) + absf(float(entry.get("skin", skin_luminance)) - skin_luminance) * 2.0
		scored.append([score, entry])
		best_score = minf(best_score, score)
	var best: Array = []
	for item in scored:
		if item[0] <= best_score + 0.15: best.append(item[1])
	if best.is_empty(): return {}
	var entry: Dictionary = best[posmod(appearance_index, best.size())]
	# Peças de cabeça do papel (fedora do detetive, óculos escuros do FBI), sorteadas pelo `appearance_index`.
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_index * 2654435761 + 7919
	var accessories: Array = []
	for piece in entry.get("accessories", []):
		if rng.randf() < float(piece.chance):
			accessories.append({"kind": piece.kind, "color": piece.get("color", Color("2f3b52")), "band": piece.get("band", Color("1d1f22"))})
	return {"path": FOLDER + String(entry.file), "tint": entry.get("tint", {}), "baked_equipment": bool(entry.get("baked_equipment", false)), "accessories": accessories}
