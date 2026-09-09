extends SceneTree

var _has_run: bool = false

func _init() -> void:
	call_deferred("run")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if _has_run:
		return
	_has_run = true
	print("--- TESTE COMPLETO: FLUXO DE DIREÇÃO PONTE -> TÚNEL -> SERRA ---")
	var failures: int = 0
	
	var scene_resource = load("res://world/mountain_pass/MountainPass.tscn")
	var mountain_pass = scene_resource.instantiate()
	root.add_child(mountain_pass)
	current_scene = mountain_pass
	
	for i in 10: await process_frame
	
	var player = mountain_pass.get_node_or_null("Player") as CharacterBody2D
	var suv = mountain_pass.get_node_or_null("SummitSUV") as CharacterBody2D
	var tunnel = mountain_pass.get_node_or_null("MountainTunnel")
	var bridge = mountain_pass.get_node_or_null("HarborBridgeCrossing")
	
	if not player or not suv or not tunnel or not bridge:
		print("FALHA: Nós fundamentais ausentes!")
		quit(1)
		return
		
	print("1. Validação de instâncias:")
	print("   Player pos: ", player.global_position)
	print("   SUV pos: ", suv.global_position)
	print("   Bridge pos: ", bridge.global_position)
	print("   Tunnel pos: ", tunnel.global_position)
	
	# Garante que HarborBridge NÃO tem o trigger MountainPassCrossing na montanha
	if bridge.has_node("MountainPassCrossing"):
		print("FALHA CRÍTICA: HarborBridge possui MountainPassCrossing dentro de MountainPass! Isso causaria loop de recarga.")
		failures += 1
	else:
		print("SUCESSO: HarborBridge não possui MountainPassCrossing em MountainPass (sem conflito de recarga)!")

	# 2. Dante entra no SUV
	print("2. Dante entrando no Summit SUV...")
	suv.enter_vehicle(player)
	for i in 5: await process_frame
	
	if not suv.is_driven_by_player:
		print("FALHA: SUV não foi assumido pelo jogador!")
		failures += 1
	if player.visible:
		print("FALHA: Jogador continua visível após entrar no carro!")
		failures += 1
		
	# 3. Dirigir pela ponte passando por x = 4650 (antigo ponto crítico do crash)
	print("3. Conduzindo SUV pela ponte cruzando x = 4650...")
	for step in 60:
		suv.velocity = Vector2(480.0, 0.0)
		suv.global_position.x += 18.0
		await physics_frame
		
	print("   SUV passou por x = 4650! Posição atual: ", suv.global_position)
	print("   Player sincronizado em: ", player.global_position)
	if player.global_position.distance_to(suv.global_position) > 2.0:
		print("FALHA: Posição do jogador divergiu do carro durante a condução!")
		failures += 1
	else:
		print("SUCESSO: Posição do jogador acompanhou o carro em tempo real!")
		
	# 4. Entrar no Túnel (x = 4950 a 5800)
	print("4. Entrando no túnel subterrâneo (x = 4950 a 5800)...")
	for step in 30:
		suv.velocity = Vector2(480.0, 0.0)
		suv.global_position.x += 18.0
		await process_frame
		
	print("   Posição dentro do túnel: ", suv.global_position)
	# Espera o tween do cutaway completar (0.28s ~ 18 frames)
	for f in 25: await process_frame
	
	var is_cutaway_open: bool = tunnel.call("is_revealed")
	if not is_cutaway_open:
		print("FALHA: Mecânica de cutaway do teto do túnel não ativou ao entrar!")
		failures += 1
	else:
		print("SUCESSO: Mecânica de cutaway abriu o teto do túnel perfeitamente! is_revealed = true")

	# 5. Percorrer o túnel e sair no vale da serra (x > 5800)
	print("5. Atravessando e saindo do túnel...")
	for step in 50:
		suv.velocity = Vector2(480.0, 0.0)
		suv.global_position.x += 18.0
		await process_frame
		
	print("   Posição na saída do túnel: ", suv.global_position)
	# Espera o tween de fechamento do teto
	for f in 25: await process_frame
	
	var is_cutaway_closed: bool = not tunnel.call("is_revealed")
	if not is_cutaway_closed:
		print("FALHA: Teto do túnel não fechou após o veículo sair!")
		failures += 1
	else:
		print("SUCESSO: Teto do túnel fechou após a saída do veículo! is_revealed = false")
		
	# 6. Desembarcar do SUV
	print("6. Desembarcando do SUV...")
	suv.exit_vehicle()
	for f in 10: await process_frame
	
	print("   Player pos pós-desembarque: ", player.global_position)
	print("   SUV pos pós-desembarque: ", suv.global_position)
	var exit_dist = player.global_position.distance_to(suv.global_position)
	print("   Distância de desembarque: ", exit_dist)
	if exit_dist > 60.0:
		print("FALHA: Boneco teleportou para longe do carro ao sair! Distância: ", exit_dist)
		failures += 1
	else:
		print("SUCESSO: Boneco desembarcou exatamente ao lado da porta do SUV (dist = %.1f px)!" % exit_dist)
		
	if not player.visible:
		print("FALHA: Boneco permaneceu invisível após desembarcar!")
		failures += 1
	else:
		print("SUCESSO: Boneco visível e com controles ativos após desembarque!")

	print("--- FIM DO TESTE: %d FALHAS ---" % failures)
	mountain_pass.queue_free()
	for f in 2: await process_frame
	quit(0 if failures == 0 else 1)
