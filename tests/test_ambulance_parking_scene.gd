extends SceneTree
## Production-world approach/crew recording, isolated saves. --obstacles selects
## a second junction; --capture records a moving sequence, not a parked snapshot.
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var second := args.has("--obstacles")
	var output := "D:/geteco/artifacts/ambulance-parking-0913/" + ("obstacles" if second else "junction")
	DirAccess.make_dir_recursive_absolute(output+"/saves")
	var save := root.get_node("SaveManager")
	save._save_dir = output+"/saves/"
	save._save_directory_ready = false
	save.clear_pending_save()
	seed(13092026)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]: campaign.set_campaign_flag(StringName(flag),true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+90000
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec()<deadline: await process_frame
	check(world.gameplay_ready and world.world_build_ready,"Production world ready")
	if not failures.is_empty(): quit(1); return
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .45
	world.weather.set_weather(0)
	var point := Vector2(2070,2330) if not second else Vector2(2070,1360)
	var player: Node2D = world.get_node("Player")
	player.global_position = point+Vector2(20,30)
	world.get_node("PlayerCar").global_position = Vector2(700,425)
	var camera := player.get_node("Camera") as Camera2D
	camera.zoom = Vector2.ONE*1.65
	camera.reset_smoothing()
	await root.get_node("EmergencyPool").prepare_presentations()
	await create_timer(10).timeout
	var patient = load("res://AnimatedPedestrian3D.gd").new()
	patient.position = point
	world.add_child(patient)
	patient.is_gangster = false
	patient.set_physics_process(false)
	var witness = load("res://AnimatedPedestrian3D.gd").new()
	witness.position = point+Vector2(55,30)
	world.add_child(witness)
	witness.is_gangster = false
	witness.set_physics_process(false)
	patient.take_damage(200)
	var care := root.get_node("NPCMedicalCare")
	var key: String = patient.get_meta("medical_identity")
	var unit: CharacterBody2D
	for i in 1200:
		await physics_frame
		if care.incidents.has(key) and is_instance_valid(care.incidents[key].unit):
			unit = care.incidents[key].unit
			break
	check(is_instance_valid(unit),"Real medical incident dispatches ambulance")
	if unit == null: quit(1); return
	unit.global_position = point+Vector2(480,-140)
	unit.global_rotation = PI
	unit.current_speed = 0
	unit.velocity = Vector2.ZERO
	unit._lane_router.reset()
	unit.reset_physics_interpolation()
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var initial_query := PhysicsShapeQueryParameters2D.new()
	initial_query.shape = hull.shape
	initial_query.transform = hull.global_transform
	initial_query.collision_mask = 7
	initial_query.exclude = [unit.get_rid()]
	print("PARKING_INITIAL_OCCUPANTS ",unit.get_world_2d().direct_space_state.intersect_shape(initial_query).map(func(hit):return str(hit.collider.get_path())))
	if args.has("--probe"):
		unit.set_physics_process(false)
		var planner = unit._ambulance_approach
		planner._collect(unit,patient)
		for candidate in planner.candidates:
			planner.rejections.clear()
			planner.last_rejection_detail = ""
			var service: bool = planner.service_clear(unit,patient,candidate.pose)
			var maneuver: bool = planner._build_trajectory(unit,candidate.pose) if service else false
			print("PARKING_CANDIDATE ",candidate.pose," service=",service," maneuver=",maneuver," reason=",planner.rejections," detail=",planner.last_rejection_detail)
		quit(0)
		return
	var review_camera := Camera2D.new()
	review_camera.position = point+Vector2(100,-65)
	review_camera.zoom = Vector2.ONE*1.1
	world.add_child(review_camera)
	review_camera.make_current()
	var file := FileAccess.open(output+"/motion.csv",FileAccess.WRITE)
	file.store_line("ms,x,y,heading,speed,phase")
	var previous := unit.global_position
	var angle := unit.global_rotation
	var phases: Array[String] = []
	var max_side := 0.0
	var max_turn := 0.0
	var last := Time.get_ticks_usec()
	var samples: Array[float] = []
	var elapsed := 0.0
	var picture_clock := 0.0
	var pictures := 0
	for frame in 5400:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now-last)/1000.0
		last = now
		samples.append(ms)
		elapsed += ms/1000
		var phase: String = unit.get_meta("medical_phase","driving")
		if frame % 180 == 0:
			print("PARKING_PLAN ",unit.global_position," queue=",unit._ambulance_approach.candidates.size()," checked=",unit._ambulance_approach.candidates_checked," rejected=",unit._ambulance_approach.rejections," max_us=",unit._ambulance_approach.max_plan_usec)
		if not phases.has(phase):
			phases.append(phase)
			print("PARKING_PHASE ",phase," at ",unit.global_position)
			if unit.has_meta("medical_sequence"):
				var sequence: Node = unit.get_meta("medical_sequence")
				print("PARKING_CREW ",sequence.crew.map(func(medic): return medic.global_position)," cot=",sequence.stretcher.global_position if is_instance_valid(sequence.stretcher) else Vector2.INF," reason=",unit.get_meta("medical_abort_reason",""))
		var motion := unit.global_position-previous
		if phase == "driving":
			var turn := absf(angle_difference(angle,unit.global_rotation))
			max_turn = maxf(max_turn,turn)
			var middle := angle+angle_difference(angle,unit.global_rotation)*.5
			max_side = maxf(max_side,absf(motion.dot(Vector2.from_angle(middle).orthogonal())))
			check(turn <= motion.length()/65.0+.002,"Yaw requires corresponding vehicle travel")
			check(absf(motion.dot(Vector2.from_angle(middle).orthogonal())) < .5,"No lateral maneuver displacement")
		previous = unit.global_position
		angle = unit.global_rotation
		file.store_line("%f,%f,%f,%f,%f,%s" % [ms,previous.x,previous.y,angle,unit.current_speed,phase])
		picture_clock += ms/1000
		if args.has("--capture") and DisplayServer.get_name() != "headless" and picture_clock >= .2:
			picture_clock = 0
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/frame-%04d.png" % pictures)
			pictures += 1
		if elapsed >= 45 and phases.has("load_patient"): break
		if phase == "access_blocked": break
		if elapsed >= 85: break
		if args.has("--probe") and elapsed >= 8: break
	file.close()
	check(phases.has("exit") and phases.has("unload_stretcher"),"Maneuver completes and team unloads cot")
	check(phases.has("treat") and phases.has("load_patient"),"Team reaches patient and returns with loaded cot")
	check(not unit.has_meta("medical_abort_reason"),"No aborted medical sequence")
	samples.sort()
	print("PARKING_FINAL_PLAN ",unit.global_position," queue=",unit._ambulance_approach.candidates.size()," checked=",unit._ambulance_approach.candidates_checked," rejected=",unit._ambulance_approach.rejections," max_us=",unit._ambulance_approach.max_plan_usec)
	var report := {"failures":failures,"phases":phases,"seconds":elapsed,"frames":samples.size(),"pictures":pictures,"fps":samples.size()/elapsed,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"max_lateral":max_side,"max_turn":max_turn,"gpu":RenderingServer.get_video_adapter_name(),"capture":args.has("--capture"),"abort_reason":unit.get_meta("medical_abort_reason","")}
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AMBULANCE_PARKING_SCENE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
