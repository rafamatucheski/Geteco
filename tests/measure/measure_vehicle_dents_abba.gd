extends "res://tests/measure/measure_desert.gd"
## ABBA within one live city avoids different population/startup states between
## separate processes. All directors remain active. Each event includes repair
## then a fresh real receive_impact: geometry rebuilds never saturate the sample.
class ToggleDents extends "res://gameplay/vehicle_effects/VehicleBodyDents.gd":
	var enabled := false
	func impact(amount: float, point: Vector3, contact_inward := Vector3.ZERO) -> void:
		if enabled: super.impact(amount,point,contact_inward)
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(12102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("vehicle-dents-abba")
	var path:=FIXTURE.write_fixture(output,"initial.json",FIXTURE.full_snapshot(Vector3(37.625,.12,18.875),true))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 7000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path: quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	var car: CharacterBody3D=world.driving.car
	car.set_physics_process(false)
	car.controlled=true
	car.body_dents.free()
	var dents:=ToggleDents.new()
	dents.name="BodyDents"
	dents.configure(car)
	car.body_dents=dents
	car.add_child(dents)
	world.camera.set_process(false)
	world.camera.size=9
	world.camera.global_position=car.global_position+Vector3(6,7,-8)
	world.camera.look_at(car.global_position+Vector3.UP*.7)
	world.camera.current=true
	if "--normal-limit" not in OS.get_cmdline_user_args():
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# Let live population settle, and prime wear/material/mesh pipelines outside
	# measured windows. Source fingerprints prove no edits during the run.
	dents.enabled=true
	car.receive_impact(18,Vector3(.6,.6,-car.half_length))
	await create_timer(20).timeout
	car.repair()
	fingerprint=source_fingerprint()
	fingerprint["res://gameplay/vehicle_effects/VehicleBodyDents.gd"]=FileAccess.get_sha256("res://gameplay/vehicle_effects/VehicleBodyDents.gd")
	var timeline: Array=[]
	var event_times: Array=[]
	for phase in [false,true,true,false]:
		dents.enabled=phase
		car.repair()
		await create_timer(1).timeout
		samples.clear(); cpu.clear(); physics.clear()
		previous=Time.get_ticks_usec(); sampling=true
		var start:=Time.get_ticks_msec()
		var next:=start+1000
		var event_count:=0
		while Time.get_ticks_msec()-start<30000:
			await process_frame
			if Time.get_ticks_msec()<next: continue
			next+=1000
			timeline.append({"phase":phase,"vehicles":world.production.vehicles.size(),"focused":DisplayServer.window_is_focused(),"seconds":(Time.get_ticks_msec()-start)/1000.0})
			car.repair()
			var began:=Time.get_ticks_usec()
			car.receive_impact(18,Vector3((.6 if event_count%2==0 else -.6),.6,-car.half_length))
			event_times.append({"phase":phase,"usec":Time.get_ticks_usec()-began,"mesh_usec":dents.rebuild_usec if phase else 0})
			car.effects.impact_effects.present_impact(car.to_global(Vector3(0,.6,-car.half_length)),car.global_basis.z,12,12345)
			event_count+=1
		sampling=false
		reports.append({"enabled":phase,"summary":stats(samples),"intervals_ms":samples.duplicate(),"events":event_count})
	var report:={"reports":reports,"timeline":timeline,"event_times":event_times,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"scope":"One rendered Main, live city, fixed observer. ABBA toggles only observer dent/recoil. Fresh impact each second, repair between hits is controlled stress, not player timing."}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("DENTS_ABBA ",output," ",JSON.stringify(reports.map(func(row): return row.summary)))
	quit(0)
