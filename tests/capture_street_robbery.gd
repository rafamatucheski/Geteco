extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size=Vector2i(1280,720)
	var state = root.get_node("CampaignState")
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_call_complete",true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	while not world.gameplay_ready: await process_frame
	world.set_process(false)
	var events=world.get_node("WorldEvents")
	events.set_process(false)
	events.start_incident("robbery")
	var incident=events.street_incident
	var player=world.get_node("Player")
	player.global_position=incident.site.point+Vector2(0,120)
	player.set_physics_process(false)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=incident.site.point+Vector2(0,-15)
	camera.zoom=Vector2(3,3)
	camera.make_current()
	for layer in world.find_children("","CanvasLayer",true,false): layer.hide()
	DirAccess.make_dir_recursive_absolute("D:/geteco/game/docs/measurements/street-life-0911")
	var captured: Array[String]=[]
	for frame in 2500:
		await physics_frame
		camera.zoom=Vector2(3,3)
		camera.make_current()
		camera.force_update_scroll()
		incident.tick(1.0/60)
		if incident.phase in ["confrontation","calling","pursuit"] and incident.phase_age>1 and not captured.has(incident.phase):
			captured.append(incident.phase)
			if incident.phase=="pursuit":
				camera.global_position=(incident.officer.global_position+incident.suspect.global_position)*.5
				camera.zoom=Vector2(1.7,1.7)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/game/docs/measurements/street-life-0911/"+incident.phase+".png")
		if captured.size()==3: break
	print("STREET_ROBBERY_CAPTURE ",captured)
	world.queue_free()
	await process_frame
	quit()
