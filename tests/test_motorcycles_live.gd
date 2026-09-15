extends SceneTree

func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete",true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	var bikes := get_nodes_in_group("motorcycle")
	var counts := {"bike_sport":0,"bike_cruiser":0,"bike_urban":0}
	var positions := {}
	for bike in bikes:
		counts[bike.active_archetype_id] += 1
		positions[bike] = bike.global_position
		assert(bike.get_parent() is PathFollow2D, "Real motorcycles follow live road paths")
		bike.ensure_presentation()
		assert(bike.body_model.style == String(bike.active_archetype_id).trim_prefix("bike_"), "Live model matches the motorcycle style")
		assert(bike.body_model.rider.visible)
		assert(bike.collision.shape.size.y < 20)
	for id in counts: assert(counts[id] >= 4,"Every motorcycle style must be distributed across the live city fleet")
	await create_timer(3.0).timeout
	var moved := 0
	for bike in bikes:
		if is_instance_valid(bike) and bike.global_position.distance_to(positions[bike]) > 10: moved += 1
	assert(moved > 0,"Motorcycle NPCs move in live traffic")
	if "capture" in OS.get_cmdline_user_args():
		for id in counts:
			var subject = bikes.filter(func(item): return item.active_archetype_id == id)[0]
			world.get_node("Player").global_position = subject.global_position + Vector2(0, 65)
			for frame in 12: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/motorcycle-feedback/" + id + "-live.png")
	# Exercise the real player actor through the same vehicle API as interaction.
	var bike = bikes[0]
	var player = world.get_node("Player")
	player.global_position = bike.global_position+Vector2(0,25)
	player.reset_physics_interpolation()
	bike.enter_vehicle(player)
	while bike.has_meta("vehicle_boarding"): await process_frame
	assert(bike.is_driven_by_player and not player.visible and bike.body_model.rider.visible)
	bike.exit_vehicle()
	while bike.has_meta("vehicle_boarding"): await process_frame
	await physics_frame
	assert(player.visible and player.is_physics_processing() and not player.is_control_disabled)
	assert(not bike.body_model.rider.visible)
	print("MOTORCYCLES LIVE PASS: styles=",counts," moving=",moved," player restored=true")
	world.queue_free()
	await process_frame
	quit()
