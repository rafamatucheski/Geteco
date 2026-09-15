extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var road = preload("res://world/mountain_pass/MountainPassRoad.gd").new()
	root.add_child(road)
	var terrain := Polygon2D.new()
	terrain.polygon = PackedVector2Array([Vector2(5000,-3000),Vector2(8000,-3000),Vector2(8000,1000),Vector2(5000,1000)])
	terrain.z_index = -3
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").apply(terrain,"forest")
	root.add_child(terrain)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.zoom = Vector2.ONE*1.2
	camera.position = Vector2(6940,-250)
	camera.make_current()
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/mountain-cliffs-0912/final-road-detail.png")
	quit()
