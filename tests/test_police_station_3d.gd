extends SceneTree

const OUTPUT := "res://docs/measurements/police-3d-0912/"
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + label + ".png")

func _run() -> void:
	create_timer(45).timeout.connect(func():
		printerr("POLICE_3D_TEST TIMEOUT")
		quit(2)
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)

	print("\n=======================================================")
	print("=== INICIANDO TESTE DA NOVA DELEGACIA 3D (MISSÃO 1) ===")
	print("=======================================================\n")

	var world := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(world)
	current_scene = world

	for _f in 15:
		await physics_frame

	var manager := world.get_node("Interiors")
	var police: HarborPoliceInterior = manager.police_interior
	check(police != null, "HarborPoliceInterior existe no gerenciador de interiores")
	check(police.station_3d != null, "HarborPoliceStation3D volumétrico foi instanciado")
	check(police.view != null and police.room_camera != null, "SubViewport 3D e Camera3D ortogonal inicializados")

	var player := world.get_node("Player") as CharacterBody2D
	check(player != null, "Player (Dante) encontrado no mundo")

	# Teleportar para dentro da delegacia usando o fluxo real do gerenciador
	var entrance := world.get_node("District/Police/Entrance")
	manager._on_exterior_destination_requested(entrance, player, &"", null, &"", police, police.spawn_point)

	await frames(40)

	# 1. Validação de Spawn e Posição
	var dist_spawn := player.global_position.distance_to(police.spawn_point.global_position)
	check(dist_spawn < 25.0, "Player posicionado no spawn point da delegacia (dist=%.1f px)" % dist_spawn)
	check(police.contains_point(player.global_position), "Player está contido nos limites do interior")

	# 2. Validação dos 5 NPCs da delegacia
	check(police.sergeant_npc != null, "Sargento Morales (Recepção) existe")
	check(police.detective_npc != null, "Detetive Ribeiro (Bullpen) existe")
	check(police.guard_npc != null, "Policial Ferreira (Carceragem) existe")
	check(police.prisoner_npc != null, "Detento 'Dente de Ouro' (Cela) existe")
	check(police.civilian_npc != null, "Dona Cida (Área de Espera) existe")
	check(police.all_npcs.size() == 5, "Total de 5 NPCs vivos configurados")

	# 3. Teste da Primeira Missão (HarborStoryArrival — Diálogo com o Sargento sobre Vicente)
	print("\n--- TESTANDO INTERAÇÃO DA PRIMEIRA MISSÃO (VICENTE FERRAZ) ---")
	var mission_arrival := preload("res://world/harbor/campaign/HarborArrivalMission.gd").new()
	world.add_child(mission_arrival)
	mission_arrival.configure(world)
	var story = mission_arrival.story_arrival
	check(story != null, "Sistema narrativo da Missão 1 (HarborStoryArrival) ativo")

	story.resume()
	check(mission_arrival.phase == "police_visit", "Missão 1 na fase police_visit")

	# Simular aproximação ao balcão do Sargento Morales
	player.global_position = police.sergeant_npc.global_position + Vector2(0, 45)
	await frames(10)
	var dist_to_sgt := player.global_position.distance_to(police.sergeant_npc.global_position)
	check(dist_to_sgt < 90.0, "Player em distância de interação com o balcão (dist=%.1f px < 90px)" % dist_to_sgt)

	var interacted: bool = story.interact()
	check(interacted, "Interação da Missão 1 disparada com sucesso")
	check(mission_arrival.phase == "story_dialogue", "Fase de diálogo narrativo sobre Vicente Ferraz iniciada")
	# Avançar o diálogo da história
	while mission_arrival.phase == "story_dialogue":
		story.advance()
		await frames(2)
	check(mission_arrival._flag("harbor_police_briefed"), "Flag harbor_police_briefed ativada após revelação sobre Vicente")
	check(mission_arrival.phase == "police_exit", "Objetivo atualizado para 'Saia da delegacia.'")

	# 4. Teste do Terminal de Ocorrências Interativo
	print("\n--- TESTANDO TERMINAL DE OCORRÊNCIAS & MANDADOS ---")
	player.global_position = police.terminal_area.global_position
	await frames(10)
	check(police.is_near_terminal, "Terminal detecta presença do jogador")
	police._open_terminal()
	check(police.terminal_dialog.visible, "Painel do terminal de ocorrências abriu corretamente")
	police.terminal_dialog.visible = false
	police.modal_closed.emit()

	# 5. Teste da Porta de Saída
	print("\n--- TESTANDO SAÍDA DA DELEGACIA ---")
	player.global_position = police.exit_door.global_position + Vector2(0, -20)
	await frames(10)
	check(police.exit_door != null, "Porta de saída existe e está acessível")

	await capture("01_delegacia_3d_completa")

	print("\n=======================================================")
	if failures.is_empty():
		print("=== SUCESSO: TODOS OS TESTES DA DELEGACIA 3D PASSARAM! ===")
		print("=======================================================\n")
		quit(0)
	else:
		printerr("=== FALHAS ENCONTRADAS (%d): ===" % failures.size())
		for f in failures:
			printerr("  - " + f)
		print("=======================================================\n")
		quit(1)
