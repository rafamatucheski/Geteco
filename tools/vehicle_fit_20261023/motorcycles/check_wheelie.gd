extends "res://tests/test_motorcycle_wheelie.gd"
func _initialize() -> void:
	for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
		preload("res://runtime/RedesignedFleet.gd")._scenes[id]=load("res://artifacts/vehicle-fit-20261023/motorcycles/"+id+".scn")
	run.call_deferred()
