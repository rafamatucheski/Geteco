extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	var scene := Node2D.new()
	root.add_child(scene)
	var script := GDScript.new()
	script.source_code = "extends Node\nvar collectibles_found: Array = ['harbor_col_navio_01','harbor_col_cobras_01','legacy_record']\n"
	script.reload()
	var player := Node.new()
	player.set_script(script)
	player.add_to_group("player")
	scene.add_child(player)
	var menu := preload("res://ui/PauseMenu.tscn").instantiate()
	scene.add_child(menu)
	menu.pause_game()
	menu._on_collectibles_pressed()
	for locale in ["pt_BR","en"]:
		TranslationServer.set_locale(locale)
		menu._on_language_changed(locale)
		for i in 8: await process_frame
		print("COLLECTION LOCALE ",locale,": ",menu.get_node("%CollectiblesModalTitle").text)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/collectibles-"+locale+".png")
	menu.resume_game()
	scene.queue_free()
	for i in 3: await process_frame
	quit()
