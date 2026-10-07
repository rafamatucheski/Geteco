extends "res://tests/measure/measure_desert.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with --benchmark --no-save required")
		quit(2)
		return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-reentry-measure")
	var snapshot:=FIXTURE.full_snapshot(Vector3(342.5,.08,-1100),true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[342.5,.08,-1100]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint=source_fingerprint()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid:
		push_error("Main native startup/isolation failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("Compiled route backend unavailable"); quit(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	await create_timer(10).timeout
	await measure("road-edge")
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"scenarios":reports,"engine":Engine.get_version_info().string,"source_start":fingerprint,"source_end":source_fingerprint(fingerprint)},"\t"))
	print("REENTRY_MEASURE ",output)
	quit()
