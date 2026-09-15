extends SceneTree

const OUTPUT := "D:/geteco/artifacts/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(120.0).timeout.connect(func(): quit(2))
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	while current_scene == null or not current_scene.region_ready:
		await process_frame
	var mountain = current_scene
	var player = mountain.player_instance
	player.set_physics_process(false)
	player.mountain_thermal_coat = true
	player.health = player.max_health
	mountain.cold_controller.set_process(false)
	mountain.parallax.hide()
	mountain.storm_manager.dynamic_weather = false
	mountain.storm_manager.hide()
	for node in mountain.find_children("*", "Camera2D", true, false):
		node.enabled = false
	var camera := Camera2D.new()
	mountain.add_child(camera)
	camera.make_current()
	await _shot(camera, Vector2(7140, -2760), Vector2.ONE * 1.02, "mountain-ski-lodge.png")
	player.money = 1000
	player.begin_ski_rental(250)
	player.take_ski_equipment()
	player.global_position = Vector2(7000, -3460)
	player.start_skiing(Vector2.UP)
	for i in 120:
		await process_frame
	await _shot(camera, Vector2(7000, -3540), Vector2.ONE * 0.78, "mountain-ski-slopes.png")
	await _shot(camera, player.global_position, Vector2.ONE * 2.2, "mountain-ski-action.png")
	await _shot(camera, Vector2(6345, -415), Vector2.ONE * 1.55, "mountain-waterfall-cave.png")
	mountain.interior_manager._interiors[&"ski_lodge"].set_npc_rendering_active(true)
	await _shot(camera, Vector2(36500, 20000), Vector2.ONE * 0.92, "mountain-ski-lodge-interior.png")
	mountain.interior_manager._interiors[&"ski_lodge"].set_npc_rendering_active(false)
	mountain.interior_manager._interiors[&"mountain_mystery_cave"].set_npc_rendering_active(true)
	await _shot(camera, Vector2(40000, 20000), Vector2.ONE * 0.92, "mountain-mystery-cave-interior.png")
	mountain.interior_manager._interiors[&"mountain_mystery_cave"].set_npc_rendering_active(false)
	for id in ["mountain_expedition_pack", "mountain_expedition_journal", "mountain_expedition_camera"]:
		player.add_collectible(id, id, player.global_position)
	player.global_position = Vector2(7350, -4140)
	for i in 24:
		await process_frame
	await _shot(camera, Vector2(7480, -4140), Vector2.ONE * 1.8, "mountain-monster-sighting.png")
	quit()

func _shot(camera: Camera2D, point: Vector2, zoom: Vector2, filename: String) -> void:
	camera.global_position = point
	camera.zoom = zoom
	camera.reset_smoothing()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(filename))
