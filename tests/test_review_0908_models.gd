@tool
extends SceneTree

## Suíte de Testes e Renderização Visual dos Modelos 3D de Review (09/08):
## - MountainGunShop3D (fachada exterior da loja de armas)
## - MountainGunShopInterior3D (interior completo com balcão, vitrines, bancada e estande)
## - CrashedCargoPlane3D (cargueiro monumental acidentado no lago com rampa e CutawayRoof)
## - LumberjackCabin3D (abrigo de lenhador aprimorado com ferramentas reais e banco)
## - MountainPineTree (pinheiro 2D low-poly com tronco visível e galhos naturais)
## Executa com o manequim métrico de 1,80 m ao lado de cada modelo para comprovação de escala.

const GUN_SHOP_EXT_SCRIPT := preload("res://world/mountain_pass/art/review_0908/MountainGunShop3D.gd")
const GUN_SHOP_INT_SCRIPT := preload("res://world/mountain_pass/art/review_0908/MountainGunShopInterior3D.gd")
const CARGO_PLANE_SCRIPT  := preload("res://world/mountain_pass/art/review_0908/CrashedCargoPlane3D.gd")
const CABIN_SCRIPT        := preload("res://world/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
const HUMAN_SCRIPT        := preload("res://world/mountain_pass/art/winter_props/HumanScaleReference3D.gd")
const PINE_SCRIPT         := preload("res://world/mountain_pass/MountainPineTree.gd")

var failures: Array[String] = []
var model_mesh_counts: Dictionary = {}

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

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("\n=======================================================")
	print("=== TESTE DE MODELOS 3D REVIEW 0908 & ARTE ISOLADA ===")
	print("=======================================================\n")

	# -------------------------------------------------------------
	# 1. VALIDAÇÃO DOS NOVOS MODELOS
	# -------------------------------------------------------------
	print("--- 1. Validação de Contratos e Nós 3D ---")

	# A. MountainGunShop3D (Fachada Exterior)
	var gun_shop_ext = GUN_SHOP_EXT_SCRIPT.new()
	root.add_child(gun_shop_ext)
	await process_frame
	await process_frame

	_check(gun_shop_ext is Node3D, "MountainGunShop3D herda de Node3D")
	_check(gun_shop_ext.footprint_size == Vector2(8.6, 6.4), "MountainGunShop3D footprint_size é (8.6, 6.4)m")
	_check(gun_shop_ext.entrance_local_position == Vector3(0.0, 0.0, 3.2), "entrance_local_position é (0.0, 0.0, 3.2)")
	_check(gun_shop_ext.entrance_clearance >= 1.20, "entrance_clearance >= 1.20m (obtido: %.2f)" % gun_shop_ext.entrance_clearance)
	model_mesh_counts["MountainGunShop3D"] = _count_meshes(gun_shop_ext)
	print("  [INFO] MountainGunShop3D total de meshes: %d" % model_mesh_counts["MountainGunShop3D"])
	gun_shop_ext.queue_free()
	await process_frame

	# B. MountainGunShopInterior3D (Interior Completo)
	var gun_shop_int = GUN_SHOP_INT_SCRIPT.new()
	root.add_child(gun_shop_int)
	await process_frame
	await process_frame

	_check(gun_shop_int is Node3D, "MountainGunShopInterior3D herda de Node3D")
	_check(gun_shop_int.room_size == Vector3(9.6, 3.4, 7.6), "room_size é (9.6, 3.4, 7.6)m")
	model_mesh_counts["MountainGunShopInterior3D"] = _count_meshes(gun_shop_int)
	print("  [INFO] MountainGunShopInterior3D total de meshes: %d" % model_mesh_counts["MountainGunShopInterior3D"])
	gun_shop_int.queue_free()
	await process_frame

	# C. CrashedCargoPlane3D (Avião Cargueiro no Lago)
	var plane = CARGO_PLANE_SCRIPT.new()
	root.add_child(plane)
	await process_frame
	await process_frame

	_check(plane is Node3D, "CrashedCargoPlane3D herda de Node3D")
	_check(plane.footprint_size == Vector2(28.0, 24.0), "CrashedCargoPlane3D footprint_size é (28.0, 24.0)m")
	_check(plane.entrance_local_position == Vector3(0.0, 0.0, 9.2), "entrance_local_position da rampa é (0.0, 0.0, 9.2)")
	_check(plane.entrance_clearance >= 2.20, "entrance_clearance da rampa traseira >= 2.20m (obtido: %.2f)" % plane.entrance_clearance)
	_check(plane.has_node("CutawayRoof"), "CrashedCargoPlane3D possui nó filho 'CutawayRoof'")
	_check(plane.cutaway_roof != null, "Referência cutaway_roof inicializada")

	# Teste do cutaway funcional
	plane.set_cutaway(true)
	_check(plane.cutaway_roof.visible == false, "set_cutaway(true) torna CutawayRoof invisível")
	plane.set_cutaway(false)
	_check(plane.cutaway_roof.visible == true, "set_cutaway(false) restaura visibilidade do teto")

	model_mesh_counts["CrashedCargoPlane3D"] = _count_meshes(plane)
	print("  [INFO] CrashedCargoPlane3D total de meshes: %d" % model_mesh_counts["CrashedCargoPlane3D"])
	plane.queue_free()
	await process_frame

	# D. LumberjackCabin3D Aprimorado
	var cabin = CABIN_SCRIPT.new()
	root.add_child(cabin)
	await process_frame
	await process_frame
	model_mesh_counts["LumberjackCabin3D"] = _count_meshes(cabin)
	print("  [INFO] LumberjackCabin3D (aprimorado) total de meshes: %d" % model_mesh_counts["LumberjackCabin3D"])
	cabin.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# 2. RENDERIZAÇÃO REAL DE CAPTURAS COM REFERÊNCIA HUMANA DE 1,80 M
	# -------------------------------------------------------------
	print("\n--- 2. Renderização de Capturas Reais (Vulkan Forward+) ---")
	await _render_all_shots()

	# -------------------------------------------------------------
	# CONCLUSÃO
	# -------------------------------------------------------------
	print("\n=======================================================")
	if failures.is_empty():
		print("=== SUCESSO TOTAL: 0 FALHAS NOS MODELOS REVIEW 0908 ===")
		print("=======================================================\n")
		quit(0)
	else:
		printerr("=== ENCONTRADAS %d FALHAS ===" % failures.size())
		for f in failures:
			printerr("  - " + f)
		print("=======================================================\n")
		quit(1)

func _render_all_shots() -> void:
	var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"

	# Cena de renderização isolada
	var world := Node3D.new()
	world.name = "ReviewWorld3D"
	root.add_child(world)

	# Iluminação suave e natural de inverno
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 32.0, 0.0)
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	world.add_child(sun)

	var sky_fill := DirectionalLight3D.new()
	sky_fill.rotation_degrees = Vector3(45.0, -145.0, 0.0)
	sky_fill.light_color = Color(0.70, 0.84, 0.98)
	sky_fill.light_energy = 0.45
	world.add_child(sky_fill)

	# Chão de neve
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	ground.mesh = plane
	var g_mat := StandardMaterial3D.new()
	g_mat.albedo_color = Color("#e5ebf0")
	g_mat.roughness = 0.95
	ground.material_override = g_mat
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.name = "ReviewCamera"
	cam.current = true
	world.add_child(cam)

	# -------------------------------------------------------------
	# CAPTURA 1: FACHADA DA LOJA DE ARMAS (MountainGunShop3D) + HUMANO 1,80 M
	# -------------------------------------------------------------
	var gun_shop = GUN_SHOP_EXT_SCRIPT.new()
	world.add_child(gun_shop)
	var human_shop = HUMAN_SCRIPT.new(Color("#2c3e50"), Color("#c0392b"))
	human_shop.position = Vector3(0.9, 0.14, 3.25) # Em pé na varanda em frente à porta
	world.add_child(human_shop)

	cam.position = Vector3(0.0, 3.2, 8.8)
	cam.look_at(Vector3(0.0, 2.2, 1.5))
	for i in range(12):
		await process_frame

	var img_shop := root.get_viewport().get_texture().get_image()
	if img_shop:
		img_shop.save_png("res://tests/review_gun_shop_facade.png")
		img_shop.save_png(artifact_dir + "/review_gun_shop_facade.png")
		print("  [OK] Captura 1 salva: Fachada Gun Shop + Humano 1,80m")

	gun_shop.queue_free()
	human_shop.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# CAPTURA 2: INTERIOR DA LOJA DE ARMAS (MountainGunShopInterior3D) + HUMANO
	# -------------------------------------------------------------
	var gun_int = GUN_SHOP_INT_SCRIPT.new()
	world.add_child(gun_int)
	var human_int = HUMAN_SCRIPT.new(Color("#1a252f"), Color("#27ae60"))
	human_int.position = Vector3(-0.4, 0.05, 1.8) # Cliente no balcão de atendimento
	world.add_child(human_int)

	cam.position = Vector3(0.0, 4.8, 6.2)
	cam.look_at(Vector3(0.0, 1.2, -0.6))
	for i in range(12):
		await process_frame

	var img_int := root.get_viewport().get_texture().get_image()
	if img_int:
		img_int.save_png("res://tests/review_gun_shop_interior.png")
		img_int.save_png(artifact_dir + "/review_gun_shop_interior.png")
		print("  [OK] Captura 2 salva: Interior Gun Shop + Humano no Balcão")

	gun_int.queue_free()
	human_int.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# CAPTURA 3: AVIÃO CARGUEIRO ACIDENTADO (VISÃO EXTERNA & RAMPA TRASEIRA)
	# -------------------------------------------------------------
	var plane_ext = CARGO_PLANE_SCRIPT.new()
	world.add_child(plane_ext)
	var human_plane = HUMAN_SCRIPT.new(Color("#34495e"), Color("#d35400"))
	human_plane.position = Vector3(1.4, 0.0, 9.4) # Humano ao lado da rampa aberta tocando o chão
	world.add_child(human_plane)

	cam.position = Vector3(9.5, 5.2, 17.0)
	cam.look_at(Vector3(0.0, 2.5, 4.0))
	for i in range(12):
		await process_frame

	var img_plane := root.get_viewport().get_texture().get_image()
	if img_plane:
		img_plane.save_png("res://tests/review_crashed_plane_ramp.png")
		img_plane.save_png(artifact_dir + "/review_crashed_plane_ramp.png")
		print("  [OK] Captura 3 salva: Cargueiro Acidentado + Rampa Aberta + Humano")

	# -------------------------------------------------------------
	# CAPTURA 4: AVIÃO CARGUEIRO COM TETO CUTAWAY ATIVO (INTERIOR CAMINHÁVEL)
	# -------------------------------------------------------------
	plane_ext.set_cutaway(true)
	# Move humano para dentro do compartimento de carga
	human_plane.position = Vector3(0.0, 0.20, 0.0) # Caminhando entre os roletes e caixas
	cam.position = Vector3(0.0, 7.8, 4.5)
	cam.look_at(Vector3(0.0, 1.2, -2.5))
	for i in range(12):
		await process_frame

	var img_cutaway := root.get_viewport().get_texture().get_image()
	if img_cutaway:
		img_cutaway.save_png("res://tests/review_crashed_plane_cutaway.png")
		img_cutaway.save_png(artifact_dir + "/review_crashed_plane_cutaway.png")
		print("  [OK] Captura 4 salva: Cargueiro Cutaway Ativo (Interior Caminhável)")

	plane_ext.queue_free()
	human_plane.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# CAPTURA 5: ABRIGO DE LENHADOR APRIMORADO (FERRAMENTAS, SERRA, BANCO)
	# -------------------------------------------------------------
	var cabin_shot = CABIN_SCRIPT.new()
	world.add_child(cabin_shot)
	var human_cabin = HUMAN_SCRIPT.new(Color("#2c3e50"), Color("#c0392b"))
	human_cabin.position = Vector3(0.8, 0.0, 2.5) # Ao lado da serra traçadeira e porta
	world.add_child(human_cabin)

	cam.position = Vector3(-0.6, 2.2, 5.8)
	cam.look_at(Vector3(-0.4, 1.4, 1.2))
	for i in range(12):
		await process_frame

	var img_cabin := root.get_viewport().get_texture().get_image()
	if img_cabin:
		img_cabin.save_png("res://tests/review_lumberjack_shelter_tools.png")
		img_cabin.save_png(artifact_dir + "/review_lumberjack_shelter_tools.png")
		print("  [OK] Captura 5 salva: Abrigo de Lenhador com Ferramentas e Banco")

	cabin_shot.queue_free()
	human_cabin.queue_free()
	world.queue_free()
	await process_frame
	quit()
