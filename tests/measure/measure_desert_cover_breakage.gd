extends SceneTree
## Diagnostic in the rendered game, with an isolated checkpoint and real car physics.
## Debug measurements do not certify release performance.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var output := ""
var samples: Array[float] = []
var recording := false
var stamp := 0
var results := {}

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("COVER_BREAKAGE timeout"); quit(3))
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0: samples.append(float(now - stamp) / 1000.0)
	stamp = now
	return false

func hold(seconds: float) -> void:
	await create_timer(seconds).timeout

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

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
	results[label] = {"frames":samples.size(), "seconds":total / 1000.0, "fps":samples.size() * 1000.0 / total, "p50":sorted[int(sorted.size() * .50)], "p95":sorted[int(sorted.size() * .95)], "p99":sorted[int(sorted.size() * .99)], "max":sorted.back(), "over33":over33, "over66":over66, "raw_ms":samples.duplicate()}
	print("COVER_BREAKAGE ", label, " fps=", results[label].fps, " p95=", results[label].p95)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output = FIXTURE.output_dir("desert-cover-breakage")
	var at := Vector3(80, .1, -1180)
	var data := FIXTURE.full_snapshot(at, true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert", "position":[at.x, at.y, at.z]}
	var path := FIXTURE.write_fixture(output, "checkpoint.json", data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native == null: quit(1); return
	world.gameplay.god_mode = true
	root.size = Vector2i(1280, 720)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .9
	world.session.weather._update()
	var car = world.production.spawn_vehicle("desert_mirage", at, 0.0)
	world.player.teleport(car.driver_door_anchor(1) + car.global_basis.x * .25 + Vector3.UP * .08)
	for i in 4: await physics_frame
	if not world.driving.interact(): quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	car.set_meta("invulnerable", true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await hold(8)
	await capture("before")
	var fragile = preload("res://gameplay/street_physics/FragileProps3D.gd")
	results.environment = {"scene":"Main.tscn", "engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":[1280,720], "native":true, "release":not OS.is_debug_build(), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps}
	begin_sample()
	# External input uses Vehicle's production movement/impact path.
	car.external_input = true
	car.controlled = true
	car.throttle_input = .35
	car.steer_input = .16
	await hold(30)
	end_sample("driving")
	car.throttle_input = 0.0
	car.brake_input = true
	await capture("after")
	var down := {}
	for list in fragile.cells.values():
		for item in list:
			if item.state == "down": down[item.kind] = int(down.get(item.kind, 0)) + 1
	results.contacts = down
	await hold(13)
	results.recovery = {"debris_remaining":world.find_children("StreetDebris*", "RigidBody3D", true, false).size(), "occupied":world.driving.occupied, "position":str(car.global_position)}
	var file := FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	print("COVER_BREAKAGE_DONE ", output, " contacts=", down, " recovery=", results.recovery)
	world.free()
	quit()
