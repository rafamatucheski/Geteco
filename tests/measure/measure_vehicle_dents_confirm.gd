extends "res://tests/measure/measure_vehicle_dents.gd"
## Confirmação A/B finita com códigos atuais idênticos. Só a deformação/recuo do carro
## observador é desligada em A; os outros sistemas da cidade viva ficam idênticos.
func _process(delta: float) -> bool:
	if baseline and is_instance_valid(car) and is_instance_valid(car.body_dents):
		car.body_dents.free()
		car.body_dents=null
	return super._process(delta)
