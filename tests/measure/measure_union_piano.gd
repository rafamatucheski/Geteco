extends SceneTree
## Production diagnostic; teleport does not certify walking access.
var world
var folder := "res://artifacts/union-piano/current"

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): folder = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	create_timer(180).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	if not ClassDB.class_exists(&"CSharpScript") or world.dispatch.router._native_graph() == null:
		push_error("Union piano requires compiled C# runtime")
		quit(2)
		return
	world.player.teleport(Vector3(114.2,.1,113.125))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.heading = 0
	world.camera.target_size = 22
	world.camera.size = 22
	world.camera.initialized = false
	world.session.weather.weather_timer = 100000
	world.session.weather.weather_state = 0
	await create_timer(15).timeout
	var piano: Node3D = world.find_child("UnionPiano",true,false)
	if piano == null:
		push_error("Piano did not load at Union Plaza")
		quit(1)
		return
	if "--functional-only" in OS.get_cmdline_user_args():
		await walk_piano(piano)
		return
	if "--without-piano" in OS.get_cmdline_user_args(): piano.queue_free()
	for phase in ["day", "night"]:
		world.session.weather.time_of_day = .5 if phase == "day" else 21.0/24.0
		world.session.weather._update()
		await create_timer(8).timeout
		await measure(phase)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(phase+".png"))
	quit()

func walk_piano(piano: Node3D) -> void:
	var notes: Array[int] = []
	piano.note_played.connect(func(index: int, by_player: bool):
		if by_player and index not in notes: notes.append(index))
	world.player.teleport(piano.global_position + Vector3(-4.8,.1,0))
	world.player.automatic_direction = Vector3.RIGHT
	await create_timer(8).timeout
	world.player.automatic_direction = Vector3.ZERO
	var finish: Vector3 = piano.to_local(world.player.global_position)
	var ok := notes.size() == 8 and finish.x > 4.2 and absf(finish.y) < .6
	print("UNION_PIANO_WALK notes=", notes, " finish=",finish," passed=",ok)
	quit(0 if ok else 1)

func measure(phase: String) -> void:
	var samples: Array[float] = []
	var begin := Time.get_ticks_usec()
	var last := begin
	while Time.get_ticks_usec()-begin < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		last = now
	var sorted := samples.duplicate()
	sorted.sort()
	var report := {"phase":phase,"frames":samples.size(),"seconds":float(last-begin)/1000000.0,
		"fps":samples.size()*1000000.0/(last-begin),"p50_ms":sorted[int(sorted.size()*.5)],
		"p95_ms":sorted[int(sorted.size()*.95)],"p99_ms":sorted[int(sorted.size()*.99)],
		"max_ms":sorted.back(),"over33":samples.filter(func(v):return v>33.3).size(),
		"over66":samples.filter(func(v):return v>66.7).size(),"samples_ms":samples,
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"engine":Engine.get_version_info().string,"resolution":str(root.size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
		"people":world.people.size(),"vehicles":world.production.vehicles.size()}
	FileAccess.open(folder.path_join(phase+"-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("samples_ms")
	print("UNION_PIANO_REPORT ",JSON.stringify(report))
