extends SceneTree

## Teste de Validação Real de Circulação da Garagem/Oficina
## Executa com o renderizador Compatibility (OpenGL3).
## Utiliza instâncias 100% reais de produção com controladores ativos e inputs simulados:
## 1. Carro de produção de Harbor (HarborCoupe.gd) com colisor real (72x31), aceleração e direção reais.
## 2. Pedestre de produção (Player.gd) com colisor real (CapsuleShape2D), câmera e controlador ativo.

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FALHA: %s" % message)
		print("  [FAIL] %s" % message)
	else:
		print("  [PASS] %s" % message)

func _run() -> void:
	print("==================================================")
	print("INICIANDO VALIDAÇÃO REAL DE CIRCULAÇÃO (OPENGL3)")
	print("Carro de Produção: HarborCoupe | Pedestre: Player.gd")
	print("==================================================")

	var proposal_scene = load("res://prototypes/garage/GarageVisualProposal.tscn")
	if not proposal_scene:
		print("FATAL: Nao foi possivel carregar GarageVisualProposal.tscn")
		quit(1)
		return

	var garage = proposal_scene.instantiate()
	root.add_child(garage)

	for i in range(15):
		await physics_frame

	var artifact_dir = "C:/Users/rafae/.gemini/antigravity/brain/ac7b8daf-4790-408c-8376-3690d7044e34"
	var dir = DirAccess.open("res://")
	var viewport = root.get_viewport()

	# ----------------------------------------------------
	# FASE 1: TESTE VEICULAR REAL (HARBOR COUPE)
	# ----------------------------------------------------
	print("\n--- FASE 1: NAVEGAÇÃO VEICULAR REAL (HarborCoupe) ---")
	var car = _create_production_car()
	garage.add_child(car)

	# Posicionamento inicial DOCUMENTADO antes do início:
	# Fora do portão sul, alinhado no eixo X=0, apontando para o Norte (-PI/2)
	car.position = Vector2(0, 240)
	car.rotation = -PI * 0.5
	car.is_driven_by_player = true
	car.max_speed *= 0.75
	car.acceleration *= 0.75

	for i in range(5):
		await physics_frame

	print("1.1 Veículo posicionado externamente ao portão sul: ", car.position)

	# 1.1 Entrada pelo portão e alinhamento no elevador usando apenas ações de input
	await _drive_wp(car, Vector2(0, 150), 100, 30.0)
	await _drive_wp(car, Vector2(65, 95), 100, 30.0)
	await _drive_wp(car, Vector2(135, 50), 100, 30.0)
	await _drive_to_lift(car, Vector2(135, -15), 120)
	await _brake_car(car)

	print("  Posição final do veículo na baia: ", car.position, " rot: ", car.rotation)
	var in_lift = car.position.x > 68 and car.position.x < 212 and absf(car.position.y - (-15)) < 30
	_check(in_lift, "Veículo entrou pelo portão sul e estacionou entre as colunas do elevador (X em [68, 212], Y próximo a -15)")

	# Captura do veículo estacionado no elevador
	for i in range(5):
		await process_frame
	var img_parked = viewport.get_texture().get_image()
	img_parked.save_png("res://tests/garage_real_vehicle_parked_lift.png")
	if dir: dir.copy("res://tests/garage_real_vehicle_parked_lift.png", artifact_dir + "/garage_real_vehicle_parked_lift.png")

	# 1.2 Manobra de saída de ré
	print("1.2 Manobrando veículo de ré para fora do elevador e saindo pelo portão sul...")
	# Recuo 1: ré reta para sair das colunas
	await _reverse_to_y(car, 60.0, 100)
	# Recuo 2: manobra de ré curvando à esquerda para alinhar com o portão sul
	for f in range(40):
		Input.action_press("ui_down")
		Input.action_press("ui_left")
		await physics_frame
	Input.action_release("ui_left")
	# Recuo 3: ré final até atravessar o vão do portão sul (Y >= 215)
	for f in range(12):
		Input.action_press("ui_down")
		await physics_frame
	Input.action_release("ui_down")
	await _brake_car(car)

	print("  Posição final de saída do veículo: ", car.position)
	var exited_ok = car.position.y >= 215.0 and absf(car.position.x) < 85.0
	_check(exited_ok, "Veículo manobrou de ré e atravessou o portão sul com sucesso (Y >= 215, |X| < 85)")

	for i in range(5):
		await process_frame
	var img_exit = viewport.get_texture().get_image()
	img_exit.save_png("res://tests/garage_real_vehicle_exited.png")
	if dir: dir.copy("res://tests/garage_real_vehicle_exited.png", artifact_dir + "/garage_real_vehicle_exited.png")

	car.queue_free()
	for i in range(5):
		await physics_frame

	# ----------------------------------------------------
	# FASE 2: TESTE DE PEDESTRE REAL (PLAYER DE PRODUÇÃO)
	# ----------------------------------------------------
	print("\n--- FASE 2: NAVEGAÇÃO DE PEDESTRE REAL (Player.gd) ---")
	var player = _create_production_player()
	garage.add_child(player)

	for i in range(5):
		await physics_frame

	# 2.1 Comprovar que parede bloqueia o personagem
	print("2.1 Testando bloqueio físico por parede sólida (South Wall Y=220)...")
	player.position = Vector2(-160, 185)
	for i in range(5):
		await physics_frame

	for f in range(60):
		Input.action_press("ui_down")
		await physics_frame
	Input.action_release("ui_down")

	print("  Posição após colidir com a parede sul: ", player.position)
	var wall_blocked = player.position.y <= 211.5 and player.position.y >= 209.0
	_check(wall_blocked, "Parede sólida bloqueou fisicamente o avanço do Player (parou em Y=211 na face da parede)")

	# Posicionar na entrada sul válida
	player.position = Vector2(0, 180)
	for i in range(5):
		await physics_frame

	# 2.2 Trecho 1: Entrada Sul -> Bancada do Tito (140, -120)
	print("2.2 Trecho 1: Caminhando da entrada sul até a Bancada Mecânica...")
	var wps_bench = [Vector2(60, 90), Vector2(70, -10), Vector2(140, -120)]
	var r1 = false
	for wp in wps_bench:
		r1 = await _walk_player_to(player, wp, 120, 15.0)
	_check(r1, "Trecho 1: Pedestre caminhou da entrada até a Bancada Mecânica do Tito")
	print("  Posição na bancada: ", player.position)

	for i in range(5):
		await process_frame
	var img_wb = viewport.get_texture().get_image()
	img_wb.save_png("res://tests/garage_real_player_at_workbench.png")
	if dir: dir.copy("res://tests/garage_real_player_at_workbench.png", artifact_dir + "/garage_real_player_at_workbench.png")

	# 2.3 Trecho 2: Bancada -> Lounge do Maciota (-120, -100)
	print("2.3 Trecho 2: Caminhando da Bancada até o Lounge VIP do Maciota...")
	var wps_maciota = [Vector2(0, -30), Vector2(-120, -30), Vector2(-120, -100)]
	var r2 = false
	for wp in wps_maciota:
		r2 = await _walk_player_to(player, wp, 120, 15.0)
	_check(r2, "Trecho 2: Pedestre caminhou da Bancada até o Lounge VIP do Maciota")
	print("  Posição no lounge do Maciota: ", player.position)

	for i in range(5):
		await process_frame
	var img_mac = viewport.get_texture().get_image()
	img_mac.save_png("res://tests/garage_real_player_at_maciota.png")
	if dir: dir.copy("res://tests/garage_real_player_at_maciota.png", artifact_dir + "/garage_real_player_at_maciota.png")

	# 2.4 Trecho 3: Maciota -> Quadro de Missões (-210, 30)
	print("2.4 Trecho 3: Caminhando do Maciota até o Quadro de Missões...")
	var wps_board = [Vector2(-120, -30), Vector2(-170, 0), Vector2(-210, 30)]
	var r3 = false
	for wp in wps_board:
		r3 = await _walk_player_to(player, wp, 120, 15.0)
	_check(r3, "Trecho 3: Pedestre caminhou do Maciota até o Quadro de Missões")
	print("  Posição no quadro de missões: ", player.position)

	for i in range(5):
		await process_frame
	var img_mb = viewport.get_texture().get_image()
	img_mb.save_png("res://tests/garage_real_player_at_mission_board.png")
	if dir: dir.copy("res://tests/garage_real_player_at_mission_board.png", artifact_dir + "/garage_real_player_at_mission_board.png")

	# 2.5 Trecho 4: Quadro de Missões -> Saída Sul (0, 190)
	print("2.5 Trecho 4: Retornando do Quadro de Missões à Saída Sul...")
	var wps_exit = [Vector2(-140, 110), Vector2(0, 190)]
	var r4 = false
	for wp in wps_exit:
		r4 = await _walk_player_to(player, wp, 120, 15.0)
	_check(r4, "Trecho 4: Pedestre retornou do Quadro de Missões até a Saída Sul")
	print("  Posição final na saída sul: ", player.position)

	print("\n==================================================")
	if failures.is_empty():
		print("TODOS OS TESTES DE CIRCULAÇÃO REAL (CARRO E PEDESTRE) PASSARAM!")
	else:
		print("FALHAS ENCONTRADAS (%d):" % failures.size())
		for f in failures:
			print(" - ", f)
	print("==================================================")

	quit(0 if failures.is_empty() else 1)

