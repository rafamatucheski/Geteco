extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("CREW_LOSS ",label," ",ok)
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var care := root.get_node("NPCMedicalCare")
	care.set_process(false)
	root.get_node("WantedManager").set_process(false)
	var vehicle = preload("res://emergency/EmergencyVehicle.gd").new()
	vehicle.type = 1
	vehicle.position = Vector2(250,0)
	world.add_child(vehicle)
	vehicle.set_physics_process(false)
	var patient = preload("res://AnimatedPedestrian3D.gd").new()
	patient.name = "CrewLossPatient"
	world.add_child(patient)
	await process_frame
	patient.take_damage(1000)
	care.report_injury(patient)
	# Rescue starts after the native fall has settled, as in the live flow.
	for i in 90: await physics_frame
	var crew: Array = []
	for i in 2:
		var medic = preload("res://emergency/Paramedic.gd").new()
		medic.name = "CrewLossMedic%d" % i
		medic.ambulance = vehicle
		medic.position = Vector2(-25+i*50,0)
		world.add_child(medic)
		crew.append(medic)
	var sequence = preload("res://emergency/MedicalRescueSequence.gd").new()
	world.add_child(sequence)
	sequence.setup(vehicle,patient,crew)
	check(care.begin_carry(patient,vehicle,sequence),"real care service accepts the patient claim")
	var cot = preload("res://emergency/MedicalStretcher.gd").new()
	world.add_child(cot)
	sequence.stretcher = cot
	cot.load_patient(patient)
	cot.update_patient()
	sequence.carrying = true
	sequence._set_phase("return_with_patient")
	var initial_pose: Transform3D = cot.patient_transform
	var key: String = patient.get_meta("medical_identity")
	var bullet = preload("res://guns/Bullet.gd").new()
	bullet.damage = 1000
	world.add_child(bullet)
	bullet._hit(crew[0],crew[0].global_position,Vector2.RIGHT)
	for i in 4: await physics_frame
	await process_frame
	check(not is_instance_valid(sequence) and not is_instance_valid(cot),"crew death cleans up the interrupted sequence and cot")
	check(vehicle.get_meta("medical_abort_reason","") == "crew_lost","fatal hit follows the existing crew-lost abort")
	check(patient.visible and patient.model_root.transform.is_equal_approx(initial_pose),"actual victim remains visible in its restored ground pose")
	check(care.incidents[key].phase == "reported" and care.incidents[key].carrier == null and care.incidents[key].unit == null,"victim is retryable with no stale carrier or vehicle claim")
	check(not crew[1].has_meta("medical_managed"),"surviving medic returns to its autonomous controller")
	check(not vehicle.has_meta("medical_sequence"),"vehicle does not retain a freed rescue owner")
	world.queue_free()
	await process_frame
	print("CREW LOSS: ",failures," failures")
	quit(1 if failures else 0)
