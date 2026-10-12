extends "res://tests/test_seated_driver.gd"
## Reuse real-rig fit, hands, follow, restore and material checks. The added
## assertion compares the seated pelvis to the independent authored door span,
## which catches a driver placed in the cargo box or ahead of the cockpit.

func selected_ids() -> Array:
	return ["medic_box","beach_cabriolet"]

func _check_fit(player, car, s: Dictionary, label: String) -> void:
	super._check_fit(player,car,s,label)
	var row: Dictionary = preload("res://data/catalogs/VehicleDoorSpecs.gd").row(str(car.archetype))
	var pelvis: Vector3 = car.to_local(INTERIOR.pelvis_world(player))
	check(pelvis.z >= float(row.zf)*car.visual.scale.z and pelvis.z <= float(row.zr)*car.visual.scale.z,
		label+" seated pelvis is within the front door opening, not cargo/hood (z=%.3f)" % pelvis.z)
	check(car.visual.has_meta("vehicle_interior_spec"),label+" cabin dimensions are authored independently of glass batching")
