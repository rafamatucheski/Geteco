extends SceneTree

func _init() -> void:
	call_deferred("_render_alley_police")

func _render_alley_police() -> void:
	var viewport = root.get_viewport()
	viewport.size = Vector2i(1024, 768)
	
	var depots_scene = load("res://world/shared/emergency/EmergencyDepots.tscn") as PackedScene
	var depots = depots_scene.instantiate()
	root.add_child(depots)
	
	# Adiciona câmera focada no beco das viaturas (X=570, Y=1050)
	var cam = Camera2D.new()
	cam.position = Vector2(570, 1050)
	cam.zoom = Vector2(2.2, 2.2)
	root.add_child(cam)
	cam.make_current()
	
	for i in 10:
		await process_frame
		
	var img = viewport.get_texture().get_image()
	img.save_png("res://tests/police_alley_view.png")
	print("SCREENSHOT_SAVED: res://tests/police_alley_view.png")
	quit(0)
