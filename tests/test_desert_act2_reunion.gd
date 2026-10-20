extends SceneTree
## Ato 2, missão A2-01 "Oito anos" (runtime/desert/act2) na sessão real (Main + save isolado):
## encontro da arrancada → Motel Oásis → Capela, com morte no meio da conversa, prisão, recarga do
## disco, carteira cheia no envelope e o recibo de R$ 1.500 validado pelo contrato do deserto.
## Uso (com tela): tools/run_godot_locked.sh --path . --script res://tests/test_desert_act2_reunion.gd -- --isolated-save-root=<pasta temporária> --no-traffic
## Sem --no-save de propósito: a recarga precisa de gravação de verdade. O save vai só para o arquivo
## isolado do fixture (menu_save_path + V2Launch.selected_path, devolvido no fim), como em
## desert_village_homes_session.gd; o save pessoal não é lido nem gravado.
## Os deslocamentos entre os lugares são teleporte (o teste não prova o caminho dirigido) e as falas
## avançam pelo mesmo _advance_dialogue do clique. Capturas na pasta de saída do fixture (evidence/).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const STATE := preload("res://runtime/desert/act2/VicenteAct2State.gd")
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const REUNION := preload("res://runtime/desert/act2/VicenteReunion.gd")
const CONTRACT := preload("res://runtime/desert/DesertSaveContract.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
var world
var checks := 0
var failures: Array[String] = []
var output := ""
var old_launch := ""

func _initialize() -> void:
	create_timer(900).timeout.connect(func(): failures.append("watchdog 900 s"); finish())
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("ACT2_REUNION ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	if not check(not "--no-save" in OS.get_cmdline_user_args() and Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--isolated-save-root=")), "gravação isolada (--isolated-save-root, sem --no-save)"): finish(); return
	contracts()
	root.size = Vector2i(1280, 720)
	output = FIXTURE.output_dir("act2-vicente-reunion")
	var at := LAYOUT.drag_meet_center() + Vector3(0, .08, 6)
	var data := FIXTURE.full_snapshot(at, true)
	data.campaign.aftermath = {"call_complete": true}
	data.region_id = "desert"
	data.world.pedestrian = {"region": "desert", "position": [at.x, at.y, at.z]}
	data.world.erase("desert_story")
	data.world.erase(STATE.KEY)
	var path := FIXTURE.write_fixture(output, "checkpoint.json", data)
	if not check(not path.is_empty(), "save isolado no encontro criado"): finish(); return
	var launch = root.get_node("V2Launch")
	old_launch = launch.selected_path
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await ready_world(): finish(); return
	var session = world.session
	check(world.production.store.path == path and not world.production.no_save, "grava só no arquivo isolado do fixture")
	await wait_until(func(): return STORY.data(session.state.world_state).arrived, 8000)
	check(STORY.data(session.state.world_state).arrived and STATE.stage(session.state.world_state) == "", "chegada registrada, missão ainda não começou")
	check(session.desert.objective() == "Encontre Vicente no encontro da arrancada.", "objetivo aponta o encontro (%s; hora %.2f)" % [session.desert.objective(), session.weather.time_of_day * 24.0])
	# --- Etapa 1: encontro, com morte no meio da conversa ---
	var vicente = await meet_vicente()
	if not check(is_instance_valid(vicente), "Vicente está no encontro"): finish(); return
	for attempt in 3:
		await approach(vicente.global_position + Vector3(0, .08, 1.2))
		if session.desert.nearest_action().get("target", "") == "vicente": break
	check(session.desert.nearest_action().get("target", "") == "vicente", "conversa com Vicente oferecida (%s)" % session.desert.nearest_action().get("target", "nenhuma"))
	check(session.desert.perform(session.desert.nearest_action()) and session.dialogue_open, "conversa do encontro abre")
	for i in 3: session._advance_dialogue()
	await photo("01-encontro")
	await die()
	check(STATE.stage(session.state.world_state) == "" and not STORY.data(session.state.world_state).met_vicente, "morte no meio da conversa não avança a missão")
	vicente = await meet_vicente()
	if not check(is_instance_valid(vicente), "Vicente continua no encontro depois do resgate"): finish(); return
	await approach(vicente.global_position + Vector3(0, .08, 1.2))
	check(session.desert.perform(session.desert.nearest_action()) and session.dialogue_open, "conversa do encontro reabre")
	var count := await close_dialogue()
	check(count >= REUNION.meet_lines().size(), "falas do encontro inteiras (%d)" % count)
	check(STATE.stage(session.state.world_state) == "motel", "encontro manda para o Motel Oásis")
	check(not STORY.data(session.state.world_state).met_vicente, "met_vicente só no fim da missão")
	check(session.desert.objective() == REUNION.objective_for({STATE.KEY: {"version": 1, "stage": "motel"}}), "objetivo aponta o motel")
	var motel_target: Vector3 = session.desert.target_position()
	var motel_center: Vector2 = ROADSIDE.site("motel").center
	check(Vector2(motel_target.x, motel_target.z).distance_to(motel_center) < 12.0, "marcador no motel (%.1f m do centro)" % Vector2(motel_target.x, motel_target.z).distance_to(motel_center))
	await wait_until(func(): return not is_instance_valid(session.desert.story.actors.get("vicente")), 3000)
	check(not is_instance_valid(session.desert.story.actors.get("vicente")), "Vicente sai do encontro")
	check(CONTRACT.valid(session.state.world_state, session.state.economy._data), "save do deserto válido na etapa do motel")
	# --- Prisão: a etapa fica ---
	world.gameplay.stars = 1
	session._on_arrest()
	check(await wait_recovered(session), "custódia termina")
	check(STATE.stage(session.state.world_state) == "motel", "prisão não perde a etapa")
	check(session.save_game(), "checkpoint gravado depois da prisão")
	# --- Recarga fria do disco: Main novo lendo o mesmo arquivo isolado ---
	var file := FileAccess.get_file_as_string(path)
	check(file.contains("\"" + STATE.KEY + "\"") and file.contains("\"motel\""), "etapa do motel gravada no arquivo do save")
	world.queue_free()
	for i in 4: await process_frame
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await ready_world(): finish(); return
	session = world.session
	check(STATE.stage(session.state.world_state) == "motel", "etapa do motel volta do disco")
	# --- Etapa 2: Motel Oásis ---
	if not await visit("motel"): finish(); return
	await photo("02-motel-chegada")
	if not await talk("motel", REUNION.motel_lines(session.state.economy.snapshot().collectibles).size()): finish(); return
	check(STATE.stage(session.state.world_state) == "chapel", "motel manda para a capela")
	check(session.desert.objective() == "Encontre Vicente na Capela da Estrada.", "objetivo aponta a capela")
	await wait_until(func(): return not is_instance_valid(session.desert.story.reunion.actor), 3000)
	check(not is_instance_valid(session.desert.story.reunion.actor), "Vicente sai do motel")
	# --- Etapa 3: Capela, primeiro com a carteira cheia ---
	if not await visit("chapel"): finish(); return
	await photo("03-capela-chegada")
	var economy = session.state.economy
	var filler: int = ECONOMY.LIMIT - economy.balance - 1000
	check(economy.grant_reward("test_act2_wallet_fill", filler), "carteira enchida para o teste")
	if not await talk("chapel", REUNION.chapel_lines().size()): finish(); return
	check(STATE.stage(session.state.world_state) == "chapel" and not economy.has_reward_receipt(STATE.ENVELOPE_RECEIPT), "carteira cheia: envelope fica pendente e a missão espera")
	check(economy.spend(filler, "test_act2_wallet_drain"), "carteira esvaziada")
	var before: int = economy.balance
	if not await talk("chapel", REUNION.chapel_lines().size()): finish(); return
	check(STATE.stage(session.state.world_state) == "done", "capela conclui a missão")
	check(economy.balance == before + STATE.ENVELOPE_AMOUNT and economy.has_reward_receipt(STATE.ENVELOPE_RECEIPT), "envelope de R$ %d pago com recibo" % STATE.ENVELOPE_AMOUNT)
	check(STORY.data(session.state.world_state).met_vicente, "conclusão marca met_vicente (destrava o resto do deserto)")
	check(session.desert.objective() == "Fale com Bia no pátio do Digo.", "objetivo segue para A2-02 (Bia) (%s; etapa %s; digo %s)" % [session.desert.objective(), STATE.track_stage(session.state.world_state), str(session.state.world_state.get("digo", {}))])
	check(CONTRACT.valid(session.state.world_state, economy._data), "save do deserto válido com o envelope")
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(session.state.snapshot()), "GameState aceita o save concluído")
	var paid: Dictionary = economy.grant_world_reward({"id": STATE.ENVELOPE_RECEIPT, "kind": "cash", "amount": STATE.ENVELOPE_AMOUNT})
	check(paid.ok and not paid.changed and economy.balance == before + STATE.ENVELOPE_AMOUNT, "envelope não paga duas vezes")
	await photo("04-capela-fim")
	await wait_until(func(): return not is_instance_valid(session.desert.story.reunion.actor), 3000)
	check(not is_instance_valid(session.desert.story.reunion.actor), "Vicente sai da capela depois da missão")
	# --- Vicente volta ao encontro ---
	vicente = await meet_vicente()
	check(is_instance_valid(vicente), "Vicente volta ao encontro depois da missão")
	await track_mission()
	await cargo_mission()
	await order_mission()
	finish()

