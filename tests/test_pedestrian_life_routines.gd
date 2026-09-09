extends SceneTree

func _init() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=================================================================")
	print("=== TESTE: ROTINAS DE VIDA DOS PEDESTRES & ANTI-AGLOMERACAO =====")
	print("=================================================================")

	var ped_script = load("res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd")
	var building_script = load("res://ProceduralBuilding.gd")

	# 1. Testar desincronizacao de passos e offsets laterais
	print("[PASSO 1] Testando desincronizacao de strides e espalhamento lateral...")
	var test_route := PackedVector2Array([Vector2(100, 200), Vector2(600, 200)])
	var p1 = ped_script.new()
	p1.configure_authored_route(test_route, "test_route", 0.0)
	root.add_child(p1)

	var p2 = ped_script.new()
	p2.configure_authored_route(test_route, "test_route", 50.0)
	root.add_child(p2)

	await process_frame

	print("  P1: walk_timer=%.2f, stride_mult=%.2f, lateral_offset=%.2f" % [p1.walk_timer, p1.stride_freq_mult, p1.lateral_offset])
	print("  P2: walk_timer=%.2f, stride_mult=%.2f, lateral_offset=%.2f" % [p2.walk_timer, p2.stride_freq_mult, p2.lateral_offset])

	assert(absf(p1.walk_timer - p2.walk_timer) > 0.1, "Pedestres devem ter fases iniciais desincronizadas")
	assert(absf(p1.lateral_offset - p2.lateral_offset) > 0.1, "Pedestres devem ter faixas laterais distintas")
	print("  ✓ Pedestres nao andam mais em fila indiana nem sincronizados!")

	# 2. Testar que quando parado, as pernas ficam paradas (idle)
	print("[PASSO 2] Testando postura e animacao quando parado...")
	p1.velocity = Vector2.ZERO
	var prev_timer = p1.walk_timer
	p1._physics_process(0.1)
	assert(p1.walk_timer == prev_timer, "Walk timer nao deve avancar quando a velocidade e zero")
	print("  ✓ Pedestres parados nao ficam correndo no lugar contra postes!")

	# 3. Testar rotina de visita a restaurante/loja
	print("[PASSO 3] Criando restaurante/diner e testando visita do pedestre...")
	var diner = building_script.new()
	diner.name = "CentralDiner"
	diner.building_kind = "corner_shop"
	diner.footprint = Vector2(160, 120)
	diner.position = Vector2(250, 140)
	root.add_child(diner)
	await process_frame

	p1.global_position = Vector2(250, 200) # Na calcada em frente ao restaurante
	p1.visit_cooldown = 0.0
	p1._update_ambient_life(0.01)

	assert(p1.is_visiting, "Pedestre deve ter iniciado a rotina de visitar o restaurante")
	print("  ✓ Pedestre escolheu visitar o restaurante e foi em direcao a porta!")

	# Simular chegada na porta
	p1.global_position = p1._visiting_door_pos
	p1._update_ambient_life(0.01)

	assert(p1._visiting_timer > 0.0, "Pedestre deve ter entrado e iniciado o timer de refeicao/compras")
	assert(p1.collision_layer == 0, "Colisao deve ser desativada enquanto esta dentro comendo")
	print("  ✓ Pedestre entrou para comer/fazer lanche (fade out e colisao suspensa)")

	# Simular conclusao da refeicao
	p1._visiting_timer = 0.05
	p1._update_ambient_life(0.1)

	assert(not p1.is_visiting, "Apos comer, deve sair do modo visiting")
	assert(p1.collision_layer == 4, "Colisao deve ser restaurada ao sair na calcada")
	print("  ✓ Pedestre terminou o lanche, saiu revigorado e retomou a caminhada!")

	print("=================================================================")
	print("=== SUCESSO: TESTES DE ROTINA AMBIENTAL APROVADOS! (EXIT 0) =====")
	print("=================================================================")
	quit(0)
