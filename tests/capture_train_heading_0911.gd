extends SceneTree
var failures := 0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(900, 420)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var piece = preload("res://world/shared/rail/TrainPiece3D.gd").new()
	world.add_child(piece)
	piece.position = Vector2(450, 240)
	piece.scale = Vector2.ONE * 4.0
	# Let the new viewport finish its initial render before comparing cached poses.
	for i in 12: await process_frame
	for heading in [0.9, 0.0, 1.57, 0.0]:
		await physics_frame
		piece.update_heading(heading)
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw
		var suffix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
		root.get_texture().get_image().save_png("D:/geteco/artifacts/collision-fix-0911/train-%s-%.2f.png" % [suffix, heading])
		print("TRAIN heading=",heading," model=",piece.model.rotation.y)
		var cached: PackedByteArray = piece.viewport.get_texture().get_image().get_data()
		piece.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
		var refreshed: PackedByteArray = piece.viewport.get_texture().get_image().get_data()
		if cached != refreshed:
			var total_difference := 0.0
			for i in cached.size(): total_difference += abs(int(cached[i])-int(refreshed[i]))
			print("TRAIN_PIXEL_DIFFERENCE ",heading," average=",total_difference / maxf(1.0,cached.size()))
			failures += 1
			push_error("Cached train pose differs from its settled render at heading " + str(heading))
	world.queue_free()
	await process_frame
	print("TRAIN_CACHED_RENDER failures=", failures)
	quit(1 if failures else 0)
