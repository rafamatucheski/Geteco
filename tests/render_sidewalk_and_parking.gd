extends SceneTree

func _init() -> void:
	call_deferred("_render_views")

func _render_views() -> void:
	var viewport = root.get_viewport()
	viewport.size = Vector2i(1024, 768)
	
	var main_scene = load("res://legacy/Main.tscn") as PackedScene
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	var cam = Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	cam.zoom = Vector2(2.0, 2.0)
	
	for i in 12:
		await process_frame
		
	# 1. Foto do local anterior (a calçada que estava entulhada em X=740, Y=1500)
	cam.position = Vector2(740, 1500)
	await process_frame
	await process_frame
	var img1 = viewport.get_texture().get_image()
	img1.save_png("res://tests/sidewalk_cleaned_view.png")
	print("SAVED: res://tests/sidewalk_cleaned_view.png")
	
	# 2. Foto do novo estacionamento comercial organizado (X=310, Y=1910)
	cam.position = Vector2(310, 1910)
	await process_frame
	await process_frame
	var img2 = viewport.get_texture().get_image()
	img2.save_png("res://tests/commercial_parking_view.png")
	print("SAVED: res://tests/commercial_parking_view.png")
	
	quit(0)
