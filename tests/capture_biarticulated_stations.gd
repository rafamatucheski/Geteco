extends SceneTree
func model_stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames":values.size(),"seconds":total/1000,"fps":values.size()*1000/total,"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	var world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	var ops=world.production.urban_transit.urban_service
	for frame in 180:
		await physics_frame
		if ops.prepared: break
	if ops.stops.size()!=6: quit(3); return
	ops.set_physics_process(false)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.35
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var bus=ops.fleet[0]
	world.camera.target=bus; world.camera.heading=0; world.camera.target_size=38
	world.camera.set_process_unhandled_input(false)
	for index in ops.stops.size():
		if "--station=1" in OS.get_cmdline_user_args() and ops.stops[index].id!=1: continue
		for other in ops.fleet: other.set_active(false)
		bus.service_stop=index
		bus.route_distance=ops.stops[index].offset
		bus._apply_poses(ops.path_poses.at(bus.route_distance),false)
		world.player.teleport(ops.stops[index].inside+Vector3.UP*.04)
		world.production._update_physical_residency(world.player.position)
		world.camera.initialized=false
		ops.refresh_presence()
		bus.set_active(true); bus.set_doors(1); ops.gate(index,true)
		for frame in 90: await process_frame
		if "--measure-model" in OS.get_cmdline_user_args():
			var tag := "before"
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--variant="): tag = arg.trim_prefix("--variant=").validate_filename()
			var warm: Array[float] = []
			var frames: Array[float] = []
			var began := Time.get_ticks_usec()
			var last := began
			while Time.get_ticks_usec()-began < 38000000:
				await process_frame
				var now := Time.get_ticks_usec()
				if now-began < 8000000: warm.append((now-last)/1000.0)
				else: frames.append((now-last)/1000.0)
				last = now
			var folder := "res://evidence/biarticulated/wheels-ads-20261010/"+tag
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
			var report := {"summary":model_stats(frames),"warmup":model_stats(warm),"frames_ms":frames,"warmup_ms":warm,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"bus_active":bus.active,"station":ops.stops[index].id}
			FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/world.png")
			print("BUS_MODEL_PERF ",tag," ",report.summary)
		await RenderingServer.frame_post_draw
		var filename: String="res://evidence/biarticulated/station_%d.png" % ops.stops[index].id
		root.get_texture().get_image().save_png(filename)
		print("STATION_CAPTURE ",filename)
	quit()
