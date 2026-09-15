extends SceneTree
## Render the resumed parcel-return checkpoint through the real garage door.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func(): quit(2))
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_first_favors_v3", "harbor_delivery_started", "harbor_delivery_receipt", "harbor_delivery_picked_up"]: state.set_campaign_flag(StringName(flag),true)
	var world: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	var mission: Node = world.campaign_controller
	var player: Node2D = world.get_node("Player")
	player.global_position = mission.entrance.get_node("OutsideReturn").global_position
	player.reset_physics_interpolation()
	for i in 8: await physics_frame
	if not mission.entrance.request_interaction(player): printerr("RETURN_CAPTURE door failed"); quit(1); return
	await create_timer(1.1).timeout
	if not mission.garage.contains_point(player.global_position): printerr("RETURN_CAPTURE entry failed"); quit(1); return
	player.global_position = mission.garage.jager_npc.global_position+Vector2(0,45)
	for i in 15: await physics_frame
	if not mission.interact_with_objective(): printerr("RETURN_CAPTURE dialogue failed"); quit(1); return
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("D:/geteco/artifacts/chapter-one-0913/maciota-delivery-dialogue.png")
	print("RETURN_CAPTURE real garage entry and dialogue ", result)
	quit(0 if result == OK else 1)
