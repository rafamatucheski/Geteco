extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	var graph = world.production.traffic_routes
	var data := {"vertices":[],"roads":[],"routes":[]}
	for point in graph.vertices: data.vertices.append([point.x,point.y,point.z])
	for segment in graph.segments:
		data.roads.append({"id":segment.id,"a":[segment.a.x,segment.a.y,segment.a.z],"b":[segment.b.x,segment.b.y,segment.b.z],"width":segment.width})
	for goal in [Vector3(190,0,137),Vector3(300,0,140),Vector3(375,0,80)]:
		var result: Dictionary = world.dispatch.router.plan(Vector3(460,0,106),goal,Vector3.FORWARD)
		var route := {"goal":str(goal),"ok":result.ok,"points":[]}
		if result.ok:
			var curve: Curve3D=result.curve
			route.length=curve.get_baked_length()
			for offset in range(0,ceili(curve.get_baked_length()),5):
				var point:=curve.sample_baked(offset)
				route.points.append([point.x,point.y,point.z])
		data.routes.append(route)
	var folder:="D:/geteco/artifacts/cobra-race-1002"
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder+"/roads.json",FileAccess.WRITE).store_string(JSON.stringify(data))
	print("COURSE ",data.routes.map(func(r): return {"goal":r.goal,"ok":r.ok,"length":r.get("length",0)}))
	if "--measure" in OS.get_cmdline_user_args():
		var label:="before"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--label="): label=argument.trim_prefix("--label=")
		root.size=Vector2i(1280,720)
		world.player.teleport(Vector3(449,.1,106))
		world.camera.target_size=30
		world.session.weather.time_of_day=.45
		world.session.weather.weather_state=0
		world.session.weather._update()
		await create_timer(6).timeout
		var samples: Array[float]=[]
		var begin:=Time.get_ticks_usec()
		var last:=begin
		while Time.get_ticks_usec()-begin<30000000:
			await process_frame
			var now:=Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last=now
		var sorted:=samples.duplicate()
		sorted.sort()
		var report:={"frames_ms":samples,"fps":samples.size()*1e6/(last-begin),"duration":(last-begin)/1e6,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":samples.filter(func(v):return v>33.3).size(),"over66":samples.filter(func(v):return v>66.7).size(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}
		FileAccess.open(folder+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		report.erase("frames_ms")
		print("RACE_BASELINE ",JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+label+".png")
	world.free()
	quit()
