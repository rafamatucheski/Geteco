extends SceneTree
## Real paused session; isolated save, screenshots and finite frame samples.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var folder := ""
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(180).timeout.connect(func(): quit(3))
	folder = FIXTURE.output_dir("collections")
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	var data = FIXTURE.full_snapshot(Vector3(132,.15,72), false)
	var path = FIXTURE.write_fixture(folder,"save.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	await create_timer(3).timeout
	var menu = world.find_child("PauseMenu",true,false)
	assert(menu != null)
	menu.pause_game()
	var results := {"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"fps_cap":Engine.max_fps,"samples":{}}
	var scenarios := [true] if "--achievements-only" in OS.get_cmdline_user_args() else [true,false]
	for achievements in scenarios:
		menu._close_collection()
		menu._show_collection(achievements)
		await create_timer(2).timeout
		var name := "achievements" if achievements else "collectibles"
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(name+".png"))
		var frames: Array[float] = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now-previous)/1000.0)
			previous = now
		results.samples[name] = frames
		assert(paused and menu.visible)
	menu.toggle()
	assert(not menu.get_node("%AchievementsModal").visible and not menu.get_node("%CollectiblesModal").visible)
	menu.toggle()
	assert(not paused)
	FileAccess.open(folder.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(results))
	print("COLLECTION_CAPTURE ",folder)
	quit()
