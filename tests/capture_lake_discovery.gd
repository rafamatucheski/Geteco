extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(90).timeout.connect(func(): quit(2))
	change_scene_to_file("res://district/mountain_pass/MountainPass.tscn")
	for i in 10: await process_frame
	var world = current_scene
	while not world.region_ready: await process_frame
	var player = world.player_instance
	player.set_physics_process(false)
	world.parallax.hide()
	world.storm_manager.dynamic_weather = false
	world.storm_manager.hide()
	for node in world.find_children("*", "Camera2D", true, false): node.enabled = false
	var camera := Camera2D.new()
	world.add_child(camera)
	var lake = world.find_child("SecretMountainLake", true, false)
	var water = lake.get_node("InteractiveLakeWater")
	var plane = lake.get_node("SmugglerCargoPlane")
	camera.position = lake.global_position
	camera.zoom = Vector2.ONE * 1.6
	camera.make_current()
	for i in 5:
		player.global_position = lake.to_global(Vector2(-175+i*8, 95))
		player.velocity = Vector2(60, 0)
		player._play_footstep(false)
		await create_timer(0.04).timeout
	for i in 5:
		player.global_position = lake.to_global(Vector2(-260-i*8, 175))
		water.actor_step(player, false)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/lake-water-effects.png")
	var pickup = plane.get_node("CargoSMG")
	player.world_pickups_collected.erase(pickup.pickup_id)
	player.weapon_inventory.erase("smg")
	player.global_position = pickup.global_position
	plane._process(0.2)
	camera.position = plane.global_position + Vector2(0,-65)
	camera.zoom = Vector2.ONE * 2.4
	pickup._collect(player)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/plane-smg-unlocked.png")
	print("LAKE_DISCOVERY_CAPTURE OK")
	world.queue_free()
	await process_frame
	quit()