## A2-02 "Respeita a pista": Bia, corrida com o Digo e Arquibancada. A corrida física não é refeita
## aqui (test_desert_drag_runtime cobre a prova): o resultado entra pelo mesmo caminho do fim da
## arrancada (DesertDragProgress.record_finish + DesertCampaign.race_finished).
func track_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(STATE.track_stage(state) == "", "A2-02 começa depois de A2-01 (etapa %s)" % STATE.track_stage(state))
	var bia_point: Vector3 = preload("res://runtime/desert/DesertCampaign.gd").LOCATIONS.bia
	check(session.desert.target_position().distance_to(bia_point) < 1.0, "marcador na Bia")
	await approach(bia_point + Vector3(0, .08, 1.2))
	await wait_until(func(): return is_instance_valid(session.desert.story.actors.get("bia")), 20000)
	var bia = session.desert.story.actors.get("bia")
	if not check(is_instance_valid(bia), "Bia está no pátio do Digo"): return
	await approach(bia.global_position + Vector3(0, .08, 1.2))
	check(session.desert.story.perform("bia", false) and session.dialogue_open, "conversa da Bia abre")
	var count := await close_dialogue()
	check(count >= REUNION.bia_lines().size(), "falas da Bia inteiras (%d)" % count)
	check(STATE.track_stage(state) == "race", "Bia manda para a corrida do Digo")
	check(session.desert.objective() == "Corra contra Digo na reta: quadro da concentração.", "objetivo aponta a corrida")
	check(CONTRACT.valid(state, session.state.economy._data), "save válido na etapa da corrida")
	var result: Dictionary = preload("res://activities/desert_drag/DesertDragProgress.gd").record_finish(state, "digo", false, 21.37)
	result.finished = true
	result.rival_id = "digo"
	session.desert.story.race_finished(result)
	check(STATE.track_stage(state) == "grandstand", "terminar a prova com o Digo (mesmo perdendo) leva à Arquibancada")
	check(session.desert.objective() == "Encontre Vicente na Arquibancada da reta.", "objetivo aponta a Arquibancada")
	if not await visit("grandstand"): return
	await photo("05-arquibancada-chegada")
	if not await talk("grandstand", REUNION.grandstand_lines(false, 21.37).size()): return
	check(STATE.track_stage(state) == "done", "Arquibancada conclui A2-02")
	check(session.desert.objective() == "Fale com Raul no encontro da arrancada.", "objetivo segue para A2-03 (Raul)")
	check(CONTRACT.valid(state, session.state.economy._data), "save do deserto válido com A2-02 concluída")
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(session.state.snapshot()), "GameState aceita o save com A2-02")
	await wait_until(func(): return not is_instance_valid(session.desert.story.reunion.actor), 3000)
	check(not is_instance_valid(session.desert.story.reunion.actor), "Vicente sai da Arquibancada")

