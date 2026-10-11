extends RefCounted
## Corpos do Meshy do pessoal "country" do parque de motocross (arquibancadas, boxes e beira de pista): camisa
## xadrez, jeans e botas, com chapéu de vaqueiro/palha e óculos escuros presos ao crânio (`MeshyAccessories`).
##
## Mesmo contrato do `CivilianBodyCatalog`: a escolha vem da identidade (estável entre sessões), entradas sem
## arquivo são ignoradas e `GETECO_NO_MESHY_BODIES=1` devolve o corpo procedural do kit. `hat: false` marca corpos
## que já trazem o chapéu na malha (não ganham outro por cima).
const FOLDER := "res://assets/civilians/meshy/country/"
const ENTRIES := [
	{"id": "country_m_a", "file": "country_m_a.glb", "female": false, "hat": false},
	{"id": "country_m_b", "file": "country_m_b.glb", "female": false, "hat": false},
	{"id": "country_f_a", "file": "country_f_a.glb", "female": true, "hat": true},
	{"id": "country_f_b", "file": "country_f_b.glb", "female": true, "hat": true},
]
const HATS := [["cowboy", 0.6], ["straw", 0.3], ["cap", 0.1]]
const HAT_COLORS := [Color("6b4a2c"), Color("8a6a3d"), Color("2b2622"), Color("c9b88a"), Color("4a3a2a"), Color("a08a62")]
static var _available: Array[Dictionary] = []
static var _scanned := false
static var enabled := OS.get_environment("GETECO_NO_MESHY_BODIES").is_empty()

static func available() -> Array[Dictionary]:
	if not _scanned:
		_scanned = true
		for entry in ENTRIES:
			if ResourceLoader.exists(FOLDER + String(entry.file)): _available.append(entry)
	return _available

## Grava corpo, variação de cor e acessórios de `identity` em `model` (ainda fora da árvore). false = sem corpo
## importado disponível: o chamador mantém o corpo procedural.
static func apply(model: Node3D, identity: int) -> bool:
	var entries := available()
	if not enabled or entries.is_empty(): return false
	var rng := RandomNumberGenerator.new()
	rng.seed = identity * 2654435761 + 91013
	var entry: Dictionary = entries[rng.randi() % entries.size()]
	model.body_source = FOLDER + String(entry.file)
	# Só variação suave de brilho: o matiz da camisa xadrez já vem da textura de cada corpo.
	model.body_tint = {"hue": rng.randf_range(-0.08, 0.08), "brightness": rng.randf_range(0.9, 1.1)}
	var accessories: Array = []
	var wears_hat := bool(entry.hat) and rng.randf() < 0.85
	var kind_roll := rng.randf()
	var color: Color = HAT_COLORS[rng.randi() % HAT_COLORS.size()]
	if wears_hat:
		var pick := kind_roll
		for hat in HATS:
			pick -= float(hat[1])
			if pick <= 0.0:
				accessories.append({"kind": hat[0], "color": color, "band": color.darkened(0.5)})
				break
	if rng.randf() < 0.22: accessories.append({"kind": "sunglasses"})
	model.body_accessories = accessories
	return true
