extends RefCounted
## Ponto de entrada de compatibilidade para objetos autorais. Todas as armas compartilham a geometria
## equipada, as peças móveis, os recursos de material e a origem de encaixe.
const MODELS = preload("res://gameplay/ArsenalWeapon3D.gd")

static func build(root: Node3D, id: String) -> Vector3:
	return MODELS.build_cached(root, id)
