extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for frame in 12:
		await process_frame
	var neighborhood := scene.get_node_or_null("CobraNeighborhood") as Node2D
	if neighborhood == null:
		push_error("Production preview has no CobraNeighborhood")
		quit(1)
		return
	var panel := scene.get_node_or_null("ReviewUI") as CanvasLayer
	if panel != null:
		panel.hide()
	var camera := Camera2D.new()
	camera.position = Vector2(7510, 1680)
	camera.zoom = Vector2.ONE * 0.73
	scene.add_child(camera)
	camera.make_current()
	var network := scene.get_node("RoadNetwork")
	if "draw_debug_lanes" in network:
		network.set("draw_debug_lanes", false)
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("D:/geteco/cobra-neighborhood-day.png")
	var weather := scene.get_node_or_null("DayNightWeather")
	if weather != null:
		weather.time_of_day = 0.9
		weather.set_biome(weather.current_biome)
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var night_result := root.get_texture().get_image().save_png("D:/geteco/cobra-neighborhood-night.png")
	print("COBRA_VISUAL day=%d night=%d" % [result, night_result])
	scene.queue_free()
	quit(0 if result == OK and night_result == OK else 1)
