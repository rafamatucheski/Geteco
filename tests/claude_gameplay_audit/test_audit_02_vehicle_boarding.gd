extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 02 — Entrada e saída de veículos
## Real Player.gd + real PlayerCar.gd (via the player's own personal car and a
## real spawned traffic vehicle), inside the production HarborGame.tscn.
## Covers the happy path with repetition (several enter/exit cycles) and
## recovery after failure/interruption, complementing tests/test_vehicle_boarding_sides.gd
## (which focuses on left/right door selection) rather than duplicating it.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "02_vehicle_boarding"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: CharacterBody2D = world.get_node("Player")
	var owned: Node2D = world.get_node("PersonalCarManager").car
	check(owned != null and is_instance_valid(owned), "PersonalCarManager expõe o carro real do jogador")

	var traffic: Node2D = ModernTrafficFactory.spawn_parked_vehicle(world, "AuditBoardingTraffic", Vector2(4500, -950), 0, "summit_suv", 0, Color("3f7589"))
	check(traffic != null and is_instance_valid(traffic), "Um veículo de tráfego real pode ser spawnado para o teste")

	print("\n[ETAPA 1] Ciclo repetido de entrada/saída no carro pessoal (3x)")
	owned.global_position = Vector2(4500, -950)
	owned.rotation = 0.0
	for cycle in range(3):
		player.set_physics_process(false)
		player.set("is_control_disabled", false)
		player.global_position = owned.to_global(Vector2(-8, 43))
		var approach: Vector2 = player.global_position
		owned.enter_vehicle(player)
		check(bool(owned.get("is_driven_by_player")), "Ciclo %d: is_driven_by_player fica verdadeiro ao entrar" % cycle)
		check(bool(player.get("is_control_disabled")), "Ciclo %d: embarque bloqueia interações do pedestre" % cycle)
		var waited := 0
		while owned.has_meta("vehicle_boarding") and waited < 300:
			await process_frame
			waited += 1
		check(not owned.has_meta("vehicle_boarding"), "Ciclo %d: animação de embarque termina sozinha (%d frames)" % [cycle, waited])
		check(not player.visible and not bool(player.get("is_control_disabled")), "Ciclo %d: motorista sentado restaura o estado de interação" % cycle)
		owned.exit_vehicle()
		check(not bool(owned.get("is_driven_by_player")), "Ciclo %d: is_driven_by_player volta a falso ao sair" % cycle)
		check(player.visible and player.is_physics_processing(), "Ciclo %d: saída restaura visibilidade e física do pedestre" % cycle)
		await physics_frames(30)

	print("\n[ETAPA 2] Falha esperada: exit_vehicle() chamado sem estar dirigindo é no-op seguro")
	var pos_before: Vector2 = owned.global_position
	var player_state_before: bool = bool(player.get("is_control_disabled"))
	owned.exit_vehicle()
	check(owned.global_position == pos_before, "exit_vehicle() sem estar dirigindo não move o carro")
	check(bool(player.get("is_control_disabled")) == player_state_before, "exit_vehicle() sem estar dirigindo não mexe no estado do pedestre")

	print("\n[ETAPA 3] Falha esperada: entrar em veículo destruído (is_broken) não deve funcionar")
	traffic.call("take_damage", 9999) # caminho real de produção, não um set() direto de health
	check(bool(traffic.get("is_broken")), "take_damage(9999) marca o veículo de tráfego como destruído (is_broken)")
	player.global_position = traffic.to_global(Vector2(-8, 43))
	traffic.enter_vehicle(player)
	check(not bool(traffic.get("is_driven_by_player")), "Veículo destruído (is_broken) recusa embarque")
	check(player.visible, "Jogador continua visível/no controle após tentativa recusada")
	traffic.queue_free() # não precisamos mais dele; evita qualquer estado residual
	await physics_frames(3)

	print("\n[ETAPA 4] Recuperação após interrupção: sair no meio da animação de embarque não deve travar o pedestre")
	player.set("is_control_disabled", false)
	player.global_position = owned.to_global(Vector2(0, 43))
	owned.enter_vehicle(player)
	await create_timer(0.2).timeout # interrompe bem no meio do tween de embarque
	owned.exit_vehicle()
	await create_timer(1.4).timeout
	check(player.visible and player.modulate.a == 1.0 and not bool(player.get("is_control_disabled")), "Embarque interrompido não deixa o pedestre invisível/travado depois")
	check(not bool(owned.get("is_driven_by_player")), "Embarque interrompido não deixa o carro marcado como dirigido")

	print("\n[ETAPA 5] Recuperação: uma segunda tentativa normal de embarque funciona após a interrupção acima")
	player.global_position = owned.to_global(Vector2(0, 43))
	owned.enter_vehicle(player)
	var waited2 := 0
	while owned.has_meta("vehicle_boarding") and waited2 < 300:
		await process_frame
		waited2 += 1
	check(bool(owned.get("is_driven_by_player")) and not player.visible, "Depois de uma interrupção, um novo embarque completo funciona normalmente")
	owned.exit_vehicle()
	await physics_frames(10)

	await finish(_tag, world)
