extends "res://tests/measure/measure_sport_coupe_redesign.gd"
## Fixed finite integration benchmark, before/after in the actual Main city.
const FLEET_REFRESH := preload("res://runtime/FleetCatalog.gd")
const BASE_IDS := ["sedan_classic","union_sedan","aurora_executive","metro_hatch","desert_faisca","ranch_pickup","station_wagon","orbita_micro","courier_van","ranch_single"]
const NEW_IDS := ["besouro_1300","mare_microvan","toco_minitruck"]
var targets: Array = []
var use_new := false
var refresh_pairs: Array = []

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args:
		push_error("Rendered .NET and --no-save required"); quit(2); return
	label="before"
	for arg in args:
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=").validate_filename()
	use_new="--new-models" in args
	folder="res://artifacts/car-fleet-implementation-20261019/performance/"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	background_run=true
	apply_background_policy()
	seed(19102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	var boot_start := Time.get_ticks_msec()
	root.add_child(world)
	current_scene=world
	# Initial concurrent cold startup advanced through 64 s + 34 s stages,
	# then exhausted the original 120 s readiness window. Preserve the failure;
	# use one finite 300 s diagnostic startup, logging actual stage progress.
	var deadline := Time.get_ticks_msec()+300000
	var last_stage := ""
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var curtain: Node = world.get_node_or_null("LoadingCurtain")
		if curtain!=null:
			var stage_name := str(curtain.get("stage_message"))
			if stage_name!=last_stage:
				last_stage=stage_name
				print("FLEET_REFRESH_BOOT ",Time.get_ticks_msec()-boot_start," ",last_stage)
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play or not world.production.no_save:
		push_error("Main isolated session not ready"); quit(3); return
	var normal_cap := Engine.max_fps
	var normal_vsync := DisplayServer.window_get_vsync_mode()
	uncapped=true
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	apply_background_policy()
	world.production.set_population(24)
	world.gameplay.health=1000000
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.set_process(false)
	world.player.teleport(Vector3(150,.05,107.8))
	world.production.region.set_focus(world.player.global_position)
	var anchor := Node3D.new()
	anchor.position=Vector3(150,.7,107.8)
	world.add_child(anchor)
	world.camera.target=anchor
	world.camera.locked=true
	world.camera.heading=0.0
	world.camera.offset=Vector3(0,40,40)
	world.camera.target_size=48.0
	world.camera.size=48.0
	world.camera.global_position=Vector3(150,40,147.8)
	world.camera.look_at(anchor.global_position)
	var warm_until := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<warm_until: await process_frame
	if not await place_refresh_targets():
		push_error("Could not admit ten cars on ground in real city"); quit(4); return
	car=targets[0]
	car_origin=car.global_position
	active_model=car.visual
	active_model_source=FLEET_REFRESH.spec(car.archetype).get("scene","")
	var aggregate := {"meshes":0,"surfaces":0,"triangles":0}
	var ids := []
	for body in targets:
		ids.append(body.archetype)
		var counts := mesh_metrics(body.visual)
		for key in aggregate: aggregate[key]+=counts[key]
	fixture={"scenario":"ten parked production vehicles in live Main near Maciota; before/after fleet integration, same seed/camera/population/candidate positions",
		"model":aggregate,"ids":ids,"seed":19102026,"requested_population":24,"new_models":use_new,
		"camera_position":str(world.camera.global_position),"camera_rotation":str(world.camera.global_rotation),"camera_size":world.camera.size,
		"normal_cap":normal_cap,"normal_vsync":normal_vsync,"provisional_budget_ms":16.67,"regression_confirmation_threshold_percent":5,
		"limits":"New models replace three donor slots when enabled. Traffic remains live and selection changes as part of the product; load/focus recorded, not a controlled model-only experiment."}
	warm_until=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<warm_until: await process_frame
	car_origin=car.global_position
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	render_timing_enabled=true
	var reports := []
	if "--paired-targets" in args:
		paired=true
		world.player.teleport(Vector3(147,.05,111.3))
		if not prepare_refresh_pair():
			push_error("Missing immutable pre-change presentation"); world.free(); quit(5); return
		expected_focus_mode="focused" if DisplayServer.window_is_focused() else "unfocused"
		allow_initial_focus_reselection=true
		for night in [false,true]:
			for index in range(4):
				var variant: String=["baseline","final","final","baseline"][index]
				select_paired_model(variant)
				var case_name := ("night" if night else "day")+"-%02d-"%(index+1)+variant
				var report: Dictionary=await scenario(night,case_name)
				paired_reports.append(report)
				var focus_ok: bool=report.focused_frames==report.summary.frames if expected_focus_mode=="focused" else report.focused_frames==0
				paired_valid=paired_valid and report.sample_complete and report.paired_invariants.valid and focus_ok and report.minimized_frames==0
				paired_focus_condition=expected_focus_mode
				write_paired_summary()
				if not paired_valid: break
			if not paired_valid: break
		select_paired_model("final")
		for report in paired_reports:
			reports.append({"scenario":report.scenario,"summary":report.summary,"invariants":report.paired_invariants,"focused_frames":report.focused_frames,"minimized_frames":report.minimized_frames})
	else:
		for night in [false,true]:
			var report: Dictionary=await scenario(night)
			report["load_after"]=load_snapshot()
			reports.append({"scenario":report.scenario,"summary":report.summary,"focused_frames":report.focused_frames,"minimized_frames":report.minimized_frames,"load":report.load_after})
	Engine.max_fps=normal_cap
	DisplayServer.window_set_vsync_mode(normal_vsync)
	uncapped=false
	await scenario(false,"normal-day")
	FileAccess.open(folder+"/completion.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":fixture,"reports":reports,"complete":true},"\t"))
	world.free()
	await process_frame
	quit(0 if paired_valid else 5)

