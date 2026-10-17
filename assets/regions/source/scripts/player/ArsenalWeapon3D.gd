extends RefCounted
## Compatibility entry point for authored props. All weapons share the equipped
## geometry, moving pieces, material resources and attachment origin.
const MODELS = preload("res://gameplay/ArsenalWeapon3D.gd")

static func build(root: Node3D, id: String) -> Vector3:
	return MODELS.build_cached(root, id)
