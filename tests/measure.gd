extends SceneTree
## Actual rendered Main scene; 5 s warm-up then 30 s real frame intervals.
## This is an initial prototype baseline, not a comparison with HarborGame.
var world
var samples: Array[float] = []
var cold: Array[float] = []
var cpu: Array[float] = []
var physics: Array[float] = []
var started := 0
var previous := 0
var measuring := false
var measured_started := 0
var label := "population24"
var waypoint := 0
var driving_mode := false
var driving_route: Curve3D
var route := PackedVector3Array([Vector3(-2,0,-12),Vector3(2,0,-12),Vector3(2,0,12),Vector3(-2,0,12)])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Benchmark requires the rendered game")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.split("=")[1]
		if arg == "--drive": driving_mode = true
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	if world.get("driving") != null: world.driving.set_process_unhandled_input(false)
	if world.get("activity") != null: world.activity.set_process_unhandled_input(false)
	# The measurement route and camera must not respond to unrelated key presses.
	world.camera.set_process_unhandled_input(false)
	for child in world.hud.get_children():
		if child.get_script() != null: child.set_process_unhandled_input(false)
	world.player.teleport(Vector3(-2,0.04,12))
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	world.camera.target_size = 32
	if "--interior" in OS.get_cmdline_user_args():
		await physics_frame
		await physics_frame
		assert(world.session.transition(true,false),"Interior benchmark transition")
		route = PackedVector3Array([Vector3(0,0,-126.8),Vector3(1,0,-128.5),Vector3(3.4,0,-128.5),Vector3(3.4,0,-130.55),Vector3(3.4,0,-128.5),Vector3(1,0,-128.5)])
		world.player.speed = 1.5
	if driving_mode:
		world.driving.car.place(Vector3(-1.8,0.04,6),PI)
		world.player.teleport(world.driving.car.to_global(Vector3(-1.65,0.04,0.15)))
		assert(world.driving.interact(),"Benchmark must enter the actual car")
		world.driving.car.external_input = true
		driving_route = world.traffic.cars[0].route
	started = Time.get_ticks_usec()
	previous = started

func _process(_delta: float) -> bool:
	if started == 0: return false
	var now := Time.get_ticks_usec()
	var frame_ms := float(now-previous)/1000.0
	previous = now
	var direction: Vector3 = route[waypoint]-world.player.position
	direction.y = 0
	if direction.length() < 0.4: waypoint = (waypoint+1)%route.size()
	world.player.automatic_direction = direction.normalized()
	if driving_mode:
		var car = world.driving.car
		var offset := driving_route.get_closest_offset(car.position)
		var ahead: Vector3 = driving_route.sample_baked(fposmod(offset+5.0,driving_route.get_baked_length()),true)-car.position
		var yaw := atan2(-ahead.x,-ahead.z)
		car.steer_input = clampf(angle_difference(car.rotation.y,yaw)*2.0,-1,1)
		car.throttle_input = 1.0 if car.speed < 5.5 else 0.0
		car.brake_input = car.obstacle_ahead()
	if not measuring:
		cold.append(frame_ms)
		if now-started >= 5000000:
			measuring = true
			measured_started = now
		return false
	samples.append(frame_ms)
	cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	if now-measured_started >= 30000000:
		started = 0
		finish.call_deferred()
	return false

func stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames":values.size(),"seconds":total/1000,"fps":values.size()*1000/total,"p50_ms":sorted[int((sorted.size()-1)*0.50)],"p95_ms":sorted[int((sorted.size()-1)*0.95)],"p99_ms":sorted[int((sorted.size()-1)*0.99)],"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}

func finish() -> void:
	var summary := stats(samples)
	var report := {"label":label,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"population":world.people.size(),"cars":8+(1+world.traffic.cars.size() if world.get("driving") != null else 0),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"summary":summary,"warmup":stats(cold),"cpu_process":stats(cpu),"physics":stats(physics),"frame_intervals_ms":samples,"warmup_intervals_ms":cold,"cpu_ms":cpu,"physics_ms":physics,"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"player_distance":world.player.travelled,"notes":"Prototype only. External process inventory determines whether the sample was isolated; CPU monitors are not a GPU profile."}
	report["driving"] = driving_mode
	if driving_mode: report["vehicle_distance"] = world.driving.car.distance_travelled
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+".png")
	var file := FileAccess.open("res://evidence/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("BENCHMARK ",label," ",JSON.stringify(summary))
	world.queue_free()
	await process_frame
	quit()