## Contratos do livro de etapas, sem mundo.
func contracts() -> void:
	var arrived := {"version": 1, "arrived": true, "met_vicente": false, "cargo_found": false, "bank_proof": false, "jessica_met": false, "delivered": false}
	var met := arrived.duplicate()
	met.met_vicente = true
	var wallet := {"transactions": {}}
	var paid := {"transactions": {"reward:" + STATE.ENVELOPE_RECEIPT: {"kind": "reward", "item": STATE.ENVELOPE_RECEIPT, "amount": STATE.ENVELOPE_AMOUNT}}}
	check(STATE.validate_wallet({}, wallet), "save sem deserto é válido")
	check(STATE.stage({"desert_story": met}) == "done" and STATE.validate_wallet({"desert_story": met}, wallet), "save antigo com a conversa única conta como reencontro feito")
	check(not STATE.validate_wallet({"desert_story": met}, paid), "envelope sem missão é recusado")
	var w := {"desert_story": arrived.duplicate()}
	check(not STATE.advance(w, "chapel"), "não pula etapa")
	check(STATE.advance(w, "motel") and STATE.advance(w, "chapel") and not STATE.advance(w, "motel"), "avança em ordem e não volta")
	check(STATE.validate_wallet(w, wallet), "etapa no meio é válida")
	check(not STATE.validate_wallet({"desert_story": met, STATE.KEY: {"version": 1, "stage": "done"}}, wallet), "conclusão sem recibo é recusada")
	check(STATE.validate_wallet({"desert_story": met, STATE.KEY: {"version": 1, "stage": "done"}}, paid), "conclusão com recibo é válida")
	check(not STATE.validate_wallet({"desert_story": arrived, STATE.KEY: {"version": 1, "stage": "done"}}, paid), "conclusão sem met_vicente é recusada")
	check(not STATE.validate_wallet({"desert_story": met, STATE.KEY: {"version": 1, "stage": "chapel"}}, wallet), "met_vicente no meio da missão é recusado")
	var wrong := {"transactions": {"reward:" + STATE.ENVELOPE_RECEIPT: {"kind": "reward", "item": STATE.ENVELOPE_RECEIPT, "amount": 999}}}
	check(not STATE.validate_wallet({"desert_story": met, STATE.KEY: {"version": 1, "stage": "done"}}, wrong), "valor do envelope diferente é recusado")
	check(not STATE.validate_wallet({"desert_story": arrived, STATE.KEY: {"version": 1, "stage": "nope"}}, wallet), "etapa desconhecida é recusada")
	var raced := {"version": 1, "met": true, "lesson_completed": false, "desert_raced": true, "friend": true}
	check(STATE.track_stage({"desert_story": met, "digo": raced}) == "done", "save antigo com a oficina conta A2-02 como feita")
	var fresh := {"desert_story": met, STATE.KEY: {"version": 1, "stage": "done"}}
	check(STATE.track_stage(fresh) == "", "A2-02 começa sem etapa")
	check(not STATE.track_advance(fresh, "done"), "A2-02 não termina sem a corrida")
	check(STATE.track_advance(fresh, "race") and STATE.track_stage(fresh) == "race", "Bia leva à corrida")
	fresh.digo = raced
	check(STATE.track_stage(fresh) == "grandstand", "corrida terminada leva à Arquibancada")
	check(STATE.validate_wallet(fresh, paid), "etapa da Arquibancada é válida")
	check(STATE.track_advance(fresh, "done") and STATE.validate_wallet(fresh, paid), "A2-02 concluída é válida")
	fresh.erase("digo")
	check(not STATE.validate_wallet(fresh, paid), "A2-02 concluída sem a corrida é recusada")
	check(not STATE.validate_wallet({"desert_story": arrived, STATE.KEY: {"version": 1, "stage": "motel"}, STATE.TRACK_KEY: {"version": 1, "stage": "race"}}, wallet), "A2-02 antes de A2-01 é recusada")
	var cargo_key: String = STATE.CHAIN.cargo.key
	var chain := {"desert_story": met.duplicate(), STATE.KEY: {"version": 1, "stage": "done"}, STATE.TRACK_KEY: {"version": 1, "stage": "done"}, "digo": raced}
	check(STATE.chain_ready(chain, "cargo") and STATE.chain_stage(chain, "cargo") == "", "A2-03 pronta depois de A2-02")
	check(not STATE.chain_ready(chain, "order"), "A2-04 espera A2-03")
	check(not STATE.chain_advance(chain, "cargo", "weigh"), "A2-03 não pula etapa")
	check(STATE.chain_advance(chain, "cargo", "crate") and STATE.chain_advance(chain, "cargo", "weigh") and STATE.chain_advance(chain, "cargo", "raul"), "A2-03 avança em ordem")
	check(STATE.validate_wallet(chain, paid), "A2-03 no meio é válida")
	var forged: Dictionary = chain.duplicate(true)
	forged[cargo_key] = {"version": 1, "stage": "done"}
	forged.desert_story.cargo_found = true
	check(not STATE.validate_wallet(forged, paid), "A2-03 concluída sem o frete é recusada")
	var legacy_cargo := {"desert_story": met.duplicate(), "digo": raced}
	legacy_cargo.desert_story.cargo_found = true
	check(STATE.chain_stage(legacy_cargo, "cargo") == "done" and STATE.validate_wallet(legacy_cargo, wallet), "save antigo com o manifesto conta A2-03 como feita")
	check(STATE.chain_ready(legacy_cargo, "order") and STATE.chain_stage(legacy_cargo, "order") == "", "save antigo segue para A2-04")
	var early := {"desert_story": met.duplicate(), STATE.KEY: {"version": 1, "stage": "done"}, STATE.CHAIN.order.key: {"version": 1, "stage": "night"}}
	check(not STATE.validate_wallet(early, paid), "A2-04 antes de A2-03 é recusada")

