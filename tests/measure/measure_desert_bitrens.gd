extends "res://tests/measure/measure_desert.gd"
## Revisão focada de arte/desempenho usando o Main, a câmera comum e um save isolado.
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		quit(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	var label := "review"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
	output=FIXTURE.output_dir("bitrens-"+label)
	var point := Vector3(250,.08,-744)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath={"call_complete":true}
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[point.x,point.y,point.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint=source_fingerprint()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.dispatch.router.nearest_edge(point)
	if world.dispatch.router._native==null or world.production.store.path!=path: quit(1); return
	world.gameplay.god_mode=true
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	for hour in [.43,.9]:
		world.session.weather.time_of_day=hour
		world.session.weather._update()
		await create_timer(10).timeout
		await measure("day" if hour<.5 else "night")
	var valid := fingerprint==source_fingerprint(fingerprint)
	var result := {"valid":valid,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"scenarios":reports,"source_sha256":fingerprint}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	# Câmera de inspeção só DEPOIS das medições com a câmera de jogo comum.
	world.session.weather.time_of_day=.43
	world.session.weather._update()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	for shot in [
		{"id":"front","at":Vector3(259,2,-757),"offset":Vector3(9,5,-12),"size":9.0},
		{"id":"profile","at":Vector3(259,1.8,-746),"offset":Vector3(30,10,-8),"size":30.0},
		{"id":"fleet","at":Vector3(249,1.5,-747),"offset":Vector3(25,28,-34),"size":40.0},
		{"id":"rear","at":Vector3(259,1.7,-736),"offset":Vector3(9,5,12),"size":9.0}]:
		camera.size=shot.size
		camera.position=shot.at+shot.offset
		camera.look_at(shot.at)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(shot.id+".png"))
	print("BITRENS_REVIEW ",output," valid=",valid)
	quit(0 if valid else 1)
