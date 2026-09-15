extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func run() -> void:
	create_timer(100).timeout.connect(func(): print("RESERVE_ADMISSION_TIMEOUT"); quit(2))
	Engine.time_scale = 2.0
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var care := root.get_node("NPCMedicalCare")
	care.set_process(false)
	var hospital := preload("res://world/harbor/hospital/HarborHospital.gd").new()
	hospital.position = Vector2(1800, 1530)
	world.add_child(hospital)
	var parking := preload("res://world/harbor/HarborMedicalParking.gd").new()
	world.add_child(parking)
	var director := preload("res://world/harbor/HarborEmergencyDirector.gd").new()
	world.add_child(director)
	director._world = world
	var units: Array[Node2D] = []
	for index in 2:
		var unit: Node2D
		for frame in 60:
			unit = root.get_node("EmergencyPool").get_vehicle("ambulance")
			if is_instance_valid(unit): break
			await process_frame
		if not is_instance_valid(unit):
			check(false, "Two finite pool ambulances are available")
			quit(1)
			return
		unit.set_physics_process(false)
		unit.set_meta("harbor_director_id", director.get_instance_id())
		unit.home_return_position = hospital.get_ambulance_stop_position()
		unit.home_depot_id = "reserve_test"
		unit.global_position = director.get_medical_return_position(unit)
		unit.global_rotation = 0.0
		units.append(unit)
	var main := units[0]
	var reserve := units[1]
	check(main.global_position.distance_to(hospital.get_ambulance_stop_position()) < .01, "First ambulance receives the main bay")
	check(reserve.global_position.distance_to(parking.RESERVE_STOP + Vector2(0, -12)) < .01, "Second ambulance receives the marked reserve bay")
	check(director.is_medical_bay_owner(main), "First arrived crew acquires admission")
	check(not director.is_medical_bay_owner(reserve), "Reserve crew waits while the hospital door is occupied")
	director.release_medical_admission(main)
	check(director.is_medical_bay_owner(reserve), "Next crew acquires admission when the first finishes")
	check(main.global_position.distance_to(hospital.get_ambulance_stop_position()) < .01, "Releasing admission does not move the parked ambulance")
	var patient = load("res://characters/AnimatedPedestrian3D.gd").new()
	patient.name = "ReservePatient"
	patient.position = reserve.global_position
	world.add_child(patient)
	patient.set_physics_process(false)
	patient.is_gangster = false
	await process_frame
	patient.is_dead = true
	patient.health = 0
	care.report_injury(patient)
	reserve.target = patient
	reserve._deploy_paramedics()
	var sequence: Node = reserve.get_meta("medical_sequence")
	sequence.stretcher = preload("res://emergency/MedicalStretcher.gd").new()
	world.add_child(sequence.stretcher)
	sequence.stretcher.global_position = reserve.to_global(Vector2(-18, 0))
	sequence.stretcher.heading = 0.0
	sequence.stretcher.add_collision_exception_with(reserve)
	for medic in sequence.crew:
		sequence.stretcher.add_collision_exception_with(medic)
		medic.add_collision_exception_with(sequence.stretcher)
	care.begin_carry(patient, reserve, sequence)
	sequence.stretcher.load_patient(patient)
	care.board_patient(patient, reserve)
	sequence.carrying = true
	sequence.delivered = true
	sequence.stretcher.hide()
	sequence.start_hospital_admission(hospital)
	var key: String = patient.get_meta("medical_identity")
	var phases: Array[String] = []
	var previous := {}
	var max_step := 0.0
	for frame in 5400:
		await physics_frame
		if not is_instance_valid(sequence): break
		if phases.is_empty() or phases.back() != sequence.phase:
			phases.append(sequence.phase)
			print("RESERVE_PHASE ", sequence.phase)
		for actor in sequence.crew + [sequence.stretcher]:
			if not is_instance_valid(actor) or not actor.visible: continue
			var id: int = actor.get_instance_id()
			if previous.has(id): max_step = maxf(max_step, actor.global_position.distance_to(previous[id]))
			previous[id] = actor.global_position
		if frame % 600 == 0:
			print("RESERVE_STATUS ", sequence.phase, " cot=", sequence.stretcher.global_position, " crew=", sequence.crew[0].global_position, ",", sequence.crew[1].global_position)
	check(care.records().get(key, {}).get("phase", "") == "hospital", "Real patient is admitted from the reserve bay")
	check(phases.has("hospital_inside") and phases.has("hospital_return_cot"), "Crew physically crosses the hospital door and returns the cot")
	check(reserve.get_meta("hospital_available", false), "Both medics finish reboarding in the reserve bay")
	check(max_step < 5.0, "Visible crew and cot never teleport around the parked main unit")
	check(main.global_position.distance_to(hospital.get_ambulance_stop_position()) < .01, "Main unit remains parked throughout the second handoff")
	print("MEDICAL_RESERVE_ADMISSION failures=", failures, " max_step=", max_step)
	world.queue_free()
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
