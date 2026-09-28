extends SceneTree
## Identical Main scenario in the preserved baseline and current checkout.
## Run rendered, no saves; eight seconds warmup, thirty seconds measured.
var world: Node3D
var label := "after"
var scenario := "pursuit"
var output := "D:/geteco/game/evidence/police-response-20260928"

func _initialize() -> void: run.call_deferred()

func stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var stalled := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: stalled += 1
	var n := sorted.size()
	if n == 0: return {}
	return {"frames": n, "seconds": total / 1000.0, "fps": n * 1000.0 / total, "p50_ms": sorted[int(n*.5)],
		"p95_ms": sorted[mini(n-1,int(n*.95))], "p99_ms": sorted[mini(n-1,int(n*.99))], "max_ms": sorted[-1], "over_33ms": slow, "over_66ms": stalled}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--skip-arrival" not in args: quit(2); return
	for arg in args:
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	create_timer(240.0).timeout.connect(func(): push_error("POLICE_MEASURE_TIMEOUT"); quit(2))
	seed(20260928)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for index in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	if scenario == "interior":
		if not await world.session.enter_place("harbor_ammunation", false): quit(4); return
	world.gameplay.register_crime(420,world.player.global_position)
	# Same baseline escalation; new policy receives explicit violent testimony.
	if world.gameplay.get("police_case") != null: world.gameplay.police_case.confirmed(0,world.player.global_position,"gunfire")
	var frames: Array[float] = []
	var warm: Array[float] = []
	var cpu: Array[float] = []
	var physics: Array[float] = []
	var peak_officers := 0
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now-previous)/1000.0
		previous = now
		world.gameplay.health = 100.0
		world.gameplay.report_contact(world.player.global_position)
		if now-start < 8000000: warm.append(ms)
		else:
			frames.append(ms)
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		peak_officers = maxi(peak_officers,world.dispatch.foot_officer_count())
	var report := {"label":label,"scenario":scenario,"scene":"res://Main.tscn","gpu":RenderingServer.get_video_adapter_name(),
		"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"seed":20260928,"population":world.people.size(),
		"position":str(world.player.position),"camera":str(world.camera.global_transform),"zoom":world.camera.size,"peak_officers":peak_officers,
		"summary":stats(frames),"warmup":stats(warm),"cpu":stats(cpu),"physics":stats(physics),"frames_ms":frames,"warmup_ms":warm}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-"+scenario+".json"),FileAccess.WRITE)
	if file == null: quit(5); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("POLICE_MEASURE ",JSON.stringify(report.summary))
	world.queue_free()
	await process_frame
	quit(0)
