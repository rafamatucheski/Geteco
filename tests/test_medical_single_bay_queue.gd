extends SceneTree
## Two medical incidents share the Harbor depot's single admission bay.
var failures: Array[String] = []

class Patient extends CharacterBody2D:
	var health := 0
	var max_health := 100
	var is_dead := true

class HospitalDoor extends Node2D:
	func set_emergency_door_open(_open: bool) -> void: pass

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var care := root.get_node("NPCMedicalCare")
	care.set_process(false)
	root.get_node("WantedManager").set_process(false)
	var director := preload("res://world/harbor/HarborEmergencyDirector.gd").new()
	world.add_child(director)
	director._world = world
	var depot := preload("res://world/shared/emergency/EmergencyDepotMarker.gd").new()
	depot.service_key = "ambulance"
	depot.depot_id = "single_bay_queue_test"
	for entry in [["SpawnPoint",Vector2.ZERO],["ReturnPoint",Vector2.ZERO],["ExitPoint",Vector2(150,0)]]:
		var marker := Marker2D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		depot.add_child(marker)
	director.add_child(depot)
	director.register_depot(depot)
	var first := Patient.new()
	first.name = "FirstPatient"
	first.position = Vector2(400, 0)
	world.add_child(first)
	var second := Patient.new()
	second.name = "SecondPatient"
	second.position = Vector2(500, 0)
	world.add_child(second)
	await process_frame
	await physics_frame
	care.report_injury(first)
	care.report_injury(second)
	var first_key: String = first.get_meta("medical_identity")
	var second_key: String = second.get_meta("medical_identity")
	care.incidents[first_key].phase = "reported"
	care.incidents[second_key].phase = "reported"
	care._process(.6)
	var unit: Node = care.incidents[first_key].unit
	check(is_instance_valid(unit) and unit.target == first, "First patient receives an ambulance")
	if not is_instance_valid(unit):
		quit(1)
		return
	unit.set_physics_process(false)
	check(care.incidents[second_key].unit == null and care.incidents[second_key].phase == "reported", "Second patient stays in the existing medical retry queue")
	check(director.request_dispatch("ambulance", first) == unit, "Repeated first-patient request keeps its original unit")
	check(director.request_dispatch("ambulance", second) == null and unit.target == first, "A second request never steals the first patient's ambulance")
	var active_units := 0
	for candidate in get_nodes_in_group("emergency_vehicle"):
		if candidate.type == 1 and candidate.visible: active_units += 1
	check(active_units == 1, "Only one ambulance can leave while its spawn is occupied")

	# Exercise the real admission/parking completion APIs, with travel already
	# covered by the native-hospital continuity fixture.
	care.incidents[first_key].phase = "transport"
	care.complete_hospital_admission(first, unit)
	care.incidents[second_key].retry = 0
	care._process(.6)
	check(care.incidents[second_key].unit == null, "Occupied departure remains blocked while the first crew returns")
	unit.global_position = Vector2(-13, 7)
	var parked_position: Vector2 = unit.global_position
	var hospital := HospitalDoor.new()
	world.add_child(hospital)
	var sequence := preload("res://world/shared/emergency/MedicalRescueSequence.gd").new()
	unit.add_child(sequence)
	sequence.set_physics_process(false)
	sequence.ambulance = unit
	sequence.hospital = hospital
	sequence._finish_hospital()
	await process_frame
	await physics_frame
	check(unit.visible and unit.get_meta("hospital_available", false), "Completed crew return leaves the ambulance physically parked")
	care.incidents[second_key].retry = 0
	care._process(.6)
	var second_unit: Node = care.incidents[second_key].unit
	check(second_unit == unit and unit.target == second, "Queued second patient dispatches with the same parked ambulance")
	check(unit.global_position.distance_to(parked_position) < .01, "Queued dispatch preserves the actual parking position without teleporting to the spawn marker")
	check(care.records()[first_key].phase == "hospital" and not first.visible, "The first patient's completed admission remains intact")
	unit.set_physics_process(false)
	# Let the director's two legitimate gate-close timers finish before teardown.
	await create_timer(1.35).timeout
	print("MEDICAL_SINGLE_BAY_QUEUE failures=", failures.size(), " ", failures)
	world.queue_free()
	await process_frame
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
