extends "res://tests/measure/measure_desert.gd"
## Mesma cava real, câmera de direção comum e população viva antes/depois.
var machine: CharacterBody3D
var hydraulics: Node
var cycle := false
var cycle_time := 0.0
var moving_frames := 0

func _physics_process(delta: float) -> bool:
	if cycle and is_instance_valid(hydraulics) and hydraulics.has_method("operate_rear"):
		cycle_time += delta
		var phase := fmod(cycle_time, 8.0)
		var direction := 1.0 if phase < 4.0 else -1.0
		if hydraulics.operate_rear(Vector4(direction*.3, direction*.25, -direction*.3, direction*.25), delta): moving_frames += 1
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		quit(2); return
	seed(7102026)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("backhoe-baseline" if "--baseline" in OS.get_cmdline_user_args() else "backhoe-after")
	fingerprint = source_fingerprint()
	for source in ["res://gameplay/mining/MiningMachine.gd", "res://world/mining/operation/MiningMachineModel.gd", "res://gameplay/mining/BackhoeHydraulics.gd", "res://world/mining/operation/BackhoeModel.gd"]:
		fingerprint[source] = FileAccess.get_sha256(source) if FileAccess.file_exists(source) else "MISSING"
	var point: Vector3 = preload("res://world/mining/MiningLayout.gd").machine_spawns()[0].point + Vector3(5,.1,0)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[point.x,point.y,point.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or world.production.save_invalid or world.production.store.path != path:
		push_error("BACKHOE Main/save startup failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("BACKHOE native route missing"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	for frame in 600:
		for car in world.production.vehicles:
			if is_instance_valid(car) and car.archetype == "mining_backhoe": machine = car; break
		if machine != null: break
		await physics_frame
	if machine == null: push_error("BACKHOE machine not resident"); quit(1); return
	world.player.teleport(machine.driver_door_anchor(1)+Vector3(.4,.05,0))
	if not world.driving.interact(): push_error("BACKHOE boarding rejected"); quit(1); return
	for frame in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active(): break
	if not world.driving.occupied or world.driving.car != machine:
		push_error("BACKHOE boarding incomplete"); quit(1); return
	hydraulics = machine.get_node("MiningMachine")
	if not hydraulics.active(): push_error("BACKHOE real driver input unavailable"); quit(1); return
	if "--capture-only" in OS.get_cmdline_user_args():
		await capture_motion()
		print("BACKHOE_CAPTURE ",output," moving_frames=",moving_frames)
		quit(0 if moving_frames > 30 else 1); return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(10).timeout
	await measure("backhoe-occupied-idle")
	cycle = true
	await create_timer(10).timeout
	await measure("backhoe-hydraulics-cycle")
	cycle = false
	if "--baseline" not in OS.get_cmdline_user_args():
		if moving_frames < 30: push_error("BACKHOE joints did not move in real Main"); quit(1); return
		await capture_motion()
	var stable := fingerprint == source_fingerprint(fingerprint)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"source_stable":stable,"source_sha256_start":fingerprint,"source_sha256_end":source_fingerprint(fingerprint),"scenarios":reports,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"benchmark_vsync":0,"benchmark_max_fps":0,"post_measure_vsync":DisplayServer.window_get_vsync_mode(),"post_measure_max_fps":Engine.max_fps,"moving_physics_frames":moving_frames,"save":path,"note":"Real Main .NET, occupied backhoe in pit, 10s warmup + 30s each. Baseline has no rear hydraulics. Six motion captures after sampling at normal60FPS settings. Provisional target 60FPS; >5% p95/p99 rise requests confirmation."},"\t"))
	print("BACKHOE_MEASURE ",output," stable=",stable)
	quit(0 if stable else 1)

func capture_motion() -> void:
	# Normal settings after sampling: image readbacks never contaminate timing.
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	cycle = true
	for frame in 6:
		await create_timer(.65).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("rear-motion-%02d.png" % frame))
	cycle = false
