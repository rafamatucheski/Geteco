extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene = load("res://legacy/Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	
	for i in range(15):
		await process_frame

	# Olhar para a calçada perto do Distrito Misto / Lojas (Y = 1180, X = 1350)
	var camera = main.get_node_or_null("Camera2D")
	if camera:
		camera.global_position = Vector2(1350, 1180)
		
	# Esperar alguns frames para os pedestres caminharem e se distribuírem
	for i in range(40):
		await process_frame
		
	var viewport = root.get_viewport()
	var img = viewport.get_texture().get_image()
	img.save_png("res://tests/pedestrians_ambient_view.png")
	print("SAVED: res://tests/pedestrians_ambient_view.png")
	quit(0)
