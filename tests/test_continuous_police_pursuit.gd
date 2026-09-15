extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(90).timeout.connect(func(): printerr("POLICE SEAM TIMEOUT"); quit(2))
	var saves := root.get_node("SaveManager")
	var output := "D:/geteco/artifacts/proximity-0912/pursuit-saves/"
	DirAccess.make_dir_recursive_absolute(output)
	saves.set("_save_dir", output)
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 25: await process_frame
	while not current_scene.gameplay_ready or not current_scene.world_build_ready: await process_frame
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
	if not crossed:
		_diagnose_blocker(car, player)
		quit(1)
		return
	assert(crossed and biggest_step < 12, "Police must physically cross Harbor into mountain without teleport")
	player.position = Vector2(6700,-4591)
	# A fresh report updates the known point; navigation never reads a hidden
	# actor's changed position merely because this fixture teleported it.
	wanted.report_crime(0)
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

func _diagnose_blocker(car: CharacterBody2D, player: Node2D) -> void:
	var clearance: float = car._forward_clearance()
	print("POLICE_SEAM_DIAGNOSTIC|player=", player.position, "|target=", car.target.global_position if is_instance_valid(car.target) else Vector2.INF, "|speed=", car.current_speed, "|clearance=", clearance, "|acting=", car.is_acting, "|returning=", car.is_returning_to_base)
	var hull := car.get_node("CollisionShape2D") as CollisionShape2D
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.transform = hull.global_transform
	query.transform.origin += car.transform.x * minf(110.0, clearance + 5.0)
	query.collision_mask = car.EMERGENCY_COLLISION_MASK
	query.exclude = [car.get_rid()]
	for hit in car.get_world_2d().direct_space_state.intersect_shape(query, 8):
		print("POLICE_SEAM_BLOCKER|", hit.collider.get_path(), "|", hit.collider.global_position)
