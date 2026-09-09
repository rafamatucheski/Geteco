extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var world := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(world)
	current_scene = world
	for i in 20: await process_frame
	if world._panel: world._panel.hide()
	var camera := world.get_node("OverviewCamera") as Camera2D
	camera.global_position = Vector2(1550, 1000)
	camera.zoom = Vector2.ONE * 1.0
	camera.make_current()
	world.weather.weather_timer = 1000.0
	world.weather.lightning_timer = 1000.0
	world.weather.set_rain_intensity(0.25)
	world.weather.set_weather(1)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/combat-audio/rain-light.png")
	world.weather.set_weather(2)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/combat-audio/rain-strong.png")
	print("RAIN_VISUAL_CAPTURE complete")
	world.queue_free()
	await create_timer(0.3).timeout
	quit()