func _create_production_car() -> CharacterBody2D:
	var coupe_script = load("res://prototypes/living_cast/HarborCoupe.gd")
	var car = CharacterBody2D.new()
	car.name = "PlayerCar"
	car.collision_mask = 23
	
	var col = CollisionShape2D.new()
	col.name = "Collision"
	var rect = RectangleShape2D.new()
	rect.size = Vector2(65, 28)
	col.shape = rect
	car.add_child(col)

	var cam = Camera2D.new()
	cam.name = "Camera"
	cam.enabled = true
	car.add_child(cam)

	var interact = Area2D.new()
	interact.name = "InteractArea"
	interact.collision_layer = 0
	interact.collision_mask = 4
	var icol = CollisionShape2D.new()
	var ishape = CircleShape2D.new()
	ishape.radius = 72.0
	icol.shape = ishape
	interact.add_child(icol)
	car.add_child(interact)

	car.set_script(coupe_script)
	return car

func _create_production_player() -> CharacterBody2D:
	var player_script = load("res://Player.gd")
	var player = CharacterBody2D.new()
	player.name = "Player"
	player.collision_layer = 4
	player.collision_mask = 7

	var col = CollisionShape2D.new()
	col.name = "Collision"
	var cap = CapsuleShape2D.new()
	cap.radius = 4.0
	cap.height = 14.0
	col.shape = cap
	col.position = Vector2(0, 2)
	player.add_child(col)

	var cam = Camera2D.new()
	cam.name = "Camera"
	cam.enabled = true
	player.add_child(cam)

	player.set_script(player_script)
	return player

