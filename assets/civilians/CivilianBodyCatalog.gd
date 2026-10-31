extends RefCounted
## Catálogo de corpos do Meshy para os pedestres genéricos da rua.
##
## Escolhe, pela identidade do pedestre, uma entrada compatível com o sexo e a corpulência que o próprio
## `CivilianModel` sortearia (`_appearance_wardrobe`), então a mesma identidade tem sempre o mesmo corpo.
## Cada GLB tem 4,1 mil triângulos, 24 ossos e uma textura 1024 (`tools/meshy_slim_glb.py`). A variedade
## extra vem dos acessórios e de uma pequena variação de brilho por instância.
## Entradas cujo arquivo não existe são ignoradas; sem nenhuma entrada o pedestre segue procedural.
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const FOLDER := "res://assets/civilians/meshy/pedestrians/"
## build: 0 magro, 1 médio, 2 robusto (mesma escala de `CivilianMeshKit.build_profile`).
const ENTRIES := [
	{"id": "m_medium_a", "file": "m_medium_a.glb", "female": false, "build": 1},
	{"id": "m_medium_b", "file": "m_medium_b.glb", "female": false, "build": 1},
	{"id": "m_heavy_a", "file": "m_heavy_a.glb", "female": false, "build": 2},
	{"id": "m_heavy_b", "file": "m_heavy_b.glb", "female": false, "build": 2},
	# Lote de diversidade (19/10): homem magro (faltava o build 0 masculino), asiático, latino e brasileiro pardo.
	{"id": "m_slim_a", "file": "m_slim_a.glb", "female": false, "build": 0},
	{"id": "m_slim_b", "file": "m_slim_b.glb", "female": false, "build": 0},
	{"id": "m_medium_c", "file": "m_medium_c.glb", "female": false, "build": 1},
	{"id": "m_medium_d", "file": "m_medium_d.glb", "female": false, "build": 1},
	{"id": "f_medium_a", "file": "f_medium_a.glb", "female": true, "build": 1},
	{"id": "f_medium_b", "file": "f_medium_b.glb", "female": true, "build": 1},
	{"id": "f_slim_a", "file": "f_slim_a.glb", "female": true, "build": 0},
	{"id": "f_slim_b", "file": "f_slim_b.glb", "female": true, "build": 0},
	# Lote de diversidade (19/10): mulher negra de cabelo crespo, sul-asiática e a primeira robusta (build 2 feminino).
	{"id": "f_slim_c", "file": "f_slim_c.glb", "female": true, "build": 0},
	{"id": "f_medium_c", "file": "f_medium_c.glb", "female": true, "build": 1},
	{"id": "f_heavy_a", "file": "f_heavy_a.glb", "female": true, "build": 2},
]
## Peças de cabeça sorteadas por identidade (chapéus/bonés/óculos escuros), presas ao crânio pelo `MeshyBodyRig`.
## Cada passo do sorteio usa o mesmo gerador da identidade, então a pessoa mantém o visual entre sessões.
const HAT_COLORS := [Color("2f3b52"), Color("6b2f2a"), Color("3d4a38"), Color("d8d2c2"), Color("1f2124"), Color("8a6a3d"), Color("b9b2a0")]
const HATS := [["cap", 0.55], ["beanie", 0.18], ["fedora", 0.10], ["straw", 0.17]]
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
	if not enabled: return false
	for key in model.wardrobe_overrides:
		if key != "female": return false
	var entries := available()
	if entries.is_empty(): return false
	var wardrobe: Dictionary = CIVILIAN._appearance_wardrobe(identity, model.coat_color, model.pants_color, Color.TRANSPARENT, model.wardrobe_overrides)
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
	if best.is_empty(): return false # Mantém o corpo procedural correspondente, nunca uma malha do gênero oposto.
	# Gerador local: não consome o RNG global do jogo e mantém a identidade estável entre sessões.
	var rng := RandomNumberGenerator.new()
	rng.seed = identity * 2654435761 + 40503
	var entry: Dictionary = best[rng.randi() % best.size()]
	model.body_source = FOLDER + String(entry.file)
	# Estas texturas não têm máscara de roupa: a heurística de matiz também
	# recoloria a pele (sobretudo tons escuros) de verde/rosa. Preserve o matiz
	# autorado e o passo do RNG para não trocar acessórios de identidades existentes.
	rng.randf()
	model.body_tint = {"hue": 0.0, "brightness": rng.randf_range(0.88, 1.12)}
	model.body_accessories = roll_accessories(rng, 0.20, 0.14, HATS)
	return true

## Para NPC de guarda-roupa fixo (moradores, funcionários): tenta o corpo Meshy do mesmo sexo e, sem
## entrada compatível, devolve o guarda-roupa original ao corpo do kit. Sem isto `apply` recusava
## qualquer override e os interiores ficavam cheios do corpo antigo (playtest 18/10).
static func apply_keeping_sex(model: Node3D, identity: int) -> bool:
	var original: Dictionary = model.wardrobe_overrides
	model.wardrobe_overrides = {"female": bool(original.get("female", false))} if original.has("female") else {}
	if apply(model, identity): return true
	model.wardrobe_overrides = original
	return false

## Sorteia chapéu (chance `hat_chance`, tipo por pesos de `hats`) e óculos escuros (`glasses_chance`).
static func roll_accessories(rng: RandomNumberGenerator, hat_chance: float, glasses_chance: float, hats: Array) -> Array:
	var list: Array = []
	var hat_roll := rng.randf()
	var kind_roll := rng.randf()
	var color: Color = HAT_COLORS[rng.randi() % HAT_COLORS.size()]
	var glasses_roll := rng.randf()
	if hat_roll < hat_chance:
		var total := 0.0
		for entry in hats: total += float(entry[1])
		var pick := kind_roll * total
		for entry in hats:
			pick -= float(entry[1])
			if pick <= 0.0:
				list.append({"kind": entry[0], "color": color, "band": color.darkened(0.55)})
				break
	if glasses_roll < glasses_chance: list.append({"kind": "sunglasses"})
	return list
