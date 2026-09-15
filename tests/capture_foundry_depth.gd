extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1400, 800)
	root.content_scale_size = root.size
	var scene := Node2D.new()
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(400, 400), Vector2(1300, 400), Vector2(1300, 950), Vector2(400, 950)])
	ground.color = Color("#a69f8c")
	scene.add_child(ground)
	for item in [["FoundryTerraceWest", Vector2(621, 640), Vector2(210, 230), "rowhouse_terrace"], ["FoundryTerraceEast", Vector2(855, 640), Vector2(210, 230), "rowhouse_terrace"], ["FoundryLofts", Vector2(1077, 655), Vector2(186, 260), "l_shaped_block"]]:
		var building := load("res://world/harbor/HarborBuilding.gd").new() as Node2D
		building.name = item[0]
		building.position = item[1]
		building.footprint = item[2]
		building.building_kind = item[3]
		scene.add_child(building)
	var camera := Camera2D.new()
	scene.add_child(camera)
	root.add_child(scene)
	current_scene = scene
	for frame in 30:
		await process_frame
	camera.make_current()
	camera.global_position = Vector2(855, 680)
	camera.zoom = Vector2.ONE * 1.75
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/foundry-depth")
	var result := root.get_texture().get_image().save_png("D:/geteco/artifacts/foundry-depth/after.png")
	assert(result == OK)
	print("FOUNDRY_DEPTH_CAPTURE_OK")
	quit()
