extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state = root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen", true)
	state.set_campaign_flag(&"harbor_call_complete", true)
	
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	
	while not world.gameplay_ready:
		await process_frame
		
	for layer in world.find_children("", "CanvasLayer", true, false):
		layer.hide()
		
	var player = world.get_node("Player")
	player.set_physics_process(false)
	
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(2.0, 2.0)
	camera.make_current()
	
	# 1. Police Parking Overview
	camera.global_position = Vector2(1080, 2120)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/debug_police_parking_after.png")
	print("SAVED: debug_police_parking_after.png")
	
	# 1b. Police Parking Closeup (matching user clip zoom)
	camera.zoom = Vector2(3.0, 3.0)
	camera.global_position = Vector2(1080, 2110)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/debug_police_parking_closeup_after.png")
	print("SAVED: debug_police_parking_closeup_after.png")
	
	# 2. Dock Collectible Overview
	camera.zoom = Vector2(2.0, 2.0)
	camera.global_position = Vector2(3450, 1760)
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/debug_dock_collectible_after.png")
	print("SAVED: debug_dock_collectible_after.png")
	
	# 2b. Dock Collectible Closeup (matching user clip zoom)
	camera.zoom = Vector2(4.5, 4.5)
	camera.global_position = Vector2(3450, 1760)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/debug_dock_collectible_closeup_after.png")
	print("SAVED: debug_dock_collectible_closeup_after.png")
	
	quit(0)
