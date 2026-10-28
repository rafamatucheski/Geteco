extends SceneTree
## Integrated rendered comparison; isolated save, finite 30s samples per cabinet.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACE = preload("res://world/places/arcade/ArcadePlace.gd")
var world

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(300).timeout.connect(func(): quit(3))
	var tag := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	var folder := "res://artifacts/arcade-upgrade-20261027/"+tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var save_folder := FIXTURE.output_dir("arcade-upgrade")
	var snapshot := FIXTURE.full_snapshot(PLACE.EXTERIOR+Vector3(0,.1,6.3),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(save_folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if not await world.session.enter_place(PLACE.ID,false): quit(4); return
	while world.session.is_transition_blocked(): await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .92
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var results := {}
	for id in ["pinball","blocks","racer","fighter"]:
		world.player.teleport(world.session.room.interaction_points["arcade_"+id]+Vector3.UP*.04)
		await physics_frame
		await physics_frame
		if not world.session.arcade.perform(id): quit(5); return
		var ui = world.session.arcade.ui
		await create_timer(.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(id+"-ready.png"))
		ui.start_game()
		ui.game.reset(827)
		await create_timer(2).timeout
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start < 30000000:
			# Exercise real screen polling; repeatable finite input without score injection.
			var seconds := float(Time.get_ticks_usec()-start)/1000000.0
			ui.touch = {"up":id == "racer", "right":sin(seconds*1.5)>0, "left":sin(seconds*1.5)<0, "action":fmod(seconds,1.0)<.15, "action_alt":fmod(seconds,1.7)<.12}
			if ui.game.finished:
				ui.start_game()
				ui.game.reset(827)
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			previous = now
		var total := float(Time.get_ticks_usec()-start)/1000.0
		var raw := samples.duplicate()
		samples.sort()
		var over33 := 0
		var over66 := 0
		for ms in samples:
			if ms > 33.3: over33 += 1
			if ms > 66.7: over66 += 1
		results[id] = {"frames":samples.size(),"duration_ms":total,"fps":samples.size()*1000.0/total,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples.back(),"over33":over33,"over66":over66,"samples_ms":raw}
		root.get_texture().get_image().save_png(folder.path_join(id+"-playing.png"))
		ui.toggle_pause()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(id+"-pause.png"))
		world.session.arcade.close()
		await process_frame
		print("ARCADE_UPGRADE_SAMPLE ",tag," ",id," fps=",results[id].fps," p95=",results[id].p95)
	results.environment = {"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"adapter":RenderingServer.get_video_adapter_name(),"scene":"Main.tscn / harbor_arcade", "night":true,"target_ms":16.67,"regression_signal_percent":5}
	FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	quit()
