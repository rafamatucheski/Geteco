extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 01 — Chegada inicial e liberação do controle
## Real production entry point (res://world/harbor/HarborGame.tscn),
## real controller (world/harbor/campaign/HarborArrivalMission.gd),
## no campaign flags pre-set: exercises the actual first-boot path a fresh
## player experiences (arrival CGI -> disembark -> free-roam window -> phone
## call -> control released for real gameplay).

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "01_arrival_and_control_release"
	arm_watchdog(90.0)

	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	isolate_saves(_tag)

	var world := await boot_harbor(20)
	var mission: Node = world.get("campaign_controller")
	var player: CharacterBody2D = world.get_node("Player")

	check(mission != null and mission.has_method("get_campaign_status"), "HarborGame expõe o controlador real de chegada (campaign_controller)")
	if mission == null:
		await finish(_tag, world)
		return

	check(String(mission.get_campaign_status().get("phase", "")) == "arrival", "Fase inicial é 'arrival' (cutscene de chegada ainda não vista, sem flags de save)")
	check(bool(player.get("is_control_disabled")) == true, "Controle do jogador começa bloqueado durante a cutscene de chegada")

	print("\n[ETAPA 1] Pulando a cutscene (skip_cinematic), com chamada repetida")
	mission.skip_cinematic()
	mission.skip_cinematic() # repetição: deve ser um no-op seguro na segunda vez
	var deadline := Time.get_ticks_msec() + 20000
	while String(mission.get_campaign_status().get("phase", "")) in ["arrival", "disembark"] and Time.get_ticks_msec() < deadline:
		await process_frame
	check(String(mission.get_campaign_status().get("phase", "")) == "arrival_wait", "Cutscene pulada avança para o desembarque real (arrival_wait) sem travar")
	check(not bool(player.get("is_control_disabled")), "Controle é liberado após o desembarque, antes do telefone tocar")

	print("\n[ETAPA 2] Verificando que o jogador de fato se move com o controle liberado")
	var start_pos: Vector2 = player.global_position
	Input.action_press("ui_right")
	await physics_frames(20)
	Input.action_release("ui_right")
	await physics_frames(2)
	check(player.global_position.distance_to(start_pos) > 5.0, "Jogador se move fisicamente quando is_control_disabled é falso (não é só uma flag solta)")

	print("\n[ETAPA 3] Forçando o telefone a tocar (avançando o relógio interno) e respondendo com tecla real")
	mission.set("_phone_wait", 999.0)
	await frames(3)
	check(String(mission.get_campaign_status().get("phase", "")) == "phone", "Telefone toca sozinho após a janela de espera")
	check(bool(player.get("is_control_disabled")), "Controle é bloqueado de novo durante a ligação")

	await press_key(KEY_ENTER)
	check(bool(mission.get("_phone_answered")), "Tecla Enter atende a ligação (mesma tecla usada para avançar o diálogo)")

	var lines_advanced := 0
	while String(mission.get_campaign_status().get("phase", "")) == "phone" and lines_advanced < 10:
		await press_key(KEY_ENTER)
		lines_advanced += 1
	check(String(mission.get_campaign_status().get("phase", "")) == "meet_maciota", "As 4 falas da ligação avançam com teclas reais até 'meet_maciota' (%d avanços)" % lines_advanced)
	check(not bool(player.get("is_control_disabled")), "Controle é liberado de vez após a ligação")
	check(bool(root.get_node("CampaignState").has_campaign_flag(&"harbor_arrival_call_complete")), "Flag harbor_arrival_call_complete setada pela ligação real (não por atalho de teste)")

	print("\n[ETAPA 4] Recuperação/robustez: métodos de diálogo fora de fase não alteram o estado")
	var phase_before := String(mission.get_campaign_status().get("phase", ""))
	mission.advance_dialogue() # fora de "phone"/"arrival": deve ser no-op
	check(String(mission.get_campaign_status().get("phase", "")) == phase_before, "advance_dialogue() fora de 'phone'/'arrival' não altera a fase (idempotente)")
	mission.skip_cinematic() # fora de "arrival": deve ser no-op
	check(String(mission.get_campaign_status().get("phase", "")) == phase_before, "skip_cinematic() fora de 'arrival' não altera a fase")

	await capture("01_meet_maciota_reached")
	await finish(_tag, world)
