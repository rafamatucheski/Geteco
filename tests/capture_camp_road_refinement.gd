extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(90).timeout.connect(func(): quit(2))
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
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
	camera.position = lake.global_position + Vector2(230,230)
	camera.zoom = Vector2.ONE * 2.1
	player.global_position = lake.global_position + Vector2(150,240)
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/camp-road-refinement-0911.png")
	quit()