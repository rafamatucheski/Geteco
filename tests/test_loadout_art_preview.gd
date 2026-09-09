@tool
extends SceneTree

## Suíte de Testes e Renderização da Prévia 3D do Porta-Malas do Summit SUV
## Valida contratos de engenharia, animação da dobradiça, reatividade aos slots
## da Astra ("curta", "longa", "corpo") e renderiza capturas reais com o manequim de 1,80 m.

const TRUNK_SCRIPT := preload("res://world/mountain_pass/art/loadout_preview/SummitSUVLoadoutTrunk3D.gd")
const HUMAN_SCRIPT := preload("res://world/mountain_pass/art/winter_props/HumanScaleReference3D.gd")

var failures: Array[String] = []
var mesh_count: int = 0

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
	print("\n==================================================================")
	print("=== TESTE DA PRÉVIA 3D PROCEDURAL: PORTA-MALAS SUMMIT SUV 4X4 ===")
	print("==================================================================\n")

	# --------------------------------------------------------------------------
	# 1. VALIDAÇÃO DE CONTRATOS E ESTRUTURA DO NÓ
	# --------------------------------------------------------------------------
	print("--- 1. Validação de Contratos de Engenharia e Nós ---")
	var trunk = TRUNK_SCRIPT.new()
	root.add_child(trunk)
	await process_frame
	await process_frame

	_check(trunk is Node3D, "SummitSUVLoadoutTrunk3D herda de Node3D")
	_check(trunk.footprint_size == Vector2(2.05, 2.20), "footprint_size é (2.05, 2.20)m")
	_check(trunk.load_floor_height == 0.68, "load_floor_height é 0.68m (ergonomia de carga)")
	_check(trunk.has_node("TailgateHingePivot"), "Possui nó articulado TailgateHingePivot")
	_check(trunk.has_node("PistolHardCase"), "Possui estojo rígido PistolHardCase")
	_check(trunk.has_node("MeleeMountBracket"), "Possui suporte tático MeleeMountBracket")
	_check(trunk.slot_longa_root != null, "Nó slot_longa_root inicializado")
	_check(trunk.slot_curta_root != null, "Nó slot_curta_root inicializado")
	_check(trunk.slot_corpo_root != null, "Nó slot_corpo_root inicializado")

	# --------------------------------------------------------------------------
	# 2. VALIDAÇÃO DA DOBRADIÇA E ANIMAÇÃO DA TAMPA TRASEIRA
	# --------------------------------------------------------------------------
	print("\n--- 2. Validação da Dobradiça e Abertura/Fechamento ---")
	# Teste de fechamento imediato
	trunk.set_open(false, true)
	_check(trunk.is_open == false, "set_open(false, true) atualiza is_open para false")
	_check(trunk.open_ratio == 0.0, "open_ratio é 0.0 quando fechada")
	_check(is_equal_approx(trunk.door_pivot.rotation_degrees.x, 0.0), "Ângulo da dobradiça é 0.0 graus (fechada)")

	# Teste de abertura imediata
	trunk.set_open(true, true)
	_check(trunk.is_open == true, "set_open(true, true) atualiza is_open para true")
	_check(trunk.open_ratio == 1.0, "open_ratio é 1.0 quando aberta")
	_check(is_equal_approx(trunk.door_pivot.rotation_degrees.x, 82.0), "Ângulo da dobradiça é 82.0 graus (totalmente aberta)")

	# Teste de interpolação suave
	trunk.set_open(false, false)
	_check(trunk._target_open_ratio == 0.0, "_target_open_ratio atualizado para 0.0 para interpolação suave")
	trunk._process(0.1)
	_check(trunk.open_ratio < 1.0 and trunk.open_ratio > 0.0, "Interpolação de abertura em andamento (open_ratio = %.3f)" % trunk.open_ratio)
	trunk.set_open(true, true) # Restaura aberta para a renderização

	# --------------------------------------------------------------------------
	# 3. VALIDAÇÃO DA REATIVIDADE AOS SLOTS DO LOADOUT
	# --------------------------------------------------------------------------
	print("\n--- 3. Validação dos Slots de Armas da Astra ---")
	# Loadout padrão
	var default_loadout: Dictionary = trunk.get_loadout()
	_check(default_loadout.get("curta") == "pistol", "Slot curta inicial é 'pistol'")
	_check(default_loadout.get("longa") == "rifle", "Slot longa inicial é 'rifle'")
	_check(default_loadout.get("corpo") == "knife", "Slot corpo inicial é 'knife'")

	# Troca para armas alternativas
	var alt_loadout := {
		"curta": "smg",
		"longa": "shotgun",
		"corpo": "bat"
	}
	trunk.set_loadout(alt_loadout)
	await process_frame
	var cur = trunk.get_loadout()
	_check(cur.get("curta") == "smg", "set_loadout atualizou curta para 'smg'")
	_check(cur.get("longa") == "shotgun", "set_loadout atualizou longa para 'shotgun'")
	_check(cur.get("corpo") == "bat", "set_loadout atualizou corpo para 'bat'")

	mesh_count = _count_meshes(trunk)
	print("  [INFO] Total de meshes no modelo do porta-malas: %d" % mesh_count)

	trunk.queue_free()
	await process_frame

	# --------------------------------------------------------------------------
	# 4. RENDERIZAÇÃO REAL DE CAPTURAS NO GODOT 4.7.2 (VULKAN FORWARD+)
	# --------------------------------------------------------------------------
	print("\n--- 4. Renderização Visual com Manequim de 1,80 m ---")
	await _render_all_shots()

	# --------------------------------------------------------------------------
	# CONCLUSÃO
	# --------------------------------------------------------------------------
	print("\n==================================================================")
	if failures.is_empty():
		print("=== SUCESSO TOTAL: 0 FALHAS NA PRÉVIA DO PORTA-MALAS (09/08) ===")
		print("==================================================================\n")
		quit(0)
	else:
		printerr("=== ENCONTRADAS %d FALHAS ===" % failures.size())
		for f in failures:
			printerr("  - " + f)
		print("==================================================================\n")
		quit(1)

