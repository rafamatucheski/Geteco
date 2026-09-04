extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=================================================================")
	print("=== TESTE: LANDMARKS V2 - MARCOS URBANOS & IDENTIDADE VISUAL ====")
	print("=================================================================")
	
	var scene = load("res://district/bairro1_v2/landmarks/LandmarksV2.tscn")
	assert(scene != null, "LandmarksV2.tscn deve carregar com sucesso!")
	
	var landmarks = scene.instantiate()
	assert(landmarks != null, "LandmarksV2 deve instanciar com sucesso!")
	root.add_child(landmarks)
	
	# Aguardar construcao
	for f in range(15):
		await process_frame
		
	var summary = landmarks.get_landmark_summary()
	print("Total de Marcos Unicos Criados: ", summary.size())
	for item in summary:
		print("  - Marco: %s | Titulo: '%s' | Posicao: %s | Dimensoes: %s" % [
			item.name, item.title, item.position, item.footprint
		])
	assert(summary.size() >= 8, "Devem haver pelo menos 8 marcos unicos instanciados!")
	
	var alleys = landmarks.get_all_alleys()
	print("Total de Becos Cenograficos Criados: ", alleys.size())
	for alley_id in alleys:
		print("  - Beco: ", alley_id, " | No: ", alleys[alley_id].name)
	assert(alleys.size() == 3, "Devem haver exatamente os 3 becos cenograficos do plano!")
	
	var lamps = root.find_children("", "PointLight2D", true, false)
	print("Total de Fontes de Luz / Neons: ", lamps.size())
	assert(lamps.size() > 10, "A rede de iluminacao noturna deve possuir luzes ativas!")
	
	print("\n=================================================================")
	print("=== SUCESSO: TESTE LANDMARKS V2 APROVADO COM EXITO (EXIT 0) =====")
	print("=================================================================")
	quit(0)
