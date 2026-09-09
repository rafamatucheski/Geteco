extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 05 — Início, falha e conclusão de missão
## Real production controller (district/harbor_preview/campaign/CobraCampaignController.gd)
## driven through its real adapter (CobraCampaignBridge.gd), inside HarborGame.tscn.
## Existing tests/test_cobra_campaign_gameplay.gd already covers the happy path
## of cobra_contact -> cobra_race extensively, but never drives a mission all
## the way to fail_mission() and back — this audit specifically targets that
## gap: start -> real failure (contact dies mid-delivery) -> verify the
## mission becomes retryable -> retry for real -> complete for real.

func _initialize() -> void:
	run.call_deferred()


func dismiss_dialogue(bridge: Node, max_tries: int = 6) -> void:
	var tries := 0
	while bridge.get("_dialog") != null and bridge._dialog.visible and tries < max_tries:
		await press_key(KEY_ENTER)
		tries += 1
	await physics_frames(3)


func run() -> void:
	_tag = "05_mission_start_fail_complete"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: CharacterBody2D = world.get_node("Player")
	var bridge: Node = world.get_node("CobraCampaign")
	var runtime: Node = bridge.runtime
	var ledger: RefCounted = bridge.ledger

	check(bool(ledger.get_status("cobra_contact").get("available", false)), "cobra_contact está disponível assim que a entrega inicial é concluída")

	print("\n[ETAPA 1] Início real da missão cobra_contact")
	var started: bool = runtime.start_mission("cobra_contact")
	check(started, "start_mission('cobra_contact') aceita o início")
	check(String(runtime.get("active_id")) == "cobra_contact", "active_id reflete a missão em andamento")
	await dismiss_dialogue(bridge) # dispensa a fala de briefing do Maciota

	var workshop_pos: Vector2 = runtime.get("objective_position")
	player.global_position = workshop_pos
	await physics_frames(8)
	var contact: Node = runtime.get("_contact")
	check(contact != null and is_instance_valid(contact), "Um contato real (Ferrugem) é atribuído/spawnado para a missão")

	var stage1_ok: bool = runtime.interact()
	check(stage1_ok, "Primeira interação real avança a missão para o estágio 1")
	await dismiss_dialogue(bridge) # dispensa a fala de resposta de Ferrugem

	print("\n[ETAPA 2] Falha real: o contato morre em serviço, a missão deve falhar sozinha")
	contact.call("take_damage", 9999)
	var fail_deadline := Time.get_ticks_msec() + 4000
	while String(runtime.get("active_id")) == "cobra_contact" and Time.get_ticks_msec() < fail_deadline:
		await process_frame
	check(String(runtime.get("active_id")) == "", "A morte do contato faz a missão falhar sozinha (active_id limpo)")
	await dismiss_dialogue(bridge) # dispensa a fala de falha ("Ferrugem não pode mais...")
	check(not bool(ledger.data.get("completed", {}).get("cobra_contact", false)), "Missão falhada não fica marcada como concluída")

	print("\n[ETAPA 3] Recuperação: a missão volta a ficar disponível para nova tentativa")
	var retry_status: Dictionary = ledger.get_status("cobra_contact")
	check(bool(retry_status.get("available", false)), "cobra_contact volta a 'available' depois da falha (retry possível)")

	print("\n[ETAPA 4] Nova tentativa real, agora até a conclusão")
	var money_before: int = int(player.get("money"))
	var restarted: bool = runtime.start_mission("cobra_contact")
	check(restarted, "start_mission('cobra_contact') aceita a segunda tentativa")
	await dismiss_dialogue(bridge)
	var new_contact: Node = runtime.get("_contact")
	check(new_contact != null and is_instance_valid(new_contact) and not bool(new_contact.get("is_dead")), "Um novo contato vivo substitui o anterior morto")
	player.global_position = runtime.get("objective_position")
	await physics_frames(8)

	var retry_stage1: bool = runtime.interact()
	check(retry_stage1, "Reentrega funciona na segunda tentativa")
	await dismiss_dialogue(bridge)
	var completed_now: bool = runtime.interact()
	check(completed_now, "Segunda interação conclui a missão de verdade")
	await dismiss_dialogue(bridge) # dispensa a fala final ("Maciota - telefone")

	check(bool(ledger.data.get("completed", {}).get("cobra_contact", false)), "Ledger marca cobra_contact como concluída de verdade")
	check(int(player.get("money")) == money_before + 120, "Recompensa de $120 é paga exatamente uma vez na conclusão real")
	check(String(runtime.get("active_id")) == "", "active_id volta a vazio após a conclusão")

	await finish(_tag, world)
