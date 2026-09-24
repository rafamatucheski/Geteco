extends "res://tests/test_cemetery_keeper_home.gd"

func run() -> void:
	create_timer(45).timeout.connect(func(): quit(2))
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var weather := ClockStub.new()
	weather.add_to_group("day_night_manager")
	world.add_child(weather)
	var manager := TestInteriors.new()
	manager.name = "Interiors"
	world.add_child(manager)
	var cemetery := preload("res://world/harbor/HarborCemetery.gd").new()
	world.add_child(cemetery)
	for i in 10: await process_frame
	var home = cemetery.get_node("KeeperHouse")
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = home.global_position
	camera.zoom = Vector2.ONE * 2.8
	camera.make_current()
	var actor := PlayerStub.new()
	actor.add_to_group("player")
	world.add_child(actor)
	actor.global_position = home.entrance.global_position + Vector2(0, 22)
	home.entrance._on_body_entered(actor)
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TEMP").path_join("geteco-door-marker-after.png")
	var result := root.get_texture().get_image().save_png(output)
	print("DOOR_MARKER_CAPTURE ", output, " error=", result)
	quit(0 if result == OK else 1)
