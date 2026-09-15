extends SceneTree
## Isolate hospital arrival with two real transported patients in HarborGame.
var failures: Array[String] = []
var units: Array = []
var patients: Array = []
var phases := [[], []]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message); push_error(message)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var label := "baseline" if args.has("--baseline") else ("road-capture" if args.has("--road-arrival") else "after")
	var output := "D:/geteco/artifacts/ambulance-hospital-0914/"+label
	DirAccess.make_dir_recursive_absolute(output+"/saves")
	var save := root.get_node("SaveManager")
	save._save_dir = output+"/saves/"
	save._save_directory_ready = false
	save.clear_pending_save()
	seed(14092026)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]: campaign.set_campaign_flag(StringName(flag),true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .45
	world.weather.set_weather(0)
	world.get_node("Player").position = Vector2(1860,1750)
	world.get_node("PlayerCar").position = Vector2(700,425)
	var camera := Camera2D.new()
	camera.position = Vector2(1970,1570)
	camera.zoom = Vector2.ONE*1.7
	world.add_child(camera)
	camera.make_current()
	await root.get_node("EmergencyPool").prepare_presentations()
	await create_timer(10).timeout
	var director = get_first_node_in_group("emergency_depot_director")
	var care := root.get_node("NPCMedicalCare")
	for i in 2:
		var patient = load("res://AnimatedPedestrian3D.gd").new()
		patient.position = Vector2(1900,1800+i*50)
		world.add_child(patient)
		patient.is_gangster = false
		patient.set_physics_process(false)
		patient.get_run_over(Vector2(80,0))
		var unit = root.get_node("EmergencyPool").get_vehicle("ambulance")
		check(is_instance_valid(unit),"Available real ambulance")
		if not is_instance_valid(unit): quit(1); return
		unit.global_position = patient.global_position
		unit.target = patient
		unit.set_physics_process(false)
		unit.set_meta("harbor_director_id",director.get_instance_id())
		unit.home_depot_id = "harbor_clinic"
		unit.home_return_position = world.get_node("District/Clinic").get_ambulance_stop_position()
		unit._deploy_paramedics()
		var sequence: Node = unit.get_meta("medical_sequence")
		sequence.set_physics_process(false)
		check(care.begin_carry(patient,unit,sequence),"Patient enters real transport ownership")
		sequence.stretcher = load("res://world/shared/emergency/MedicalStretcher.gd").new()
		world.add_child(sequence.stretcher)
		sequence.stretcher.load_patient(patient)
		sequence.stretcher.hide()
		sequence.carrying = true
		sequence.delivered = true
		sequence._boarded = [true,true]
		care.board_patient(patient,unit)
		for medic in sequence.crew:
			medic.hide()
			medic.collision_layer = 0
			medic.collision_mask = 0
			unit.visual_3d.close_door(medic.crew_side)
		sequence._set_phase("transport")
		unit.global_position = unit.home_return_position+Vector2(55 if i==0 else 110,0 if i==0 else 86)
		unit.global_rotation = 0
		if i==1 and args.has("--road-arrival"):
			unit.global_position = Vector2(2230,1450)
			unit.global_rotation = PI*.5
		unit.is_acting = false
		unit.is_returning_to_base = true
		unit.remove_meta("depot_departure_pending")
		unit._lane_router.reset()
		director.get_medical_return_position(unit)
		units.append(unit)
		patients.append(patient)
	await physics_frame
	for unit in units:
		var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = hull.shape
		query.transform = hull.global_transform
		query.exclude = [unit.get_rid()]
		query.collision_mask = 3
		var hits: Array = unit.get_world_2d().direct_space_state.intersect_shape(query)
		print("HOSPITAL_INITIAL_HITS ",unit.position," ",hits.map(func(hit):return {"path":str(hit.collider.get_path()),"position":hit.collider.global_position}))
		# The entry aisle contains physical roadside furniture. Place the
		# transported fixture at the first clear pose, never inside a solid.
		if not hits.is_empty() and not args.has("--road-arrival"):
			for offset in [100.0,90.0,80.0]:
				unit.global_position.x = unit.home_return_position.x+offset
				query.transform = hull.global_transform
				hits = unit.get_world_2d().direct_space_state.intersect_shape(query)
				if hits.is_empty(): break
		check(hits.is_empty(),"Arrival fixture starts outside solids")
		unit.get_meta("medical_sequence").set_physics_process(true)
		unit.set_physics_process(true)
	var samples: Array[float] = []
	var last := Time.get_ticks_usec()
	var seconds := 0.0
	var capture_clock := 0.0
	var pictures := 0
	var completed_at := -1.0
	var debug_at := 0.0
	var motion := FileAccess.open(output+"/motion.csv",FileAccess.WRITE)
	motion.store_line("seconds,unit,x,y,angle,phase,siren")
	while seconds < (35.0 if args.has("--baseline") else 90.0):
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now-last)/1000.0
		last = now
		samples.append(ms)
		seconds += ms/1000
		if seconds>=debug_at:
			debug_at=seconds+5
			for item in units: _debug_dock(item)
		for i in units.size():
			var unit = units[i]
			var phase: String = unit.get_meta("medical_phase","")
			if not phases[i].has(phase): phases[i].append(phase); print("HOSPITAL_PHASE ",i," ",phase," ",unit.global_position)
			if phase == "access_blocked" and is_instance_valid(unit.get_meta("medical_sequence",null)):
				var sequence: Node = unit.get_meta("medical_sequence")
				print("BLOCKED_CREW ",sequence.crew.map(func(m):return m.global_position)," cot=",sequence.stretcher.global_position)
			motion.store_line("%f,%d,%f,%f,%f,%s,%s"%[seconds,i,unit.position.x,unit.position.y,unit.rotation,phase,unit.siren_audio.playing])
			if bool(unit.get_meta("hospital_unloading",false)) or bool(unit.get_meta("hospital_available",false)):
				check(not unit.siren_audio.playing,"Hospital arrival silences siren")
			check(not unit.has_meta("medical_abort_reason"),"No stalled medical sequence: "+str(unit.get_meta("medical_abort_reason","")))
		if args.has("--capture") and seconds>=capture_clock:
			capture_clock=seconds+.2
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/frame-%04d.png"%pictures)
			pictures+=1
		if phases[0].has("parked") and phases[1].has("parked"):
			if completed_at<0: completed_at=seconds
			if seconds>=35 and seconds-completed_at>=3: break
	for i in 2:
		check(phases[i].has("hospital_inside") and phases[i].has("parked"),"Patient %d admitted and arrival reaches terminal parked state"%i)
		check(not patients[i].visible,"Admitted patient absent from street")
		check(care.records().get(patients[i].get_meta("medical_identity"),{}).get("phase","")=="hospital","Patient %d registered inside hospital"%i)
	check(units[0].position.distance_to(units[1].position)>65,"Two ambulances occupy different bays")
	if failures.is_empty() and not args.has("--baseline"):
		# A separate empty return must finish too; this was excluded from the
		# old hospital branch and could steer forever around its own marker.
		var unit = units[0]
		unit.remove_meta("hospital_available")
		unit.remove_meta("hospital_arrived")
		unit._hospital_arrival.reset()
		unit.global_position = unit.home_return_position+Vector2(8,0)
		unit.global_rotation = 0
		unit.is_returning_to_base = true
		await create_timer(1).timeout
		check(bool(unit.get_meta("hospital_available",false)),"Empty return reaches parked state within one second")
		var parked: Vector2 = unit.global_position
		await create_timer(7).timeout
		check(unit.global_position.distance_to(parked)<.01 and not unit.siren_audio.playing,"Terminal parking stays still and silent beyond anti-stuck timer")
		# Both candidate bays physically occupied: an arrival must wait, not
		# reuse the second slot simply because the first one was taken.
		unit.set_physics_process(false)
		unit.remove_meta("hospital_arrived")
		director._medical_slots.erase(unit.get_instance_id())
		unit.global_position += Vector2(400,0)
		var obstruction := StaticBody2D.new()
		obstruction.collision_layer = 1
		var shape := CollisionShape2D.new()
		shape.shape = unit.get_node("CollisionShape2D").shape.duplicate()
		obstruction.add_child(shape)
		obstruction.position = unit.home_return_position
		world.add_child(obstruction)
		await physics_frame
		check(not director.get_medical_return_position(unit).is_finite(),"Full hospital never assigns two units to one bay")
		obstruction.queue_free()
		await physics_frame
		check(director.get_medical_return_position(unit).is_finite(),"Freed hospital bay becomes available again")
	motion.close()
	var sorted := samples.duplicate(); sorted.sort()
	var report := {"failures":failures,"phases":phases,"seconds":seconds,"pictures":pictures,"fps":samples.size()/seconds,"p50":sorted[int(sorted.size()*.50)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":samples.filter(func(v):return v>33.3).size(),"over66":samples.filter(func(v):return v>66.7).size(),"gpu":RenderingServer.get_video_adapter_name()}
	FileAccess.open(output+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HOSPITAL_COMPLETION ",JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _debug_dock(unit: CharacterBody2D) -> void:
	if unit.get_meta("medical_phase","")!="transport": return
	var dock: RefCounted = unit._hospital_arrival
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.transform = hull.global_transform
	query.exclude = [unit.get_rid()]
	query.collision_mask = 7
	query.margin = 3
	var hits := unit.get_world_2d().direct_space_state.intersect_shape(query)
	print("DOCK_DEBUG ",unit.position," goal=",dock.goal," angle=",unit.rotation," path=",dock.path.size()," cursor=",dock.cursor," blocked=",dock.blocked," search=",dock.search.expansions if dock.search else -1," overlaps=",hits.map(func(h):return {"path":str(h.collider.get_path()),"at":h.collider.global_position}))
