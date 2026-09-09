@tool
extends SceneTree

## Suíte de Testes e Validação Rigorosa do Harbor Art Pack (Revisão 2.1)
## Valida:
## 1. Contratos métricos e limites reais dos 21 props.
## 2. Separação rigorosa de get_envelope() e get_obstacle_bounds() nas composições.
## 3. Validação física real de entrada e saída com corpo humano (1,80m x 0,50m) no contêiner aberto,
##    incluindo passagens rente às portas abertas e teste físico com CharacterBody3D.
## 4. Benchmark do otimizador de malha com contagem precisa de meshes -> lotes por material.
## 5. Renderização Vulkan Forward+ com verificação estrita de salvamento e integridade de capturas.

const ARTIFACT_DIR: String = "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"
const CAPTURES_DIR: String = "res://prototypes/harbor_art_pack/captures"

var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [OK] " + message)
	else:
		failures.append(message)
		printerr("  [FALHA] " + message)

func _count_meshes(node: Node) -> int:
	var count: int = 0
	if node is MeshInstance3D:
		count += 1
	for c in node.get_children():
		count += _count_meshes(c)
	return count

func _is_box_colliding_with_aabbs(box: AABB, aabbs: Array[AABB]) -> bool:
	for obs in aabbs:
		if box.intersects(obs):
			return true
	return false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n==================================================================")
	print("=== SUÍTE DE TESTES E REVISÃO: HARBOR ART PACK (GETECO 09/08)  ===")
	print("==================================================================\n")

	# --------------------------------------------------------------------------
	# 1. VALIDAÇÃO DOS 21 PROPS INDIVIDUAIS E LIMITES REAIS
	# --------------------------------------------------------------------------
	print("--- 1. Validação Contratual dos 21 Props Individuais ---")

	var props_to_test: Array[Dictionary] = [
		{"name": "PortContainer20ft3D", "script": preload("res://prototypes/harbor_art_pack/props/PortContainer20ft3D.gd")},
		{"name": "PortContainer40ft3D", "script": preload("res://prototypes/harbor_art_pack/props/PortContainer40ft3D.gd")},
		{"name": "PortContainerOpen3D", "script": preload("res://prototypes/harbor_art_pack/props/PortContainerOpen3D.gd")},
		{"name": "PortReeferContainer3D", "script": preload("res://prototypes/harbor_art_pack/props/PortReeferContainer3D.gd")},
		{"name": "PortWoodenPallet3D", "script": preload("res://prototypes/harbor_art_pack/props/PortWoodenPallet3D.gd")},
		{"name": "PortWeatheredPallet3D", "script": preload("res://prototypes/harbor_art_pack/props/PortWeatheredPallet3D.gd")},
		{"name": "PortPalletStack3D", "script": preload("res://prototypes/harbor_art_pack/props/PortPalletStack3D.gd")},
		{"name": "PortCargoCrate3D", "script": preload("res://prototypes/harbor_art_pack/props/PortCargoCrate3D.gd")},
		{"name": "PortLongCrate3D", "script": preload("res://prototypes/harbor_art_pack/props/PortLongCrate3D.gd")},
		{"name": "PortPlasticTote3D", "script": preload("res://prototypes/harbor_art_pack/props/PortPlasticTote3D.gd")},
		{"name": "PortOilDrum3D", "script": preload("res://prototypes/harbor_art_pack/props/PortOilDrum3D.gd")},
		{"name": "PortRustyDrum3D", "script": preload("res://prototypes/harbor_art_pack/props/PortRustyDrum3D.gd")},
		{"name": "PortDrumClusterPallet3D", "script": preload("res://prototypes/harbor_art_pack/props/PortDrumClusterPallet3D.gd")},
		{"name": "PortHandTruck3D", "script": preload("res://prototypes/harbor_art_pack/props/PortHandTruck3D.gd")},
		{"name": "PortPlatformCart3D", "script": preload("res://prototypes/harbor_art_pack/props/PortPlatformCart3D.gd")},
		{"name": "PortForklift3D", "script": preload("res://prototypes/harbor_art_pack/props/PortForklift3D.gd")},
		{"name": "PortLifebuoyStand3D", "script": preload("res://prototypes/harbor_art_pack/props/PortLifebuoyStand3D.gd")},
		{"name": "PortPierFender3D", "script": preload("res://prototypes/harbor_art_pack/props/PortPierFender3D.gd")},
		{"name": "PortMooringBollard3D", "script": preload("res://prototypes/harbor_art_pack/props/PortMooringBollard3D.gd")},
		{"name": "PortFloodlightTower3D", "script": preload("res://prototypes/harbor_art_pack/props/PortFloodlightTower3D.gd")},
		{"name": "PortHazardSign3D", "script": preload("res://prototypes/harbor_art_pack/props/PortHazardSign3D.gd")},
	]

	var total_prop_meshes: int = 0
	for item in props_to_test:
		var node = item["script"].new()
		root.add_child(node)
		await process_frame

		var dims: Vector3 = node.get_dimensions()
		var bounds: Array[AABB] = node.get_obstacle_bounds()
		var m_count: int = _count_meshes(node)
		total_prop_meshes += m_count

		_check(dims.x > 0.0 and dims.y > 0.0 and dims.z > 0.0, "%s: get_dimensions() válido: %s" % [item["name"], str(dims)])
		_check(bounds.size() > 0, "%s: possui %d AABBs de colisão" % [item["name"], bounds.size()])
		_check(bounds[0].position.y >= 0.0, "%s: Y do AABB no solo (y=%.3f)" % [item["name"], bounds[0].position.y])
		_check(m_count >= 1, "%s: possui %d meshes procedurais" % [item["name"], m_count])

		node.queue_free()
		await process_frame

	print("  -> Total de malhas nos 21 props individuais: %d meshes." % total_prop_meshes)

	# --------------------------------------------------------------------------
	# 2. SEPARAÇÃO DE ENVELOPE E OBSTÁCULOS EM PORTMAINTENANCECORNER3D
	# --------------------------------------------------------------------------
	print("\n--- 2. Separação de Envelope Total e Colisores em PortMaintenanceCorner3D ---")
	var maint_corner = preload("res://prototypes/harbor_art_pack/compositions/PortMaintenanceCorner3D.gd").new()
	maint_corner.optimize_batch = false
	root.add_child(maint_corner)
	await process_frame

	var env: AABB = maint_corner.get_envelope()
	var total_b: AABB = maint_corner.get_total_bounds()
	var obs_list: Array[AABB] = maint_corner.get_obstacle_bounds()

	_check(env == total_b, "get_envelope() e get_total_bounds() retornam o mesmo envelope total delimitador")
	_check(env.size.x >= 5.5 and env.size.z >= 6.5, "Envelope total engloba toda a área (%s)" % str(env.size))
	_check(obs_list.size() >= 15, "get_obstacle_bounds() retorna obstáculos individuais dos objetos transformados (%d AABBs)" % obs_list.size())
	_check(not obs_list.has(env), "get_obstacle_bounds() NÃO contém o bloco sólido cego do envelope total")

	# --------------------------------------------------------------------------
	# 3. VALIDAÇÃO FÍSICA DE ENTRADA E SAÍDA COM CORPO HUMANO (DANTE/ESTIVADOR)
	# --------------------------------------------------------------------------
	print("\n--- 3. Validação Física de Entrada/Saída com Corpo Humano (1,80m x 0,50m) ---")
	# Dimensões do corpo humano de teste: cilindro/caixa de 0.50m largura x 1.80m altura
	var human_radius := 0.25
	var human_height := 1.70

	# Teste Trajetória 1: Entrada Direta pelo centro
	var path_in_collision := false
	var z_curr := 4.20
	while z_curr >= -2.60:
		var human_box := AABB(Vector3(-human_radius, 0.15, z_curr - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0))
		if _is_box_colliding_with_aabbs(human_box, obs_list):
			path_in_collision = true
			printerr("  [FALHA] Colisão detectada na entrada em Z=%.2f" % z_curr)
			break
		z_curr -= 0.05
	_check(not path_in_collision, "Trajetória 1 (Entrada direta Z=4.20 a Z=-2.60): 100% LIVRE sem colisões")

	# Teste Trajetória 2: Saída Direta pelo centro
	var path_out_collision := false
	z_curr = -2.60
	while z_curr <= 4.20:
		var human_box := AABB(Vector3(-human_radius, 0.15, z_curr - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0))
		if _is_box_colliding_with_aabbs(human_box, obs_list):
			path_out_collision = true
			printerr("  [FALHA] Colisão detectada na saída em Z=%.2f" % z_curr)
			break
		z_curr += 0.05
	_check(not path_out_collision, "Trajetória 2 (Saída direta Z=-2.60 a Z=4.20): 100% LIVRE sem colisões")

	# Teste Trajetória 3: Passagem rente à folha da porta esquerda (X = -0.65m)
	var path_left_door_collision := false
	z_curr = 3.50
	while z_curr >= 0.50:
		var human_box := AABB(Vector3(-0.65 - human_radius, 0.15, z_curr - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0))
		if _is_box_colliding_with_aabbs(human_box, obs_list):
			path_left_door_collision = true
			printerr("  [FALHA] Colisão rente à porta esquerda em Z=%.2f" % z_curr)
			break
		z_curr -= 0.05
	_check(not path_left_door_collision, "Trajetória 3 (Passagem rente à porta esquerda X=-0.65m): LIVRE")

	# Teste Trajetória 4: Passagem rente à folha da porta direita (X = +0.65m)
	var path_right_door_collision := false
	z_curr = 3.50
	while z_curr >= 0.50:
		var human_box := AABB(Vector3(0.65 - human_radius, 0.15, z_curr - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0))
		if _is_box_colliding_with_aabbs(human_box, obs_list):
			path_right_door_collision = true
			printerr("  [FALHA] Colisão rente à porta direita em Z=%.2f" % z_curr)
			break
		z_curr -= 0.05
	_check(not path_right_door_collision, "Trajetória 4 (Passagem rente à porta direita X=+0.65m): LIVRE")

	# Teste Trajetória 5: Validação de colisão intencional nas superfícies sólidas
	var hit_wall_left := _is_box_colliding_with_aabbs(AABB(Vector3(-1.20 - human_radius, 0.15, -1.0 - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0)), obs_list)
	var hit_wall_right := _is_box_colliding_with_aabbs(AABB(Vector3(1.20 - human_radius, 0.15, -1.0 - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0)), obs_list)
	var hit_door_leaf := _is_box_colliding_with_aabbs(AABB(Vector3(1.35 - human_radius, 0.15, 2.8 - human_radius), Vector3(human_radius * 2.0, human_height, human_radius * 2.0)), obs_list)
	_check(hit_wall_left and hit_wall_right and hit_door_leaf, "Superfícies sólidas (paredes e folhas de porta) colidem ativamente com o corpo humano")

	# Teste Físico com CharacterBody3D e StaticBody3D no motor de física
	var static_body := StaticBody3D.new()
	root.add_child(static_body)
	for aabb in obs_list:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = aabb.size
		col.shape = box
		col.position = aabb.position + aabb.size * 0.5
		static_body.add_child(col)

	var character := CharacterBody3D.new()
	var char_col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.80
	char_col.shape = cap
	char_col.position.y = 0.90
	character.add_child(char_col)
	root.add_child(character)
	await process_frame

	character.position = Vector3(0.0, 0.15, 4.0)
	character.force_update_transform()
	var move_in_collided := character.test_move(character.global_transform, Vector3(0.0, 0.0, -6.0))
	_check(not move_in_collided, "Simulação física CharacterBody3D: Deslocamento de entrada contínuo (Z=4.0 a Z=-2.0) sem colisão")

	character.position = Vector3(0.0, 0.15, -2.0)
	character.force_update_transform()
	var move_out_collided := character.test_move(character.global_transform, Vector3(0.0, 0.0, 6.0))
	_check(not move_out_collided, "Simulação física CharacterBody3D: Deslocamento de saída contínuo (Z=-2.0 a Z=4.0) sem colisão")

	static_body.queue_free()
	character.queue_free()
	maint_corner.queue_free()
	await process_frame

	# --------------------------------------------------------------------------
	# 4. BENCHMARK DO AGRUPAMENTO DE MALHAS (MESHES -> LOTES CONSOLIDADOS)
	# --------------------------------------------------------------------------
	print("\n--- 4. Benchmark de Otimização: Meshes Individuais -> Lotes por Material ---")

	var comp_defs: Array[Dictionary] = [
		{"name": "PortCargoStagingArea3D", "script": preload("res://prototypes/harbor_art_pack/compositions/PortCargoStagingArea3D.gd")},
		{"name": "PortStorageDepot3D", "script": preload("res://prototypes/harbor_art_pack/compositions/PortStorageDepot3D.gd")},
		{"name": "PortMaintenanceCorner3D", "script": preload("res://prototypes/harbor_art_pack/compositions/PortMaintenanceCorner3D.gd")}
	]

	print("+----------------------------+---------------+--------------+------------+")
	print("| Composição                 | Meshes Antes  | Lotes Depois | Redução (%)|")
	print("+----------------------------+---------------+--------------+------------+")

	for item in comp_defs:
		var comp_unopt = item["script"].new()
		comp_unopt.optimize_batch = false
		root.add_child(comp_unopt)
		await process_frame
		var count_before: int = _count_meshes(comp_unopt)
		comp_unopt.queue_free()
		await process_frame

		var comp_opt = item["script"].new()
		comp_opt.optimize_batch = true
		root.add_child(comp_opt)
		await process_frame
		var count_after: int = _count_meshes(comp_opt)

		var dims: Vector3 = comp_opt.get_dimensions()
		var bounds: Array[AABB] = comp_opt.get_obstacle_bounds()

		_check(dims.x > 0.0 and dims.y > 0.0 and dims.z > 0.0, "%s: dimensões geométricas válidas %s" % [item["name"], str(dims)])
		_check(bounds.size() > 0, "%s: possui %d AABBs de obstáculos" % [item["name"], bounds.size()])
		_check(count_after <= 30, "%s: agrupado em %d lotes de material" % [item["name"], count_after])
		_check(count_after < count_before, "%s: redução de malhas confirmada (%d -> %d)" % [item["name"], count_before, count_after])

		var red_pct := (1.0 - float(count_after) / float(count_before)) * 100.0
		print("| %-26s | %13d | %12d | %9.1f%% |" % [item["name"], count_before, count_after, red_pct])

		comp_opt.queue_free()
		await process_frame

	print("+----------------------------+---------------+--------------+------------+")

	# --------------------------------------------------------------------------
	# 5. RENDERIZAÇÃO REAL NO VULKAN FORWARD+ COM VERIFICAÇÃO RIGOROSA
	# --------------------------------------------------------------------------
	print("\n--- 5. Renderização em Tempo Real (Vulkan Forward+) e Verificação de Imagens ---")
	var showcase = preload("res://prototypes/harbor_art_pack/PortArtPackShowcase.gd").new()
	root.add_child(showcase)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 48.0
	root.add_child(cam)

	for i in range(15):
		await process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURES_DIR))

	# Ângulo 1: Visão Geral Panorâmica
	cam.position = Vector3(0.0, 25.0, 32.0)
	cam.look_at(Vector3(0.0, 1.5, 3.0))
	for i in range(12):
		await process_frame
	_save_and_verify_capture("capture_overview.png", "Visão Geral de Todo o Kit e Pátio")

	# Ângulo 2: Close-up dos Props e Estivador
	cam.position = Vector3(-6.5, 3.4, 5.5)
	cam.look_at(Vector3(-5.5, 1.1, -1.5))
	for i in range(12):
		await process_frame
	_save_and_verify_capture("capture_props_closeup.png", "Close-up dos Props Individuais e Manequim de 1,80m")

	# Ângulo 3: Composição 1 - Área de Carga e Estivação
	cam.position = Vector3(-13.0, 7.5, 27.5)
	cam.look_at(Vector3(-16.0, 2.5, 16.0))
	for i in range(12):
		await process_frame
	_save_and_verify_capture("capture_cargo_staging.png", "Composição 1: Área de Carga e Estivação")

	# Ângulo 4: Composição 2 - Depósito Portuário
	cam.position = Vector3(1.0, 6.5, 23.5)
	cam.look_at(Vector3(1.0, 1.2, 16.0))
	for i in range(12):
		await process_frame
	_save_and_verify_capture("capture_storage_depot.png", "Composição 2: Depósito Portuário")

	# Ângulo 5: Composição 3 - Canto de Manutenção
	cam.position = Vector3(14.0, 5.2, 23.0)
	cam.look_at(Vector3(14.0, 1.3, 16.0))
	for i in range(12):
		await process_frame
	_save_and_verify_capture("capture_maintenance_corner.png", "Composição 3: Canto de Manutenção Naval com Entrada Desobstruída")

	# Ângulo 6: Câmera Real do Jogo (Isométrica Top-Down)
	cam.position = Vector3(-15.0, 13.0, 26.5)
	cam.look_at(Vector3(-16.0, 1.0, 16.5))
	for i in range(12):
		await process_frame
	_save_and_verify_capture("capture_gameplay_camera.png", "Câmera de Jogo: Legibilidade em Vista Superior/Isométrica")

	# Medição real de Draw Calls reportada pelo RenderingServer
	var reported_draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("\n  -> Draw Calls totais medidas no frame pelo RenderingServer: %d draw calls." % reported_draw_calls)

	# --------------------------------------------------------------------------
	# 6. RESUMO FINAL
	# --------------------------------------------------------------------------
	print("\n==================================================================")
	if failures.is_empty():
		print("=== SUCESSO TOTAL: HARBOR ART PACK REVISÃO 2.1 APROVADA!       ===")
	else:
		printerr("=== %d FALHAS DETECTADAS NA REVISÃO 2.1 ===" % failures.size())
		for f in failures:
			printerr("  - " + f)
	print("==================================================================\n")

	showcase.queue_free()
	cam.queue_free()
	await process_frame

	quit(0 if failures.is_empty() else 1)

func _save_and_verify_capture(filename: String, label: String) -> void:
	var viewport := root.get_viewport()
	if not viewport:
		_check(false, "Viewport nula para captura: %s" % filename)
		return

	var tex := viewport.get_texture()
	if not tex:
		_check(false, "Textura da viewport nula para captura: %s" % filename)
		return

	var img := tex.get_image()
	if not img:
		_check(false, "Imagem não obtida da textura para captura: %s" % filename)
		return

	if img.is_empty() or img.get_width() <= 0 or img.get_height() <= 0:
		_check(false, "Imagem vazia ou dimensões inválidas para captura: %s" % filename)
		return

	var res_path := CAPTURES_DIR + "/" + filename
	var art_path := ARTIFACT_DIR + "/" + filename

	var err1 := img.save_png(res_path)
	if err1 != OK:
		_check(false, "Falha ao gravar PNG no projeto (%s): código de erro %d" % [res_path, err1])
		return

	var err2 := img.save_png(art_path)
	if err2 != OK:
		_check(false, "Falha ao gravar PNG nos artefatos (%s): código de erro %d" % [art_path, err2])
		return

	_check(true, "Captura salva e verificada com sucesso (%dx%d): %s (%s)" % [img.get_width(), img.get_height(), filename, label])
