extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440,1000)
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while not scene.world_build_ready: await process_frame
	for i in 10: await process_frame
	var port = scene.get_node("SouthPort")
	var camera = scene.get_node("OverviewCamera")
	camera.make_current()
	camera.position = Vector2(4680,4360)
	camera.zoom = Vector2.ONE*.65
	scene.get_node("Player").position = Vector2(4700,4220)
	port.checkpoint.set_process(false)
	port.checkpoint.panel.hide()
	assert(port.workers.size() == 32)
	assert(get_nodes_in_group("port_floodlight").size() == 8)
	scene.weather.is_dynamic_time = false
	scene.weather.weather_state = 0
	for night in [false,true]:
		scene.weather.time_of_day = .0 if night else .5
		scene.weather._update_lighting()
		for light in get_nodes_in_group("port_floodlight"):
			assert(light.is_lit == night)
			assert(light.pools.size() == 2)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/port-dressing-%s.png" % ("night" if night else "day"))
	print("PORT_DRESSING_PASS workers=32 cargo_groups=12 twin_floodlights=8 day/night=OK")
	quit()
