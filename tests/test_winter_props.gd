@tool
extends SceneTree

const HUMAN_SCRIPT := preload("res://district/mountain_pass/art/winter_props/HumanScaleReference3D.gd")
const CABIN_SCRIPT := preload("res://district/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
const SHELTER_SCRIPT := preload("res://district/mountain_pass/art/winter_props/PatrolShelter3D.gd")
const WOODPILE_SCRIPT := preload("res://district/mountain_pass/art/winter_props/CoveredWoodpile3D.gd")
const SIGN_BENCH_SCRIPT := preload("res://district/mountain_pass/art/winter_props/TrailSignAndBench3D.gd")
const SHOWCASE_SCRIPT := preload("res://district/mountain_pass/art/winter_props/WinterPropsShowcase.gd")

var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [OK] " + message)
	else:
		failures.append(message)
		printerr("  [FALHA] " + message)

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("\n=======================================================")
	print("=== TESTE DOS MODELOS 3D PROCEDURAIS DE INVERNO ===")
	print("=======================================================\n")

	# -------------------------------------------------------------
	# 1. REFERÊNCIA HUMANA DE 1,80 M
	# -------------------------------------------------------------
	print("--- 1. Validação da Referência Humana (1,80 m) ---")
	var human = HUMAN_SCRIPT.new()
	root.add_child(human)
	await process_frame
	await process_frame

	_check(human is Node3D, "HumanScaleReference3D herda de Node3D")
	_check(is_equal_approx(human.TOTAL_HEIGHT, 1.80), "Altura total da referência é exatamente 1,80 m")
	_check(human.get_child_count() > 0, "Manequim anatômico possui membros e geometria gerada")
	human.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# 2. CONTRATOS ARQUITETURAIS DE CADA MODELO
	# -------------------------------------------------------------
	print("\n--- 2. Contratos Arquiteturais dos Modelos ---")

	# A. Microchalé de Lenhador
	var cabin = CABIN_SCRIPT.new()
	_check("footprint_size" in cabin, "LumberjackCabin3D expõe footprint_size")
	_check("entrance_local_position" in cabin, "LumberjackCabin3D expõe entrance_local_position")
	_check("entrance_clearance" in cabin, "LumberjackCabin3D expõe entrance_clearance")
	_check(cabin.footprint_size == Vector2(3.6, 4.2), "footprint_size do chalé é Vector2(3.6, 4.2)")
	_check(cabin.entrance_local_position == Vector3(0.0, 0.0, 2.1), "entrance_local_position é Vector3(0.0, 0.0, 2.1)")
	_check(cabin.entrance_clearance >= 0.90, "entrance_clearance do chalé >= 0.90m (obtido: %.2f)" % cabin.entrance_clearance)

	# B. Abrigo de Patrulha
	var shelter = SHELTER_SCRIPT.new()
	_check("footprint_size" in shelter, "PatrolShelter3D expõe footprint_size")
	_check("entrance_local_position" in shelter, "PatrolShelter3D expõe entrance_local_position")
	_check("entrance_clearance" in shelter, "PatrolShelter3D expõe entrance_clearance")
	_check(shelter.footprint_size == Vector2(3.0, 2.4), "footprint_size do abrigo é Vector2(3.0, 2.4)")
	_check(shelter.entrance_local_position == Vector3(0.0, 0.0, 1.2), "entrance_local_position é Vector3(0.0, 0.0, 1.2)")
	_check(shelter.entrance_clearance >= 1.20, "entrance_clearance do abrigo >= 1.20m (obtido: %.2f)" % shelter.entrance_clearance)

	# C. Pilha de Lenha Coberta
	var woodpile = WOODPILE_SCRIPT.new()
	_check("footprint_size" in woodpile, "CoveredWoodpile3D expõe footprint_size")
	_check("entrance_local_position" in woodpile, "CoveredWoodpile3D expõe entrance_local_position")
	_check("entrance_clearance" in woodpile, "CoveredWoodpile3D expõe entrance_clearance")
	_check(woodpile.footprint_size == Vector2(2.4, 1.4), "footprint_size da pilha é Vector2(2.4, 1.4)")
	_check(woodpile.entrance_local_position == Vector3(0.0, 0.0, 0.7), "entrance_local_position é Vector3(0.0, 0.0, 0.7)")
	_check(woodpile.entrance_clearance >= 1.30, "entrance_clearance da pilha >= 1.30m (obtido: %.2f)" % woodpile.entrance_clearance)

	# D. Placa de Trilha e Banco de Madeira
	var bench = SIGN_BENCH_SCRIPT.new()
	_check("footprint_size" in bench, "TrailSignAndBench3D expõe footprint_size")
	_check("entrance_local_position" in bench, "TrailSignAndBench3D expõe entrance_local_position")
	_check("entrance_clearance" in bench, "TrailSignAndBench3D expõe entrance_clearance")
	_check(bench.footprint_size == Vector2(2.2, 1.3), "footprint_size do conjunto é Vector2(2.2, 1.3)")
	_check(bench.entrance_local_position == Vector3(0.0, 0.0, 0.65), "entrance_local_position é Vector3(0.0, 0.0, 0.65)")
	_check(bench.entrance_clearance >= 1.10, "entrance_clearance do conjunto >= 1.10m (obtido: %.2f)" % bench.entrance_clearance)

	# -------------------------------------------------------------
	# 3. TESTE DE TROCA DE COR PRINCIPAL (ANTES E DEPOIS DA ÁRVORE)
	# -------------------------------------------------------------
	print("\n--- 3. Customização de Cores (Antes e Depois de Entrar na Árvore) ---")

	# Teste antes de entrar na árvore via _init
	var custom_color_init := Color("#1a3c5a") # Azul Ártico profundo
	var cabin_custom = CABIN_SCRIPT.new(custom_color_init)
	_check(cabin_custom.main_color == custom_color_init, "main_color configurada via _init antes da árvore")
	root.add_child(cabin_custom)
	await process_frame
	await process_frame
	_check(cabin_custom._materials.has("wood_main"), "Material wood_main gerado")
	if cabin_custom._materials.has("wood_main"):
		_check(cabin_custom._materials["wood_main"].albedo_color == custom_color_init,
			"Material wood_main reflete a cor customizada definida antes da árvore")

	# Teste alterando após entrar na árvore via setter
	var runtime_color := Color("#7d281a") # Vermelho Mogno
	cabin_custom.main_color = runtime_color
	_check(cabin_custom._materials["wood_main"].albedo_color == runtime_color,
		"Material wood_main atualizado dinamicamente via setter em tempo de execução")
	cabin_custom.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# 4. VALIDAÇÃO DE AUSÊNCIA DE COLISÕES 2D / GAMEPLAY
	# -------------------------------------------------------------
	print("\n--- 4. Verificação de Ausência de Nós 2D / Gameplay ---")
	var test_instances = [
		CABIN_SCRIPT.new(),
		SHELTER_SCRIPT.new(),
		WOODPILE_SCRIPT.new(),
		SIGN_BENCH_SCRIPT.new()
	]
	for inst in test_instances:
		root.add_child(inst)
	await process_frame
	await process_frame

	for inst in test_instances:
		var has_2d: bool = _has_2d_or_gameplay(inst)
		_check(not has_2d, "%s não possui colisores 2D nem scripts de gameplay" % inst.get_script().get_global_name())
		inst.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# 5. RENDERIZAÇÃO DA CENA DE DEMONSTRAÇÃO & CAPTURA DE TELA
	# -------------------------------------------------------------
	print("\n--- 5. Renderização da Cena de Demonstração (Showcase) ---")
	for contract_instance in [cabin, shelter, woodpile, bench]:
		contract_instance.free()
	await _render_showcase_screenshots()
	await process_frame

	# -------------------------------------------------------------
	# CONCLUSÃO DO TESTE
	# -------------------------------------------------------------
	print("\n=======================================================")
	if failures.is_empty():
		print("=== SUCESSO TOTAL: 0 FALHAS NOS MODELOS 3D DE INVERNO ===")
		print("=======================================================\n")
		quit(0)
	else:
		printerr("=== ENCONTRADAS %d FALHAS ===" % failures.size())
		for f in failures:
			printerr("  - " + f)
		print("=======================================================\n")
		quit(1)

func _has_2d_or_gameplay(node: Node) -> bool:
	if node is Node2D or node is CollisionShape2D or node is CollisionPolygon2D or node is Area2D:
		return true
	for c in node.get_children():
		if _has_2d_or_gameplay(c):
			return true
	return false

func _render_showcase_screenshots() -> void:
	# Cria SubViewport offscreen de alta definição (1920x1080)
	var vp := SubViewport.new()
	vp.name = "ShowcaseOffscreenViewport"
	vp.size = Vector2i(1920, 1080)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(vp)

	var showcase := SHOWCASE_SCRIPT.new()
	vp.add_child(showcase)

	# Aguarda frames de renderização para garantir iluminação e sombras
	for i in range(15):
		await process_frame

	var tex := vp.get_texture()
	var img := tex.get_image()
	if img:
		var out_path := "res://tests/winter_props_showcase.png"
		var abs_out := ProjectSettings.globalize_path(out_path)
		var err := img.save_png(abs_out)
		_check(err == OK, "Captura geral do showcase salva em %s" % abs_out)

		# Salva cópia na pasta de artefatos para visualização no chat
		var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"
		var artifact_path := artifact_dir + "/winter_props_showcase.png"
		img.save_png(artifact_path)
		print("  [OK] Imagem do showcase espelhada no artefato: %s" % artifact_path)

	# Captura em close-up do Chalé e da referência humana de 1,80 m
	var cam: Camera3D = showcase.get_node_or_null("ShowcaseCamera") as Camera3D
	if cam:
		# Ângulo close-up no chalé e humano
		cam.position = Vector3(-5.8, 2.4, 6.8)
		cam.look_at(Vector3(-6.2, 1.4, 1.5))
		for i in range(10):
			await process_frame
		var img_cabin := vp.get_texture().get_image()
		if img_cabin:
			var cabin_shot := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797/winter_props_cabin_human_scale.png"
			img_cabin.save_png(cabin_shot)
			print("  [OK] Close-up do chalé e humano 1,80m salvo em: %s" % cabin_shot)

		# Ângulo close-up no abrigo e pilha de lenha
		cam.position = Vector3(1.2, 2.2, 5.8)
		cam.look_at(Vector3(0.5, 1.2, 1.0))
		for i in range(10):
			await process_frame
		var img_shelter := vp.get_texture().get_image()
		if img_shelter:
			var shelter_shot := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797/winter_props_shelter_woodpile.png"
			img_shelter.save_png(shelter_shot)
			print("  [OK] Close-up do abrigo e pilha de lenha salvo em: %s" % shelter_shot)

		# Ângulo close-up no banco e placa de trilha
		cam.position = Vector3(7.2, 1.8, 4.4)
		cam.look_at(Vector3(7.0, 1.0, 1.0))
		for i in range(10):
			await process_frame
		var img_bench := vp.get_texture().get_image()
		if img_bench:
			var bench_shot := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797/winter_props_bench_sign.png"
			img_bench.save_png(bench_shot)
			print("  [OK] Close-up do banco e placa de trilha salvo em: %s" % bench_shot)

	vp.queue_free()