func prepare_refresh_pair() -> bool:
	for index in targets.size():
		var body: CharacterBody3D=targets[index]
		var path := "res://artifacts/car-fleet-implementation-20261019/baseline/assets/"+str(BASE_IDS[index])+".scn"
		if not ResourceLoader.exists(path): return false
		var old: Node3D=(load(path) as PackedScene).instantiate()
		old.name="ImmutableBeforePresentation"
		old.scale=body.visual.scale
		old.visible=false
		body.add_child(old)
		var paint := preload("res://runtime/VehiclePaint.gd").new()
		paint.bind(old,BASE_IDS[index])
		paint.apply(body.paint_color)
		preload("res://runtime/VehicleUsage.gd").apply(old,BASE_IDS[index],body.vehicle_id,paint.materials)
		var materials := {}
		var mounts: Array[Vector3]=[]
		var bars: Array[Vector3]=[]
		for part: MeshInstance3D in old.find_children("*","MeshInstance3D",true,false):
			if part.mesh==null or part.has_meta("wheel_center"): continue
			for surface in (1 if part.material_override!=null else part.mesh.get_surface_count()): body.equipment._bind_lens(part,surface,materials,mounts,bars)
		body.equipment._lens_state=-1
		body.equipment._tail_state=-1
		body.equipment._refresh()
		refresh_pairs.append({"body":body,"before":old,"after":body.visual,"before_path":path,"origin":body.global_position,"health":body.health})
	paired_contract={"camera":str(world.camera.global_transform),"camera_size":world.camera.size,"targets":targets.size(),"player":str(world.player.global_position)}
	return refresh_pairs.size()==10

func select_paired_model(variant: String) -> void:
	active_variant=variant
	var aggregate := {"meshes":0,"surfaces":0,"triangles":0}
	for item in refresh_pairs:
		item.before.visible=variant=="baseline"
		item.after.visible=variant=="final"
		var counts := mesh_metrics(item.before if variant=="baseline" else item.after)
		for key in aggregate: aggregate[key]+=counts[key]
	active_model=refresh_pairs[0].before if variant=="baseline" else refresh_pairs[0].after
	active_model_source=refresh_pairs[0].before_path if variant=="baseline" else FLEET_REFRESH.spec(targets[0].archetype).scene
	fixture=fixture.duplicate(true)
	fixture.model=aggregate
	fixture.paired_variant=variant
	fixture.limits="Ten fixed physical bodies and the current city, only target presentation switches. Three old donor visuals compare with the new silhouettes; parked, not a handling comparison. External processes remain uncontrolled."

func check_paired_contract() -> Dictionary:
	var valid: bool=refresh_pairs.size()==10 and str(world.camera.global_transform)==paired_contract.camera and world.camera.size==paired_contract.camera_size
	var states := []
	for item in refresh_pairs:
		var body: CharacterBody3D=item.body
		var delta: float=body.global_position.distance_to(item.origin)
		var visible_count := int(item.before.visible)+int(item.after.visible)
		valid=valid and delta<.05 and body.health==item.health and visible_count==1 and not body.controlled and not body.traffic
		states.append({"id":body.archetype,"body_id":body.get_instance_id(),"displacement_m":delta,"health":body.health,"visible_presentations":visible_count})
	return {"valid":valid,"states":states}

func write_paired_summary() -> void:
	super.write_paired_summary()
	var path := folder+"/paired-summary.json"
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	data.notes="Finite ABBA day/night, ten production bodies parked in real Main. Immutable pre-change presentation snapshots versus installed visuals, same current shadows, physics, camera, lights, city and traffic selection. Three slots replace donors with new models. Both visual sets resident; one visible per slot. This diagnoses presentation cost, not a whole-roster simulation comparison. External concurrent processes were allowed by the user and prevent clean causal FPS certification. Every sample includes10s warmup and>=30s real frame intervals; focus and body invariants recorded."
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))

func place_refresh_targets() -> bool:
	var candidates: Array[Vector3]=[]
	for z in [-14.0,-7.0,0.0,7.0,14.0]:
		for x in [-20.0,-16.0,-12.0,-8.0,-4.0,0.0,4.0,8.0,12.0,16.0,20.0]: candidates.append(Vector3(150+x,.3,107.8+z))
	candidates.sort_custom(func(a: Vector3,b: Vector3): return a.distance_squared_to(Vector3(150,0,107.8))<b.distance_squared_to(Vector3(150,0,107.8)))
	for candidate in candidates:
		if targets.size()==BASE_IDS.size(): break
		var close := false
		for target in targets:
			var difference: Vector3=target.global_position-candidate
			if absf(difference.x)<3.1 and absf(difference.z)<6.9: close=true; break
		if close: continue
		world.production.region.prepare_collision_at(candidate)
		await physics_frame
		var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP,candidate-Vector3.UP*2,1))
		if ground.is_empty() or ground.normal.y<.98 or absf(ground.position.y)>.4: continue
		candidate=ground.position+Vector3.UP*.035
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(world.camera.global_position,candidate+Vector3.UP*.85,1)).is_empty(): continue
		var index := targets.size()
		var id: String=NEW_IDS[index-7] if use_new and index>=7 else BASE_IDS[index]
		var body: CharacterBody3D=world.production.spawn_vehicle(id,candidate,0.0)
		if body==null: continue
		body.vehicle_id="fleet_refresh_benchmark_"+str(index)
		body.external_input=true
		body.throttle_input=0.0
		body.brake_input=true
		body.ensure_equipment(world)
		targets.append(body)
		await physics_frame
	return targets.size()==BASE_IDS.size()
