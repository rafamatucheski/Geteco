extends SceneTree
## Quadros nativos contínuos do Main, só para inspeção visual (não é benchmark).
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACE = preload("res://world/places/arcade/ArcadePlace.gd")
var world

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(180).timeout.connect(func(): quit(3))
	var folder := FIXTURE.output_dir("arcade-temporal")
	var snapshot := FIXTURE.full_snapshot(PLACE.EXTERIOR+Vector3(0,.1,6.3),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if not await world.session.enter_place(PLACE.ID,false): quit(4); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(world.session.room.to_global(Vector3(0,.04,1)))
	world.session.weather.time_of_day = .92
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	await create_timer(3).timeout
	var frames := []
	var started := Time.get_ticks_usec()
	var index := 0
	var waypoint := 0
	var route := [Vector3(-2.8,0,1),Vector3(-2.8,0,-1),Vector3(2.8,0,-1),Vector3(2.8,0,1),Vector3(0,0,1)]
	while Time.get_ticks_usec()-started < 31000000:
		await RenderingServer.frame_post_draw
		var elapsed := float(Time.get_ticks_usec()-started)/1000000.0
		if elapsed > 15:
			var target: Vector3 = world.session.room.to_global(route[waypoint])
			var offset: Vector3 = target-world.player.global_position
			offset.y = 0
			if offset.length() < .18: waypoint = (waypoint+1)%route.size()
			world.player.automatic_direction = offset.normalized()
		var frame := root.get_texture().get_image()
		frame.resize(960,540,Image.INTERPOLATE_BILINEAR)
		if frame.save_jpg(folder.path_join("frame-%06d.jpg"%index),.86) != OK: quit(5); return
		frames.append({"index":index,"seconds":elapsed,"drawn":Engine.get_frames_drawn(),"player":str(world.player.global_position)})
		index += 1
	world.player.automatic_direction = Vector3.ZERO
	FileAccess.open(folder.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":frames,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"native_resolution":str(root.size),"capture_resolution":"960x540","night":true,"note":"Readback/JPEG recording has overhead; not FPS evidence."},"\t"))
	print("ARCADE_TEMPORAL ",folder," frames=",index)
	var pinball_ok := await capture_pinball(folder)
	quit(0 if pinball_ok else 6)

func capture_pinball(folder: String) -> bool:
	world.player.teleport(world.session.room.interaction_points.arcade_pinball+Vector3.UP*.04)
	await physics_frame
	await physics_frame
	if not world.session.arcade.perform("pinball"): return false
	var ui = world.session.arcade.ui
	ui.start_game()
	await process_frame
	await process_frame
	Input.action_press("interact")
	await process_frame
	await process_frame
	Input.action_release("interact")
	var entered_field := false
	var minimum := Vector2(800,480)
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		minimum = minimum.min(ui.game.ball)
		if ui.game.ball.x < 520 and ui.game.ball.y < 270 and ui.game.lives == 3:
			if not entered_field:
				root.get_texture().get_image().save_png(folder.path_join("pinball-natural-launch.png"))
			entered_field = true
		if entered_field and ui.game.score > 0:
			root.get_texture().get_image().save_png(folder.path_join("pinball-first-points.png"))
			break
		if ui.game.lives < 3: break
	var result := {"entered_bumper_field":entered_field,"score":ui.game.score,"lives":ui.game.lives,"minimum":str(minimum),"scene":"Main.tscn","input":"interact through actual ArcadeScreen; no ball mutation"}
	FileAccess.open(folder.path_join("pinball-launch.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ARCADE_PINBALL_NATURAL ",JSON.stringify(result))
	world.session.arcade.close()
	return entered_field and result.score > 0
