extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	current_scene.get_node("CobraCampaign").set_process(false)
	system.clock.is_dynamic_time = false
	system.clock.time_of_day = 0.5
	system.clock._update_lighting()
	var bus: Node2D = system.buses[0]
	var player: Node2D = current_scene.get_node("Player")
	player.global_position = system.stops[0].global_position
	player.set_physics_process(false)
	player.hide()
	for layer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	for control in root.find_children("*","Control",true,false): control.hide()
	var camera := Camera2D.new()
	current_scene.add_child(camera)
	camera.global_position = system.stops[0].global_position+Vector2(15,-30)
	camera.zoom = Vector2.ONE*1.65
	camera.make_current()
	await create_timer(4).timeout
	var wait_start := Time.get_ticks_msec()
	while system.stops[0].view.animated_people == 0 and Time.get_ticks_msec()-wait_start<12000:
		await physics_frame
	print("NATIVE_PLATFORM_PEOPLE ",system.stops[0].view.animated_people)
	for body in [bus]+bus.sections:
		print("BODY_POSE ",body.name," heading=",body.global_rotation," model=",body.body_model.rotation.y," sprite=",body.visual.global_rotation," processing=",body.is_processing())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/urban-terminal.png")
	system.clock.time_of_day = 3.0/24
	system._update_schedule()
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/urban-terminal-03h.png")
	for station_index in [1,3,4,5]:
		camera.global_position = system.stops[station_index].global_position
		camera.reset_smoothing()
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/urban-station-%d.png"%station_index)
	print("URBAN CAPTURE COMPLETE bus=",bus.name)
	quit()
