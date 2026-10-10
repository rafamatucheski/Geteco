extends RefCounted
## Catálogo de corpos do Meshy para os pedestres genéricos da rua.
##
## Escolhe, pela identidade do pedestre, uma entrada compatível com o sexo e a corpulência que o próprio
## `CivilianModel` sortearia (`_appearance_wardrobe`), então a mesma identidade tem sempre o mesmo corpo.
## Cada GLB tem 4,1 mil triângulos, 24 ossos e uma textura 1024 (`tools/meshy_slim_glb.py`). A variedade
## extra vem de `civilian_meshy.gdshader`: matiz e brilho só das roupas coloridas, por instância.
## Entradas cujo arquivo não existe são ignoradas; sem nenhuma entrada o pedestre segue procedural.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const FOLDER := "res://assets/civilians/meshy/pedestrians/"
## build: 0 magro, 1 médio, 2 robusto (mesma escala de `CivilianMeshKit.build_profile`).
const ENTRIES := [
	{"id": "m_medium_a", "file": "m_medium_a.glb", "female": false, "build": 1},
	{"id": "m_medium_b", "file": "m_medium_b.glb", "female": false, "build": 1},
	{"id": "m_heavy_a", "file": "m_heavy_a.glb", "female": false, "build": 2},
	{"id": "m_heavy_b", "file": "m_heavy_b.glb", "female": false, "build": 2},
	{"id": "f_medium_a", "file": "f_medium_a.glb", "female": true, "build": 1},
	{"id": "f_medium_b", "file": "f_medium_b.glb", "female": true, "build": 1},
	{"id": "f_slim_a", "file": "f_slim_a.glb", "female": true, "build": 0},
	{"id": "f_slim_b", "file": "f_slim_b.glb", "female": true, "build": 0},
]
static var _available: Array[Dictionary] = []
static var _scanned := false
## Interruptor para comparar desempenho e para desligar o catálogo sem mexer em arquivos:
## `GETECO_NO_MESHY_BODIES=1` deixa todos os pedestres no corpo procedural do kit; testes também podem
## atribuir `enabled` em tempo de execução.
static var enabled := OS.get_environment("GETECO_NO_MESHY_BODIES").is_empty()

static func available() -> Array[Dictionary]:
	if not _scanned:
		_scanned = true
		for entry in ENTRIES:
			if ResourceLoader.exists(FOLDER + String(entry.file)): _available.append(entry)
	return _available

## Escolhe o corpo de `identity` e o grava em `model` (que ainda não entrou na árvore). Devolve false, e
## deixa o corpo procedural, quando o modelo tem guarda-roupa fixo (montanha, uniformes) ou não há entrada.
static func apply(model: Node3D, identity: int) -> bool:
	if not enabled or not model.wardrobe_overrides.is_empty(): return false
	var entries := available()
	if entries.is_empty(): return false
	var wardrobe: Dictionary = CIVILIAN._appearance_wardrobe(identity, model.coat_color, model.pants_color, Color.TRANSPARENT, {})
	var best: Array[Dictionary] = []
	var best_distance := 99
	for entry in entries:
		if bool(entry.female) != bool(wardrobe.female): continue
		var distance := absi(int(entry.build) - int(wardrobe.build))
		if distance < best_distance:
			best_distance = distance
			best = [entry]
		elif distance == best_distance:
			best.append(entry)
	if best.is_empty(): best = entries # só existem corpos do outro sexo: melhor um corpo novo do que nenhum
	# Gerador local: não consome o RNG global do jogo e mantém a identidade estável entre sessões.
	var rng := RandomNumberGenerator.new()
	rng.seed = identity * 2654435761 + 40503
	var entry: Dictionary = best[rng.randi() % best.size()]
	model.body_source = FOLDER + String(entry.file)
	model.body_tint = {"hue": rng.randf_range(-0.5, 0.5), "brightness": rng.randf_range(0.88, 1.12)}
	return true
