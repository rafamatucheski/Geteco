extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_res = load("res://prototypes/dante_cgi/DanteRealPlayerComparisonScene.tscn")
	if not scene_res:
		print("ERROR: Failed to load DanteRealPlayerComparisonScene.tscn")
		quit(1)
		return

	var scene_instance = scene_res.instantiate()
	root.add_child(scene_instance)

	# Estabilizar inicialização
	for i in range(25):
		await process_frame

	var viewport = root.get_viewport()
	var artifact_dir = "C:/Users/rafae/.gemini/antigravity/brain/ac7b8daf-4790-408c-8376-3690d7044e34"
	var dir = DirAccess.open("res://")

	# 1. Captura da visão geral estática de comparação lado a lado
	var img_static = viewport.get_texture().get_image()
	img_static.save_png("res://tests/dante_real_player_comparison.png")
	print("SAVED: res://tests/dante_real_player_comparison.png")

	# 2. Captura de sequência de frames para compilação do vídeo de animação
	var frame_dir = "res://tests/temp_dante_frames"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(frame_dir)):
		DirAccess.make_dir_absolute(ProjectSettings.globalize_path(frame_dir))

	var total_frames = 60 # 60 frames capturados a cada 2 ticks (~2 segundos de ciclo completo)
	for f in range(total_frames):
		# Avança 2 frames de processamento
		await process_frame
		await process_frame
		var frame_img = viewport.get_texture().get_image()
		frame_img.save_png("%s/frame_%03d.png" % [frame_dir, f])

	print("CAPTURED: %d animation frames in %s" % [total_frames, frame_dir])

	# Copiar imagem estática para artefatos
	if dir:
		dir.copy("res://tests/dante_real_player_comparison.png", artifact_dir + "/dante_real_player_comparison.png")

	print("DANTE_REAL_COMPARISON_FINISHED_SUCCESSFULLY")
	quit(0)
