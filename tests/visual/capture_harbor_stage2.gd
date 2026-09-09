extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	var scene := load("res://district/harbor_preview/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for i in 12:
		await process_frame
	var ui := scene.get_node_or_null("ReviewUI") as CanvasLayer
	if ui: ui.hide()
	scene.get_node("RoadNetwork").set("draw_debug_lanes",false)
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.make_current()
	var views := [{"id":"lofts","at":Vector2(945,745),"zoom":1.8},{"id":"east","at":Vector2(5550,1380),"zoom":0.48},{"id":"north","at":Vector2(5550,-1110),"zoom":0.5}]
	var failures := 0
	for view in views:
		camera.global_position = view.at
		camera.zoom = Vector2.ONE*float(view.zoom)
		for night in [false,true]:
			scene.weather.time_of_day = 0.9 if night else 0.45
			scene.weather.set_biome(scene.weather.current_biome)
			for i in 20:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "D:/geteco/harbor-stage2-%s-%s.png" % [view.id,"night" if night else "day"]
			var result := root.get_texture().get_image().save_png(path)
			print("STAGE2_CAPTURE ",path," result=",result)
			if result != OK: failures += 1
	scene.queue_free()
	quit(0 if failures==0 else 1)
