extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 09 — Transição entre porto (Harbor) e montanha (Mountain Pass)
## Real production streaming (district/harbor_preview/ContinuousWorld.gd):
## since a documented refactor, port<->mountain is NOT a scene swap — both
## regions live as siblings under the same running HarborGame scene, and
## ContinuousWorld toggles visibility/process_mode/region flags as the
## player's exterior position crosses the seam (SEAM_X=7300, y<-2000).
## tests/test_harbor_mountain_drive.gd asserts the OPPOSITE — that
## current_scene stops being res://district/mountain_pass/MountainPass.tscn —
## which reads as leftover pre-refactor logic; this audit instead verifies the
## actual current contract (current_region + current_scene identity) directly,
## with a real driven vehicle, crossing back and forth twice.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "09_port_mountain_transition"
	# ContinuousWorld's mountain-region streaming/build has been observed
	# (see AUDIT_REPORT.md, "Preparação da região da montanha é muito lenta em
	# headless") to take 70-90+ real seconds in this headless environment — a
	# generous watchdog avoids a false NAO_EXECUTADO on a slow machine/run.
	arm_watchdog(240.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: Node2D = world.get_node("Player")
	var stream: Node = world.get_node("ContinuousWorld")
	var car: Node2D = world.get_node("PersonalCarManager").car

	print("\n[ETAPA 1] Dirigindo para o norte até acionar a preparação real da região da montanha")
	car.global_position = Vector2(6300, -950)
	car.health = 87
	car.call("enter_vehicle", player)
	var boarding_deadline := Time.get_ticks_msec() + 3000
	while car.has_meta("vehicle_boarding") and Time.get_ticks_msec() < boarding_deadline:
		await process_frame
	check(bool(car.get("is_driven_by_player")), "Carro pessoal real é embarcado para atravessar a fronteira")

	car.global_position = Vector2(6300, -1500) # y < -1000 aciona ensure_mountain() em ContinuousWorld._process
	# NÃO chamamos stream.ensure_mountain() diretamente aqui: ContinuousWorld._process()
	# já dispara isso sozinho (a cada 0.2s) assim que detecta y<-1000; uma segunda
	# chamada explícita cairia no guard "if building or ready_for_crossing: return"
	# e retornaria na hora, dando falsa sensação de que já esperou o real término.
	# Medido isoladamente neste ambiente headless (sem GPU real), a preparação
	# streamed da montanha (interiores + expedição + povoado + tráfego) levou
	# ~74s numa execução limpa — bem mais que o esperado para um "sem tela de
	# carregamento". Ver AUDIT_REPORT.md.
	var ready_deadline := Time.get_ticks_msec() + 150000
	while not bool(stream.get("ready_for_crossing")) and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	check(bool(stream.get("ready_for_crossing")), "A região da montanha termina de preparar (streaming em thread) e fica pronta para a travessia")
	check(current_scene == world, "A preparação da montanha NÃO troca a cena atual (current_scene continua sendo o próprio HarborGame)")

	for cycle in range(2):
		print("\n[CICLO %d] Atravessando para a montanha e verificando a região real" % cycle)
		car.global_position = Vector2(7500.0, -4600.0) # x>=SEAM_X(7300) e y<-2000: dentro da montanha
		await create_timer(0.5).timeout
		check(String(stream.get("current_region")) == "mountain", "Ciclo %d: current_region muda para 'mountain' ao cruzar fisicamente a fronteira" % cycle)
		check(current_scene == world, "Ciclo %d: ainda assim não há troca de cena (mesma HarborGame)" % cycle)
		check(int(car.get("health")) == 87, "Ciclo %d: o dano/estado do carro pessoal atravessa a fronteira sem ser resetado" % cycle)
		if cycle == 0:
			await capture("09_crossed_into_mountain")

		print("[CICLO %d] Voltando para o porto e verificando o retorno real da região" % cycle)
		car.global_position = Vector2(1500.0, 500.0) # bem dentro do Porto
		await create_timer(0.5).timeout
		check(String(stream.get("current_region")) == "harbor", "Ciclo %d: current_region volta para 'harbor' ao retornar fisicamente" % cycle)
		check(int(car.get("health")) == 87, "Ciclo %d: o carro continua com o mesmo estado depois da ida e volta" % cycle)

	print("\n[ETAPA FINAL] Saindo do veículo com segurança após os cruzamentos")
	car.call("exit_vehicle")
	await physics_frames(10)
	check(player.visible and not bool(player.get("is_control_disabled")), "Jogador sai do carro normalmente após múltiplas travessias porto/montanha")

	await finish(_tag, world)
