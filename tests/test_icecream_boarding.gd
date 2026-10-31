extends "res://tests/test_vehicle_doors.gd"
## Reaproveita as asserções reais de entrada/saída, mão, cabeça, corpo e folga da porta.
func spawn(id: String, yaw: float) -> CharacterBody3D:
	var car := super.spawn(id,yaw)
	car.vehicle_id = "street_icecream_boarding"
	return car

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	actor = ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	await test_vehicle("courier_van")
	for line in report: print(line)
	print("ICECREAM_BOARDING checks=",checks," failures=",failures)
	stage.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
