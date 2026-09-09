extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene = load("res://legacy/Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	
	for i in range(15):
		await process_frame

	var player = main.get_node_or_null("Player")
	if player:
		# Posicionar o Player exatamente embaixo do prédio na calçada/pista
		player.global_position = Vector2(1380, 1135)
		
	var camera = main.get_node_or_null("Camera2D")
	if camera:
		camera.global_position = Vector2(1380, 1135)
		
	for i in range(20):
		await process_frame
		
	var viewport = root.get_viewport()
	var img = viewport.get_texture().get_image()
	img.save_png("res://tests/building_pass_through_view.png")
	print("SAVED: res://tests/building_pass_through_view.png")
	quit(0)
