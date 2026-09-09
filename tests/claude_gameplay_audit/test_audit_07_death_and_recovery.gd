extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 07 — Morte e recuperação
## Real production path: Player.take_damage() driving health to 0 triggers
## the real Player._wasted() coroutine (hospital flash, respawn, grace
## window), exactly as ambient damage does in normal play — nothing here
## calls _wasted() directly. No existing test in tests/ drives this against
## the real HarborGame.tscn (tests/test_police_fair_arrest.gd uses a local
## mock Suspect class instead), so this is new coverage. Also exercises
## arrest_and_respawn() and repeats the death cycle to check recovery holds
## up a second time.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "07_death_and_recovery"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: Node = world.get_node("Player")

	var hospital_spawns := get_nodes_in_group("hospital_spawn")
	check(hospital_spawns.size() > 0, "O distrito do Porto tem pelo menos um ponto real no grupo 'hospital_spawn'")
	log_line("  [INFO] hospital_spawn encontrados: %d" % hospital_spawns.size())

	for cycle in range(2):
		print("\n[CICLO %d] Morte real via take_damage(999) e recuperação" % cycle)
		player.set("health", int(player.get("max_health")))
		player.set("money", 3000)
		# Move away from wherever the previous cycle's respawn left the player,
		# so "did death actually relocate the player" stays meaningful even
		# when it dies again right at the hospital.
		player.global_position = Vector2(600, 600) + Vector2(cycle * 400, 0)
		await physics_frames(3)
		var money_before: int = int(player.get("money"))
		var pos_before_death: Vector2 = player.global_position

		player.call("take_damage", 999)
		check(bool(player.get("is_dead")), "Ciclo %d: take_damage(999) mata o jogador de verdade (is_dead)" % cycle)

		# _wasted() waits ~2.2s (flash) + _respawn_at_hospital() + ~1.5s more
		# before clearing is_dead — real wall-clock waits, like the codebase's
		# own create_timer(...) idiom for these coroutines.
		await create_timer(4.5).timeout

		check(not bool(player.get("is_dead")), "Ciclo %d: is_dead volta a falso depois da sequência real de respawn" % cycle)
		check(int(player.get("health")) == int(player.get("max_health")), "Ciclo %d: vida é restaurada ao máximo no hospital" % cycle)
		check(player.visible and player.is_physics_processing(), "Ciclo %d: jogador volta visível e controlável" % cycle)

		var distance_from_fallback: float = player.global_position.distance_to(Vector2(1125, 375))
		var moved_from_death_spot: bool = player.global_position.distance_to(pos_before_death) > 5.0
		check(moved_from_death_spot, "Ciclo %d: jogador é de fato teleportado para longe do local da morte" % cycle)
		if hospital_spawns.size() > 0:
			var nearest_hospital_distance := INF
			for h in hospital_spawns:
				nearest_hospital_distance = minf(nearest_hospital_distance, player.global_position.distance_to(h.global_position))
			check(nearest_hospital_distance < 5.0, "Ciclo %d: posição final coincide com um hospital_spawn real (não o fallback antigo Vector2(1125,375), dist=%.0f)" % [cycle, distance_from_fallback])

		check(int(player.get("money")) == money_before, "Ciclo %d: morte não desconta dinheiro (comportamento observado, sem penalidade monetária)" % cycle)

		print("  Recuperação: janela de invulnerabilidade pós-respawn")
		player.call("take_damage", 50)
		check(int(player.get("health")) == int(player.get("max_health")), "Ciclo %d: dano logo após respawn é ignorado pela janela de graça (_respawn_grace_active)" % cycle)

		await create_timer(3.2).timeout # espera a janela de graça (3.0s) expirar de verdade
		player.call("take_damage", 20)
		check(int(player.get("health")) == int(player.get("max_health")) - 20, "Ciclo %d: depois da janela de graça expirar, dano real volta a valer" % cycle)

	print("\n[ETAPA FINAL] Prisão e recuperação (arrest_and_respawn) — caminho irmão do de morte")
	player.set("health", int(player.get("max_health")))
	player.set("is_dead", false)
	player.set("is_arrested", false)
	player.call("arrest_and_respawn")
	check(bool(player.get("is_arrested")), "arrest_and_respawn() marca is_arrested de verdade")
	await create_timer(4.5).timeout
	check(not bool(player.get("is_arrested")), "is_arrested volta a falso depois da sequência real de liberação")
	check(player.visible and player.is_physics_processing(), "Jogador preso e liberado volta visível e controlável")

	await finish(_tag, world)
