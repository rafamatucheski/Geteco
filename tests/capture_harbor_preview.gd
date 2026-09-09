extends SceneTree

## Run with a real renderer (not --headless). Artifacts stay outside the repo.
func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(2000, 1100)
	root.content_scale_size = Vector2i(2000, 1100)
	var preview := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(preview)
	current_scene = preview
	for frame in 60:
		await process_frame
	var camera := preview.get_node("OverviewCamera") as Camera2D
	camera.zoom = Vector2.ONE * 0.12
	camera.position = Vector2(3320, -450)
	camera.make_current()
	await RenderingServer.frame_post_draw
	var output := "D:/geteco/harbor-overview.png"
	var result := root.get_texture().get_image().save_png(output)
	assert(result == OK)
	print("CAPTURE " + output)
	for shot in [["market", Vector2(1620, 900), 0.85], ["port", Vector2(3050, 1380), 0.60], ["garage", Vector2(1030, 1800), 0.9], ["bridge", Vector2(3790, 420), 0.9], ["northbank", Vector2(5530, 1230), 0.60], ["viaduct", Vector2(2110, 1050), 0.9], ["tunnel", Vector2(3100, 2870), 0.75], ["alleys", Vector2(850, 840), 1.0], ["local-streets", Vector2(5100, 1470), 0.72], ["north-expansion", Vector2(5550, -1070), 0.47], ["highway", Vector2(6000, -2990), 0.36], ["gateway-entrance", Vector2(6000, -1960), 0.82]]:
		camera.position = shot[1]
		camera.zoom = Vector2.ONE * shot[2]
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		output = "D:/geteco/harbor-%s.png" % shot[0]
		result = root.get_texture().get_image().save_png(output)
		assert(result == OK)
		print("CAPTURE " + output)
	# Observe the running train arriving naturally, without teleporting any actor.
	var train: Node2D = preview.get_node("FreightRail/AmbientTrain")
	Engine.time_scale = 4.0
	var approaching := false
	for frame in 2400:
		await physics_frame
		if train.global_position.distance_to(Vector2(3114, 3180)) < 70.0 and train.self_modulate.a > 0.5:
			approaching = true
			break
	Engine.time_scale = 1.0
	assert(approaching, "Actual train never approached the East Cut portal")
	camera.position = Vector2(3114, 3140)
	camera.zoom = Vector2.ONE * 1.3
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("D:/geteco/harbor-train-approach.png") == OK)
	print("CAPTURE D:/geteco/harbor-train-approach.png")
	var entered := false
	for frame in 360:
		await physics_frame
		if train.self_modulate.a < 0.1:
			entered = true
			break
	assert(entered, "Actual train failed to enter the tunnel")
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("D:/geteco/harbor-train-entering.png") == OK)
	print("CAPTURE D:/geteco/harbor-train-entering.png")
	quit(0)
