extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	var state = root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen", true)
	state.set_campaign_flag(&"harbor_call_complete", true)
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready:
		await process_frame
	var cemetery: Node2D = world.get_node("Cemetery")
	var player = world.get_node("Player")
	player.global_position = cemetery.get_gate_position()
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = cemetery.global_position
	camera.zoom = Vector2(0.85,0.85)
	camera.make_current()
	for layer in world.find_children("", "CanvasLayer", true, false):
		layer.hide()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/cemetery-location.png")
	var events=world.get_node("WorldEvents")
	events.set_process(false)
	events.start_funeral()
	Engine.time_scale=4
	var guard:=0
	while events.funeral_phase=="arriving" and guard<1200:
		await physics_frame
		events._tick_funeral(4.0/60.0)
		guard+=1
	Engine.time_scale=1
	camera.zoom=Vector2(1.5,1.5)
	camera.global_position=cemetery.global_position+Vector2(0,30)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/cemetery-ceremony.png")
	print("CEMETERY_CAPTURE ", cemetery.global_position)
	world.queue_free()
	await process_frame
	quit()
