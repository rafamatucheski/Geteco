extends SceneTree
## Production road scene, parked response pose and two casualties from the film.
var failures: Array[String] = []
var samples: Array[float] = []
var phases := {}
var world: Node2D
var unit: Node2D
var patients: Array = []
var label := "after"
var last_tick := 0
var sampling := false
var movie_frame := 0
var movie_time := 0.0
var movie := false
var near_post := false
var parked_teams := false
var far_parking := false
var movie_times: Array[float] = []
var solid_errors := {}

func _initialize() -> void: run.call_deferred()

func run() -> void:
	seed(13092313)
	if not OS.get_cmdline_user_args().is_empty(): label = OS.get_cmdline_user_args()[0]
	movie = "--motion" in OS.get_cmdline_user_args()
	near_post = "--near-post" in OS.get_cmdline_user_args()
	parked_teams = "--parked-teams" in OS.get_cmdline_user_args()
	far_parking = "--far-parking" in OS.get_cmdline_user_args()
	parked_teams = parked_teams or far_parking
	if movie: DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/rescue-0913/"+label+"-motion")
	create_timer(150).timeout.connect(func(): print("JUNCTION TIMEOUT ", phases); quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("SaveManager").set("_save_dir", "D:/geteco/artifacts/rescue-0913/saves/")
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/rescue-0913/saves")
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag), true)
	world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	print("JUNCTION WORLD READY paused=",paused)
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(2130, 2330)
	player.velocity = Vector2.ZERO
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(2160, 2240)
	camera.zoom = Vector2.ONE * 1.6
	camera.make_current()
	world.weather.time_of_day = .42
	world.weather.is_dynamic_time = false
	world.weather.set_weather(0)
	await create_timer(6).timeout
	for signal_post in get_nodes_in_group("fixed_traffic_signal"):
		if signal_post.global_position.distance_to(Vector2(2200, 2200)) < 200: print("JUNCTION POST ",signal_post.global_position)
	var care := root.get_node("NPCMedicalCare")
	if parked_teams: care.set_process(false)
	for position in [Vector2(2070,2330), Vector2(2180,2330)]:
		var actor = load("res://AnimatedPedestrian3D.gd").new()
		actor.position = position
		world.add_child(actor)
		actor.is_gangster = false
		actor.set_physics_process(false)
		patients.append(actor)
	await process_frame
	for actor in patients:
		# The current triage distinguishes living incapacitated victims from
		# confirmed deaths, which belong to the coroner service.
		actor.take_damage(actor.health-maxi(1,actor.health/5))
		actor.is_incapacitated = true
		actor._start_fall()
		care.report_injury(actor)
		care.witness_called(actor)
	# Start at the already parked ambulance: driving/parking is a separate contract.
	var director: Node = care._nearest_director(patients[0])
	for frame in 60:
		unit = director.request_dispatch("ambulance",patients[0])
		if is_instance_valid(unit): break
		await process_frame
	unit.global_position = Vector2(2096, 2224)
	if near_post: unit.global_position.x -= 24
	unit.global_rotation = PI - .26
	unit.target = patients[0]
	unit.is_acting = true
	unit.set_physics_process(false)
	var key: String = patients[0].get_meta("medical_identity")
	care.incidents[key].unit = unit
	care.incidents[key].phase = "dispatched"
	unit._deploy_paramedics()
	if parked_teams:
		var second: Node2D = director.request_dispatch("ambulance",patients[1])
		if not is_instance_valid(second):
			push_error("No second ambulance for the parked-team fixture")
			quit(1)
			return
		second.set_physics_process(false)
		var found := false
		# Set up an already parked second unit using the production clearance
		# contract. All positioning happens before observing either rescue.
		for x in [2370,2450,2530,1910,1830,1750]:
			var pose := Transform2D(PI-.26,Vector2(x,2224))
			if far_parking: pose = Transform2D(PI,Vector2(1939.899,1981))
			for slice in 240:
				if second._ambulance_approach.service_clear(second,patients[1],pose):
					found = true
					break
				if not second._ambulance_approach._walk_pending: break
				await physics_frame
			if found:
				second.global_transform = pose
				break
		if not found:
			push_error("No physically clear second parking fixture")
			quit(1)
			return
		var second_key: String = patients[1].get_meta("medical_identity")
		care.incidents[second_key].unit = second
		care.incidents[second_key].phase = "dispatched"
		second.target = patients[1]
		second.set_meta("ambulance_walk_route",second._ambulance_approach.walk_route.duplicate())
		second.is_acting = true
		second._deploy_paramedics()
		print("SECOND_PARKED ",second.global_position)
	print("JUNCTION ENV ",RenderingServer.get_video_adapter_name()," vsync=",DisplayServer.window_get_vsync_mode()," fps_limit=",Engine.max_fps)
	process_frame.connect(measure)
	sampling = true
	var start := Time.get_ticks_msec()
	var last_phase := ""
	var next_picture := 0.0
	while Time.get_ticks_msec() - start < 95000:
		await physics_frame
		for response in get_nodes_in_group("emergency_vehicle"):
			if not response.has_meta("medical_sequence"): continue
			var active_sequence: Node = response.get_meta("medical_sequence")
			if is_instance_valid(active_sequence) and active_sequence.phase_time > .15:
				observe_solids(active_sequence)
		if movie and Time.get_ticks_msec()/1000.0 >= movie_time:
			movie_time = Time.get_ticks_msec()/1000.0 + .1
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/rescue-0913/"+label+"-motion/%04d.png"%movie_frame)
			movie_times.append((Time.get_ticks_msec()-start)/1000.0)
			movie_frame += 1
		var phase: String = unit.get_meta("medical_phase", "none")
		# Only the roadside starting pose is authored by this fixture. Once
		# boarded, restore native driving so this unit cannot block the next one.
		if phase == "transport" and not parked_teams: unit.set_physics_process(true)
		if phase != last_phase:
			print("JUNCTION PHASE ",phase," t=",(Time.get_ticks_msec()-start)/1000.0)
			last_phase = phase
			phases[phase] = true
		var sequence: Node = unit.get_meta("medical_sequence") if unit.has_meta("medical_sequence") else null
		if is_instance_valid(sequence) and sequence.elapsed >= next_picture:
			next_picture += 5
			print("JUNCTION STATE ",phase," cot=",sequence.stretcher.global_position if is_instance_valid(sequence.stretcher) else Vector2.ZERO," crew=",sequence.crew[0].global_position,",",sequence.crew[1].global_position)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/rescue-0913/"+label+"-%03d.png"%int(next_picture))
		var second_key: String = patients[1].get_meta("medical_identity")
		var second_incident: Dictionary = care.incidents.get(second_key,{})
		var second_unit: Node = second_incident.get("unit")
		if is_instance_valid(second_unit) and int(Time.get_ticks_msec()-start)%5000 < 25:
			print("SECOND_UNIT ",second_unit.global_position," phase=",second_unit.get_meta("medical_phase","driving")," abort=",second_unit.get_meta("medical_abort_reason",""))
			print("SECOND_PASSAGE ",second_unit._traffic_passage.state," joining=",second_unit._traffic_passage.joining," complete=",second_unit._traffic_passage.completed," reason=",second_unit._traffic_passage.route.failure if second_unit._traffic_passage.route else "")
			if second_unit.has_meta("medical_sequence"):
				var rescue: Node = second_unit.get_meta("medical_sequence")
				print("SECOND_RESCUE ",rescue.phase," cot=",rescue.stretcher.global_position if is_instance_valid(rescue.stretcher) else Vector2.INF," crew=",rescue.crew.map(func(m): return m.global_position)," no_progress=",rescue._no_progress," goal=",rescue._service_index," route_index=",rescue._parking_route_index," route=",rescue._parking_route," goals=",rescue._service_goals)
			var approach = second_unit.get("_ambulance_approach")
			if approach: print("SECOND_PARKING rejected=",approach.rejections," detail=",approach.last_rejection_detail," pending=",approach._walk_pending," candidates=",approach.candidates.size()," recoveries=",approach.recovery_attempts," trajectory=",approach.trajectory.size())
		var second_done: bool = is_instance_valid(second_unit) and second_incident.get("phase", "") == "transport" and second_unit.returned_paramedics == 2
		second_done = second_done or care.records().get(second_key,{}).get("phase", "") == "hospital"
		var first_done: bool = phases.has("transport") and (phase == "transport" or care.records().get(key,{}).get("phase", "") == "hospital")
		if Time.get_ticks_msec() - start >= 35000 and first_done and second_done: break
	sampling = false
	var file := FileAccess.open("D:/geteco/artifacts/rescue-0913/"+label+"-frames.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"samples":samples,"phases":phases,"gpu":RenderingServer.get_video_adapter_name(),"movie_times":movie_times}))
	print("JUNCTION RESULT ",phases," abort=",unit.get_meta("medical_abort_reason", ""))
	print("JUNCTION SOLIDS ",solid_errors)
	if not solid_errors.is_empty(): failures.append("Rescue body overlaps a live solid")
	for actor in patients:
		var incident: Dictionary = care.incidents.get(actor.get_meta("medical_identity"),{})
		print("JUNCTION VICTIM ",actor.global_position," phase=",incident.get("phase","finished")," failure=",actor.get_meta("medical_access_failure",""))
		if incident.get("phase", "") != "transport" and care.records().get(actor.get_meta("medical_identity"),{}).get("phase", "") != "hospital": failures.append("Casualty not transported")
	quit(0 if phases.has("transport") and failures.is_empty() else 1)

func measure() -> void:
	var tick := Time.get_ticks_usec()
	if sampling and last_tick > 0: samples.append((tick-last_tick)/1000.0)
	last_tick = tick

func observe_solids(sequence: Node) -> void:
	for actor in sequence.crew + [sequence.stretcher]:
		if not is_instance_valid(actor) or not actor.visible or actor.collision_mask == 0: continue
		var excluded: Array[RID] = [actor.get_rid()]
		for exception in actor.get_collision_exceptions():
			if is_instance_valid(exception): excluded.append(exception.get_rid())
		for child in actor.get_children():
			if not child is CollisionShape2D or child.disabled or child.shape == null: continue
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = child.shape
			query.transform = child.global_transform
			query.collision_mask = actor.collision_mask & 3
			query.exclude = excluded
			query.margin = 0
			for hit in actor.get_world_2d().direct_space_state.intersect_shape(query,4):
				var issue := "%s: %s intersects %s"%[sequence.phase,actor.get_script().resource_path,hit.collider.get_path()]
				if not solid_errors.has(issue): print("SOLID_FAILURE ",issue)
				solid_errors[issue] = true
