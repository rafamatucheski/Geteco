extends "res://tests/measure.gd"
## Rendered Main. PNG readbacks occur outside frame-time sampling.
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=").validate_filename()
	var folder := "res://evidence/sidewalk-glitches/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(22092026)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	for i in 1800:
		await process_frame
		if world.session!=null and world.session.weather!=null: break
	if world.session==null or world.session.weather==null:
		push_error("Sidewalk startup incomplete: paused=%s production_ready=%s session=%s"%[paused,world.production.ready_for_play,world.session])
		quit(1)
		return
	world.player.controlled_automatically=true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	# Diagnostic A/B only: reconstruct the former coplanar draw list without
	# reverting shared production files. Cold startup is not a before/after claim.
	if "--legacy-surfaces" in OS.get_cmdline_user_args():
		var region = world.production.region
		region.harbor_urban_surface._visible_surfaces.assign(region.harbor_urban_surface._surfaces)
		for key in region.chunks:
			var chunk = region.chunks[key]
			for child in chunk.get_children():
				if str(child.name).begins_with("HarborSurface_"):
					chunk.remove_child(child)
					child.queue_free()
			region.harbor_urban_surface.build_chunk(chunk,Rect2(Vector2(key)*region.CELL,Vector2.ONE*region.CELL))
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"cases":[]}
	for entry in [["day",.55,3],["sunset",.75,0],["night",.84,0],["rain",.55,1]]:
		world.player.teleport(Vector3(137.5,.08,105))
		world.production._update_physical_residency(world.player.position)
		world.production._update_logical_region(world.player.position)
		world.camera.heading=0
		world.camera.target_size=26
		world.camera.initialized=false
		world.session.weather.time_of_day=entry[1]
		world.session.weather.weather_state=entry[2]
		world.session.weather.weather_timer=10000
		world.session.weather._update()
		world.session.weather.set_process(false)
		var warm: Array[float]=[]
		var frames: Array[float]=[]
		var last := Time.get_ticks_usec()
		var begin := last
		while Time.get_ticks_usec()-begin<8000000:
			await process_frame
			var now := Time.get_ticks_usec()
			warm.append((now-last)/1000.0)
			last=now
		begin=last
		while Time.get_ticks_usec()-begin<30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now-last)/1000.0)
			last=now
			var t := (now-begin)/1000000.0
			world.player.automatic_direction=Vector3(0,0,sin(t*.6))
			world.camera.heading=sin(t*.2)*.25
			world.camera.target_size=26+sin(t*.3)*4
		world.player.automatic_direction=Vector3.ZERO
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+entry[0]+".png")
		var result := {"id":entry[0],"population":world.people.size(),"traffic":world.traffic.cars.size(),"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm}
		report.cases.append(result)
		var file := FileAccess.open(folder+"/report.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
		print("SIDEWALK_BENCHMARK ",entry[0]," ",JSON.stringify(result.summary))
	world.queue_free()
	await process_frame
	quit()
