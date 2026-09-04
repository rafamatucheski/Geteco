extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=================================================================")
	print("=== TESTE: LANDMARKS V2 - VINCULAÇÃO DINÂMICA COM MARKER2D ======")
	print("=================================================================")
	
	# Simular cena Bairro1V2 contendo LayoutV2 com markers customizados
	var bairro_root := Node2D.new()
	bairro_root.name = "Bairro1V2"
	root.add_child(bairro_root)
	
	var layout := Node2D.new()
	layout.name = "LayoutV2"
	bairro_root.add_child(layout)
	
	# Adicionar marcadores simulados do Claude
	var markers_data := {
		"MarketEntrance": Vector2(920, 610),
		"TerminalStop": Vector2(1710, 720),
		"ParkEntrance": Vector2(380, 1020),
		"GarageEntrance": Vector2(1280, 1220),
		"WarehouseEntrance": Vector2(1820, 1390),
		"RailUnderpass": Vector2(1150, 1780),
		"PlayerSpawn": Vector2(800, 960)
	}
	for m_name in markers_data:
		var m := Marker2D.new()
		m.name = m_name
		m.position = markers_data[m_name]
		layout.add_child(m)
		
	var scene = load("res://district/bairro1_v2/landmarks/LandmarksV2.tscn")
	var landmarks = scene.instantiate()
	bairro_root.add_child(landmarks)
	
	for f in range(15):
		await process_frame
		
	print("Verificando se marcos alinharam com os marcadores do Layout:")
	var market = landmarks.get_landmark("market")
	assert(market != null, "Mercado deve existir")
	print("  ✓ Mercado posicionado em: ", market.position, " (Esperado em torno de Y=610 - 90 = 520, X=920)")
	assert(absf(market.position.x - 920.0) < 1.0, "Mercado alinhado com X do MarketEntrance")
	
	var terminal = landmarks.get_landmark("terminal")
	assert(terminal != null, "Terminal deve existir")
	print("  ✓ Terminal posicionado em: ", terminal.position, " (Esperado X=1710)")
	assert(absf(terminal.position.x - 1710.0) < 1.0, "Terminal alinhado com X do TerminalStop")
	
	var garage = landmarks.get_landmark("garage")
	assert(garage != null, "Oficina deve existir")
	print("  ✓ Oficina posicionada em: ", garage.position, " (Esperado X=1280)")
	assert(absf(garage.position.x - 1280.0) < 1.0, "Oficina alinhada com X do GarageEntrance")
	
	print("\n=================================================================")
	print("=== SUCESSO: VINCULAÇÃO DINÂMICA COM LAYOUT APROVADA (EXIT 0) ===")
	print("=================================================================")
	quit(0)
