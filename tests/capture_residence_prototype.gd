extends SceneTree

const OUTPUT := "C:/Users/rafae/.codex/visualizations/2026/09/13/01a09829-5726-7f72-9b96-f25c7fa93245/residence-prototype"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("geteco_residence_capture_%d" % Time.get_ticks_msec()) + "/"
	saves._save_directory_ready = false
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.get("gameplay_ready"):
		await process_frame
	for frame in 8:
		await process_frame

	var world := current_scene
	var player: Node2D = world.get_node("Player")
	var manager: ResidenceManager = world.get_node("ResidencePrototype")
	player.set_physics_process(false)
	var player_camera := player.get_node_or_null("Camera") as Camera2D
	if is_instance_valid(player_camera):
		player_camera.enabled = false
	var camera := Camera2D.new()
	camera.name = "ResidenceCaptureCamera"
	world.add_child(camera)
	camera.make_current()

	for property_id in ["westgate_garden", "quayside_house", "canal_north"]:
		var property: ResidenceProperty = manager.properties[property_id]
		player.global_position = property.entrance_position() + Vector2(0, 18)
		camera.global_position = property.global_position + Vector2(0, 58)
		camera.zoom = Vector2.ONE * (1.22 if property_id == "canal_north" else 1.38)
		await _settle(8)
		await _save("exterior-%s.png" % property_id)

	player.money = 100000
	player.global_position = manager.properties.westgate_garden.entrance_position()
	camera.global_position = manager.properties.westgate_garden.global_position + Vector2(0, 58)
	camera.zoom = Vector2.ONE * 1.38
	manager.open_purchase("westgate_garden")
	await _settle(5)
	await _save("purchase-westgate.png")
	manager.menu.close()
	manager.purchase_home("westgate_garden")
	manager.enter_home("westgate_garden")
	while world.get_node("Interiors").is_transitioning():
		await process_frame
	var room: ResidenceInterior = manager.residence_interiors.westgate_garden
	camera.global_position = room.global_position
	camera.zoom = Vector2.ONE * 1.28
	camera.make_current()
	await _settle(8)
	await _save("interior-westgate.png")
	for property_id in ["quayside_house","canal_north"]:
		manager.exit_home(manager.active_home_id())
		while world.get_node("Interiors").is_transitioning(): await process_frame
		manager.purchase_home(property_id)
		manager.enter_home(property_id)
		while world.get_node("Interiors").is_transitioning(): await process_frame
		camera.global_position = manager.residence_interiors[property_id].global_position
		camera.make_current()
		await _settle(8)
		await _save("interior-%s.png" % property_id)
	manager.exit_home("canal_north")
	while world.get_node("Interiors").is_transitioning(): await process_frame
	var home: ResidenceProperty = manager.properties.canal_north
	preload("res://emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(world,"ParkedAtHome",home.extra_vehicle_position(),0.0,"sedan_classic",0,Color("a8463b"))
	manager.capture_parking_for_save()
	saves.save_game("residence_visual_parking")
	camera.global_position = home.global_position+Vector2(0,65)
	camera.zoom = Vector2.ONE*1.2
	camera.make_current()
	await create_timer(4.0).timeout
	await _settle(8)
	await _save("parking-canal-north.png")
	manager.set_time_period("night")
	await create_timer(1.0).timeout
	await _settle(8)
	await _save("parking-canal-north-night.png")
	print("RESIDENCE_CAPTURE_COMPLETE " + OUTPUT)
	world.queue_free()
	await process_frame
	quit(0)


func _settle(frames: int) -> void:
	for frame in frames:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(filename: String) -> void:
	var path := OUTPUT.path_join(filename)
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK, "Could not save " + path)
	print("CAPTURE " + path)