func ready_world() -> bool:
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.get("session") != null and world.session.ready_for_play, "sessão real carregou"): return false
	for i in 12:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
	if world.session.modal: world.session.close_menu()
	return true

func wait_until(condition: Callable, ms: int) -> void:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and not condition.call(): await physics_frame

func wait_recovered(session) -> bool:
	for i in 2400:
		await physics_frame
		if not session.rescue_pending and not session.arrest_pending and not session.respawn_busy: return true
	return false

func meet_vicente():
	var at := LAYOUT.drag_vicente_point() + Vector3(0, .08, 8)
	await approach(at)
	var session = world.session
	await wait_until(func(): return is_instance_valid(session.desert.story.actors.get("vicente")), 30000)
	return session.desert.story.actors.get("vicente")

func die() -> void:
	var session = world.session
	# Dano de verdade (a queda para fora do mundo só conta fora de menu, e a conversa é um menu).
	world.gameplay.damage_environment(100000.0)
	for i in 3: await physics_frame
	check(session.rescue_pending or world.gameplay.health <= 0, "morte inicia o resgate")
	check(await wait_recovered(session), "resgate termina")
	check(not session.dialogue_open, "resgate fecha a conversa")

## Vai até o lugar da etapa e espera Vicente montar ali.
func visit(stage: String) -> bool:
	var session = world.session
	var reunion = session.desert.story.reunion
	var stand: Vector3 = reunion._site_point(stage, Vector3(0, 0, 12) if REUNION.SPOTS[stage].has("anchor") else Vector3(0, 0, 30)) + Vector3.UP * .1
	await approach(stand)
	world.production.region.set_focus(stand, true)
	await wait_until(func(): return is_instance_valid(reunion.actor), 30000)
	if not check(is_instance_valid(reunion.actor), "%s espera no %s" % [str(REUNION.SPOTS[stage].get("who", "vicente")), stage]): return false
	await frames(30)
	var actor: CharacterBody3D = reunion.actor
	var spot: Vector3 = reunion._site_point(stage, REUNION.SPOTS[stage].points[0])
	check(Vector2(actor.global_position.x, actor.global_position.z).distance_to(Vector2(spot.x, spot.z)) < 6.0, "%s: Vicente no ponto autorado" % stage)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * .5, actor.global_position - Vector3.UP * .6, 1))
	check(not hit.is_empty() and absf(actor.global_position.y - float(hit.position.y)) < .25, "%s: Vicente de pé no chão" % stage)
	check(session.desert.target_position().distance_to(actor.global_position) < .5, "%s: marcador em cima do Vicente" % stage)
	return true

