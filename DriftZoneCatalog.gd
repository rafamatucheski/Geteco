class_name DriftZoneCatalog
extends RefCounted

## Catálogo de zonas de desafio de derrapagem. Cada entrada vira uma
## DriftChallengeZone própria, instanciada por CityDemo._spawn_world_extras().

const ZONES := {
	"patio_central": {
		"id": "patio_central",
		"name": "PÁTIO CENTRAL",
		"pos": Vector2(950, 650),
		"radius": 95.0,
		"reward_per_1000": 150,
	},
	"curva_oeste": {
		"id": "curva_oeste",
		"name": "CURVA OESTE",
		"pos": Vector2(250, 700),
		"radius": 85.0,
		"reward_per_1000": 170,
	},
	"rotatoria_leste": {
		"id": "rotatoria_leste",
		"name": "ROTATÓRIA LESTE",
		"pos": Vector2(1300, 700),
		"radius": 90.0,
		"reward_per_1000": 190,
	},
}

static func get_all() -> Array:
	return ZONES.values()
