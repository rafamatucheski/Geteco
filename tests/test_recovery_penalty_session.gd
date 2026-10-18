extends SceneTree
## Morte e prisão na sessão real (Main): Dante volta pela porta do Bay Medical ou da delegacia,
## paga a conta ou a multa e, preso, perde a munição que carregava (RecoveryPenalty).
## Uso: "$GODOT" --path . --script res://tests/test_recovery_penalty_session.gd -- --no-save --skip-arrival
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PENALTY := preload("res://runtime/RecoveryPenalty.gd")
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): failures.append("watchdog 420 s"); finish())
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("RECOVERY_PENALTY ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func wait_recovered(session) -> bool:
	for i in 2400:
		await physics_frame
		if not session.rescue_pending and not session.arrest_pending and not session.respawn_busy: return true
	return false

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args(), "--no-save obrigatório"): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if not check(world.session != null and world.session.ready_for_play, "sessão real carregou"): finish(); return
	for i in 600:
		var curtain := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"): curtain = true
		if not curtain: break
		await process_frame
	var session = world.session
	if session.modal: session.close_menu()
	check(session.state.region_id == "harbor", "começa no Harbor")
	var economy = session.state.economy
	economy.grant_reward("test_recovery_session_wallet", 10000)
	# O dinheiro novo pode liberar conquista com prêmio no próximo save; liquida antes de medir.
	session.activities.refresh_achievements()

	# Morte: cair para fora do mundo é a mesma morte de verdade (_on_death).
	var before_death: int = economy.balance
	world.player.teleport(world.player.global_position * Vector3(1, 0, 1) + Vector3(0, -15, 0))
	session._process(0.0)
	check(session.rescue_pending, "queda inicia o resgate")
	check(await wait_recovered(session), "resgate termina")
	var hospital: Dictionary = PLACES.get_definition(PENALTY.HOSPITAL)
	var near_hospital := planar_distance(world.player.global_position, hospital.return_position) < 3.0
	var near_fallback := planar_distance(world.player.global_position, session.controller.region.spawn_position) < 3.0
	check(near_hospital, "acorda na porta do Bay Medical (%.1f m; ponto da região: %s)" % [planar_distance(world.player.global_position, hospital.return_position), near_fallback])
	check(economy.balance == before_death - PENALTY.fee(before_death), "conta do hospital cobrada uma vez (R$ %d → R$ %d)" % [before_death, economy.balance])
	check(world.gameplay.health == 100 and not world.player.dead and world.gameplay.stars == 0, "volta vivo e sem procura")

	# Prisão: pistola carregada no bolso, multa e munição apreendida.
	if not economy.owns_weapon("pistol"): economy.grant_weapon("pistol")
	economy.add_ammo("pistol", 24)
	var ammo_before: Dictionary = economy.get_ammo("pistol")
	var before_arrest: int = economy.balance
	world.gameplay.stars = 1
	session._on_arrest()
	check(await wait_recovered(session), "custódia termina")
	var precinct: Dictionary = PLACES.get_definition(PENALTY.PRECINCT)
	check(planar_distance(world.player.global_position, precinct.return_position) < 3.0, "sai pela porta da delegacia (%.1f m)" % planar_distance(world.player.global_position, precinct.return_position))
	check(economy.balance == before_arrest - PENALTY.fee(before_arrest), "multa cobrada uma vez (R$ %d → R$ %d)" % [before_arrest, economy.balance])
	var ammo_after: Dictionary = economy.get_ammo("pistol")
	check(int(ammo_before.magazine) + int(ammo_before.reserve) > 0 and int(ammo_after.magazine) + int(ammo_after.reserve) == 0, "munição carregada apreendida")
	check(economy.owns_weapon("pistol"), "a pistola fica")
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(session.state.snapshot()), "save continua válido depois da conta e do confisco")
	finish()

func finish() -> void:
	print("RECOVERY_PENALTY checks=%d failures=%s" % [checks, failures])
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)
