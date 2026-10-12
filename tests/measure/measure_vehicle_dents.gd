extends "res://tests/measure/measure_desert.gd"
## Identical real Main scene before/after, 30 s idle + 30 s repeated impacts.
var baseline := false
var car: CharacterBody3D
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args: quit(2); return
	baseline = "--baseline" in args
	fingerprint=source_fingerprint()
	fingerprint["res://gameplay/vehicle_effects/VehicleBodyDents.gd"]=FileAccess.get_sha256("res://gameplay/vehicle_effects/VehicleBodyDents.gd")
	seed(12102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("vehicle-dents-"+("before" if baseline else "after"))
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",FIXTURE.full_snapshot(Vector3(37.625,.12,18.875),true))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 7000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path: quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	car=world.driving.car
	car.place(world.production.nearest_road(world.player.position)+Vector3.UP*.12,0)
	car.set_physics_process(false)
	world.camera.set_process(false)
	world.camera.size=9
	world.camera.global_position=car.global_position+Vector3(6,7,-8)
	world.camera.look_at(car.global_position+Vector3.UP*.7)
	world.camera.current=true
	if "--normal-limit" not in args:
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	samples.clear(); previous=Time.get_ticks_usec(); sampling=true
	await create_timer(10).timeout
	sampling=false
	var warmup:={"summary":stats(samples),"intervals_ms":samples.duplicate()}
	await shot("intact")
	for scenario in ["idle","impacts"]:
		samples.clear(); cpu.clear(); physics.clear()
		previous=Time.get_ticks_usec()
		sampling=true
		var started:=Time.get_ticks_msec()
		var next:=started+1000
		while Time.get_ticks_msec()-started<30000:
			await process_frame
			if scenario=="impacts" and Time.get_ticks_msec()>=next:
				next+=1000
				car.health=car.max_health
				car.receive_impact(18,Vector3(car.half_width*.65,.65,-car.half_length))
				if car.effects!=null: car.effects.impact_effects.present_impact(car.to_global(Vector3(0,.65,-car.half_length)),car.global_basis.z,12,12345)
		sampling=false
		reports.append({"scenario":scenario,"summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_ms":cpu.duplicate(),"physics_ms":physics.duplicate()})
		await shot(scenario)
	if not baseline:
		var record:=preload("res://runtime/FleetState.gd").capture(car,"harbor")
		var file:=FileAccess.open(output.path_join("fleet.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(record)); file.close()
		car.repair()
		await shot("repaired")
		var loaded: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("fleet.json")))
		car.restore_body_dents(loaded.get("body_dents",[]))
		await shot("restored")
	var report:={"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"archetype":car.archetype,"traffic":world.production.vehicles.size(),"reports":reports,"warmup":warmup,"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"scope":"Real Main with live population; fixed camera, direct impacts are diagnostic, not a driven route."}
	var report_file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report,"\t")); report_file.close()
	print("DENTS_REPORT ",output," ",JSON.stringify(reports.map(func(row): return row.summary)))
	quit(0)
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
