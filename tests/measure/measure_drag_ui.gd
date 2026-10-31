extends SceneTree
## Benchmark renderizado no Main. A preparação usa um checkpoint isolado; as corridas usam física real.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT = preload("res://world/desert/DesertLayout.gd")
var world
var output := ""
var samples: Array[float] = []
var recording := false
var stamp := 0
var results := {}

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("DRAG_UI timeout"); quit(3))
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0: samples.append(float(now-stamp)/1000.0)
	stamp = now
	return false

func hold(seconds: float) -> void:
	await create_timer(seconds).timeout

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func begin_sample() -> void:
	samples.clear()
	stamp = Time.get_ticks_usec()
	recording = true

func end_sample(label: String) -> void:
	recording = false
	var sorted := samples.duplicate()
	sorted.sort()
	if sorted.is_empty(): return
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in samples:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	results[label] = {"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50":sorted[int(sorted.size()*.50)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":samples.duplicate()}
	print("DRAG_UI ",label," ",JSON.stringify({"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)]}))

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("drag-ui")
	var at: Vector3 = LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary = FIXTURE.full_snapshot(at,true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode = true
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	var session = world.session
	var race = session.desert.drag
	var car = world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not is_instance_valid(car): quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if not world.driving.interact(): quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	session.weather.set_process(false)
	session.weather.time_of_day = .45
	session.weather._update()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("DRAG_UI_READY ",output)
	results.environment = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"time":.45,"scene":"Main.tscn","native":true,"population":world.people.size(),"user_args":OS.get_cmdline_user_args()}
	if not race.perform("board"): quit(1); return
	await hold(3)
	await capture("board")
	begin_sample()
	await hold(30)
	end_sample("board")
	session.close_menu()
	for cycle in 2:
		if not race.perform("start"): push_error(race.start_block_reason()); quit(1); return
		race._rng.seed = 2247
		race._rival_wait = .32
		await hold(.2)
		await capture("staging-%d"%cycle)
		if cycle==0:
			session._menu("Pausa")
			await hold(.2)
			await capture("pause")
			session.close_menu()
		begin_sample()
		while race.active and race.elapsed<18:
			race._throttle_override = .54 if race.phase=="staging" else 1.0
			race._nitro_override = race.phase=="racing"
			if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
			await physics_frame
		end_sample("race-%d"%cycle)
		await capture("racing-%d"%cycle)
		race.cancel_attempt()
		var point: Vector3 = race.staging_point+Vector3(0,.1,-6)
		world.production.region.prepare_collision_at(point)
		car.place(point,-PI*.5)
		world.player.global_position = point
		world.player.reset_physics_interpolation()
		world.production.region.set_focus(point)
		await hold(2)
	var file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	file.close()
	print("DRAG_UI_DONE ",output)
	world.free()
	quit()
