extends SceneTree
var done := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var opening := preload("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.finished.connect(func(_destination): done = true)
	root.add_child(opening)
	var captured: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 55000
	while not done and Time.get_ticks_msec() < deadline:
		await process_frame
		var index: int = opening._shot_index
		if index in [0, 1, 3, 4, 9] and opening._shot_elapsed > 1.4 and not captured.has(index):
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png("D:/geteco/opening-v2-shot-%02d.png" % index)
			if error != OK:
				quit(1)
				return
			captured[index] = true
	print("OPENING_V2_RENDER finished=%s captures=%d" % [done, captured.size()])
	opening.queue_free()
	await process_frame
	quit(0 if done and captured.size() == 5 else 1)
