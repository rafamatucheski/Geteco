extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var proposal_scene = load("res://prototypes/garage/GarageVisualProposal.tscn")
	if not proposal_scene:
		print("ERROR: Failed to load GarageVisualProposal.tscn")
		quit(1)
		return

	var scene_instance = proposal_scene.instantiate()
	root.add_child(scene_instance)

	for i in range(20):
		await process_frame

	var viewport = root.get_viewport()
	var artifact_dir = "C:/Users/rafae/.gemini/antigravity/brain/ac7b8daf-4790-408c-8376-3690d7044e34"
	var dir = DirAccess.open("res://")

	# 1. Capturar visão visual de gameplay realista geral
	scene_instance.set("show_circulation_plan", false)
	scene_instance.call("set_camera_view", Vector2(0, 0), Vector2(1.55, 1.55))
	for i in range(12):
		await process_frame

	var img_visual = viewport.get_texture().get_image()
	img_visual.save_png("res://tests/garage_proposal_visual.png")
	print("SAVED: res://tests/garage_proposal_visual.png")

	# 2. Capturar planta de circulação técnica e pontos de interação
	scene_instance.set("show_circulation_plan", true)
	for i in range(12):
		await process_frame

	var img_circ = viewport.get_texture().get_image()
	img_circ.save_png("res://tests/garage_proposal_circulation.png")
	print("SAVED: res://tests/garage_proposal_circulation.png")

	# 3. Detalhe 1: Baia do Elevador Automotivo, Carro Esportivo e Bancada
	scene_instance.set("show_circulation_plan", false)
	scene_instance.call("set_camera_view", Vector2(140, -80), Vector2(2.5, 2.5))
	for i in range(12):
		await process_frame

	var img_detail_lift = viewport.get_texture().get_image()
	img_detail_lift.save_png("res://tests/garage_proposal_detail_lift.png")
	print("SAVED: res://tests/garage_proposal_detail_lift.png")

	# 4. Detalhe 2: Lounge VIP do Maciota e Quadro de Missões
	scene_instance.call("set_camera_view", Vector2(-190, -40), Vector2(2.4, 2.4))
	for i in range(12):
		await process_frame

	var img_detail_lounge = viewport.get_texture().get_image()
	img_detail_lounge.save_png("res://tests/garage_proposal_detail_lounge.png")
	print("SAVED: res://tests/garage_proposal_detail_lounge.png")

	# Copiar todos para o diretório de artefatos
	if dir:
		dir.copy("res://tests/garage_proposal_visual.png", artifact_dir + "/garage_proposal_visual.png")
		dir.copy("res://tests/garage_proposal_circulation.png", artifact_dir + "/garage_proposal_circulation.png")
		dir.copy("res://tests/garage_proposal_detail_lift.png", artifact_dir + "/garage_proposal_detail_lift.png")
		dir.copy("res://tests/garage_proposal_detail_lounge.png", artifact_dir + "/garage_proposal_detail_lounge.png")

	print("ALL_GARAGE_PROPOSALS_CAPTURED_SUCCESSFULLY")
	quit(0)
