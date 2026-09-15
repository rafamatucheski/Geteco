extends SceneTree

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=================================================================")
	print("=== TESTE: PREDIO PROPRIO DO IML E CONTROLE DE BOMBEIROS =======")
	print("=================================================================")

	var central_script = load("res://legacy/CentralDistrict.gd")
	var central = central_script.new()

	# 1. Verificar lote da CLINICA (Hospital)
	print("[PASSO 1] Verificando lote do Hospital (CLINICA)...")
	var clinica_block: Dictionary = {}
	var docas_block: Dictionary = {}
	for b in central.blocks:
		if b.id == "CLINICA": clinica_block = b
		elif b.id == "DOCAS": docas_block = b

	var clinica_kinds: Array[String] = []
	for lot in clinica_block.get("lots", []):
		clinica_kinds.append(String(lot.get("kind", "")))

	print("  Lots em CLINICA: %s" % str(clinica_kinds))
	assert(not clinica_kinds.has("morgue"), "CLINICA nao pode ter morgue/IML grudada no hospital!")
	assert(clinica_kinds.has("hospital"), "CLINICA deve conter o hospital")
	assert(clinica_kinds.has("park"), "CLINICA deve conter o jardim/praca do hospital")
	print("  ✓ Hospital liberado com jardim proprio, sem IML no lote!")

	# 2. Verificar novo predio do IML em DOCAS
	print("[PASSO 2] Verificando predio proprio do IML em DOCAS...")
	var iml_found := false
	var iml_size := Vector2.ZERO
	for lot in docas_block.get("lots", []):
		if String(lot.get("kind", "")) == "morgue":
			iml_found = true
			iml_size = (lot.get("rect") as Rect2).size
			break

	assert(iml_found, "DOCAS deve conter o predio do IML (morgue)")
	assert(iml_size.x >= 200.0 and iml_size.y >= 120.0, "IML deve ter dimensoes de predio proprio (254x160)")
	print("  Tamanho do IML: %s" % str(iml_size))
	print("  ✓ IML possui predio proprio dedicado e robusto nas DOCAS!")

	# 3. Testar controle de despacho de bombeiros
	print("[PASSO 3] Testando filtro de despacho de bombeiros...")
	var traffic_script = load("res://cars/traffic/TrafficVehicle.gd")
	var car = traffic_script.new()
	root.add_child(car)
	await process_frame

	car.global_position = Vector2(2500, 2500) # Longe do jogador
	car._dispatch_fire_truck()
	assert(car._fire_truck_dispatched == false, "Acidentes de IA ao longe nao devem despachar bombeiros 'do nada'!")
	print("  ✓ Veiculo distante nao despachou bombeiros 'do nada'!")

	# 4. Testar sirene do caminhao de bombeiros ao perder alvo
	print("[PASSO 4] Testando desligamento de sirene de bombeiros sem ocorrencia...")
	var em_script = load("res://emergency/EmergencyVehicle.gd")
	var em_truck = em_script.new()
	em_truck.type = 2 # FIRE
	root.add_child(em_truck)
	await process_frame

	em_truck.target = null
	em_truck._physics_process(0.1)
	assert(em_truck.is_returning_to_base or not em_truck.visible, "Caminhao sem ocorrencia ativa deve retornar ou desativar")
	print("  ✓ Sirene desligada e caminhao retornado a base com seguranca!")

	print("=================================================================")
	print("=== SUCESSO: TESTE DO IML E BOMBEIROS APROVADO! (EXIT 0) ========")
	print("=================================================================")
	quit(0)
