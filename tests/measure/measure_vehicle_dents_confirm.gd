extends "res://tests/measure/measure_vehicle_dents.gd"
## Finite A/B confirmation on identical current sources. Only observer car's
## deformation/recoil is disabled in A; other live city systems stay identical.
func _process(delta: float) -> bool:
	if baseline and is_instance_valid(car) and is_instance_valid(car.body_dents):
		car.body_dents.free()
		car.body_dents=null
	return super._process(delta)
