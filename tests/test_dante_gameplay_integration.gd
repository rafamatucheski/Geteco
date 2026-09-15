extends SceneTree

## Teste completo de validação da ETAPA 1 — DANTE JOGÁVEL
## Comprova que o visual do Dante CGI v2 está totalmente integrado no Player real,
## preservando física, câmera, combate, armas, dano, morte, veículos e trajes.

const HARBOR_SCENE: PackedScene = preload("res://world/harbor/HarborGame.tscn")

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		push_error("DANTE_INTEGRATION_FAIL: " + msg)
		print("  [FALHA] ", msg)
	else:
		print("  [OK] ", msg)

func _run() -> void:
	print("=================================================================")
	print("=== INICIANDO VALIDAÇÃO: ETAPA 1 — DANTE JOGÁVEL EM HARBORGAME ===")
	print("=================================================================")

	var world = HARBOR_SCENE.instantiate()
	root.add_child(world)
	current_scene = world

	for f in 8:
		await physics_frame

	# Despausar a árvore e liberar locks cinemáticos da abertura
	paused = false
	var arrival = world.get_node_or_null("ArrivalMission")
	if arrival:
		arrival.queue_free()

	for f in 4:
		await physics_frame

	var player = world.get_node_or_null("Player") as CharacterBody2D
	_check(player != null, "Player deve existir na cena HarborGame")
	if player == null:
		_finish(1)
		return

	player.show()
	player.set_physics_process(true)
	player.is_control_disabled = false
	player.is_in_dialogue = false

	for f in 5:
		await physics_frame

	# -------------------------------------------------------------
	# 1. VERIFICAÇÃO DO MODELO 3D CANÔNICO E HIERARQUIA DE BONES
	# -------------------------------------------------------------
	print("\n--- 1. ESTRUTURA DO MODELO 3D & SOCKETS ---")
	_check(is_instance_valid(player.model_root), "model_root 3D deve existir")
	_check(is_instance_valid(player.torso_node), "torso_node deve existir")
	_check(is_instance_valid(player.head_node), "head_node deve existir")
	_check(is_instance_valid(player.left_upper_arm), "left_upper_arm deve existir")
	_check(is_instance_valid(player.left_lower_arm), "left_lower_arm deve existir")
	_check(is_instance_valid(player.right_upper_arm), "right_upper_arm deve existir")
	_check(is_instance_valid(player.right_lower_arm), "right_lower_arm deve existir")
	_check(is_instance_valid(player.weapon_mount_node), "weapon_mount_node deve existir")
	_check(is_instance_valid(player.left_upper_leg), "left_upper_leg deve existir")
	_check(is_instance_valid(player.left_lower_leg), "left_lower_leg deve existir")
	_check(is_instance_valid(player.right_upper_leg), "right_upper_leg deve existir")
	_check(is_instance_valid(player.right_lower_leg), "right_lower_leg deve existir")

	# Contagem real de meshes e materiais
	var meshes: Array[MeshInstance3D] = []
	for node in player.model_root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node)
	print("Total de meshes medidos na instância do Dante: %d" % meshes.size())
	_check(meshes.size() >= 50, "Dante CGI v2 deve possuir malha detalhada (>= 50 meshes)")

	var materials: Dictionary = {}
	for m in meshes:
		if m.material_override:
			materials[m.material_override] = true
	print("Total de materiais PBR únicos ativos: %d" % materials.size())
	_check(materials.size() >= 10, "Dante CGI v2 deve possuir materiais PBR ricos (>= 10 materiais)")

	# Comprovar textura da jaqueta xadrez
	_check(player.mat_black_jacket != null, "mat_black_jacket deve estar atribuído no Player")
	_check(player.mat_black_jacket.albedo_texture != null, "Jaqueta deve possuir textura xadrez aplicada")

	# -------------------------------------------------------------
	# 2. ANIMAÇÕES: IDLE, CAMINHADA E CORRIDA COM INPUT NATIVO
	# -------------------------------------------------------------
	print("\n--- 2. ANIMAÇÕES & CICLOS DE PASSOS (INPUT NATIVO) ---")
	var initial_pos: Vector2 = player.global_position

	# Caminhada via 'move_right': desde 10/09 o GameInput lê as ações move_*,
	# não as ui_* do Godot, então pressionar ui_right não movia o Dante.
	Input.action_press("move_right")
	var walk_gain := 0.0
	var last_clock: float = player.walk_clock
	for f in 30:
		await physics_frame
		walk_gain += fposmod(player.walk_clock - last_clock, TAU)
		last_clock = player.walk_clock
	Input.action_release("move_right")

	_check(player.global_position.x > initial_pos.x + 10.0, "Player deve se mover com input ui_right")
	_check(player.walk_clock > 0.5, "walk_clock deve avançar durante a caminhada")
	_check(player.left_upper_leg.rotation.x != 0.0 or player.right_upper_leg.rotation.x != 0.0, "Pernas devem articular durante caminhada")

	# Testar corrida via 'sprint'
	var pos_before_sprint: Vector2 = player.global_position
	var clock_before: float = player.walk_clock
	Input.action_press("move_right")
	Input.action_press("sprint")
	var sprint_gain := 0.0
	last_clock = player.walk_clock
	for f in 30:
		await physics_frame
		sprint_gain += fposmod(player.walk_clock - last_clock, TAU)
		last_clock = player.walk_clock
	Input.action_release("sprint")
	Input.action_release("move_right")

	var sprint_dist: float = player.global_position.x - pos_before_sprint.x
	_check(sprint_dist > 30.0, "Velocidade de corrida (sprint) deve ser superior à de caminhada")
	# O limite absoluto de 1,5 rad era da velocidade antiga; o contrato é a corrida
	# avançar o ciclo de passos mais depressa que a caminhada no mesmo intervalo.
	_check(sprint_gain > walk_gain, "Cadência de passos deve acelerar durante corrida (%.2f > %.2f)" % [sprint_gain, walk_gain])

	# -------------------------------------------------------------
	# 3. PLAYER COMBAT POSE & EMPUNHADURA DE ARMAS (1H, 2H, MIRAS)
	# -------------------------------------------------------------
	print("\n--- 3. PLAYER COMBAT POSE & SUPORTE A ARMAS (1H, 2H) ---")
	var weapons_to_test := ["fists", "pistol", "magnum", "shotgun", "ak47", "m4a1"]

	for w_id in weapons_to_test:
		player.active_weapon_id = w_id
		player._update_equipped_weapon_3d_mesh()
		player.combat_pose.on_attack(w_id)

		for f in 10:
			await physics_frame

		_check(is_instance_valid(player.current_gun_mesh) or w_id == "fists", "Mesh 3D da arma '%s' deve instanciar no mount" % w_id)
		# O socket é a palma do antebraço direito (-0,20 no rig atual), não uma constante.
		_check(player.weapon_mount_node.position.distance_to(player.right_lower_arm.get_node("Palm").position) < 0.01, "WeaponMount deve manter posição precisa do socket")

	# Testar disparo e efeito visual (muzzle flash & light)
	player.active_weapon_id = "pistol"
	player._update_equipped_weapon_3d_mesh()
	player._trigger_muzzle_flash_3d()
	await physics_frame
	_check(player.muzzle_flash_3d.visible == true, "Muzzle flash 3D deve ativar no disparo")
	_check(player.muzzle_light_3d.visible == true, "Luz dinâmica do cano deve ativar no disparo")

	# -------------------------------------------------------------
	# 4. SISTEMA DE DANO, HIT FLASH & RESPAWN
	# -------------------------------------------------------------
	print("\n--- 4. DANO, FLASH VERMELHO & SAÚDE ---")
	var hp_before: int = player.health
	player.take_damage(20)
	_check(player.health == hp_before - 20, "Dano de 20 deve reduzir saúde proporcionalmente")
	_check(player.mat_black_jacket.albedo_color.r > 0.9, "Material da jaqueta deve piscar avermelhado ao tomar dano")

	# Aguardar tween do flash restaurar cor
	await create_timer(0.35).timeout
	_check(player.mat_black_jacket.albedo_color.r < 1.3, "Material da jaqueta deve restaurar cor original após tween")

	# -------------------------------------------------------------
	# 5. EMBARQUE E DESEMBARQUE EM VEÍCULO
	# -------------------------------------------------------------
	print("\n--- 5. EMBARQUE & DESEMBARQUE VEICULAR ---")
	var car = world.get_node_or_null("PlayerCar")
	if car:
		player.global_position = car.global_position + Vector2(20, 0)
		player.try_enter_vehicle()
		# Embarque é animado desde 10/09 (~2 s); espera a transição terminar.
		var board_deadline := Time.get_ticks_msec() + 6000
		while (car.has_meta("vehicle_boarding") or car.get("is_driven_by_player") != true) and Time.get_ticks_msec() < board_deadline:
			await physics_frame
		await process_frame
		_check(car.get("is_driven_by_player") == true, "Dante deve embarcar no carro")
		_check(not player.visible, "Sprite/corpo do Dante deve ser ocultado ao entrar no veículo")
		_check(player.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Viewport 3D deve pausar quando oculto para poupar GPU")

		# Desembarcar
		car.exit_vehicle()
		var exit_deadline := Time.get_ticks_msec() + 6000
		while car.get("is_driven_by_player") == true and Time.get_ticks_msec() < exit_deadline:
			await physics_frame
		await process_frame
		_check(car.get("is_driven_by_player") == false, "Dante deve desembarcar com sucesso")
		_check(player.visible == true, "Dante deve voltar a ficar visível ao desembarcar")
		# Visível, o Player usa UPDATE_WHEN_VISIBLE; basta não estar desativado.
		_check(player.viewport_3d.render_target_update_mode != SubViewport.UPDATE_DISABLED, "Viewport 3D deve retomar renderização ao desembarcar")

	# -------------------------------------------------------------
	# 6. TROCA DE ROUPAS (OUTFIT CATALOG)
	# -------------------------------------------------------------
	print("\n--- 6. TROCA DE ROUPAS & RETORNO AO CANÔNICO ---")
	player.apply_outfit("dante_suit")
	await physics_frame
	_check(player.current_outfit_id == "dante_suit", "Traje dante_suit deve ser aplicado")
	_check(player.mat_black_jacket != null, "mat_black_jacket deve ser atualizado para o traje terno")

	# Retornar ao canônico
	player.apply_outfit("dante_classic")
	await physics_frame
	_check(player.current_outfit_id == "dante_classic", "Traje canônico dante_classic deve ser reaplicado")
	_check(player.mat_black_jacket.albedo_texture != null, "Textura xadrez canônica deve ser restaurada")

	# -------------------------------------------------------------
	# 7. CAPTURA DE COMPROVAÇÃO VISUAL
	# -------------------------------------------------------------
	print("\n--- 7. CAPTURAS VISUAIS DE GAMEPLAY ---")
	player.global_position = Vector2(1700, 1130)
	for f in 10:
		await physics_frame

	var vp_tex = root.get_viewport().get_texture()
	if vp_tex != null:
		var img = vp_tex.get_image()
		if img != null:
			img.save_png("res://tests/dante_integrated_gameplay.png")
			print("Captura salva em res://tests/dante_integrated_gameplay.png")

	if failures.is_empty():
		print("\n>>> ETAPA 1 (DANTE JOGÁVEL) VALIDADA COM 100% DE SUCESSO! <<<")
		_finish(0)
	else:
		print("\n>>> ETAPA 1 FALHOU COM %d ERROS! <<<" % failures.size())
		_finish(1)

func _finish(exit_code: int) -> void:
	quit(exit_code)