## Conversa com o Vicente da etapa até o fim; devolve falso se a ação não apareceu.
func talk(stage: String, expected: int) -> bool:
	var session = world.session
	var actor: CharacterBody3D = session.desert.story.reunion.actor
	if not is_instance_valid(actor): return check(false, "%s: Vicente presente para conversar" % stage)
	var face: Vector3 = session.desert.story.reunion._site_point(stage, REUNION.SPOTS[stage].face)
	face.y = actor.global_position.y
	var toward: Vector3 = (face - actor.global_position).normalized()
	var found := false
	for distance in [1.1, 1.4]:
		for turn in [0.0, .6, -.6, 1.2, -1.2]:
			var stand: Vector3 = actor.global_position + toward.rotated(Vector3.UP, turn) * distance + Vector3.UP * .08
			if not session.position_clear(stand): continue
			await approach(stand)
			# O ator não é deste ponto quando está no meio de um passo: espera assentar.
			if session.desert.nearest_action().get("target", "") == "vicente_reunion":
				found = true
				break
		if found: break
	if not check(found, "%s: conversa com Vicente oferecida" % stage): return false
	if not check(session.desert.perform(session.desert.nearest_action()) and session.dialogue_open, "%s: conversa abre" % stage): return false
	await frames(20)
	await photo("%s-conversa" % stage)
	var count := await close_dialogue()
	check(count >= expected, "%s: falas inteiras (%d de %d)" % [stage, count, expected])
	await frames(10)
	return true

