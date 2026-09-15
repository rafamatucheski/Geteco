extends SceneTree
var failures: Array[String] = []
var phases: Array[String] = []
var render := false
var world: Node2D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	create_timer(120).timeout.connect(func(): print("MEDICAL TIMEOUT ",phases); quit(2))
	render = DisplayServer.get_name() != "headless"
	if not render: Engine.time_scale = 2.0
	root.size = Vector2i(1100,700)
	world = Node2D.new()
	world.name = "MedicalTestRegion"
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var care = root.get_node("NPCMedicalCare")
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-2000,-2000),Vector2(2000,-2000),Vector2(2000,2000),Vector2(-2000,2000)])
	ground.color = Color("637478")
	world.add_child(ground)
	var camera := Camera2D.new()
	camera.position = Vector2(115,0)
	camera.zoom = Vector2.ONE*3.0
	world.add_child(camera)
	var lane := Path2D.new()
	lane.curve = Curve2D.new()
	lane.curve.add_point(Vector2(-500,0))
	lane.curve.add_point(Vector2(500,0))
	lane.curve.add_point(Vector2(600,100))
	lane.curve.add_point(Vector2(500,200))
	lane.curve.add_point(Vector2(-500,200))
	lane.curve.add_point(Vector2(-600,100))
	lane.curve.add_point(Vector2(-500,0))
	lane.add_to_group("unified_traffic_lane")
	world.add_child(lane)
	var director := preload("res://emergency/EmergencyDepotDirector.gd").new()
	var depot := preload("res://emergency/EmergencyDepotMarker.gd").new()
	depot.service_key = "ambulance"
	depot.depot_id = "test_hospital"
	depot.position = Vector2(-250,0)
	for entry in [["SpawnPoint",Vector2.ZERO],["ReturnPoint",Vector2.ZERO],["ExitPoint",Vector2(90,0)]]:
		var marker := Marker2D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		depot.add_child(marker)
	director.add_child(depot)
	world.add_child(director)
	var patient = load("res://characters/AnimatedPedestrian3D.gd").new()
	patient.name = "ReturningResident"
	patient.position = Vector2(180,30)
	world.add_child(patient)
	patient.set_physics_process(false)
	var witness = load("res://characters/AnimatedPedestrian3D.gd").new()
	witness.name = "RegionalColleague"
	witness.position = Vector2(240,90)
	world.add_child(witness)
	witness.is_gangster = false
	witness.set_physics_process(false)
	await process_frame
	await process_frame
	care.residents[patient.get_meta("medical_identity")].physics = true
	var home: Vector2 = patient.global_position
	patient.take_damage(1000)
	patient.set_physics_process(true)
	var key: String = patient.get_meta("medical_identity")
	check(patient.has_meta("medical_pending"), "Lethal injury stays available for ambulance")
	var saw_witness := false
	var call_time := 0.0
	var saw_phone := false
	var premature_dispatch := false
	var loaded_patient := false
	var unit: Node
	var last_phase := ""
	for frame in 6500:
		await physics_frame
		if witness.has_meta("medical_witness"): saw_witness = true
		if care.incidents.has(key):
			var caller: Variant = care.incidents[key].witness
			if is_instance_valid(caller) and caller.phase == "call":
				call_time = maxf(call_time, caller.CALL_DURATION - caller.timer)
				saw_phone = saw_phone or (is_instance_valid(caller._phone) and caller._phone.visible)
			var candidate: Variant = care.incidents[key].unit
			if is_instance_valid(candidate):
				unit = candidate
				if call_time < 4.9: premature_dispatch = true
		if is_instance_valid(unit):
			if frame % 600 == 0: print("MEDICAL STATUS ",unit.global_position," returning=",unit.is_returning_to_base," crew=",unit.returned_paramedics,"/",unit.deployed_paramedics)
			var phase: String = unit.get_meta("medical_phase", "driving")
			if phase != last_phase:
				last_phase = phase
				phases.append(phase)
				print("MEDICAL PHASE ",phase)
			var sequence: Node = unit.get_meta("medical_sequence") if unit.has_meta("medical_sequence") else null
			if is_instance_valid(sequence) and sequence.carrying:
				loaded_patient = is_instance_valid(sequence.stretcher.patient_model)
			if render and phase in ["open_rear", "treat", "lift_patient", "return_with_patient", "load_patient"] and is_instance_valid(sequence) and sequence.phase_time > .6 and not unit.has_meta("photo_"+phase):
				unit.set_meta("photo_"+phase, true)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/medical-"+phase+".png")
		if care.records().get(key,{}).get("phase", "") == "hospital": break
	check(saw_witness, "Colleague notices and calls")
	check(saw_phone, "Caller visibly holds a phone")
	check(call_time >= 4.9 and not premature_dispatch, "Ambulance waits for five seconds of visible calling")
	check(loaded_patient, "Stretcher contains the actual character model")
	check(care.records().get(key,{}).get("phase", "") == "hospital", "Ambulance reaches hospital before admission")
	check(not patient.visible, "Hospitalized NPC stays absent")
	var saved: Dictionary = root.get_node("CampaignState").to_save_data()
	check(saved.npc_medical_care.has(key), "Hospital record is serialized")
	care.advance_days(1.0)
	check(not patient.visible and patient.is_dead, "Critical patient stays hospitalized after one day")
	care.advance_days(1.01)
	await process_frame
	check(patient.visible and not patient.is_dead and patient.health == patient.max_health, "Same NPC returns healthy after two days")
	check(patient.global_position.distance_to(home) < 5, "Resident returns to original region and routine")
	check(not care.records().has(key), "Discharge clears only completed admission")
	print("NPC_MEDICAL_ROUTINE failures=",failures.size()," ",failures)
	world.queue_free()
	await process_frame
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)
