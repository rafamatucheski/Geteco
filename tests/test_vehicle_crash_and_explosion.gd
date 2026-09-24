extends SceneTree

func _init() -> void:
	call_deferred("_run_crash_test")

func _run_crash_test() -> void:
	print("=================================================================")
	print("=== TESTE DE IMPACTO, RUPTURA E EXPLOSÃO VEICULAR (SEM SQUASH) ===")
	print("=================================================================")
	
	var failures: Array[String] = []
	
	# 1. Instanciar TrafficVehicle (Carro usado na foto do jogador)
	var vehicle_scene = load("res://cars/traffic/TrafficVehicle.tscn")
	if not vehicle_scene:
		printerr("Falha ao carregar TrafficVehicle.tscn")
		quit(1)
		return
		
	var car = vehicle_scene.instantiate()
	root.add_child(car)
	await process_frame
	await process_frame
	
	var initial_scale: Vector2 = car.visual.scale
	var initial_pos: Vector2 = car.visual.position
	var initial_skew: float = car.visual.skew
	print("[PASSO 1] Estado inicial do veículo:")
	print("  - Escala visual: %s" % str(initial_scale))
	print("  - Posição visual: %s" % str(initial_pos))
	print("  - Skew visual: %f" % initial_skew)
	
	# 2. Simular impactos violentos repetidos de diferentes ângulos
	print("\n[PASSO 2] Simulando múltiplos impactos severos (450 px/s)...")
	var normals = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]
	for norm in normals:
		car._apply_crash_deformation(norm, 450.0, car.global_position + norm * 30.0)
	
	print("  - Escala após 5 batidas: %s" % str(car.visual.scale))
	print("  - Posição após 5 batidas: %s" % str(car.visual.position))
	print("  - Skew após 5 batidas: %f" % car.visual.skew)
	
	if car.visual.scale != initial_scale:
		failures.append("A escala do carro foi alterada durante a colisão! Esperado %s, obtido %s" % [str(initial_scale), str(car.visual.scale)])
	if car.visual.position != Vector2.ZERO:
		failures.append("A posição do sprite do carro foi deslocada! Obtido %s" % str(car.visual.position))
	if car.visual.skew != 0.0:
		failures.append("O skew do carro foi deformado! Obtido %f" % car.visual.skew)
		
	if failures.is_empty():
		print("  ✓ Batidas aplicadas: o carro manteve rigidez estrutural perfeita (sem esticar nem encolher)!")
	
	# 3. Simular jogador entrando e o carro pegando fogo (combustão)
	print("\n[PASSO 3] Simulando jogador a bordo e motor pegando fogo...")
	var player_script = load("res://characters/Player.gd")
	var player = CharacterBody2D.new()
	player.set_script(player_script)
	var player_camera := Camera2D.new()
	player_camera.name = "Camera"
	player.add_child(player_camera)
	player.add_to_group("player")
	root.add_child(player)
	
	car.enter_vehicle(player)
	if not car.is_driven_by_player:
		failures.append("Jogador não conseguiu entrar no carro de teste")
	else:
		print("  ✓ Jogador entrou no veículo")
	
	# Reduzir vida a 0 (dispara _start_combustion_countdown)
	car.take_damage(200)
	if not car.is_exploding:
		failures.append("Carro não entrou em combustão após dano fatal")
	if not car.is_driven_by_player:
		failures.append("ERRO: O jogador foi ejetado automaticamente 'do nada' ao pegar fogo!")
	else:
		print("  ✓ Carro em chamas: o jogador PERMANECEU dentro do carro sem ser expulso do nada!")
	
	# 4. Simular ejeção voluntária segura
	print("\n[PASSO 4] Testando cálculo de saída segura (_get_safe_exit_position)...")
	var safe_exit = car._get_safe_exit_position()
	print("  - Posição de saída segura calculada: %s" % str(safe_exit))
	car.exit_vehicle()
	# Exit now reverses the real boarding animation; wait for the seat to clear.
	for frame in 150:
		if not car.is_driven_by_player: break
		await physics_frame
	if car.is_driven_by_player:
		failures.append("Falha ao sair voluntariamente do carro em chamas")
	else:
		print("  ✓ Jogador pulou do carro em chamas voluntariamente antes de explodir")
	
	# 5. Detonação final (_explode)
	print("\n[PASSO 5] Executando detonação final (_explode)...")
	car.health = car.max_health
	car.is_broken = false
	car.is_exploding = false
	car.enter_vehicle(player)
	var health_before_explosion: int = player.health
	car._explode()
	if player.health != health_before_explosion - 25:
		failures.append("O ocupante recebeu dano de explosão acima do limite reduzido: %d" % (health_before_explosion - player.health))
	print("  - Escala após explosão: %s" % str(car.visual.scale))
	print("  - Posição após explosão: %s" % str(car.visual.position))
	print("  - Skew após explosão: %f" % car.visual.skew)
	
	if car.visual.scale != initial_scale:
		failures.append("Carro inflou/esticou na explosão! Esperado %s, obtido %s" % [str(initial_scale), str(car.visual.scale)])
	if car.visual.position != Vector2.ZERO:
		failures.append("Carro saltou/teletransportou na explosão! Obtido %s" % str(car.visual.position))
	if car.visual.skew != 0.0:
		failures.append("Carro inclinou/deformou no solo na explosão! Obtido %f" % car.visual.skew)
		
	car.queue_free()
	player.queue_free()
	
	print("\n=================================================================")
	if failures.is_empty():
		print("=== SUCESSO: TESTE DE VEÍCULO APROVADO COM ÊXITO! (EXIT 0) ===")
		print("=================================================================")
		quit(0)
	else:
		printerr("=== FALHAS ENCONTRADAS (%d) ===" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
		print("=================================================================")
		quit(1)
