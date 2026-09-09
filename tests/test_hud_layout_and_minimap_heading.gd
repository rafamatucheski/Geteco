extends SceneTree
## Testes de:
## 1) Sobreposição corrigida entre o card de objetivo de missão, o bloco de
##    temperatura/proteção térmica (ColdStatusHUD.gd) e o readout de
##    altitude (MountainExpedition.gd), sem cortar texto.
## 2) A seta do pedestre no minimapa (ui/HarborMinimap.gd) acompanha a
##    direção real de movimento, conserva a última direção ao parar, e usa
##    a orientação do veículo ao dirigir -- preservando os ícones da
##    Monaliza e do spray.
## 3) Legibilidade/quebra de linha dos avisos temporários.
##
## Roda sem --headless para também tirar capturas reais em 1280x720 e numa
## resolução maior (1920x1080):
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --path "D:/geteco/game" --script res://tests/test_hud_layout_and_minimap_heading.gd

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func frames(n: int) -> void:
	for i in n: await process_frame

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " -> ", err)

func run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	# Start from an authored post-arrival state; the real opening has its own
	# end-to-end regression test. Never delete a live CGI to unlock this fixture.
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	await frames(30)
	var world := current_scene
	var player: Node2D = world.get_node("Player")
	var map = world.get_node("Minimap")
	var stream = world.get_node("ContinuousWorld")
	var arrival_mission = world.get_node_or_null("ArrivalMission")
	check(not (arrival_mission != null and is_instance_valid(arrival_mission.get("_opening_layer"))), "post-arrival fixture starts without an opening CGI layer")

	# ==========================================
	# MINIMAPA: heading do pedestre acompanha o movimento real
	# ==========================================
	player.set_physics_process(false)
	player.global_position = Vector2(700, 1700)

	player.velocity = Vector2(220, 0) # leste
	map.refresh()
	check(is_equal_approx(map.heading, Vector2(220, 0).angle()), "pedestrian heading follows real movement direction (leste)")

	player.velocity = Vector2(0, -180) # norte
	map.refresh()
	check(is_equal_approx(map.heading, Vector2(0, -180).angle()), "pedestrian heading follows real movement direction (norte)")

	player.velocity = Vector2(-150, 150) # sudoeste
	map.refresh()
	check(is_equal_approx(map.heading, Vector2(-150, 150).angle()), "pedestrian heading follows real movement direction (sudoeste)")

	var held_heading: float = map.heading
	player.velocity = Vector2.ZERO
	map.refresh()
	check(is_equal_approx(map.heading, held_heading), "pedestrian heading holds the last direction while stopped")

	player.velocity = Vector2(3, 0) # ruído abaixo do limiar de "parado"
	map.refresh()
	check(is_equal_approx(map.heading, held_heading), "residual velocity below the stop threshold does not jitter the held heading")

	await _shot("D:/geteco/game/tests/_capture_minimap_pedestrian_heading.png")

	# ==========================================
	# MINIMAPA: dirigindo usa a orientação real do veículo
	# ==========================================
	var manager: Node = world.get_node("PersonalCarManager")
	var car: Node2D = manager.car
	var was_unlocked: bool = car.unlocked
	car.unlocked = true # estado mínimo p/ testar enter_vehicle(); não é uma edição de arquivo fonte
	car.global_position = player.global_position + Vector2(60, 0)
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	car.enter_vehicle(player)
	await frames(3)

	car.rotation = PI * 0.5
	map.refresh()
	check(is_equal_approx(wrapf(map.heading, -PI, PI), wrapf(car.global_rotation, -PI, PI)), "driving heading matches the vehicle's real orientation (90°)")

	car.rotation = -PI * 0.35
	map.refresh()
	check(is_equal_approx(wrapf(map.heading, -PI, PI), wrapf(car.global_rotation, -PI, PI)), "driving heading tracks vehicle rotation changes (-63°)")

	car.exit_vehicle()
	car.unlocked = was_unlocked
	await frames(3)

	# ==========================================
	# MINIMAPA: ícones da Monaliza e do spray preservados (chamadas de desenho intactas)
	# ==========================================
	var minimap_source := (map.get_script() as GDScript).source_code
	check(minimap_source.contains("service_marker") and minimap_source.contains("aerosol"), "spray icon draw block preserved (aerosol silhouette comment + service_marker)")
	check(minimap_source.contains("car_marker") and minimap_source.contains("show_car"), "Monaliza marker draw block preserved (car_marker + show_car)")

	# ==========================================
	# HUD: coluna esquerda (objetivo / frio / altitude) sem sobreposição
	# ==========================================
	if not stream.ready_for_crossing:
		stream.ensure_mountain()
	var wait_frames := 0
	while not stream.ready_for_crossing and wait_frames < 600:
		await process_frame
		wait_frames += 1
	check(stream.ready_for_crossing, "mountain region finished streaming in for the HUD test")

	var mountain: Node2D = stream.mountain
	var cold_hud = mountain.cold_hud
	var expedition = mountain.get_node("MountainExpedition")
	await frames(3)

	# Card de objetivo (não editado por esta tarefa) -- mede o que existe de
	# verdade em vez de assumir, para validar a margem de segurança.
	var objective_card: Control = world.get_node("CobraCampaign").get("_objective_card")
	var objective_bottom := 150.0
	if objective_card != null:
		await frames(1) # 1 frame de layout para o VBoxContainer calcular a altura real
		objective_bottom = objective_card.position.y + objective_card.size.y
		check(objective_bottom <= cold_hud.BLOCK_TOP, "cold HUD block starts at/after the real measured bottom of the objective card (%.1f <= %.1f)" % [objective_bottom, cold_hud.BLOCK_TOP])
	else:
		check(false, "objective card not found (CobraCampaign._objective_card) -- could not measure the real overlap margin")

	var cold_bottom: float = cold_hud.get_stack_bottom_offset()
	check(is_instance_valid(expedition._readout_panel), "altitude readout panel exists")
	check(expedition._readout_panel.position.y >= cold_bottom, "altitude readout starts at/after the cold HUD's documented stack offset (%.1f >= %.1f)" % [expedition._readout_panel.position.y, cold_bottom])

	check(is_instance_valid(expedition._prompt_panel), "temporary notice panel exists")
	check(expedition._prompt_panel.position.y > expedition._readout_panel.position.y, "temporary notice panel sits below the altitude readout")

	# Move o jogador para dentro da região da montanha (x>=SEAM_X, y<-2000)
	# para os textos reais (temperatura/altitude) aparecerem.
	player.global_position = Vector2(9000, -3500)
	mountain.player_instance = player
	stream._update_region()
	await frames(5)
	map.refresh()
	check(cold_hud.visible, "cold HUD becomes visible once the mountain region is selected")
	check(expedition.readout.text != "", "altitude readout has real text once inside the mountain region")

	expedition._notice("funds", "Você precisa de $650 para o casaco térmico e mais um pouco de texto para testar a quebra de linha automática sem cortar nada.")
	await frames(1)
	check(expedition._prompt_panel.visible, "notice panel becomes visible when a temporary notice is active")

	# ==========================================
	# Nenhum HUD por cima da CGI: simula uma CGI ativa outra vez e confirma
	# que os dois blocos se escondem, depois voltam quando ela "termina".
	# ==========================================
	if arrival_mission != null:
		var fake_cgi_layer := CanvasLayer.new()
		arrival_mission.set("_opening_layer", fake_cgi_layer)
		await frames(2)
		check(not cold_hud.get("_panel").visible, "cold HUD hides itself while the opening CGI is active")
		check(not expedition._readout_panel.visible, "altitude readout hides itself while the opening CGI is active")
		check(not expedition._prompt_panel.visible, "temporary notice panel hides itself while the opening CGI is active")
		fake_cgi_layer.queue_free()
		arrival_mission.set("_opening_layer", null)
		await frames(2)
		map.refresh()
		check(cold_hud.get("_panel").visible, "cold HUD reappears once the CGI is gone")
		check(expedition._readout_panel.visible, "altitude readout reappears once the CGI is gone")
	else:
		check(false, "ArrivalMission node not found -- could not test the CGI/HUD guard")
	check(expedition.prompt.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "temporary notice label wraps instead of clipping long text")
	check(expedition.prompt.custom_minimum_size.x > 0 and expedition.prompt.custom_minimum_size.x < 700, "temporary notice label has a bounded width (wraps within the HUD column, not full-screen)")

	# ==========================================
	# CAPTURAS REAIS: 1280x720 (base do projeto) e uma resolução maior
	# ==========================================
	var camera := root.get_camera_2d()
	if is_instance_valid(camera):
		camera.global_position = player.global_position
		camera.reset_smoothing()
	await frames(3)

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	await frames(3)
	await _shot("D:/geteco/game/tests/_capture_hud_stack_1280x720.png")

	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	await frames(3)
	await _shot("D:/geteco/game/tests/_capture_hud_stack_1920x1080.png")

	print("HUD_LAYOUT_MINIMAP_TEST failures=", failures)
	quit(0 if failures.is_empty() else 1)
