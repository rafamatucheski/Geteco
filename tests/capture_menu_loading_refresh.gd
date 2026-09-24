extends SceneTree

const OUTPUT := "res://docs/measurements/menu-loading-refresh-0920/"
const MINIMUM_ART_SIZE := Vector2i(1600, 900)
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok:
		failures.append(description)

func frames(count := 4) -> void:
	for _i in count:
		await process_frame

func capture(file_name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUTPUT + file_name)
	check(error == OK, "saved " + file_name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	change_scene_to_file("res://ui/MainMenu.tscn")
	await frames(12)
	await create_timer(0.8).timeout
	var presentation = current_scene.get_node("SunsetPresentation")
	var menu_art_size := Vector2i(presentation.background.texture.get_size())
	check(menu_art_size.x >= MINIMUM_ART_SIZE.x and menu_art_size.y >= MINIMUM_ART_SIZE.y,
		"menu source art is at least 1600x900")
	await capture("menu.png")
	for variant in 3:
		var layer := CanvasLayer.new()
		layer.layer = 220
		root.add_child(layer)
		var screen = preload("res://ui/LoadingScreen.gd").new()
		screen.variant = variant
		layer.add_child(screen)
		await frames(6)
		var loading_art_size := Vector2i(screen.get_node("Background").texture.get_size())
		check(loading_art_size.x >= MINIMUM_ART_SIZE.x and loading_art_size.y >= MINIMUM_ART_SIZE.y,
			"loading %d source art is at least 1600x900" % variant)
		screen.set_stage(0.52, "Carregando a cidade…")
		await capture("loading_%d.png" % variant)
		layer.queue_free()
		await frames()
	print("MENU_LOADING_REFRESH failures=", failures)
	quit(0 if failures.is_empty() else 1)
