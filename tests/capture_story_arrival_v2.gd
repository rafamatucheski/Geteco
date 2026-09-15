extends SceneTree
func _initialize() -> void: call_deferred("run")
func shot(file: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/"+file+".png")
func run() -> void:
	root.size = Vector2i(1280,800)
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for key in ["harbor_arrival_seen","harbor_story_arrival_v2","harbor_police_briefed","harbor_arrival_call_complete"]: campaign.set_campaign_flag(StringName(key),true)
	root.get_node("SaveManager").clear_pending_save()
	var world: Node2D = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	var intro: Node = world.campaign_controller.story_arrival
	var player: Node2D = world.get_node("Player")
	player.global_position = intro.maciota.global_position+Vector2(0,35)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = intro.car.global_position+Vector2(0,-50)
	camera.zoom = Vector2.ONE*2.4
	camera.make_current()
	world.weather.time_of_day = .42
	world.weather.set_weather(0)
	await create_timer(1.5).timeout
	await shot("story-v2-yard")
	intro.interact()
	await shot("story-v2-introductions")
	world.campaign_controller._dialog.hide()
	world.campaign_controller._unlock_player()
	player.global_position = intro.police.sergeant_npc.global_position+Vector2(0,60)
	intro.police.set_npc_rendering_active(true)
	camera.global_position = intro.police.global_position
	camera.zoom = Vector2.ONE
	world.campaign_controller._set_phase("police_visit","",Vector2.ZERO)
	intro.interact()
	world.campaign_controller.advance_dialogue()
	world.campaign_controller.advance_dialogue()
	world.campaign_controller.advance_dialogue()
	await shot("story-v2-police")
	quit()
