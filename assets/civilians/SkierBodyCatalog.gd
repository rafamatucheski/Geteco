extends RefCounted
## Corpos do Meshy dos esquiadores do Cume Branco (20/10/2026): conjunto de esqui de cores diferentes,
## botas e gorro na própria malha. Mesmo contrato do `CountryBodyCatalog`: a escolha vem da identidade,
## entradas sem arquivo são ignoradas (o esquiador fica no corpo do kit com as cores do traje) e
## `GETECO_NO_MESHY_BODIES=1` devolve o corpo procedural.
const FOLDER := "res://assets/civilians/meshy/skiers/"
const ENTRIES := [
	{"id": "ski_m_a", "file": "ski_m_a.glb", "female": false},
	{"id": "ski_m_b", "file": "ski_m_b.glb", "female": false},
	# ski_f_a (conjunto amarelo) ficou de fora: braço colado ao tronco na malha do Meshy virou "lâmina"
	# com as mãos à frente (tools/capture_catalog_bodies.gd --catalog=skiers, 20/10).
	{"id": "ski_f_b", "file": "ski_f_b.glb", "female": true},
]
static var _available: Array[Dictionary] = []
static var _scanned := false
static var enabled := OS.get_environment("GETECO_NO_MESHY_BODIES").is_empty()

static func available() -> Array[Dictionary]:
	if not _scanned:
		_scanned = true
		for entry in ENTRIES:
			if ResourceLoader.exists(FOLDER + String(entry.file)): _available.append(entry)
	return _available

## Grava corpo e variação de brilho de `identity` em `model` (ainda fora da árvore). false = sem corpo
## importado: o chamador mantém o corpo do kit com as cores do traje.
static func apply(model: Node3D, identity: int) -> bool:
	var entries := available()
	if not enabled or entries.is_empty(): return false
	var rng := RandomNumberGenerator.new()
	rng.seed = identity * 2654435761 + 70117
	var entry: Dictionary = entries[rng.randi() % entries.size()]
	model.body_source = FOLDER + String(entry.file)
	# O matiz do conjunto já vem da textura; um pouco de matiz muda a cor do traje entre esquiadores do
	# mesmo corpo sem mexer muito na pele.
	model.body_tint = {"hue": rng.randf_range(-0.05, 0.05), "brightness": rng.randf_range(0.92, 1.08)}
	model.body_accessories = [{"kind": "sunglasses"}] if rng.randf() < 0.5 else []
	return true
