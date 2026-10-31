extends "res://tests/test_vehicle_park_manhole_passage.gd"
## Regressão integrada da entrada com carro de produção, save isolado e cronometragem renderizada.
const METRICS := preload("res://tests/measure/measure.gd")
var intervals: Array[float] = []
var tracing := false
var tick := 0
var pictures := false
var photo_tick := 0
var photo_index := 0

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if tracing: intervals.append(float(now-tick)/1000.0)
	tick = now
	if pictures and now-photo_tick>500000 and DisplayServer.get_name()!="headless":
		photo_tick = now
		photo_index += 1
		root.get_texture().get_image().save_png(folder.path_join("route-%03d.png" % photo_index))
	return false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): push_error("Park entry timeout"); quit(3))
	seed(81026)
	folder = FIXTURE.output_dir("park-vehicle-entry")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"fixture.json",FIXTURE.full_snapshot(PARK.ENTRY,false)))
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("C# route service required"); quit(4); return
	car = VEHICLE.new()
	car.archetype = "sport_coupe"
	car.position = PARK.ORIGIN+Vector3(55,.1,16)
	world.add_child(car)
	car.set_external_driver(true)
	car.brake_input = true
	world.player.teleport(PARK.ORIGIN+Vector3(51,.1,22))
	world.production.region.set_focus(PARK.ENTRY)
	world.production.region.prepare_collision_at(PARK.ENTRY)
	world.camera.initialized = false
	await create_timer(8).timeout
	var summary := {}
	if DisplayServer.get_name()!="headless" and "--physics-only" not in OS.get_cmdline_user_args():
		tick = Time.get_ticks_usec()
		tracing = true
		await create_timer(30).timeout
		tracing = false
		var metrics = METRICS.new()
		summary = metrics.stats(intervals)
		metrics.free()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("entrance.png"))
	# Mantém o trânsito comum durante a medição. Durante a checagem varrida do terreno,
	# ignora veículos nos dois sentidos para que um carro passando não acerte a fixture.
	car.collision_mask = 1
	car.collision_layer = 0
	pictures = true
	for z in [16.0,15.2,16.8]:
		await drive("entry_"+str(z),PARK.ORIGIN+Vector3(55,0,z),PARK.ORIGIN+Vector3(32,0,z))
		await drive("exit_"+str(z),PARK.ORIGIN+Vector3(32,0,z),PARK.ORIGIN+Vector3(55,0,z))
	pictures = false
	var report := {"results":results,"failures":failures,"summary":summary,"samples_ms":intervals,"native_csharp":true,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"ground_hash":FileAccess.get_sha256("res://world/places/amusement_park/ParkLumeGround.gd")}
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PARK_ENTRY_RESULT ",folder," ",JSON.stringify(summary)," failures=",failures)
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
