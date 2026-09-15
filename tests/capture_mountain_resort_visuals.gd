extends SceneTree

const OUT_DIR := "D:/geteco/artifacts/resort-road-repair/review"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)

	var mountain := preload("res://world/mountain_pass/MountainPass.gd").new()
	mountain.streamed_region = false
	mountain.spawn_player_on_ready = false
	root.get_node("SaveManager")._save_dir = OUT_DIR + "/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.add_child(mountain)
	current_scene = mountain

	var camera := Camera2D.new()
	camera.name = "CaptureCamera"
	root.add_child(camera)
	camera.set_meta("mountain_fixed_framing", true)
	camera.make_current()

	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	while not mountain.region_ready: await process_frame
	for i in 60: await process_frame
	camera.make_current()

	# 1. Captura do Heliponto e Bunker
	camera.zoom = Vector2.ONE * 1.5
	camera.position = Vector2(6450, -2750)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_DIR + "/helipad_architectural_platform.png")
	print("Salvo: ", OUT_DIR + "/helipad_architectural_platform.png")

	# 2. Captura da Conexão Asfáltica e Porte-Cochère do Resort
	camera.zoom = Vector2.ONE * 1.2
	camera.position = Vector2(6880, -2530)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_DIR + "/resort_asphalt_concourse.png")
	print("Salvo: ", OUT_DIR + "/resort_asphalt_concourse.png")

	# 3. Captura da Promenade, Chalé e Boutique Alpina
	camera.zoom = Vector2.ONE * 1.45
	camera.position = Vector2(7200, -2720)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_DIR + "/resort_promenade_and_shops.png")
	print("Salvo: ", OUT_DIR + "/resort_promenade_and_shops.png")

	quit(0)
