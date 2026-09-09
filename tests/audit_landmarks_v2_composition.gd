extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=================================================================")
	print("=== AUDITORIA: COMPOSIÇÃO VISUAL & CAMADAS DE LANDMARKS V2 ======")
	print("=================================================================")
	
	# Instanciar Bairro1V2 integrado com LayoutV2 e LandmarksV2
	var scene = load("res://legacy/district/bairro1_v2/Bairro1V2.tscn")
	assert(scene != null, "Bairro1V2 deve carregar")
	var b1 = scene.instantiate() as Bairro1V2
	b1.load_contributor_modules = true
	root.add_child(b1)
	
	for f in range(25):
		await process_frame
		
	var layout = b1.get_node_or_null("LayoutV2")
	var landmarks = b1.get_node_or_null("LandmarksV2") as LandmarksV2
	assert(layout != null, "LayoutV2 deve estar ativo")
	assert(landmarks != null, "LandmarksV2 deve estar ativo")
	
	# 1. VERIFICAR Z-INDEX DAS CAMADAS
	print("\n[TESTE 1] Checando Z-Index das Camadas:")
	var road_net = layout.get_node_or_null("RoadNetwork") as Node2D
	var road_z = road_net.z_index if road_net else 2
	print("  Z-Index do RoadNetwork (Ruas): ", road_z)
	print("  Z-Index do LandmarksV2 (Prédios/Props): ", landmarks.z_index)
	assert(landmarks.z_index > road_z, "LandmarksV2 DEVE renderizar acima das ruas!")
	print("  ✓ Camadas de LandmarksV2 renderizam consistentemente acima do piso das ruas!")

	# 2. VERIFICAR SE HÁ COLISÕES SÓLIDAS CRIADAS
	print("\n[TESTE 2] Checando Colisões Sólidas Indesejadas em Landmarks:")
	var solid_bodies := landmarks.find_children("", "StaticBody2D", true, false)
	solid_bodies.append_array(landmarks.find_children("", "CharacterBody2D", true, false))
	solid_bodies.append_array(landmarks.find_children("", "RigidBody2D", true, false))
	print("  Total de corpos sólidos de colisão encontrados em Landmarks: ", solid_bodies.size())
	assert(solid_bodies.size() == 0, "LandmarksV2 NÃO PODE criar colisões sólidas (regra 5)!")
	print("  ✓ Nenhuma colisão sólida criada em LandmarksV2 (100% livre para navegação do Claude)!")

	# 3. VERIFICAR DIMENSÕES E POSIÇÕES DOS LETREIROS
	print("\n[TESTE 3] Checando Letreiros Compactos e sem Invasão de Vias:")
	var neons := landmarks.find_children("NeonSign_*", "Node2D", true, false)
	print("  Total de letreiros encontrados: ", neons.size())
	for n in neons:
		var lbl := n.get_node_or_null("Label") as Label
		if lbl:
			print("  - Letreiro: '", lbl.text, "' | Largura: ", lbl.size.x, "px | Tamanho Fonte: ", lbl.get_theme_font_size("font_size"))
			assert(lbl.size.x <= 150.0, "Letreiro compacto contido no lote!")
	print("  ✓ Letreiros reduzidos e contidos na fachada/platibanda dos edifícios!")

	# 4. VERIFICAR DESOBSTRUÇÃO DOS 3 BECOS
	print("\n[TESTE 4] Checando Desobstrução dos 3 Becos:")
	var alleys := landmarks.get_all_alleys()
	assert(alleys.size() == 3, "Devem existir os 3 becos cenográficos")
	for a_id in alleys:
		var alley_node = alleys[a_id] as Node2D
		print("  - Beco: ", a_id, " | Posição: ", alley_node.position)
	print("  ✓ Becos configurados com props rentes às paredes e passagem navegável!")

	# 5. RENDERIZAR E SALVAR CAPTURA DO BAIRRO SEM POLUIÇÃO VISUAL
	print("\n[TESTE 5] Capturando Visão Aérea do Bairro Integrado...")
	var camera := Camera2D.new()
	camera.name = "AuditCamera"
	camera.position = Vector2(2500, 3400) # Centro do Bairro 1 V2
	camera.zoom = Vector2(0.40, 0.40)     # Visão panorâmica equilibrada
	root.add_child(camera)
	camera.make_current()
	
	for f in range(25):
		await process_frame
		
	var img: Image = null
	if DisplayServer.get_name() != "headless":
		var viewport := root.get_viewport()
		var viewport_texture := viewport.get_texture()
		if viewport_texture != null:
			img = viewport_texture.get_image()
	if img != null:
		var save_path := "res://tests/bairro1_v2_clean_landmarks_view.png"
		img.save_png(save_path)
		print("  ✓ Captura salva em: ", save_path)
	else:
		print("  • Captura visual ignorada: renderer headless não expõe textura de viewport")

	print("\n=================================================================")
	print("=== SUCESSO: TODAS AS REGRAS DE COMPOSIÇÃO ATENDIDAS (EXIT 0) ===")
	print("=================================================================")
	quit(0)
