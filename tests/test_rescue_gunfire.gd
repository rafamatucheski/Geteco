extends "res://tests/test_medical_choreography_continuity.gd"
## The production rescue fixture, interrupted by real projectiles in two stages.
var fired_before := false
var fired_loaded := false
var saw_shelter := false
var saw_regroup := false
var saw_resume := false
var saw_evacuation := false
var retreat_distance := 0.0
var threat_origin := Vector2.ZERO
var cot_at_pause := Vector2.ZERO
var patient_at_pause := Vector2.ZERO
var interruption_errors := {}
var observed_positions := {}
var captured := {}

func run() -> void:
	# The unchanged fixture has 100s including 7s parked observation. This
	# scenario adds a mandatory 4s pause plus the physical return from shelter
	# (at most 4*136/90 seconds in this open fixture), rounded up to 12s.
	maximum_test_seconds = 112.0
	physics_frame.connect(_observe_threat)
	await super.run()

func _nearby_shot(sequence: Node) -> void:
	var medic: CharacterBody2D = sequence.crew[0]
	var origin := Vector2.INF
	for i in 8:
		var candidate := medic.global_position + Vector2.from_angle(i*PI/4)*75
		if preload("res://world/shared/combat/ShotQuery.gd").cast(medic,candidate,medic.global_position,7,[medic.get_rid()],true).is_empty():
			origin = candidate
			break
	if origin == Vector2.INF:
		interruption_errors["Threat fixture requires a shooter with unobstructed sight"] = true
		return
	var bullet = preload("res://Bullet.tscn").instantiate()
	bullet.position = origin
	bullet.direction = medic.global_position.direction_to(origin)
	bullet.damage = 1
	bullet.speed = 1200
	world.add_child(bullet)

func _observe_threat() -> void:
	# Keep evidence local to this task, including when the parent fixture runs
	# with a renderer. Its default medical-*.png filenames are shared.
	render = false
	for unit in get_nodes_in_group("emergency_vehicle"):
		if not unit.has_meta("medical_sequence"): continue
		var sequence: Node = unit.get_meta("medical_sequence")
		if not is_instance_valid(sequence): continue
		for actor in sequence.crew + [sequence.patient,sequence.stretcher]:
			if not is_instance_valid(actor): continue
			var id: int = actor.get_instance_id()
			if actor.visible:
				if observed_positions.has(id) and actor.global_position.distance_to(observed_positions[id]) > 5:
					print("RESCUE STEP ", actor.name," phase=",sequence.phase," from=",observed_positions[id]," to=",actor.global_position)
				observed_positions[id] = actor.global_position
			else: observed_positions.erase(id)
		if sequence.hospital_delivery: continue
		if sequence.phase == "treat" and sequence.phase_time > .4 and not fired_before:
			fired_before = true
			threat_origin = sequence.crew[0].global_position
			cot_at_pause = sequence.stretcher.global_position
			patient_at_pause = sequence.patient.global_position
			_nearby_shot(sequence)
		var response: String = unit.get_meta("medical_threat_response", "")
		var capture_ready: bool = (response == "sheltering" and sequence.danger.quiet_time < 2.8) or response == "regrouping" or (response == "evacuating" and sequence.phase != "lift_patient")
		if DisplayServer.get_name() != "headless" and capture_ready and not captured.has(response):
			captured[response] = true
			_capture_response.call_deferred(response)
		if response == "sheltering":
			saw_shelter = true
			retreat_distance = maxf(retreat_distance, sequence.crew[0].global_position.distance_to(threat_origin))
			if sequence.phase != "treat" or sequence.carrying: interruption_errors["Treatment must pause before claiming patient"] = true
			if sequence.phase_time > .05: interruption_errors["Interrupted treatment restarts its care interval"] = true
			if sequence.stretcher.global_position.distance_to(cot_at_pause) > .01: interruption_errors["Unattended cot stays at its physical position"] = true
			if sequence.patient.global_position.distance_to(patient_at_pause) > .01: interruption_errors["Unclaimed patient stays on the ground"] = true
		if response == "regrouping": saw_regroup = true
		if saw_regroup and sequence.phase == "lift_patient": saw_resume = true
		if sequence.phase == "lift_patient" and sequence.phase_time > .6 and not fired_loaded:
			fired_loaded = true
			_nearby_shot(sequence)
		if fired_loaded and response == "evacuating":
			saw_evacuation = true
			if not sequence.carrying or sequence.stretcher.patient_actor != sequence.patient:
				interruption_errors["Evacuating team retains the actual patient on the cot"] = true

func check(ok: bool, label: String) -> void:
	if label.begins_with("Parked ambulance survives"):
		super.check(fired_before and saw_shelter and retreat_distance > 15, "Real nearby gunfire makes the treating crew withdraw")
		super.check(saw_regroup and saw_resume, "Crew physically regroups and resumes interrupted treatment")
		super.check(fired_loaded and saw_evacuation, "Gunfire during carrying prioritizes evacuation together")
		for issue in interruption_errors: super.check(false, str(issue))
		print("RESCUE GUNFIRE retreat=",retreat_distance," shelter=",saw_shelter," regroup=",saw_regroup," resume=",saw_resume," evacuation=",saw_evacuation)
	super.check(ok, label)

func _capture_response(label: String) -> void:
	var camera := root.get_camera_2d()
	var old_position := camera.position
	var old_zoom := camera.zoom
	camera.zoom = Vector2.ONE*1.7
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/shot-feedback-0913/"+label+".png")
	camera.position = old_position
	camera.zoom = old_zoom
