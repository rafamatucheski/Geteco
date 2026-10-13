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
	# Reconstrói a partir das peças autorais, nunca de um lote já fundido.
	preload("res://runtime/RedesignedFleet.gd").enabled = false
	for id in IDS:
		var model: Node3D = preload("res://runtime/FleetCatalog.gd").create(id)
		var vehicle = preload("res://scripts/Vehicle.gd").new()
		vehicle.archetype = id
		vehicle.visual = model
		vehicle.traffic = true
		vehicle._bind_motorcycle_rider()
		assert(not vehicle._motorcycle_rider_parts.is_empty(), "Missing authored rider: " + id)
		for part in vehicle._motorcycle_rider_parts:
			part.set_meta("batch_group", "MotorcycleRider")
		# Manoplas ficam cada uma na sua malha: Vehicle.motorcycle_handholds mira o centro delas e,
		# fundidas no garfo, o piloto ficava com as mãos soltas. O wheel_center que elas trazem
		# mantém a peça no pivô de direção.
		assert(vehicle._motorcycle_grips.size() == 2, "Missing authored grips: " + id)
		for grip_side in vehicle._motorcycle_grips:
			var grip: MeshInstance3D = vehicle._motorcycle_grips[grip_side]
			grip.set_meta("batch_group", "MotorcycleGrip" + grip_side)
			grip.set_meta("batch_group_meta", {"motorcycle_grip": grip_side})
		var before: Dictionary = MESH.counts(model)
		var baked: Node3D = MESH.bake(model, 1.0, id)
		var rider := baked.get_node("MotorcycleRider")
		rider.set_meta("motorcycle_rider", true)
		baked.set_meta("motorcycle_seat", vehicle._motorcycle_seat)
		vehicle.visual = null
		vehicle.free()
		var info: Dictionary = MESH.counts(baked)
		info["before"] = before
		var destination: String = "res://assets/fleet/redesigned/" + id + ".scn"
		info["status"] = MESH.save_model(baked, destination)
		report[id] = info
		print("TWO_WHEEL_BAKED ", id, " ", info)
		baked.free()
		model.free()
	quit()
