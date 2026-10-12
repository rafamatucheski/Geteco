extends SceneTree
## Junta as peças estáticas das motos por material (uma malha por grupo de roda/garfo/corpo),
## preservando as marcações `wheel_center`/`wheel_spins` que o Vehicle usa para girar e esterçar.
## O `FleetSpeedPass` pula as motos de propósito, então elas chegavam ao jogo com ~190-240 malhas cada.
## Parte do modelo que o jogador já vê (FleetCatalog.create, com acabamento) e grava em
## assets/fleet/redesigned/<id>.scn; depois registrar o id em runtime/RedesignedFleet.gd.
const MESH := preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const IDS := ["bike_urban", "bike_sport", "bike_cruiser"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var report := {}
	for id in IDS:
		var model: Node3D = preload("res://runtime/FleetCatalog.gd").create(id)
		var before: Dictionary = MESH.counts(model)
		var baked: Node3D = MESH.bake(model, 1.0, id)
		var info: Dictionary = MESH.counts(baked)
		info["before"] = before
		var destination: String = "res://assets/fleet/redesigned/" + id + ".scn"
		info["status"] = MESH.save_model(baked, destination)
		report[id] = info
		print("TWO_WHEEL_BAKED ", id, " ", info)
		baked.free()
		model.free()
	quit()
