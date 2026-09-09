extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var opening := preload("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.show_studio_intro = true
	root.add_child(opening)
	await create_timer(1.9).timeout
	await shot("D:/geteco/rcm-studios-intro.png")
	await create_timer(2.9).timeout
	await shot("D:/geteco/rcm-harbor-card.png")
	await create_timer(3.0).timeout
	await shot("D:/geteco/rcm-cgi-transition.png")
	preload("res://district/harbor_preview/HarborAudioBank.gd").sound("logo").save_to_wav("D:/geteco/rcm-studios-signature.wav")
	opening.queue_free()
	await process_frame
	quit()