func close_dialogue() -> int:
	var count := 0
	for i in 40:
		if not world.session.dialogue_open: break
		world.session._advance_dialogue()
		count += 1
		await process_frame
	return count

func approach(point: Vector3) -> void:
	world.production.region.prepare_collision_at(point)
	await frames(2)
	world.player.teleport(point)
	await frames(40)

func photo(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	world.camera.initialized = false
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(id + ".png")) == OK, "captura " + id)

func finish() -> void:
	var launch = root.get_node_or_null("V2Launch")
	if launch != null and not old_launch.is_empty(): launch.selected_path = old_launch
	print("ACT2_REUNION checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

## A2-03 "Peso morto": Raul -> caixote do Miragem -> Fiscal Rosa na Balança -> Raul (R$ 900).
func cargo_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(STATE.chain_stage(state, "cargo") == "" and STATE.chain_ready(state, "cargo"), "A2-03 começa depois de A2-02")
	if not await talk_contact("raul", REUNION.raul_start_lines().size()): return
	check(STATE.chain_stage(state, "cargo") == "crate", "Raul manda abrir o caixote")
	check(session.desert.objective() == "Abra o caixote dos Cobras no posto Miragem.", "objetivo aponta o caixote")
	check(session.desert.target_position().distance_to(REUNION.MIRAGE_CRATE) < .5, "marcador no caixote")
	if not await use_point(REUNION.MIRAGE_CRATE, "act2:crate", [Vector3(0, 0, 1.0), Vector3(0, 0, -1.0), Vector3(1.1, 0, 0), Vector3(-1.1, 0, 0)], REUNION.crate_lines().size()): return
	await photo("06-caixote")
	check(STATE.chain_stage(state, "cargo") == "weigh", "caixote manda para a Balança")
	check(not STORY.data(state).cargo_found, "cargo_found só no fim da missão")
	var rosa: Vector3 = REUNION.rosa_point()
	check(session.desert.target_position().distance_to(rosa) < .5, "marcador na Fiscal Rosa")
	# A balança monta pela beira de estrada; chega de longe para a Rosa estar lá.
	await approach(rosa + Vector3(0, .1, -14))
	world.production.region.set_focus(rosa, true)
	await frames(90)
	if not await use_point(rosa, "act2:rosa", [Vector3(0, 0, -1.2), Vector3(1.2, 0, -.6), Vector3(-1.2, 0, -.6), Vector3(0, 0, 1.2), Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0)], REUNION.rosa_lines().size()): return
	check(STATE.chain_stage(state, "cargo") == "raul", "Fiscal Rosa manda de volta ao Raul")
	check(CONTRACT.valid(state, session.state.economy._data), "save válido no meio de A2-03")
	var economy = session.state.economy
	var before: int = economy.balance
	if not await talk_contact("raul", REUNION.raul_end_lines().size()): return
	var spec: Dictionary = STATE.CHAIN.cargo
	check(STATE.chain_complete(state, "cargo") and STORY.data(state).cargo_found, "Raul conclui A2-03 e marca cargo_found")
	# O autosave da conclusão pode pagar também uma conquista (refresh_achievements): o recibo é a prova,
	# e o saldo tem que ter subido pelo menos o frete.
	var receipt: Dictionary = preload("res://systems/economy/RecurringReceipts.gd").lookup(economy._data, "reward", str(spec.receipt))
	check(int(receipt.get("amount", -1)) == int(spec.amount) and economy.balance >= before + int(spec.amount), "frete de R$ %d pago com recibo (saldo +%d)" % [int(spec.amount), economy.balance - before])
	var settled: int = economy.balance
	check(not STATE.chain_finish(state, economy, "cargo").ok and economy.balance == settled, "frete não paga duas vezes")
	check(CONTRACT.valid(state, economy._data), "save do deserto válido com A2-03 concluída")
	check(session.desert.objective() == "Leve o manifesto a Irene, no Cobre.", "objetivo segue para A2-04 (Irene)")

