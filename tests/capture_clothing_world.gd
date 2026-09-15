extends SceneTree

const OUTPUT := "D:/geteco/artifacts/winter-clothing-0910/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(file: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+file+".png")

func _run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete",true)
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	var player=world.get_node("Player")
	player.set_physics_process(false)
	player.global_position=Vector2(1890,285)
	var camera:=Camera2D.new()
	camera.set_meta("mountain_fixed_framing",true)
	world.add_child(camera)
	camera.position=Vector2(1890,190)
	camera.zoom=Vector2.ONE*2.6
	camera.make_current()
	for layer in world.find_children("","CanvasLayer",true,false): layer.hide()
	await _shot("union-exterior")
	await world.get_node("ContinuousWorld").ensure_mountain()
	var mountain=world.get_node("ContinuousWorld").mountain
	var shop=mountain.get_node("MountainExpedition/SnowOutfitters")
	player.global_position=shop.global_position+Vector2(0,105)
	camera.global_position=shop.global_position+Vector2(0,-25)
	camera.zoom=Vector2.ONE*3.4
	for layer in mountain.find_children("","CanvasLayer",true,false): layer.hide()
	await _shot("mountain-exterior")
	print("CLOTHING WORLD CAPTURES COMPLETE")
	world.queue_free()
	await process_frame
	quit()
