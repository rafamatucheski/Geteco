extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	var background := TextureRect.new()
	background.texture = ImageTexture.create_from_image(Image.load_from_file("res://evidence/race-phone-20261002/final/night-rain.png"))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(background)
	var prompt := preload("res://ui/hud/InteractionPrompt.gd").new()
	root.add_child(prompt)
	prompt.update_prompt("E  Atender telefone","interact",root.get_node("GameInput"))
	await create_timer(.4).timeout
	prompt.follow_actor(null,null,Vector2(1920,1080))
	await process_frame
	var ok: bool = prompt.caption.text == "Atender" and prompt.key.visible and prompt.size.y < 45
	DirAccess.make_dir_recursive_absolute("res://evidence/footer-prompt-20261002")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/footer-prompt-20261002/preview.png")
	prompt.update_prompt("","interact",root.get_node("GameInput"))
	ok = ok and not prompt.visible
	print("FOOTER_ISOLATED ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
