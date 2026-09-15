extends SceneTree

func _init() -> void:
	var s = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(s)
	for i in 15: await physics_frame
	var cam = Camera2D.new()
	cam.position = Vector2(6350, -1370)
	cam.zoom = Vector2(1.2, 1.2)
	s.add_child(cam)
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/alive_service_cafe.png")
	print("CAPTURED")
	quit(0)