## A2-04 "A ordem alterada": Irene no balcão -> Irene na porta à noite -> orelhão do Horizonte.
func order_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	set_hour(12.0)
	var definition: Dictionary = preload("res://world/places/PlaceCatalog.gd").get_definition("desert_bank")
	await approach(definition.entry_position + Vector3(0, .08, 1.0))
	if not check(await session.enter_place("desert_bank", false), "entra no Cobre"): return
	for i in 60: await physics_frame
	var service: Vector3 = session.room.to_global(Vector3(-1.5, .08, -1.35))
	world.player.teleport(service)
	await frames(30)
	var action: Dictionary = session.desert.nearest_action()
	if not check(action.get("target", "") == "irene", "conversa com Irene no balcão (%s)" % action.get("target", "nenhuma")): return
	check(session.desert.perform(action) and session.dialogue_open, "conversa da Irene abre")
	await photo("07-irene-balcao")
	var count := await close_dialogue()
	check(count >= REUNION.irene_bank_lines().size(), "falas da Irene inteiras (%d)" % count)
	check(STATE.chain_stage(state, "order") == "night", "Irene marca a porta à noite")
	check(session.desert.objective() == "Encontre Irene na porta do Cobre depois das 20h (descanse no Horizonte).", "objetivo aponta a porta à noite")
	check(await session.leave_place(), "sai do Cobre")
	await frames(30)
	# De dia ela não está na porta.
	await approach(session.desert.story.reunion._site_point("bank_night", Vector3(0, 0, 12)) + Vector3.UP * .1)
	await frames(60)
	check(not is_instance_valid(session.desert.story.reunion.actor), "de dia Irene não espera na porta")
	set_hour(21.0)
	if not await visit("bank_night"): return
	await photo("08-irene-noite")
	if not await talk("bank_night", REUNION.irene_night_lines().size()): return
	check(STATE.chain_stage(state, "order") == "call", "Irene entrega a matrícula 0417")
	check(session.desert.objective() == "Ligue para o Maciota do orelhão do Horizonte.", "objetivo aponta o orelhão")
	await wait_until(func(): return not is_instance_valid(session.desert.story.reunion.actor), 3000)
	check(not is_instance_valid(session.desert.story.reunion.actor), "Irene vai embora depois da conversa")
	var phone: Vector3 = REUNION.HORIZON_PHONE
	phone.y = preload("res://world/desert/DesertTerrainMesh.gd").surface_height(Vector2(phone.x, phone.z))
	if not await use_point(phone, "act2:phone", [Vector3.ZERO, Vector3(0, 0, 1.0), Vector3(1.0, 0, 0), Vector3(-1.0, 0, 0), Vector3(0, 0, -1.0)], REUNION.phone_lines().size()): return
	check(STATE.chain_complete(state, "order") and STORY.data(state).bank_proof, "ligação conclui A2-04 e marca bank_proof")
	check(session.desert.objective() == "Avance nas provas de arrancada e enfrente Jessica.", "objetivo segue para a Jessica (esqueleto)")
	check(CONTRACT.valid(state, session.state.economy._data), "save do deserto válido com A2-04 concluída")
	check(preload("res://runtime/GameState.gd").new().restore_snapshot(session.state.snapshot()), "GameState aceita o save com A2-04")
	await photo("09-orelhao")

