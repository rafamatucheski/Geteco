extends "res://tests/test_seated_driver.gd"
## Reaproveita as checagens de encaixe no rig real, mãos, acompanhamento, restauração e material. A
## asserção acrescentada compara a pelve sentada com o vão autoral independente da porta,
## o que pega um motorista posto na caixa de carga ou à frente da cabine.

func selected_ids() -> Array:
	return ["medic_box","beach_cabriolet"]

func _check_fit(player, car, s: Dictionary, label: String) -> void:
	super._check_fit(player,car,s,label)
	var row: Dictionary = preload("res://data/catalogs/VehicleDoorSpecs.gd").row(str(car.archetype))
	var pelvis: Vector3 = car.to_local(INTERIOR.pelvis_world(player))
	check(pelvis.z >= float(row.zf)*car.visual.scale.z and pelvis.z <= float(row.zr)*car.visual.scale.z,
		label+" seated pelvis is within the front door opening, not cargo/hood (z=%.3f)" % pelvis.z)
	check(car.visual.has_meta("vehicle_interior_spec"),label+" cabin dimensions are authored independently of glass batching")
