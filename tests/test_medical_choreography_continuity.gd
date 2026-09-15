extends SceneTree
var failures: Array[String] = []
var phases: Array[String] = []
var render := false
var world: Node2D
var previous_positions := {}
var max_visible_step := 0.0
var identity_preserved := true
var premature_admission := false
var hidden_crew_solid := false
var saw_westbound_rescue := false
var reserve_bay := false
var parked_main: Node2D
# Covers rescue, a full road loop and a physically swept hospital maneuver.
# The former 100-second watchdog assumed the old pivot/slide into the bay;
# the measured native-hospital cycle now takes about 110 simulated seconds.
# Per-phase access and no-progress deadlines remain enforced by production.
var maximum_test_seconds := 150.0

class AdmissionDoor extends Node2D:
	var opened := false
	func _ready() -> void: add_to_group("hospital_emergency_admission")
	func get_ambulance_stop_position() -> Vector2: return Vector2(-250, 0)
	func get_ambulance_stop_rotation() -> float: return 0
	func get_admission_door_position() -> Vector2: return Vector2(-352, 0)
	func get_admission_inside_position() -> Vector2: return Vector2(-390, 0)
	func set_emergency_door_open(value: bool) -> void: opened = value

class RailGate extends Node2D:
	var road_width := 80.0
	var gate_offset := 72.0
	var closed := true
	func _ready() -> void: add_to_group("rail_level_crossing")
	func should_stop_vehicle() -> bool: return closed

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	create_timer(maximum_test_seconds).timeout.connect(func(): print("MEDICAL TIMEOUT ",phases); quit(2))
	render = DisplayServer.get_name() != "headless"
	reserve_bay = "--reserve-hospital" in OS.get_cmdline_user_args()
	if not render: Engine.time_scale = 2.0
	root.size = Vector2i(1100,700)
	world = Node2D.new()
	world.name = "MedicalTestRegion"
	root.add_child(world)
	current_scene = world
	if reserve_bay or "--native-hospital" in OS.get_cmdline_user_args():
		var hospital := preload("res://world/harbor/hospital/HarborHospital.gd").new()
		hospital.position = Vector2(-435, -40)
		world.add_child(hospital)
	else:
		world.add_child(AdmissionDoor.new())
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
	if reserve_bay or "--native-hospital" in OS.get_cmdline_user_args():
		# The old mock loop crossed straight through the new hospital's body.
		# Keep the authored arrival lane on the open east side of its bay.
		lane.curve.clear_points()
		for point in [Vector2(-250,0), Vector2(500,0), Vector2(600,100), Vector2(500,200), Vector2(-180,200), Vector2(-180,60), Vector2(-250,0)]:
			lane.curve.add_point(point)
	if "--reverse-ambulance" in OS.get_cmdline_user_args():
		# Approach the casualty westbound as in the user's film. Every
		# responder waypoint must rotate with the ambulance, including return.
		lane.curve.clear_points()
		for point in [Vector2(-250,0), Vector2(-180,-60), Vector2(-180,-200), Vector2(500,-200), Vector2(600,-100), Vector2(500,0), Vector2(-250,0)]:
			lane.curve.add_point(point)
	world.add_child(lane)
	var director: Node2D = preload("res://world/harbor/HarborEmergencyDirector.gd").new() if reserve_bay else preload("res://world/shared/emergency/EmergencyDepotDirector.gd").new()
	var depot := preload("res://world/shared/emergency/EmergencyDepotMarker.gd").new()
	depot.service_key = "ambulance"
	depot.depot_id = "test_hospital"
	depot.position = Vector2(-250,0)
	for entry in [["SpawnPoint",Vector2.ZERO],["ReturnPoint",Vector2.ZERO],["ExitPoint",Vector2(90,0)]]:
		var marker := Marker2D.new()
		marker.name = entry[0]
		marker.position = entry[1]
		if reserve_bay and entry[0] != "ReturnPoint": marker.position.y += 86.0
		depot.add_child(marker)
	director.add_child(depot)
	world.add_child(director)
	if reserve_bay:
		director._world = world
		for frame in 30:
			parked_main = root.get_node("EmergencyPool").get_vehicle("ambulance")
			if is_instance_valid(parked_main): break
			await process_frame
		if not is_instance_valid(parked_main):
			check(false, "Reserve fixture obtains the parked main ambulance from the real pool")
			quit(1)
			return
		parked_main.global_position = Vector2(-250, 0)
		parked_main.global_rotation = 0
		parked_main.set_physics_process(false)
		parked_main.set_meta("harbor_director_id", director.get_instance_id())
		director._medical_slots[parked_main.get_instance_id()] = parked_main.global_position
	var patient = load("res://AnimatedPedestrian3D.gd").new()
	patient.name = "ReturningResident"
	patient.position = Vector2(180,30)
	world.add_child(patient)
	patient.is_gangster = false
	patient.set_physics_process(false)
	var witness = load("res://AnimatedPedestrian3D.gd").new()
	witness.name = "RegionalColleague"
	witness.position = Vector2(240,90)
	world.add_child(witness)
	witness.is_gangster = false
	witness.set_physics_process(false)
	await process_frame
	await process_frame
	care.residents[patient.get_meta("medical_identity")].physics = true
	var home: Vector2 = patient.global_position
	patient.get_run_over(Vector2(80,0))
	patient.set_physics_process(true)
	var key: String = patient.get_meta("medical_identity")
	check(patient.has_meta("medical_pending"), "Survivable injury stays available for ambulance")
	var saw_witness := false
	var loaded_patient := false
	var unit: Node
	var last_phase := ""
	for frame in 6500:
		await physics_frame
		if witness.has_meta("medical_witness"): saw_witness = true
		if care.incidents.has(key):
			var candidate: Variant = care.incidents[key].unit
			if is_instance_valid(candidate): unit = candidate
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
				identity_preserved = identity_preserved and sequence.stretcher.patient_model == patient.model_root
			if is_instance_valid(sequence):
				if phase == "exit" and not sequence.hospital_delivery:
					saw_westbound_rescue = saw_westbound_rescue or absf(angle_difference(unit.global_rotation, PI)) < .25
				if phase == "transport" and sequence.phase_time > .1:
					for medic in sequence.crew:
						if medic.collision_layer != 0 or medic.collision_mask != 0: hidden_crew_solid = true
				for actor in sequence.crew + [patient, sequence.stretcher]:
					if not is_instance_valid(actor): continue
					var id: int = actor.get_instance_id()
					if actor.visible:
						if previous_positions.has(id): max_visible_step = maxf(max_visible_step, actor.global_position.distance_to(previous_positions[id]))
						previous_positions[id] = actor.global_position
					else: previous_positions.erase(id)
				if sequence.hospital_delivery and not sequence.admitted and care.records().get(key,{}).get("phase", "") == "hospital": premature_admission = true
			if render and phase in ["open_rear", "treat", "lift_patient", "return_with_patient", "load_patient"] and is_instance_valid(sequence) and sequence.phase_time > .6 and not unit.has_meta("photo_"+phase):
				unit.set_meta("photo_"+phase, true)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/medical-"+phase+".png")
		if is_instance_valid(unit) and unit.get_meta("medical_phase", "") == "parked": break
	if reserve_bay:
		check(parked_main.global_position.distance_to(Vector2(-250, 0)) < .01, "First ambulance remains in its own main bay during the second admission")
		check(is_instance_valid(unit) and unit.global_position.distance_to(director.get_medical_return_position(unit)) < 18.0, "Second ambulance returns physically to its assigned reserve bay")
	check(saw_witness, "Colleague notices and calls")
	check(loaded_patient, "Stretcher contains the actual character model")
	if "--reverse-ambulance" in OS.get_cmdline_user_args():
		check(saw_westbound_rescue, "The rescue was actually performed with the ambulance facing PI as in the filmed case")
	check(identity_preserved, "Patient keeps the original model and viewport through every handoff")
	check(max_visible_step < 5, "No visible crew, cot or patient jumps: maximum step %0.3f" % max_visible_step)
	check(not premature_admission, "Hospital admission waits until the patient crosses the entrance")
	check(not hidden_crew_solid, "Boarded medics leave no invisible colliders at the rescue scene")
	check(is_instance_valid(unit) and unit.visible and unit.get_meta("hospital_available", false), "Ambulance remains physically parked after hospital delivery")
	var before_idle: Vector2 = unit.global_position
	await create_timer(7.0).timeout
	check(unit.visible and unit.get_meta("hospital_available", false) and unit.global_position.distance_to(before_idle) < .01, "Parked ambulance survives the old five-second anti-stuck recycle window")
	check(phases.has("hospital_inside") and phases.has("parked"), "Crew wheels the patient inside and concludes the hospital handoff")
	var rail := RailGate.new()
	world.add_child(rail)
	var rail_sequence = preload("res://world/shared/emergency/MedicalRescueSequence.gd").new()
	world.add_child(rail_sequence)
	rail_sequence.set_physics_process(false)
	rail_sequence.stretcher = CharacterBody2D.new()
	world.add_child(rail_sequence.stretcher)
	rail_sequence.stretcher.position = Vector2(-130, 0)
	check(rail_sequence._wait_for_rail(Vector2.RIGHT), "Entire cot team waits outside an active railway gate")
	rail_sequence.stretcher.position = Vector2(0, 0)
	check(not rail_sequence._wait_for_rail(Vector2.RIGHT), "A team already on the railway clears it instead of stopping on the tracks")
	rail.closed = false
	rail_sequence.stretcher.position = Vector2(-130, 0)
	check(not rail_sequence._wait_for_rail(Vector2.RIGHT), "Team resumes after the railway opens")
	rail_sequence.queue_free()
	rail.queue_free()
	check(care.records().get(key,{}).get("phase", "") == "hospital", "Ambulance reaches hospital before admission")
	check(not patient.visible, "Hospitalized NPC stays absent")
	var saved: Dictionary = root.get_node("CampaignState").to_save_data()
	check(saved.npc_medical_care.has(key), "Hospital record is serialized")
	care.advance_days(.5)
	check(not patient.visible and patient.is_incapacitated, "Patient stays hospitalized until recovery completes")
	care.advance_days(.51)
	# Check the restored spawn before the resident resumes walking. A rendered
	# frame may contain several physics ticks, especially in headless mode.
	check(patient.global_position.distance_to(home) < 5, "Resident returns to original region and routine")
	await process_frame
	check(patient.visible and not patient.is_dead and patient.health == patient.max_health, "Same NPC returns healthy after hospital recovery")
	check(not care.records().has(key), "Discharge clears only completed admission")
	var parked_position: Vector2 = unit.global_position
	var reused: Node = root.get_node("EmergencyPool").get_vehicle("ambulance")
	check(reused == unit and reused.global_position.distance_to(parked_position) < .01, "Next dispatch reuses the same parked ambulance without relocation")
	var ownership = preload("res://world/harbor/HarborEmergencyDirector.gd").new()
	world.add_child(ownership)
	reused.set_meta("harbor_director_id", ownership.get_instance_id())
	reused.set_meta("hospital_available", true)
	ownership.queue_free()
	await process_frame
	check(not reused.visible and reused.target == null, "Region teardown returns parked units even after their completed request bucket was removed")
	print("MEDICAL_CONTINUITY max_visible_step=", max_visible_step, " identity=", identity_preserved, " phases=", phases)
	print("NPC_MEDICAL_ROUTINE failures=",failures.size()," ",failures)
	world.queue_free()
	await process_frame
	await process_frame
	care.incidents.clear()
	care.residents.clear()
	quit(0 if failures.is_empty() else 1)

