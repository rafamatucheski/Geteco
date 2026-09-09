extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(90).timeout.connect(func(): printerr("POLICE SEAM TIMEOUT"); quit(2))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 25: await process_frame
	var stream := current_scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var player: Node2D = current_scene.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector2(8000,-4529)
	for car in get_nodes_in_group("vehicle"):
		if car.get_parent() is PathFollow2D: car.get_parent().queue_free()
	var wanted = root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.report_crime(15)
	var car = root.get_node("EmergencyPool").get_vehicle("police")
	car.position = Vector2(7100,-4529)
	car.rotation = 0
	car.target = player
	car.set_meta("police_player_pursuit", true)
	var original_id: int = car.get_instance_id()
	var crossed := false
	var biggest_step := 0.0
	var old: Vector2 = car.position
	for i in 300:
		await physics_frame
		biggest_step = maxf(biggest_step, old.distance_to(car.position))
		old = car.position
		if car.position.x > 7560:
			crossed = true
			break
	print("POLICE_SEAM_OUT|",car.position,"|step=",biggest_step)
	assert(crossed and biggest_step < 12, "Police must physically cross Harbor into mountain without teleport")
	player.position = Vector2(6700,-4591)
	car.position = Vector2(7500,-4591)
	car.rotation = PI
	car.current_speed = 0
	car.velocity = Vector2.ZERO
	car._lane_router.reset()
	old = car.position
	var returned := false
	for i in 300:
		await physics_frame
		biggest_step = maxf(biggest_step, old.distance_to(car.position))
		old = car.position
		if car.position.x < 7070:
			returned = true
			break
	print("POLICE_SEAM_RETURN|",car.position,"|step=",biggest_step)
	assert(returned and car.get_instance_id() == original_id and biggest_step < 12, "Same police car returns through inbound lane without teleport")
	wanted.dismiss_all_police()
	print("CONTINUOUS_POLICE_PURSUIT|PASS")
	quit()
