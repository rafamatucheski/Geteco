extends SceneTree
const OUTPUT := "D:/geteco/artifacts/neve-detalhada-0910"
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size=Vector2i(1440,1000)
	root.content_scale_size=root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_phone_answered",true)
	root.get_node("SaveManager").clear_pending_save()
	var world=load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	for frame in 12: await process_frame
	var service=world.get_node("HarborMountainCoachService")
	var started:=Time.get_ticks_msec()
	while service.access_lane==null and Time.get_ticks_msec()-started<180000: await process_frame
	if service.access_lane==null:
		push_error("Mountain service did not finish loading")
		quit(1)
		return
	var mountain:Node2D=service.stream.mountain
	while not mountain.region_ready:await process_frame
	var player=get_first_node_in_group("player")
	player.set_physics_process(false)
	player.collision_layer=0
	player.hide()
	var camera:=Camera2D.new()
	mountain.add_child(camera)
	camera.set_meta("mountain_fixed_framing",true)
	camera.make_current()
	for shot in [["01_vila_neve.png",Vector2(7480,-1640),1.2],["02_abrigo_detalhado.png",Vector2(7130,-1510),2.2],["03_caminhos_chales.png",Vector2(7650,-1540),1.95],["04_estrada_alpina.png",Vector2(6880,-2710),1.3],["05_juncoes.png",Vector2(6950,-1570),2.0],["06_terminal_defensa.png",Vector2(6940,-1595),4.2]]:
		camera.global_position=mountain.to_global(shot[1])
		camera.zoom=Vector2.ONE*shot[2]
		player.global_position=camera.global_position
		for frame in 30:await process_frame
		for layer in root.find_children("*","CanvasLayer",true,false):layer.hide()
		for control in root.find_children("*","Control",true,false):
			if control.get_script()!=null and control.get_script().resource_path.ends_with("SalvageLocator.gd"):control.hide()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT.path_join(shot[0]))
		print("WINTER_CAPTURE ",shot[0])
	print("WINTER_CAPTURE_DONE props=",get_nodes_in_group("mountain_dressing").size())
	world.queue_free()
	for frame in 4:await process_frame
	quit()
