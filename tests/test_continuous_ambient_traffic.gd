extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(70).timeout.connect(func(): quit(2))
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 25: await process_frame
	var stream := current_scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var player: Node2D = current_scene.get_node("Player")
	player.position = Vector2(7300,-4430)
	player.set_physics_process(false)
	# Isolate the lane handoff from random ambient obstructions on the apron.
	for other in get_nodes_in_group("modern_traffic"):
		if other.global_position.distance_to(Vector2(7300,-4560))<500:
			other.get_parent().queue_free()
	await process_frame
	var outbound: Path2D
	var inbound: Path2D
	for lane in get_nodes_in_group("unified_traffic_lane"):
		var id := String(lane.get_meta("traffic_road_id",""))
		if id.ends_with("mountain_bridge_outbound"): outbound=lane
		if id.ends_with("mountain_bridge_inbound"): inbound=lane
	check(outbound!=null and inbound!=null,"bridge lanes discoverable")
	var car := ModernTrafficFactory.spawn_moving_vehicle(outbound,"SeamTrafficProbe","union_sedan",0.9,100,0)
	var follower := car.get_parent() as PathFollow2D
	follower.progress = outbound.curve.get_baked_length()-65
	var id := car.get_instance_id()
	var old: Vector2 = car.global_position
	var largest_step := 0.0
	for i in 220:
		await physics_frame
		largest_step=maxf(largest_step,car.global_position.distance_to(old))
		old=car.global_position
	check(car.get_instance_id()==id and follower.get_parent()==stream.mountain.get_node("MountainTraffic").lane,"same ambient car flows Harbor to mountain")
	check(stream.handoff_max_displacement<8,"ambient border handoff preserves position within one frame of travel")
	var mountain_lane: Path2D = stream.mountain.get_node("MountainTraffic").lane
	if follower.get_parent()!=mountain_lane: stream._handoff(follower,mountain_lane)
	follower.progress = mountain_lane.curve.get_baked_length()-65
	old=car.global_position
	largest_step=0
	for i in 130:
		await physics_frame
		largest_step=maxf(largest_step,car.global_position.distance_to(old))
		old=car.global_position
	check(follower.get_parent()==inbound and car.get_instance_id()==id,"same ambient car returns to Harbor")
	check(stream.handoff_max_displacement<12,"return lane joins continuously")
	stream.set_process(false)
	stream._budget_traffic(car.global_position + Vector2(20000,0))
	var sleeping_progress := follower.progress
	for i in 12: await process_frame
	check(not car.is_processing() and not car.is_physics_processing() and is_equal_approx(follower.progress,sleeping_progress),"distant ambient traffic stops both simulation loops without moving")
	stream._budget_traffic(car.global_position)
	check(car.is_processing(),"approaching traffic resumes its original idle simulation")
	print("AMBIENT SEAM FAILURES: ",failures," lastpos=",car.global_position," step=",largest_step)
	quit(0 if failures.is_empty() else 1)
