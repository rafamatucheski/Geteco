extends SceneTree

func _init() -> void:
	call_deferred("_render_interstate_junction")

func _render_interstate_junction() -> void:
	var viewport = root.get_viewport()
	viewport.size = Vector2i(1024, 768)
	
	var main_scene = load("res://legacy/Main.tscn") as PackedScene
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	var cam = Camera2D.new()
	cam.position = Vector2(870, 1260)
	cam.zoom = Vector2(1.6, 1.6)
	root.add_child(cam)
	cam.make_current()
	
	for i in 15:
		await process_frame
		
	var img = viewport.get_texture().get_image()
	img.save_png("res://tests/interstate_junction_after.png")
	print("SAVED: res://tests/interstate_junction_after.png")
	quit(0)
