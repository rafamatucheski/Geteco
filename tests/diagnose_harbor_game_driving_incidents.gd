extends SceneTree

## Diagnostic only: reproduces measure_harbor_game_driving.gd's exact fixture
## and route, but also logs WantedManager stars and active EmergencyVehicle
## count over time, to determine whether the benchmark's straight-line drive
## incidentally triggers a police/fire/medical response (which would explain
## a large per-frame script cost unrelated to "ordinary" driving).

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 90: await process_frame
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(2200, 1050)
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	world.call("_drive")
	for i in 30: await process_frame
	var wanted = root.get_node_or_null("/root/WantedManager")
	Input.action_press("ui_up")
	var dead_pedestrians_seen: Dictionary = {}
	for i in 600:
		await process_frame
		var stars: int = wanted.current_stars if wanted else -1
		var active := 0
		var active_types: Dictionary = {}
		for v in get_nodes_in_group("vehicle"):
			if v.get_script() != null and String(v.get_script().resource_path).ends_with("EmergencyVehicle.gd") and v.visible:
				active += 1
				var t := int(v.get("type"))
				active_types[t] = int(active_types.get(t, 0)) + 1
		for p in get_nodes_in_group("pedestrian"):
			if p.get("is_dead") == true and not dead_pedestrians_seen.has(p.get_instance_id()):
				dead_pedestrians_seen[p.get_instance_id()] = true
				print("PEDESTRIAN_DIED frame=%d car_pos=%s ped_pos=%s" % [i, car.global_position, p.global_position])
		if i % 60 == 0 or active > 0:
			print("INCIDENT_STATE frame=%d stars=%d active_emergency=%d types=%s car_health=%s car_pos=%s dead_peds=%d" % [i, stars, active, active_types, car.get("health"), car.global_position, dead_pedestrians_seen.size()])
	Input.action_release("ui_up")
	print("FINAL_STATE stars=%d car_pos=%s dead_peds=%d" % [wanted.current_stars if wanted else -1, car.global_position, dead_pedestrians_seen.size()])
	world.queue_free()
	await process_frame
	quit()