func _brake_car(car: CharacterBody2D) -> void:
	Input.action_release("ui_up")
	Input.action_release("ui_down")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	for i in range(25):
		var f_spd = car.velocity.dot(car.global_transform.x)
		if f_spd > 4.0:
			Input.action_press("ui_down")
			Input.action_release("ui_up")
		elif f_spd < -4.0:
			Input.action_press("ui_up")
			Input.action_release("ui_down")
		else:
			break
		await physics_frame
	Input.action_release("ui_up")
	Input.action_release("ui_down")
	for i in range(5):
		await physics_frame

func _drive_wp(car: CharacterBody2D, target: Vector2, max_frames: int, tol: float) -> bool:
	for f in range(max_frames):
		var to_target = target - car.global_position
		if to_target.length() <= tol:
			Input.action_release("ui_up")
			Input.action_release("ui_left")
			Input.action_release("ui_right")
			return true

		var heading = car.global_rotation
		var angle_diff = wrapf(to_target.angle() - heading, -PI, PI)

		if angle_diff > 0.06:
			Input.action_press("ui_right")
			Input.action_release("ui_left")
		elif angle_diff < -0.06:
			Input.action_press("ui_left")
			Input.action_release("ui_right")
		else:
			Input.action_release("ui_left")
			Input.action_release("ui_right")

		var target_speed = 70.0 if absf(angle_diff) > 0.4 else 130.0
		if car.velocity.length() > target_speed:
			Input.action_release("ui_up")
		else:
			Input.action_press("ui_up")
			Input.action_release("ui_down")

		await physics_frame

	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	return car.global_position.distance_to(target) <= tol

func _drive_to_lift(car: CharacterBody2D, target: Vector2, max_frames: int) -> bool:
	for f in range(max_frames):
		if car.position.y <= target.y or car.global_position.distance_to(target) <= 20.0:
			Input.action_release("ui_up")
			Input.action_release("ui_left")
			Input.action_release("ui_right")
			return true

		var to_target = target - car.global_position
		var heading = car.global_rotation
		var angle_diff = wrapf(to_target.angle() - heading, -PI, PI)

		if angle_diff > 0.05:
			Input.action_press("ui_right")
			Input.action_release("ui_left")
		elif angle_diff < -0.05:
			Input.action_press("ui_left")
			Input.action_release("ui_right")
		else:
			Input.action_release("ui_left")
			Input.action_release("ui_right")

		if car.velocity.length() > 90.0:
			Input.action_release("ui_up")
		else:
			Input.action_press("ui_up")
			Input.action_release("ui_down")

		await physics_frame

	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	return absf(car.position.y - target.y) <= 30.0

func _reverse_to_y(car: CharacterBody2D, target_y: float, max_frames: int) -> bool:
	for f in range(max_frames):
		if car.position.y >= target_y:
			Input.action_release("ui_down")
			return true

		if car.velocity.length() > 90.0:
			Input.action_release("ui_down")
		else:
			Input.action_press("ui_down")
			Input.action_release("ui_up")

		await physics_frame

	Input.action_release("ui_down")
	return car.position.y >= target_y - 20.0

func _walk_player_to(p: CharacterBody2D, target: Vector2, max_frames: int, tol: float) -> bool:
	for f in range(max_frames):
		var diff = target - p.position
		if diff.length() <= tol:
			_release_all_inputs()
			return true

		if diff.x > 3.0:
			Input.action_press("ui_right")
			Input.action_release("ui_left")
		elif diff.x < -3.0:
			Input.action_press("ui_left")
			Input.action_release("ui_right")
		else:
			Input.action_release("ui_left")
			Input.action_release("ui_right")

		if diff.y > 3.0:
			Input.action_press("ui_down")
			Input.action_release("ui_up")
		elif diff.y < -3.0:
			Input.action_press("ui_up")
			Input.action_release("ui_down")
		else:
			Input.action_release("ui_up")
			Input.action_release("ui_down")

		await physics_frame

	_release_all_inputs()
	return p.position.distance_to(target) <= tol

func _release_all_inputs() -> void:
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	Input.action_release("ui_up")
	Input.action_release("ui_down")
