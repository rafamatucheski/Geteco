extends "res://world/places/NativePlace.gd"
## Dedicated Harbor shop; FullSession owns admission, camera and resident lifetime.
const ID := "harbor_curitiba_cellar"
const EXTERIOR := Vector3(136.5, .12, 10.5)

static func definition_data() -> Dictionary:
	return {
		"id": ID, "original_name": "Curitiba Cellar", "region": "harbor",
		"source_id": "curitiba_cellar", "model": "res://world/places/curitiba_cellar/CuritibaCellarInterior.gd",
		"exterior_position": EXTERIOR, "entry_position": EXTERIOR + Vector3(0, 0, 6.7),
		"return_position": EXTERIOR + Vector3(0, 0, 7.8),
		"spawn": Vector3(0, 0, 4), "exit": Vector3(0, 0, 4.95),
		"size": Vector2(14, 11), "camera_target": Vector3(0, .7, -.3), "camera_size": 15.2,
		"variant": 0, "service": "wine", "reward": {}, "rewards": [],
		"npc_model": "", "npc_point": Vector3.ZERO, "integration_status": "native",
		"npcs": [
			{"id": "cellar_nelson", "name": "Nelson", "model": "res://world/places/curitiba_cellar/NelsonModel.gd",
				"appearance": {}, "local_position": Vector3(-1.8, 0, -3.62)},
			{"id": "cellar_luisa", "name": "Luísa", "model": "res://world/places/curitiba_cellar/LuisaModel.gd",
				"appearance": {}, "local_position": Vector3(4.65, 0, -3.92)},
		],
	}

func _ready() -> void:
	super._ready()
	interaction_points.service = to_global(Vector3(-1.8, 0, -1.35))
	interaction_points.luisa = to_global(Vector3(3.05, 0, -2.15))
	interaction_points.nelson = interaction_points.service
