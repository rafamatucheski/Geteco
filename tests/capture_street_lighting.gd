extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var state=root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_call_complete",true)
	var world=load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	world.weather.time_of_day=0.0
	world.weather.is_dynamic_time=false
	world.weather._update_lighting()
	world.weather.set_process(false)
	for layer in world.find_children("", "CanvasLayer",true,false): layer.hide()
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	for item in [[Vector2(1250,1330),1.3,"city-night"],[Vector2(-650,1740),1.1,"cemetery-night"]]:
		camera.global_position=item[0]
		camera.zoom=Vector2.ONE*item[1]
		world.get_node("Player").global_position=item[0]
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/"+item[2]+".png")
	print("NIGHT_LIGHTING_CAPTURE lamps=",get_nodes_in_group("street_lamp").size())
	world.queue_free()
	await process_frame
	quit()
