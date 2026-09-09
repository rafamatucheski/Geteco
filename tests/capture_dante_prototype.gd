extends SceneTree

const SCENE_PATH := "res://prototypes/dante_cgi/DanteComparisonScene.tscn"

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)

	var scene := load(SCENE_PATH).instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene

	# Avançar alguns frames para inicialização do viewport e renderização dos materiais
	for f in 40:
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var out_path := "d:/geteco/game/tests/dante_cgi_comparison.png"
	var err := img.save_png(out_path)
	assert(err == OK, "Falha ao salvar captura do protótipo Dante: " + out_path)
	print("DANTE_PROTOTYPE_CAPTURED: " + out_path)

	quit(0)
