extends SceneTree
## Capturas do menu principal animado, das três abas de Configurações e da tela de
## carregamento, em 1280x720 com renderização real. Saída em evidence/menu-refresh-20260925.

const OUTPUT := "res://evidence/menu-refresh-20260925/"

func _initialize() -> void: run.call_deferred()

func shot(file_name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + file_name))
	print("CAPTURE ", file_name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://ui/MainMenu.tscn")
	await create_timer(2.5).timeout
	await shot("menu_a.png")
	await create_timer(3.0).timeout
	await shot("menu_b.png")
	var menu := current_scene
	menu._open_settings()
	for tab in 3:
		menu.settings._select_tab(tab)
		await create_timer(.3).timeout
		await shot("settings_%d.png" % tab)
	menu.settings.close()
	for variant in 3:
		var curtain = load("res://runtime/StartupCurtain.gd").new()
		curtain.variant = variant
		root.add_child(curtain)
		curtain.set_stage(.46, "Preparando texturas e prédios…")
		await create_timer(1.2).timeout
		await shot("loading_%d.png" % variant)
		curtain.queue_free()
		await process_frame
	quit(0)
