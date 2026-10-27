extends SceneTree
## Sessão curta (Main real, sem save): a cadeia da Helena monta no jogo, sem rodar campanha.
## Liga o nó, a TV do terminal (M00), a conversa com o Neco (M02-B) abrindo o serviço do guincho no
## contrato do save, a Helena no cais (M05-B) e os ganchos do posto e do banco à noite.
## Uso: tools/run_godot_locked.sh --path . --script res://tests/test_helena_act1_session.gd -- --no-save
const ACT1 := preload("res://systems/campaign/HelenaAct1State.gd")
const RUNTIME := preload("res://runtime/harbor_act1/HelenaAct1.gd")
const STATE := preload("res://runtime/GameState.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print(("HELENA_ACT1 PASS " if ok else "HELENA_ACT1 FAIL ") + label)
	if not ok: failures.append(label)
	return ok

func frames(count: int) -> void:
	for _i in count: await physics_frame

func wait_until(predicate: Callable, count := 240) -> bool:
	for _i in count:
		if predicate.call(): return true
		await physics_frame
	return false

func _go(point: Vector3) -> void:
	world.session.controller.region.set_focus(point)
	world.player.teleport(point + Vector3.UP * .08)
	await frames(90)

func _finish_dialogue() -> void:
	var session = world.session
	for _i in 40:
		if not session.dialogue_open: return
		session._advance_dialogue()
		await frames(2)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(420).timeout.connect(func(): push_error("HELENA_ACT1 timeout"); quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play, 10800):
		check(false, "Main ready"); quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var session = world.session
	var act1 = session.helena_act1
	if not check(act1 != null and act1.get_script() == RUNTIME, "nó da cadeia montado na sessão"): _end(); return
	# M00: a TV do noticiário monta perto do terminal.
	await _go(RUNTIME.TV_POINT + Vector3(-3, 0, 2))
	var tv_ok := await wait_until(func(): return is_instance_valid(act1._tv), 120)
	check(tv_ok, "TV do terminal com o delegado Prado (M00)")
	# Harbor concluído (fixture do save): só campanha e abertura; o resto da sessão fica como está.
	var fixture: Dictionary = FIXTURE.full_snapshot(Vector3.ZERO, true)
	if not check(session.state.campaign.restore_snapshot(fixture.campaign) and session.state.intro.restore_snapshot(fixture.intro), "fixture: Harbor concluído"): _end(); return
	# A fixture termina o Harbor: a ligação do Maciota (MissionWorld._update_aftermath) abre sozinha.
	await frames(30)
	await _finish_dialogue()
	session.weather.time_of_day = 15.0 / 24.0
	act1.focus("debt")
	check(act1.objective() != "" and act1.target_position().is_equal_approx(act1._bank_entry()), "diário põe M02-B no objetivo e no marcador")
	check(ACT1.advance(session.state.world_state, session.state.campaign.snapshot(), "debt", "neco"), "M02-B: Helena feita")
	var neco: Vector3 = session.mission_world.targets.neco
	await _go(neco + Vector3(0, 0, 1.2))
	var action: Dictionary = session.nearest()
	if check(action.get("id") == "helena_act1" and action.get("target") == "neco:debt", "Neco oferece a conversa da cobrança (%s)" % [action]):
		check(session.interact(), "conversa com o Neco abre")
		await _finish_dialogue()
		check(ACT1.stage(session.state.world_state, "debt") == "tow1", "etapa do primeiro carro")
		check(await wait_until(func(): return session.mission_world.tow_job.get("chain") == "debt", 180), "guincho do Neco reservado para o carro 1")
		# A carteira desta sessão não tem os recibos da campanha da fixture; confere só os contratos novos.
		var tow: Dictionary = session.mission_world.snapshot()
		check(preload("res://runtime/MissionWorld.gd").validate_ownership(tow, "", {}, ACT1.debt_tow_index(session.state.world_state)), "serviço de M02-B passa no contrato do guincho")
		check(ACT1.validate(session.state.world_state, session.state.economy.snapshot(), session.state.campaign.snapshot()), "etapa de M02-B passa no contrato da cadeia")
		check(act1.target_position().is_finite(), "marcador no carro 1")
	# M05-B: Helena no cais, depois de M02-B pago.
	ACT1.advance(session.state.world_state, session.state.campaign.snapshot(), "debt", "tow2")
	ACT1.advance(session.state.world_state, session.state.campaign.snapshot(), "debt", "tow3")
	session.mission_world.cancel_tow_job()
	check(ACT1.finish(session.state.world_state, session.state.campaign.snapshot(), session.state.economy, "debt").ok, "M02-B paga")
	await _go(RUNTIME.DOCK + Vector3(0, 0, -2))
	check(await wait_until(func(): return is_instance_valid(act1.helena) and act1._helena_scene == "dock", 180), "Helena espera no cais")
	if is_instance_valid(act1.helena):
		world.player.teleport(act1.helena.global_position + Vector3(1.2, .08, 0))
		await frames(20)
		action = session.nearest()
		check(action.get("target") == "helena:dock", "conversar com a Helena no cais (%s)" % [action])
	# Ganchos de noite: posto fechado (M05-B) e só o vigia no banco (M06-B).
	ACT1.advance(session.state.world_state, session.state.campaign.snapshot(), "wash", "station")
	act1._refresh()
	session.weather.time_of_day = 1.0 / 24.0
	check(act1.fuel_closed() and not act1.bank_night_shift(), "posto dos Cobras fechado depois da meia-noite")
	session.weather.time_of_day = 15.0 / 24.0
	check(not act1.fuel_closed(), "de dia o posto funciona")
	check(ACT1.validate(session.state.world_state, session.state.economy.snapshot(), session.state.campaign.snapshot()), "M05-B aberta e M02-B paga passam no contrato da cadeia")
	_end()

func _end() -> void:
	print("HELENA_ACT1_RESULT checks=", checks, " failures=", failures)
	if is_instance_valid(world): world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)
