extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 03 — Entrada e saída da oficina (Northgate Auto) + bancada
## Real production interior (world/harbor/interiors/HarborWorkshopInterior.gd)
## reached through the real exterior door (scripts/entrances/BuildingEntrance.gd,
## via its own Area2D proximity sensor — not a manager-internal shortcut) and
## its real "bancada de preparação" (tuning bench). Covers repeated
## entry/exit and repeated bench open/close, plus recovery when the player
## walks away mid-interaction.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "03_workshop_entry_exit_and_bench"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: CharacterBody2D = world.get_node("Player")
	var interiors: Node = world.get_node("Interiors")
	var workshop: Node2D = interiors.get("workshop_interior")
	var entrance: Node = world.get_node_or_null("NorthDistrict/MotorWorkshop/Entrance")

	check(workshop != null, "HarborInteriorManager expõe workshop_interior (Northgate Auto)")
	check(entrance != null, "A porta exterior real da oficina existe em NorthDistrict/MotorWorkshop/Entrance")
	if workshop == null or entrance == null:
		await finish(_tag, world)
		return

	print("\n[ETAPA 1] Ciclo repetido de entrada/saída pela porta real (sensor de proximidade, 2x)")
	# HarborWorkshopInterior's room (720x500) is wider than the 500px threshold
	# that switches HarborInteriorManager._frame_interior_camera into its
	# "compact_interior" meta branch (that branch is only exercised by the much
	# smaller garage interior) — so here the real, interior-agnostic signal
	# that the camera actually reframed is its limit_left leaving the default
	# +/-10000000 exterior bounds, checked alongside physical distance.
	var cam: Camera2D = player.get_node("Camera")
	for cycle in range(2):
		player.global_position = entrance.global_position
		player.velocity = Vector2.ZERO
		await physics_frames(8)
		check(entrance.is_actor_in_range(player), "Ciclo %d: sensor de proximidade real detecta o jogador na porta" % cycle)
		var entered: bool = entrance.request_interaction(player)
		check(entered, "Ciclo %d: request_interaction() aceita a entrada" % cycle)
		# BuildingEntrance._begin_transition() only emits destination_requested
		# after open_duration (~0.22s); HarborInteriorManager then arms a further
		# 0.35s cooldown on the INTERIOR'S OWN exit door at that point — i.e. the
		# exit door is briefly (~0.2s-0.9s after this call) disabled too. Wait
		# comfortably past that whole window before touching the exit door.
		await create_timer(1.2).timeout
		check(cam.limit_left != -10000000, "Ciclo %d: câmera é reenquadrada para os limites do interior" % cycle)
		check(player.global_position.distance_to(workshop.global_position) < 900.0, "Ciclo %d: jogador foi teleportado para dentro da oficina" % cycle)

		# Exit through the interior's own real exit door.
		player.global_position = workshop.exit_door.global_position
		await physics_frames(8)
		check(workshop.exit_door.is_actor_in_range(player), "Ciclo %d: sensor da porta de saída detecta o jogador" % cycle)
		var exited: bool = workshop.exit_door.request_interaction(player)
		check(exited, "Ciclo %d: saída real pela porta é aceita" % cycle)
		await create_timer(0.6).timeout
		check(cam.limit_left == -10000000, "Ciclo %d: câmera volta ao modo exterior ao sair" % cycle)
		check(player.global_position.distance_to(workshop.global_position) > 900.0, "Ciclo %d: jogador retorna fisicamente para fora da oficina" % cycle)
		await create_timer(0.4).timeout # deixa o cooldown de transição (0.35s) expirar antes do próximo ciclo

	print("\n[ETAPA 2] Bancada de preparação: abrir/fechar repetidamente com tecla real (E)")
	player.global_position = entrance.global_position
	await physics_frames(8)
	entrance.request_interaction(player)
	await create_timer(1.2).timeout
	check(player.global_position.distance_to(workshop.global_position) < 900.0, "Reentrada na oficina para o teste da bancada funciona")

	player.global_position = workshop.bench_area.global_position
	await physics_frames(8)
	check(bool(workshop.get("is_near_bench")), "Área real da bancada detecta o jogador (Area2D body_entered)")
	check(workshop.bench_badge.visible, "Selo [E] da bancada fica visível na proximidade real")

	for cycle in range(2):
		await press_key(KEY_E)
		check(workshop.bench_dialog.visible, "Ciclo %d: tecla E abre o relatório da bancada" % cycle)
		if cycle == 0:
			await capture("03_northgate_bench_report_open")
		await press_key(KEY_E)
		check(not workshop.bench_dialog.visible, "Ciclo %d: tecla E fecha o relatório da bancada de novo" % cycle)

	print("\n[ETAPA 3] Recuperação: sair da área com o diálogo aberto deve fechá-lo sozinho, sem travar")
	await press_key(KEY_E) # reabre
	check(workshop.bench_dialog.visible, "Relatório reaberto antes de testar o afastamento")
	player.global_position = workshop.bench_area.global_position + Vector2(400, 400)
	await physics_frames(10)
	check(not bool(workshop.get("is_near_bench")), "Afastar-se fisicamente desativa is_near_bench")
	check(not workshop.bench_dialog.visible, "Afastar-se fecha o diálogo da bancada automaticamente (sem input extra)")

	# Leave the interior cleanly before finishing.
	player.global_position = workshop.exit_door.global_position
	await physics_frames(8)
	workshop.exit_door.request_interaction(player)
	await create_timer(0.6).timeout

	await finish(_tag, world)