func set_hour(hour: float) -> void:
	var weather = world.session.weather
	weather.time_of_day = hour / 24.0
	world.session.state.world_state.time = weather.time_of_day
	weather._update()

## Fala com um contato do DesertCampaign (Raul, Bia...) pelo "Conversar" dele.
func talk_contact(id: String, expected: int) -> bool:
	var session = world.session
	var at: Vector3 = preload("res://runtime/desert/DesertCampaign.gd").LOCATIONS[id]
	await approach(at + Vector3(0, .08, 3.0))
	await wait_until(func(): return is_instance_valid(session.desert.story.actors.get(id)), 20000)
	var contact = session.desert.story.actors.get(id)
	if not check(is_instance_valid(contact), "%s presente" % id): return false
	await approach(contact.global_position + Vector3(0, .08, 1.2))
	if not check(session.desert.story.perform(id, false) and session.dialogue_open, "conversa de %s abre" % id): return false
	var count := await close_dialogue()
	return check(count >= expected, "falas de %s inteiras (%d de %d)" % [id, count, expected])

## Ação de missão num ponto (sem ator): procura um lugar livre em volta onde a ação aparece.
func use_point(point: Vector3, target: String, offsets: Array, expected: int) -> bool:
	var session = world.session
	# Vai para perto primeiro: longe, a colisão do lugar ainda não existe e todo ponto parece ocupado.
	if world.player.global_position.distance_to(point) > 20.0:
		await approach(point + Vector3(0, .1, 8))
		world.production.region.set_focus(point, true)
		await frames(90)
	var found := false
	for offset: Vector3 in offsets:
		var stand: Vector3 = point + offset + Vector3.UP * .08
		world.production.region.prepare_collision_at(stand)
		await frames(2)
		if not session.position_clear(stand): continue
		await approach(stand)
		if session.desert.nearest_action().get("target", "") == target:
			found = true
			break
	if not check(found, "%s oferecido (%s)" % [target, session.desert.nearest_action().get("target", "nenhuma")]): return false
	if not check(session.desert.perform(session.desert.nearest_action()) and session.dialogue_open, "%s abre" % target): return false
	await frames(10)
	var count := await close_dialogue()
	return check(count >= expected, "%s: falas inteiras (%d de %d)" % [target, count, expected])
