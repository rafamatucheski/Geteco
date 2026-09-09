extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 04 — Conversa com Maciota + interação com a lousa (quadro de missões)
## Real production NPC (JagerNPC.gd, wrapped as garage.jager_npc) and real
## mission board (CarChalkboard.gd, wrapped as garage.mission_board), reached
## with real key presses inside the real HarborGame.tscn garage interior.
## tests/test_maciota_interrupted_conversation.gd already covers the
## "walk away mid-conversation" edge case in depth, so this audit instead
## targets: a full real conversation to completion, REPEATED re-approaches
## after unlock (not just once), repeated chalkboard open/close, and the full
## primeiro_giro contract (accept -> pickup -> deliver -> reward) including
## idempotency of repeated interaction after it is already complete.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "04_maciota_and_chalkboard"
	arm_watchdog(90.0)

	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	isolate_saves(_tag)
	# Flags set BEFORE instantiation (single start_or_resume() call) — resume
	# straight at "meet_maciota", same convention as
	# tests/test_maciota_interrupted_conversation.gd.
	campaign.set_campaign_flag(&"harbor_arrival_seen", true)
	campaign.set_campaign_flag(&"harbor_arrival_call_complete", true)

	var world := await boot_harbor(20)
	var mission: Node = world.get("campaign_controller")
	var player: CharacterBody2D = world.get_node("Player")
	var garage: Node2D = world.get_node("Interiors").garage_interior
	var npc: Node2D = garage.jager_npc
	var board: Node2D = garage.mission_board

	check(String(mission.get_campaign_status().get("phase", "")) == "meet_maciota", "Fluxo real chega em 'meet_maciota' antes desta auditoria começar")

	print("\n[ETAPA 1] Conversa completa e real com Maciota (tecla E + Espaço até o fim)")
	player.global_position = npc.interact_area.global_position
	await physics_frames(8)
	await press_key(KEY_E)
	check(npc.is_talking, "Tecla E abre a conversa real com Maciota")
	await capture("04_maciota_conversation_open")
	var advances := 0
	while npc.is_talking and advances < 15:
		await press_key(KEY_SPACE)
		advances += 1
	check(not npc.is_talking, "A conversa termina sozinha após um número finito de falas (%d avanços)" % advances)
	check(String(mission.get_campaign_status().get("phase", "")) == "board", "Conversa completa avança a campanha para a fase 'board'")
	check(board.interaction_enabled, "Quadro de missões desbloqueia de verdade após a conversa completa")
	check(bool(campaign.has_campaign_flag(&"harbor_maciota_met")), "harbor_maciota_met é setada pela conversa real")

	print("\n[ETAPA 2] Repetição: reabordar Maciota depois de desbloqueado, 3 vezes seguidas")
	for cycle in range(3):
		player.global_position = npc.interact_area.global_position + Vector2(0, 600)
		await physics_frames(6)
		player.global_position = npc.interact_area.global_position
		await physics_frames(6)
		await press_key(KEY_E)
		check(npc.is_talking, "Ciclo %d: Maciota ainda responde normalmente depois de já concluído" % cycle)
		var closes := 0
		while npc.is_talking and closes < 8:
			await press_key(KEY_SPACE)
			closes += 1
		check(not npc.is_talking, "Ciclo %d: a conversa de acompanhamento também termina sozinha" % cycle)
		check(board.interaction_enabled, "Ciclo %d: repetir a conversa não relockeia o quadro de missões" % cycle)

	print("\n[ETAPA 3] Lousa: abrir/fechar repetidamente com tecla real (E), 3x")
	player.global_position = board.global_position + Vector2(0, 25)
	await physics_frames(8)
	for cycle in range(3):
		await press_key(KEY_E)
		check(board.is_ui_open, "Ciclo %d: tecla E abre a lousa (já desbloqueada)" % cycle)
		if cycle == 0:
			await capture("04_mission_board_open")
		await press_key(KEY_ESCAPE)
		check(not board.is_ui_open, "Ciclo %d: ESC fecha a lousa de novo" % cycle)

	print("\n[ETAPA 4] Contrato 'primeiro_giro' completo: aceitar -> buscar -> entregar -> recompensa")
	var money_before: int = int(player.get("money"))
	await press_key(KEY_E)
	check(board.is_ui_open, "Lousa aberta para aceitar o contrato")
	var accepted: bool = mission.accept_mission("primeiro_giro")
	check(accepted, "accept_mission('primeiro_giro') funciona a partir da fase 'board'")
	check(String(mission.get_campaign_status().get("phase", "")) == "delivery_pickup", "Aceitar o contrato avança para 'delivery_pickup'")
	board.close_chalkboard()

	var pickup_target: Vector2 = world.get_node("FirstDeliveryPickup").global_position
	player.global_position = pickup_target
	await physics_frames(8)
	var picked_up: bool = mission.interact_with_objective()
	check(picked_up, "Interagir no ponto de coleta recolhe a encomenda")
	check(String(mission.get_campaign_status().get("phase", "")) == "delivery_return", "Coleta avança para 'delivery_return'")

	# HarborArrivalMission.interact_with_objective() checks distance to the
	# NPC's own origin (garage.jager_npc.global_position), not its interact_area
	# — a different anchor than JagerNPC's own conversation trigger above.
	player.global_position = npc.global_position + Vector2(0, 30)
	await physics_frames(8)
	var delivered: bool = mission.interact_with_objective()
	check(delivered, "Entregar a Maciota conclui o contrato")
	check(int(player.get("money")) == money_before + 150, "Recompensa de $150 é paga exatamente uma vez")
	check(bool(campaign.has_campaign_flag(&"harbor_delivery_complete")), "harbor_delivery_complete é setada pela entrega real")

	print("\n[ETAPA 5] Idempotência: interagir de novo após a conclusão não deve pagar de novo nem travar")
	var repeat_result: bool = mission.interact_with_objective()
	check(not repeat_result, "interact_with_objective() depois de completo retorna falso (idempotente)")
	check(int(player.get("money")) == money_before + 150, "Nenhum pagamento duplicado ocorre ao repetir a interação")

	await finish(_tag, world)
