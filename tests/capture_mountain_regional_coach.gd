extends SceneTree
const Layout = preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const OUTPUT := "D:/geteco/artifacts/rodoviaria-gelo-0910"

func _initialize() -> void:
	call_deferred("run")

func picture(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for layer in current_scene.find_children("*", "CanvasLayer", true, false): layer.hide()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(file))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_phone_answered", true)
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 12: await process_frame
	print("CAPTURE_GAMEPLAY_READY ", world.gameplay_ready)
	var service = world.get_node("HarborMountainCoachService")
	var preparation_frames := 0
	while service.access_lane == null and preparation_frames < 6000:
		await process_frame
		preparation_frames += 1
		if preparation_frames % 600 == 0: print("CAPTURE_PREPARING ", service.get_service_status())
	if service.access_lane == null:
		push_error("Regional capture destination was not prepared")
		quit(1)
		return
	print("CAPTURE_DESTINATION_READY")
	var mountain = service.stream.mountain
	var player = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = mountain.to_global(Layout.HEAT_SOURCE + Vector2(0, 35))
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = mountain.to_global(Vector2(7550, -1640))
	camera.zoom = Vector2.ONE * 1.2
	camera.set_meta("mountain_fixed_framing", true)
	camera.make_current()
	world.weather.time_of_day = 0.45
	for frame in 30: await process_frame
	for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
	# Only this visual fixture begins on the approach. The separate route test
	# drives the complete Harbor-to-mountain return journey without repositioning.
	var follow = service.coach.get_parent()
	follow.reparent(service.mountain_lane, false)
	follow.progress = service.mountain_entry_offset - 120.0
	service.coach.position = Vector2.ZERO
	service.coach.rotation = 0.0
	service.coach.dwelling = false
	service.coach.doors = 0.0
	service.coach.stop_armed = true
	service.coach.stop_lane = service.access_lane
	service.coach.stop_offset = service.mountain_berth_offset
	service.state = "mountain_approach"
	follow.reset_physics_interpolation()
	var passengers = mountain.get_node("MountainTransitVillage/TransitPassengers")
	var pictured_arrival := false
	var pictured_departure := false
	for frame in 9000:
		await process_frame
		if frame % 600 == 0: print("CAPTURE_PROGRESS ", service.get_service_status(), " at=", service.coach.global_position)
		if not pictured_arrival and not passengers.history.is_empty() and passengers.history.back().alighted >= 3:
			await picture("03_onibus_na_micro_rodoviaria.png")
			pictured_arrival = true
		if pictured_arrival and not pictured_departure and service.state == "returning":
			await picture("04_onibus_retornando.png")
			pictured_departure = true
		if passengers.purchases >= 2:
			await picture("05_passageiros_com_agasalhos.png")
			break
	print("REGIONAL_CAPTURE_RESULT ", service.get_service_status(), " arrivals=", passengers.history, " purchases=", passengers.purchases)
	var success: bool = pictured_arrival and pictured_departure and passengers.purchases >= 2
	world.queue_free()
	await process_frame
	quit(0 if success else 1)
