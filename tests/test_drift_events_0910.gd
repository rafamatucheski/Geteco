extends SceneTree
const SAFETY := preload("res://cars/VehicleMotionSafety.gd")
var failures: Array[String] = []
var capture_dir := "D:/geteco/artifacts/drift-events-0910/"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=").trim_suffix("/")+"/"
	root.get_node("SaveManager")._save_dir = OS.get_temp_dir().path_join("drift_0910_%d" % Time.get_ticks_usec())+"/"
	root.get_node("SaveManager")._save_directory_ready = false
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 8: await process_frame
	if world.campaign_controller: world.campaign_controller.skip_cinematic()
	paused = false
	for i in 4: await process_frame
	# Freeze unrelated world scripts while exercising explicit controller steps.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	for action in InputMap.get_actions(): Input.action_release(action)
	root.get_node("GameInput").reset_bindings()
	await process_frame
	check(get_nodes_in_group("drift_zone").size()==2,"two drift yards in production scene")
	check(get_nodes_in_group("night_race").size()==2,"two night races in production scene")
	var puddles := get_nodes_in_group("rain_puddle")
	check(puddles.size()<=96,"initial weather keeps puddles within budget")
	var weather := get_first_node_in_group("day_night_manager")
	weather.weather_state = 1
	weather.rain_intensity = 0.8
	var rain: Node = world.get_node("RainPuddles")
	for i in 100: rain._process(0.1)
	check(rain.wetness>0.65,"puddles accumulate during rain")
	puddles = get_nodes_in_group("rain_puddle")
	check(puddles.size()>20 and puddles.size()<=96,"rain creates road puddles within fixed budget")
	weather.weather_state = 0
	rain._process(1.0)
	check(rain.wetness<0.25,"puddles evaporate promptly when the sun returns")
	for i in 100: rain._process(1.0)
	check(rain.wetness<0.01,"puddles dry in clear weather")
	var car = world.get_node("PlayerCar")
	car.process_mode = Node.PROCESS_MODE_ALWAYS
	car.set_process(false)
	car.set_physics_process(false)
	await physics_frame
	car.is_driven_by_player = true
	car._drive_input_armed = true
	car.global_position = Vector2(28000,28000)
	car.rotation = 0
	car.velocity = Vector2(200,0)
	car.steering_angle = 0
	for i in 30: car._apply_steering_motion(1,1.0/60)
	check(absf(car.velocity.dot(car.global_transform.y))<1,"normal coupe steering retains grip")
	car.rotation = 0
	car.velocity = Vector2(220,0)
	car.steering_angle = 0
	Input.action_press("move_up")
	Input.action_press("move_right")
	Input.action_press("handbrake")
	var max_lateral := 0.0
	for i in 30:
		car._physics_process(1.0/60)
		max_lateral = maxf(max_lateral,absf(car.velocity.dot(car.global_transform.y)))
	check(max_lateral>50 and car.velocity.length()>70,"real handbrake input produces moving sideways slip")
	print("DRIFT_MEASURE lateral=",max_lateral," speed=",car.velocity.length())
	for action in ["move_up","move_right","handbrake"]: Input.action_release(action)
	for i in 120: car._physics_process(1.0/60)
	check(car.handbrake_slide==0 and car.velocity.length()<5,"release recovers and coasting stops without runaway")
	car.rotation = 0
	car.velocity = Vector2.ZERO
	Input.action_press("move_up")
	for i in 60: car._physics_process(1.0/60)
	check(car.velocity.length()>220,"coupe reaches useful drift speed within one second from rest")
	Input.action_press("move_right")
	Input.action_press("handbrake")
	for i in 12: car._physics_process(1.0/60)
	Input.action_release("handbrake")
	for i in 10: car._physics_process(1.0/60)
	check(absf(car.velocity.dot(car.global_transform.y))>35 and car.velocity.length()>60,"brief handbrake tap keeps scoring slip after release")
	for action in ["move_up","move_right"]: Input.action_release(action)
	var traffic = ModernTrafficFactory.spawn_parked_vehicle(world,"DriftTraffic",Vector2(29000,29000),0,"sport_coupe",0,Color.RED)
	traffic.process_mode = Node.PROCESS_MODE_ALWAYS
	traffic.set_process(false)
	traffic.set_physics_process(false)
	await physics_frame
	traffic.is_driven_by_player = true
	traffic._drive_input_armed = true
	car.is_driven_by_player = false
	traffic.velocity = Vector2(200,0)
	traffic.set_physics_process(false)
	Input.action_press("move_up")
	Input.action_press("move_right")
	Input.action_press("handbrake")
	for i in 25: traffic._physics_process(1.0/60)
	check(traffic.lateral_speed>35 and traffic.velocity.length()>60,"traffic car uses remappable driving and drift telemetry")
	for action in ["move_up","move_right","handbrake"]: Input.action_release(action)
	traffic.is_driven_by_player = false
	car.is_driven_by_player = true
	world.get_node("Player").is_in_dialogue = false
	world.get_node("Player").is_control_disabled = false
	# Input.just_pressed uses different counters in physics and render callbacks.
	# Event invitations are consumed by _process in the real game.
	await process_frame
	var zone = get_nodes_in_group("drift_zone")[0]
	car.global_position = zone.global_position
	car.velocity = Vector2.ZERO
	zone._process(0.1)
	check(not zone._running and zone._card.layer.visible,"entering drift only shows invitation")
	check(zone._card.detail.text.contains("sem meta mínima") and zone._card.detail.text.contains(zone.UI.key(zone,"handbrake")),"invitation explains controls and scoring objective before starting")
	car._entry_input_released = true
	Input.action_press("interact")
	car._physics_process(1.0/60)
	zone._process(1.0/60)
	Input.action_release("interact")
	check(car.is_driven_by_player and zone._running,"interact starts event without exiting the coupe")
	await process_frame
	car.rotation = 0
	car.velocity = Vector2(100,90)
	for i in 20: zone._process(0.1)
	check(zone._score>0 and zone._combo>1,"real lateral momentum earns combo points")
	var race = get_nodes_in_group("night_race")[0]
	weather.time_of_day = 0.9
	race._try_start_race(car)
	check(race._state == race.State.IDLE,"one motorsport event at a time")
	car.global_position += Vector2(1000,0)
	zone._process(1)
	check(zone._running,"short excursion has return grace")
	zone._process(2.1)
	check(not zone._running,"leaving zone ends challenge after grace")
	weather.time_of_day = 0.5
	weather.is_dark = true
	race._try_start_race(car)
	check(race._state == race.State.IDLE,"daytime storm cannot start night race")
	weather.time_of_day = 0.9
	car.global_position = race.to_global(race.start_pos)
	car.velocity = Vector2.ZERO
	race._process(0.1)
	check(race._state == race.State.IDLE,"crossing race start never auto-starts")
	race._try_start_race(car)
	race._process(3.1)
	check(race._state == race.State.RUNNING,"explicit start counts down before clock runs")
	var mini = world.get_node("Minimap")
	mini.refresh()
	check(mini.motorsport_route and mini.objective_target == race._get_current_target_position(),"minimap directs to current race gate")
	for i in race.checkpoints.size()+1:
		var target: Vector2 = race._get_current_target_position()
		race._previous_position = target-Vector2(90,0)
		car.global_position = target+Vector2(90,0)
		race._process(1)
	check(race._state == race.State.RESULT and race._best_time>0,"swept gate crossing finishes full ordered circuit")
	mini.refresh()
	check(not mini.motorsport_route,"campaign navigation restored on finish")
	traffic.is_driven_by_player = true
	traffic._entry_input_released = true
	Input.action_press("interact")
	traffic._physics_process(1.0/60)
	Input.action_release("interact")
	check(traffic.is_driven_by_player,"interact does not exit a traffic car")
	traffic.is_driven_by_player = false
	# Production placements must be outside authored building solids.
	for event in get_nodes_in_group("drift_zone"):
		for site in world.get_node("District").sites:
			check(not site.bounds.grow(event.radius).has_point(event.global_position),"drift yard clears "+String(site.get("id","building")))
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		for layer in get_nodes_in_group("motorsport_card"): layer.visible = false
		car.global_position = zone.global_position+Vector2(-65,45)
		car.velocity = Vector2.ZERO
		zone._result_time = 0
		race._state = race.State.IDLE
		world.process_mode = Node.PROCESS_MODE_DISABLED
		var camera := Camera2D.new()
		root.add_child(camera)
		camera.position = zone.global_position
		camera.zoom = Vector2(1.4,1.4)
		camera.make_current()
		weather.time_of_day = 0.55
		weather.weather_state = 1
		weather.rain_intensity = 0.8
		rain._process(10.0)
		world.get_node("Player").is_in_dialogue = false
		world.get_node("Player").is_control_disabled = false
		world.get_node("Player").global_position = zone.global_position
		zone._process(0.01)
		mini.refresh()
		weather._process(0.01)
		rain._process(0.3)
		car.reset_physics_interpolation()
		car.request_appearance_update()
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_dir+"drift-world.png")
		zone._card.layer.visible = false
		camera.position = race.to_global(race.start_pos)
		car.global_position = camera.position
		world.get_node("Player").global_position = camera.position
		weather.time_of_day = 0.9
		weather.is_dynamic_time = false
		for i in 60: weather._process(1.0/60)
		race._process(0.01)
		mini.refresh()
		car.reset_physics_interpolation()
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_dir+"race-world.png")
		race._try_start_race(car)
		race._process(3.1)
		race._process(0.1)
		check(race._state == race.State.RUNNING and race._card.layer.visible,"active race HUD renders after countdown")
		mini._route_clock = 1
		mini.refresh()
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_dir+"race-active.png")
		race._card.layer.visible = false
		rain._process(0.25)
		camera.position = puddles[0].global_position
		camera.reset_physics_interpolation()
		for i in 4: await physics_frame
		camera.force_update_scroll()
		rain._process(0.3)
		print("PUDDLE_VISUAL wetness=",rain.wetness," center=",camera.get_screen_center_position()," puddle=",puddles[0].global_position," current=",root.get_camera_2d().name)
		check(puddles[0].visible and puddles[0].monitoring,"nearby wet puddle renders and triggers splashes")
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_dir+"puddles-world.png")
	print("DRIFT_EVENTS failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