func _render_all_shots() -> void:
	var artifact_dir := "C:/Users/rafae/.gemini/antigravity/brain/4a0f8662-6ef0-43ba-8d58-499a8b90d797"

	var world := Node3D.new()
	world.name = "LoadoutWorld3D"
	root.add_child(world)

	# Iluminação direcional de inverno
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	sun.light_color = Color(1.0, 0.98, 0.95)
	sun.light_energy = 1.40
	sun.shadow_enabled = true
	world.add_child(sun)

	var sky_fill := DirectionalLight3D.new()
	sky_fill.rotation_degrees = Vector3(50.0, -140.0, 0.0)
	sky_fill.light_color = Color(0.72, 0.85, 0.98)
	sky_fill.light_energy = 0.50
	world.add_child(sky_fill)

	# Piso de neve
	var ground := MeshInstance3D.new()
	var pmesh := PlaneMesh.new()
	pmesh.size = Vector2(40.0, 40.0)
	ground.mesh = pmesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color("#eaf0f4")
	gmat.roughness = 0.95
	ground.material_override = gmat
	world.add_child(ground)

	var cam := Camera3D.new()
	cam.name = "RenderCamera"
	cam.current = true
	world.add_child(cam)

	# Instancia o porta-malas e o manequim humano
	var trunk = TRUNK_SCRIPT.new(true, {"curta": "pistol", "longa": "rifle", "corpo": "knife"})
	world.add_child(trunk)

	var human = HUMAN_SCRIPT.new(Color("#2c3e50"), Color("#c0392b"))
	human.position = Vector3(1.25, 0.0, 2.30) # Em pé ao lado do para-choque traseiro
	human.rotation_degrees.y = -25.0
	world.add_child(human)

	# --------------------------------------------------------------------------
	# CAPTURA 1: VISÃO GERAL TRASEIRA COM PORTA ABERTA & MANEQUIM DE 1,80 M
	# --------------------------------------------------------------------------
	cam.position = Vector3(0.65, 1.85, 4.85)
	cam.look_at(Vector3(0.15, 1.15, 1.80))
	for i in range(12):
		await process_frame

	var img1 := root.get_viewport().get_texture().get_image()
	if img1:
		img1.save_png("res://tests/test_loadout_trunk_open.png")
		img1.save_png(artifact_dir + "/test_loadout_trunk_open.png")
		print("  [OK] Captura 1 salva: Visão Geral Porta-Malas Aberto + Humano 1,80m")

	# --------------------------------------------------------------------------
	# CAPTURA 2: CLOSE-UP DOS 3 SLOTS DE ARMAS E ACABAMENTOS (BORRACHA/TECIDO)
	# --------------------------------------------------------------------------
	cam.position = Vector3(0.0, 1.45, 2.75)
	cam.look_at(Vector3(0.0, 0.72, 1.62))
	for i in range(12):
		await process_frame

	var img2 := root.get_viewport().get_texture().get_image()
	if img2:
		img2.save_png("res://tests/test_loadout_trunk_closeup.png")
		img2.save_png(artifact_dir + "/test_loadout_trunk_closeup.png")
		print("  [OK] Captura 2 salva: Close-up dos 3 Slots de Armas e Acabamento")

	# --------------------------------------------------------------------------
	# CAPTURA 3: CONFIGURAÇÃO ALTERNATIVA DE ARMAS (SHOTGUN, SMG, TACO)
	# --------------------------------------------------------------------------
	trunk.set_loadout({"curta": "smg", "longa": "shotgun", "corpo": "bat"})
	for i in range(12):
		await process_frame

	var img3 := root.get_viewport().get_texture().get_image()
	if img3:
		img3.save_png("res://tests/test_loadout_trunk_alt_weapons.png")
		img3.save_png(artifact_dir + "/test_loadout_trunk_alt_weapons.png")
		print("  [OK] Captura 3 salva: Loadout Alternativo (Shotgun, SMG, Taco)")

	# --------------------------------------------------------------------------
	# CAPTURA 4: TAMPA FECHADA (ALINHAMENTO DA CARROCERIA, VIDRO E LANTERNAS)
	# --------------------------------------------------------------------------
	trunk.set_open(false, true)
	cam.position = Vector3(0.50, 1.70, 5.20)
	cam.look_at(Vector3(0.0, 1.10, 2.00))
	for i in range(12):
		await process_frame

	var img4 := root.get_viewport().get_texture().get_image()
	if img4:
		img4.save_png("res://tests/test_loadout_trunk_closed.png")
		img4.save_png(artifact_dir + "/test_loadout_trunk_closed.png")
		print("  [OK] Captura 4 salva: Tampa Fechada com Alinhamento de Carroceria")

	trunk.queue_free()
	human.queue_free()
	world.queue_free()
	await process_frame
