extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene = load("res://Main.tscn")
	var main = main_scene.instantiate()
	root.add_child(main)
	
	for i in range(15):
		await process_frame

	var player = main.get_node_or_null("Player")
	if player:
		player.global_position = Vector2(1120, 280)
	for i in range(15):
		await process_frame
		
	var viewport = root.get_viewport()
	var img1 = viewport.get_texture().get_image()
	img1.save_png("res://tests/hospital_clean_plaza_view.png")
	print("SAVED: res://tests/hospital_clean_plaza_view.png")

	# 2. Foto do novo Prédio Próprio do IML nas DOCAS (X = 550, Y = 840)
	if player:
		player.global_position = Vector2(550, 840)
	for i in range(20):
		await process_frame
		
	var img2 = viewport.get_texture().get_image()
	img2.save_png("res://tests/iml_dedicated_building_view.png")
	print("SAVED: res://tests/iml_dedicated_building_view.png")

	quit(0)
