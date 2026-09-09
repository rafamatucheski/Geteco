extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 10 — Percurso completo até a Ammu-Nation da montanha
## A loja de armas real e jogável "Timber Ridge Guns & Ammo"
## (district/mountain_pass/MountainGunShopFacade.gd, instalada por
## MountainSceneryBuilder.build_mountain_ammunation(), documentada em
## docs/MOUNTAIN_PLANE_SHOP_2026-09-08.md).
##
## Esta versão NÃO usa nenhum atalho/bypass: o jogador caminha de verdade
## (walk_to, entrada real via Input.action_press) desde uma posição próxima
## até a porta, aciona o sensor físico real e só avança para dentro da loja
## se a entrada real funcionar. Se a porta não detectar o jogador, o teste
## FALHA nesse ponto e para — não há teleporte de contorno.
##
## Histórico (ver AUDIT_REPORT.md): a primeira versão deste teste encontrou e
## documentou um bug real na porta (collision_mask=3 nunca incluía a camada
## do jogador, 4) e usava MountainInteriorManager._on_entrance_requested()
## diretamente como bypass para seguir testando o resto da loja. Esse bug foi
## corrigido localmente em MountainGunShopFacade.install_entrance() (agora
## atribui collision_mask=4 ao $InteractionArea desta porta especificamente,
## sem tocar no padrão da cena BuildingEntrance.tscn nem em outras portas).
## Este arquivo foi reescrito para provar a correção fim a fim, sem bypass.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "10_mountain_ammunation_full_path"
	# Ver AUDIT_REPORT.md ("Preparação da região da montanha é muito lenta em
	# headless"): medido isoladamente neste ambiente, ready_for_crossing só
	# fica verdadeiro depois de ~74s reais numa execução limpa (sem GPU real,
	# streaming orçado por quadro para interiores + expedição + povoado +
	# tráfego). O watchdog e o prazo de espera abaixo dão margem generosa para
	# não confundir "lento" com "não executado".
	arm_watchdog(240.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: CharacterBody2D = world.get_node("Player")
	var stream: Node = world.get_node("ContinuousWorld")

	print("\n[ETAPA 1] Preparando a região da montanha e localizando a loja real no mundo")
	player.global_position = Vector2(6300, -1500) # y < -1000 aciona ensure_mountain() em ContinuousWorld._process
	# Não chamamos stream.ensure_mountain() diretamente: uma segunda chamada
	# explícita cairia no guard "if building or ready_for_crossing: return" e
	# voltaria na hora, sem realmente esperar o término (ver test_audit_09).
	var region_ready: bool = await wait_until(
		func(): return bool(stream.get("ready_for_crossing")),
		150.0, "Região da montanha não terminou de preparar (ready_for_crossing)"
	)
	check(region_ready, "Região da montanha termina de preparar")
	if not region_ready:
		await finish(_tag, world)
		return

	var facade: Node2D = world.find_child("MountainAmmuNation", true, false)
	check(facade != null, "A fachada real 'MountainAmmuNation' existe no mundo (MountainSceneryBuilder.build_mountain_ammunation)")
	if facade == null:
		await finish(_tag, world)
		return
	var entrance: Node = facade.get("entrance")
	check(entrance != null, "A fachada tem uma porta real instalada (install_entrance -> register_exterior_entrance)")
	var interior: Node2D = stream.mountain.interior_manager.ammunation_interior
	check(interior != null and is_instance_valid(interior), "MountainInteriorManager expõe um ammunation_interior real e válido")
	if entrance == null or interior == null:
		await finish(_tag, world)
		return

	print("\n[ETAPA 2] Entrada real: caminhar pela circulação até a porta e acionar o sensor físico (sem bypass)")
	var sensor: Area2D = entrance.get_node("InteractionArea")
	# Ponto de partida a 160px da porta, na área aberta do alpendre em frente
	# à fachada (não em cima do sensor) — a aproximação em si é o que este
	# teste está verificando, não apenas a detecção final.
	var approach_start: Vector2 = sensor.global_position + Vector2(0, 160)
	player.global_position = approach_start
	player.velocity = Vector2.ZERO
	await physics_frames(5)

	var walked: bool = await walk_to(player, sensor.global_position, 300, 12.0)
	check(walked, "Jogador caminha de verdade (entrada real, sem obstáculo bloqueando) até o sensor da porta")

	await create_timer(0.4).timeout
	var sensor_detected: bool = entrance.is_actor_in_range(player)
	check(sensor_detected, "Sensor de proximidade real da porta detecta o jogador depois de caminhar até ela")
	if not sensor_detected:
		log_line("  [ACHADO] entrance InteractionArea: collision_layer=%d collision_mask=%d — player.collision_layer=%d. Sobreposição física real: %s" % [
			sensor.collision_layer, sensor.collision_mask, player.collision_layer, sensor.get_overlapping_bodies()
		])
		log_line("  [FALHA SEM CONTORNO] A entrada real falhou; o teste para aqui de propósito (nenhum teleporte de contorno é usado).")
		await finish(_tag, world)
		return

	await capture("10_real_entry_door_approach")
	var entered: bool = entrance.request_interaction(player)
	check(entered, "request_interaction() aceita a entrada real pela porta")
	if not entered:
		log_line("  [FALHA SEM CONTORNO] request_interaction() recusou; o teste para aqui de propósito.")
		await finish(_tag, world)
		return

	var teleported: bool = await wait_until(
		func(): return player.global_position.distance_to(interior.global_position) < 900.0,
		5.0, "Jogador não foi teleportado para dentro do interior após a entrada real"
	)
	check(teleported, "Após a entrada real pela porta, o jogador fica dentro do interior real da loja")
	check(bool(player.get_meta("mountain_interior", false)), "Meta 'mountain_interior' é setada pela entrada real (MountainInteriorManager._on_entrance_requested, via sinal — não chamado diretamente por este teste)")
	if not teleported:
		await finish(_tag, world)
		return
	await capture("10_real_entry_inside_shop")

	print("\n[ETAPA 3] Caminhar até o balcão e conversar de verdade com o armeiro Vance (tecla F)")
	var walked_to_counter: bool = await walk_to(player, interior.counter_area.global_position, 300, 12.0)
	check(walked_to_counter, "Jogador caminha de verdade do ponto de entrada até o balcão")
	await create_timer(0.4).timeout
	check(bool(interior.get("is_near_counter")), "Área real do balcão detecta o jogador")
	await press_key(KEY_F)
	check(bool(interior.gunsmith_npc.get("is_talking")), "Tecla F abre a conversa real com o armeiro Vance")
	await capture("10_vance_conversation_open")
	var dialogue_lines: int = interior.gunsmith_npc.dialogues.size()
	for i in range(dialogue_lines + 1): # avança por todas as falas + 1 (deve continuar falando, o diálogo do Vance é cíclico)
		await press_key(KEY_F)
	check(bool(interior.gunsmith_npc.get("is_talking")), "Diálogo cíclico do Vance continua aberto após dar a volta completa nas falas (repetição real, sem travar)")
	await press_key(KEY_ESCAPE)
	check(not bool(interior.gunsmith_npc.get("is_talking")), "ESC encerra a conversa com Vance de verdade")

	print("\n[ETAPA 4] Compra real pelo balcão (mesmos botões clicáveis da UI de produção)")
	player.set("money", 5000)
	var money_before: int = int(player.get("money"))
	await press_key(KEY_E)
	check(interior.counter_dialog.visible, "Tecla E abre o catálogo real de compra no balcão")
	await capture("10_purchase_catalog_open")
	var shotgun_button: Button = interior.weapon_buttons.get("shotgun")
	check(shotgun_button != null and not shotgun_button.disabled, "Botão real de compra da escopeta está habilitado")
	shotgun_button.pressed.emit() # mesmo caminho de um clique real do mouse
	check(int(player.get("money")) == money_before - int(WeaponCatalog.get_weapon("shotgun").price), "Compra pelo botão real debita o preço correto da escopeta")
	var inventory: Dictionary = player.get("weapon_inventory")
	check(bool(inventory.get("shotgun", false)), "Escopeta comprada pelo balcão real consta no inventário do jogador")

	print("\n[ETAPA 5] Recompra pelo mesmo botão deve recusar (produção: já possuída)")
	var money_after_first_buy: int = int(player.get("money"))
	shotgun_button.pressed.emit()
	if interior.has_method("_refresh_weapon_buttons"):
		interior._refresh_weapon_buttons()
	check(int(player.get("money")) == money_after_first_buy, "Clicar de novo no botão da mesma arma não debita dinheiro outra vez")

	print("\n[ETAPA 6] Reposição de munição pelo balcão real")
	var ammo_button: Button = null
	for child in interior.counter_text.get_parent().get_children():
		if child is Button and child.text.begins_with("MUNIÇÃO"):
			ammo_button = child
			break
	check(ammo_button != null, "Botão real de reposição de munição existe no balcão")
	if ammo_button:
		player.call("equip_weapon", "shotgun")
		var money_before_ammo: int = int(player.get("money"))
		ammo_button.pressed.emit()
		check(int(player.get("money")) == money_before_ammo - 120, "Reposição de munição pelo botão real debita $120")

	await press_key(KEY_ESCAPE)
	check(not interior.counter_dialog.visible, "ESC fecha o catálogo de compra")

	print("\n[ETAPA 7] Seleção real de arma com tecla numérica, dentro da própria loja")
	player.call("equip_weapon", "pistol")
	player.set("is_control_disabled", false)
	player.set("is_in_dialogue", false)
	await press_key(KEY_4) # mapeada para "shotgun" em Player._input
	check(str(player.get("active_weapon_id")) == "shotgun", "Tecla 4 seleciona a escopeta recém-comprada, dentro da loja")

	print("\n[ETAPA 8] Caminhar até a porta de saída e sair de verdade")
	var exit_door: Node = interior.get("exit_door")
	check(exit_door != null, "Interior tem uma porta de saída real")
	if exit_door == null:
		await finish(_tag, world)
		return
	var exit_sensor: Area2D = exit_door.get_node("InteractionArea")
	var walked_to_exit: bool = await walk_to(player, exit_sensor.global_position, 300, 12.0)
	check(walked_to_exit, "Jogador caminha de verdade do balcão até a porta de saída")
	await create_timer(0.4).timeout
	check(exit_door.is_actor_in_range(player), "Sensor da porta de saída detecta o jogador")
	var exited: bool = exit_door.request_interaction(player)
	check(exited, "request_interaction() aceita a saída real pela porta")
	var left_interior: bool = await wait_until(
		func(): return player.global_position.distance_to(interior.global_position) > 900.0,
		5.0, "Jogador não retornou fisicamente para fora da loja após a saída real"
	)
	check(not bool(player.get_meta("mountain_interior", false)), "Meta 'mountain_interior' é removida pela saída real")
	check(left_interior, "Jogador retorna fisicamente para fora da loja")
	if left_interior:
		await capture("10_real_exit_outside_shop")

	await finish(_tag, world)
