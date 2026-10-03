extends SceneTree
const CENTER := Vector3(716,0,-363)
var world
var label := "before"
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.production._update_physical_residency(CENTER)
	world.production._update_logical_region(CENTER)
	world.player.teleport(CENTER+Vector3(0,.08,12))
	world.player.controlled_automatically=true
	world.session.state.economy.grant_outfit("dante_ski")
	world.session.state.economy.equip_outfit("dante_ski")
	world.session.apply_outfit()
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.locked=true
	world.camera.size=55
	world.camera.position=CENTER+Vector3(12,44,34)
	world.camera.look_at(CENTER)
	var walking: bool="--walking" in OS.get_cmdline_user_args()
	if walking:
		world.camera.size=preload("res://scripts/CameraRig.gd").WALK_SIZE_CLOSE
		world.camera.position=world.player.global_position+preload("res://scripts/CameraRig.gd").EXTERIOR_OFFSET
		world.camera.look_at(world.player.global_position)
	world.camera.make_current()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	world.hud.hide()
	world.session.weather.time_of_day=.5
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	await create_timer(25).timeout
	if "--paired" in OS.get_cmdline_user_args():
		var zoo=world.production.region.find_child("MountainZoo",true,false)
		if zoo==null: push_error("Zoo missing for paired measurement"); quit(1); return
		var parent=zoo.get_parent()
		for pass_index in 2:
			parent.remove_child(zoo)
			await frames(300)
			label=("walking-without-%d" if walking else "batched-without-%d")%pass_index
			await sample()
			parent.add_child(zoo)
			await frames(600)
			label=("walking-with-%d" if walking else "batched-with-%d")%pass_index
			await sample()
	else: await sample()
	world.queue_free()
	for i in 4: await process_frame
	quit()
func sample() -> void:
	var values: Array[float]=[]
	var process_ms:=0.0
	var physics_ms:=0.0
	var gpu_ms:=0.0
	var render_cpu_ms:=0.0
	var began:=Time.get_ticks_usec()
	var previous:=began
	while Time.get_ticks_usec()-began<30000000:
		await process_frame
		if world.player.global_position.distance_to(CENTER+Vector3(0,.08,12))>3:
			push_error("Benchmark invalid: player left the measured mountain location")
			quit(1); return
		var now:=Time.get_ticks_usec()
		values.append(float(now-previous)/1000.0)
		process_ms+=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
		physics_ms+=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
		gpu_ms+=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		render_cpu_ms+=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		previous=now
	var sorted:=values.duplicate()
	sorted.sort()
	var total:=0.0
	var over33:=0
	var over66:=0
	for v in values:
		total+=v
		if v>33.3: over33+=1
		if v>66.7: over66+=1
	var report: Dictionary={"label":label,"frames":values.size(),"duration_ms":total,"fps":values.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over33":over33,"over66":over66,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.people.size()}
	print("ZOO_PERF ",JSON.stringify(report))
	report["mean_process_ms"]=process_ms/values.size()
	report["mean_physics_ms"]=physics_ms/values.size()
	report["mean_gpu_ms"]=gpu_ms/values.size()
	report["mean_render_cpu_ms"]=render_cpu_ms/values.size()
	report["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	report["primitives"]=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	report["position"]=str(world.player.global_position)
	report["outfit"]=world.session.state.economy.outfit
	report["samples_ms"]=values
	DirAccess.make_dir_recursive_absolute("res://artifacts/mountain-zoo")
	FileAccess.open("res://artifacts/mountain-zoo/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/mountain-zoo/"+label+".png")
