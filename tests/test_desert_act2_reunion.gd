extends SceneTree
## Ato 2 inteiro (runtime/desert/act2, 13 missões) na sessão real (Main + save isolado): A2-01 com morte no
## meio da conversa, prisão, recarga do disco e carteira cheia; A2-02 a A2-13 em sequência, com as duas
## provas de história corridas de verdade (troca de marcha automática; a do Cascavel com o turbo cortado),
## a Monaliza perdida e o armazém no carro do Nonato, morte durante o ataque dos Cobras, a passagem norte
## aberta e, no fim, recarga fria do Main para conferir que tudo volta do disco.
## Uso (com tela): tools/run_godot_locked.sh --path . --script res://tests/test_desert_act2_reunion.gd -- --isolated-save-root=<pasta temporária> --no-traffic
## Sem --no-save de propósito: a recarga precisa de gravação de verdade. O save vai só para o arquivo
## isolado do fixture (menu_save_path + V2Launch.selected_path, devolvido no fim), como em
## desert_village_homes_session.gd; o save pessoal não é lido nem gravado.
## Teste leve: `--from=<missão>` monta pelo próprio livro de etapas o estado das missões anteriores (como
## se tivessem sido jogadas) e começa ali; `--to=<missão>` para depois dela. Missões: order, brothers, cave,
## letters, bet, trunk, convoy, salt, teodoro, finale. Sem os dois, roda o ato inteiro (~25 min).
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
	create_timer(2400).timeout.connect(func(): failures.append("watchdog 2400 s"); finish())
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
	var from := arg_value("--from")
	if not from.is_empty():
		await run_from(from, arg_value("--to"))
		if arg_value("--to").is_empty(): await final_reload(path)
		finish()
		return
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
	# Invencível pelo próprio interruptor do jogo: vida acima de 100 deixa o save inválido.
	world.gameplay.god_mode = true
	await brothers_mission()
	await cave_mission()
	await letters_mission()
	await bet_mission()
	await trunk_mission()
	await convoy_mission()
	await salt_mission()
	await teodoro_mission()
	await finale_mission()
	await final_reload(path)
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
	world.gameplay.god_mode = false
	world.gameplay.health = 100.0
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
	if not check(is_instance_valid(reunion.actor), "%s: alguém espera (%s)" % [stage, reunion.scene()]): return false
	await frames(30)
	var actor: CharacterBody3D = reunion.actor
	var spot: Vector3 = reunion._site_point(stage, reunion._points(stage)[0])
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
	var face: Vector3 = session.desert.story.reunion._face_point(stage)
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
	check(session.desert.objective() == "Vá à porta dos fundos do Cobre depois das 20h (descanse no Horizonte).", "objetivo aponta a porta à noite")
	check(await session.leave_place(), "sai do Cobre")
	await frames(30)
	# De dia ela não está na porta.
	await approach(session.desert.story.reunion._site_point("bank_night", Vector3(0, 0, 12)) + Vector3.UP * .1)
	await frames(60)
	check(not is_instance_valid(session.desert.story.reunion.actor), "de dia Irene não espera na porta")
	set_hour(21.0)
	if not await visit("bank_night"): return
	check(session.desert.story.reunion.actor.identity_id == "helena", "A2-04: Helena espera na porta do Cobre")
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
	check(session.desert.objective() == "Fale com Vicente no encontro da arrancada.", "objetivo segue para A2-05 (Vicente)")
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
	if not is_instance_valid(contact):
		var drag = session.desert.drag
		print("ACT2_REUNION INFO %s ausente: drag.active=%s rival=%s pendente=%s pista=%s retirado=%s longe=%s livre=%s jogador=%s carro=%s" % [id, str(drag.active), drag.rival_id, str(drag.open_meet.pending), str(drag.open_meet.track_busy()), str(session.desert.story.retired.has(id)), str(session.desert.story.reunion.away_from_meet()), str(session.position_clear(at + Vector3.UP * .08)), str(world.player.global_position), str(world.driving.occupied)])
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

# --- A2-05 a A2-13 ----------------------------------------------------------------------------------

const ACT2_LINES := preload("res://runtime/desert/act2/Act2Lines.gd")
const NORTH := preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const HEIST := preload("res://gameplay/desert_heist/DesertHeistState.gd")

func chain_done(id: String, label: String) -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(STATE.chain_complete(state, id), "%s concluída" % label)
	var spec: Dictionary = STATE.CHAIN[id]
	if int(spec.amount) > 0:
		var receipt: Dictionary = preload("res://systems/economy/RecurringReceipts.gd").lookup(session.state.economy._data, "reward", str(spec.receipt))
		check(int(receipt.get("amount", -1)) == int(spec.amount), "%s: recibo de R$ %d" % [label, int(spec.amount)])
		var before: int = session.state.economy.balance
		check(not STATE.chain_finish(state, session.state.economy, id).ok and session.state.economy.balance == before, "%s não paga duas vezes" % label)
	check(CONTRACT.valid(state, session.state.economy._data), "%s: save do deserto válido" % label)

## Prova de história de verdade: carro na concentração, ação da missão, troca de marcha automática.
func story_race(identity: String) -> Dictionary:
	var session = world.session
	var drag = session.desert.drag
	set_hour(12.0)
	var staging: Vector3 = REUNION.STAGING
	await approach(staging + Vector3(0, .1, 6))
	world.production.region.set_focus(staging, true)
	await frames(60)
	var car: CharacterBody3D = session.controller.spawn_vehicle("desert_faisca", staging + Vector3(0, .15, 0), -PI * .5)
	if not check(is_instance_valid(car), "%s: carro na concentração" % identity): return {}
	await frames(30)
	var entered := false
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		await frames(4)
		if world.driving.interact():
			await wait_until(func(): return world.driving.occupied and not world.driving.is_body_transition_active(), 8000)
			entered = world.driving.occupied
			if entered: break
	if not check(entered, "%s: Dante entra no carro" % identity): return {}
	await frames(20)
	var action: Dictionary = session.desert.nearest_action()
	if not check(action.get("target", "") == "act2:race", "%s: alinhar oferecido (%s)" % [identity, action.get("target", "nenhuma")]): return {}
	check(session.desert.perform(action), "%s: prova pedida" % identity)
	await wait_until(func(): return drag.active, 40000)
	if not check(drag.active and drag.rival_id == identity, "%s: prova começou" % identity): return {}
	await photo("race-" + identity)
	# Como test_desert_drag_runtime: giro na faixa de largada, depois acelerador e nitro, troca no giro ideal.
	var deadline := Time.get_ticks_msec() + 90000
	while drag.active and Time.get_ticks_msec() < deadline:
		if drag.phase == "staging": drag._throttle_override = .54
		else:
			drag._throttle_override = 1.0
			drag._nitro_override = true
			if drag.phase == "racing" and drag.racers.size() == 2:
				var drive = drag.racers[0].drive
				if drive.rpm >= drive.ideal_shift_rpm: drag.request_shift()
		await physics_frame
	drag._throttle_override = -1.0
	drag._nitro_override = false
	var result: Dictionary = drag.last_result
	print("ACT2_REUNION INFO depois da prova: ativa=%s fase=%s pendente=%s" % [str(drag.active), drag.phase, str(drag.open_meet.pending)])
	check(result.get("finished", false) and result.get("rival_id", "") == identity, "%s: prova terminou (%s)" % [identity, str(result.get("reason", "ok"))])
	print("ACT2_REUNION INFO %s: Dante %.2f s, rival %.2f s, venceu %s" % [identity, float(result.get("seconds", -1)), float(result.get("rival_seconds", -1)), str(result.get("won", false))])
	# Logo depois da frenagem a saída do carro pode ser recusada: espera parar e tenta de novo.
	var exit_deadline := Time.get_ticks_msec() + 20000
	while world.driving.occupied and Time.get_ticks_msec() < exit_deadline:
		# O painel de resultado da arrancada é um menu: o jogador fecha antes de sair do carro.
		if session.dialogue_open: session._advance_dialogue()
		elif session.modal: session.close_menu()
		if not world.driving.is_body_transition_active() and is_instance_valid(world.driving.car) and absf(float(world.driving.car.speed)) < .5: world.driving.leave()
		await frames(30)
	check(not world.driving.occupied, "%s: Dante sai do carro depois da prova" % identity)
	await frames(10)
	return result

func brothers_mission() -> void:
	var state: Dictionary = world.session.state.world_state
	check(REUNION.chain_at(state, "brothers") == "", "A2-05 começa depois de A2-04")
	check(world.session.desert.objective() == "Fale com Vicente no encontro da arrancada.", "A2-05: objetivo aponta Vicente")
	if not await talk_contact("vicente", ACT2_LINES.brothers_start().size()): return
	check(REUNION.chain_at(state, "brothers") == "race", "A2-05: Vicente chama para a prova")
	var result := await story_race("vicente")
	if result.is_empty(): return
	var expected := "won" if result.get("won", false) else "lost"
	check(REUNION.chain_at(state, "brothers") == expected, "A2-05: resultado físico vira etapa (%s)" % expected)
	if not await talk_contact("vicente", ACT2_LINES.brothers_after(expected == "won").size()): return
	chain_done("brothers", "A2-05")

func cave_mission() -> void:
	var state: Dictionary = world.session.state.world_state
	check(world.session.desert.objective() == "Encontre Vicente na caverna da mesa de pedra, ao sul do leito seco.", "A2-06: objetivo aponta a caverna")
	if not await visit("cave"): return
	await photo("10-caverna")
	# Conversa, flashback da blitz pelos olhos do Vicente (joga sozinho e rápido no teste) e o resto.
	var reunion = world.session.desert.story.reunion
	reunion.flashback_autoplay = true
	reunion.flashback_pace = 4.0
	var expected: int = ACT2_LINES.cave_before(false, false).size()
	if not await talk("cave", expected): return
	await wait_until(func(): return world.session.dialogue_open or REUNION.chain_at(state, "cave") == "done", 120000)
	check(world.session.dialogue_open or REUNION.chain_at(state, "cave") == "done", "A2-06: flashback termina e devolve à fogueira")
	if world.session.dialogue_open:
		var rest := await close_dialogue()
		check(rest >= ACT2_LINES.cave_after().size(), "A2-06: segunda parte da conversa depois do flashback (%d)" % rest)
	chain_done("cave", "A2-06")

func letters_mission() -> void:
	var state: Dictionary = world.session.state.world_state
	check(world.session.desert.objective() == "Pergunte à Dona Fátima, na Capela da Estrada.", "A2-07: objetivo aponta a Dona Fátima")
	var around := [Vector3(0, 0, 1.2), Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, -1.2), Vector3(1.0, 0, 1.0), Vector3(-1.0, 0, 1.0)]
	if not await use_point(REUNION.roadside_point("chapel", ROADSIDE.CHAPEL_KEEPER), "act2:fatima", around, ACT2_LINES.fatima().size()): return
	check(REUNION.chain_at(state, "letters") == "tower", "A2-07: Dona Fátima manda para a torre")
	if not await use_point(REUNION.roadside_point("radio_tower", ROADSIDE.TOWER_LADDER), "act2:tower", around, ACT2_LINES.tower().size()): return
	check(REUNION.chain_at(state, "letters") == "coop", "A2-07: torre manda para Santa Lua")
	if not await use_point(REUNION.coop_point(), "act2:coop", around, ACT2_LINES.coop().size()): return
	await photo("11-santa-lua")
	check(REUNION.chain_at(state, "letters") == "water", "A2-07: rádio manda para a caixa-d'água")
	if not await visit("water_tower"): return
	check(world.session.desert.story.reunion.actor.identity_id == "helena", "A2-07: Helena na caixa-d'água")
	if not await talk("water_tower", ACT2_LINES.water_tower().size()): return
	chain_done("letters", "A2-07")

func bet_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(session.desert.objective() == "Corra contra Jessica pelo quadro da concentração.", "A2-08: objetivo aponta a prova da Jessica")
	# A prova da Jessica é a que já existe (test_desert_drag_runtime): aqui o resultado entra pelo mesmo
	# caminho do fim da arrancada.
	session.desert.story.race_finished({"finished": true, "rival_id": "jessica", "won": false, "seconds": 18.0})
	check(STORY.data(state).jessica_met and not session.dialogue_open, "A2-08: prova da Jessica marca jessica_met sem a fala antiga")
	if not await talk_contact("jessica", ACT2_LINES.jessica_bet().size()): return
	check(REUNION.chain_at(state, "bet") == "cascavel", "A2-08: Jessica aponta o Cascavel")
	if not await visit("meet_edge"): return
	if not await talk("meet_edge", ACT2_LINES.cascavel().size()): return
	check(REUNION.chain_at(state, "bet") == "race", "A2-08: chave na chave apostada")
	var result := await story_race("cascavel")
	if result.is_empty(): return
	check(not result.get("won", true), "A2-08: com o turbo cortado depois de 400 m, Dante perde a prova de verdade")
	check(REUNION.chain_at(state, "bet") == "keys", "A2-08: aposta perdida leva à chave")
	if not await visit("meet_edge"): return
	if not await talk("meet_edge", ACT2_LINES.cascavel_keys(false).size()): return
	chain_done("bet", "A2-08")
	check(STATE.monaliza_lost(state), "A2-08: Monaliza perdida")
	await frames(60)
	var monaliza = session.garage_rewards.cars.get("personal_monaliza")
	check(not is_instance_valid(monaliza) or monaliza.get_meta("garage_suspended", false), "A2-08: a Monaliza não está mais no mundo")
	check(not session.personal_car._available(), "A2-08: sem armazém até A2-09")

func trunk_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(session.desert.objective().begins_with("Arranje outro carro"), "A2-09: objetivo pede outro carro")
	var dealer := REUNION.roadside_point("scrapyard", ROADSIDE.SCRAP_DEALER)
	if not await use_point(dealer, "act2:nonato", [Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.2), Vector3(0, 0, -1.2), Vector3(1.0, 0, 1.0)], ACT2_LINES.nonato().size()): return
	check(REUNION.chain_at(state, "trunk") == "car", "A2-09: Nonato dá o carro")
	check(state.get("desert_fleet", {}).has(STATE.NONATO_CAR_ID) and session.state.economy.has_reward_receipt(STATE.NONATO_CAR_RECEIPT), "A2-09: Bison do Nonato na frota com recibo")
	var car: CharacterBody3D = null
	for vehicle in session.controller.vehicles:
		if is_instance_valid(vehicle) and vehicle.vehicle_id == STATE.NONATO_CAR_ID: car = vehicle
	if not check(is_instance_valid(car), "A2-09: Bison na baia do ferro-velho"): return
	await photo("12-ferro-velho")
	# O caminho até o pátio não é dirigido aqui: o carro é posto ao lado da Bia.
	var park := REUNION.BIA_POINT + Vector3(7, .15, 5)
	world.production.region.prepare_collision_at(park)
	await frames(2)
	car.place(park, 0.0)
	await approach(REUNION.BIA_POINT + Vector3(0, .08, 3))
	await frames(30)
	if not await talk_contact("bia", ACT2_LINES.trunk_ready(true).size()): return
	chain_done("trunk", "A2-09")
	check(STATE.trunk_car(state) == STATE.NONATO_CAR_ID, "A2-09: armazém no Bison")
	check(session.personal_car._available() and session.personal_car._car() == car, "A2-09: porta-malas do Bison é o armazém")
	var behind: Vector3 = car.global_position + car.global_basis.z * (car.half_length + 1.0)
	world.player.teleport(behind + Vector3.UP * .08)
	await frames(20)
	check(session.field_inventory == null or session.field_inventory.trunk_access(), "A2-09: atrás do Bison o armazém abre")

func convoy_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(session.desert.objective().begins_with("Roube a carga do comboio"), "A2-10: objetivo aponta o comboio")
	# O assalto em si é o DesertHeist (test_desert_cargo_heist); aqui entra o estado final que ele grava.
	set_hour(12.0)
	var heist = session.desert.heist
	var robbed := HEIST.initial(session.weather.moon_day(), 0)
	robbed.phase = "looted"
	check(session.state.economy.grant_reward(HEIST.receipt(robbed), HEIST.reward(robbed)), "A2-10: recibo da carga do comboio")
	heist.data = robbed
	heist._store()
	await wait_until(func(): return REUNION.chain_at(state, "convoy") == "motel", 3000)
	check(REUNION.chain_at(state, "convoy") == "motel", "A2-10: carga roubada leva ao motel")
	if not await visit("motel"): return
	if not await talk("motel", ACT2_LINES.convoy_motel().size()): return
	chain_done("convoy", "A2-10")

func salt_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	var around := [Vector3(0, 0, -1.2), Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.2), Vector3(1.0, 0, -1.0)]
	if not await use_point(REUNION.roadside_point("salt_works", ROADSIDE.SALT_FOREMAN), "act2:bento", around, ACT2_LINES.bento().size()): return
	check(REUNION.chain_at(state, "salt") == "camp", "A2-11: Seu Bento manda ao acampamento")
	var center := REUNION.ledger_point()
	await approach(center + Vector3(0, .1, 40))
	world.production.region.set_focus(center, true)
	var wilds = session.desert.frontier.wilds
	await wait_until(func(): return wilds.sites.has(REUNION.LEDGER_SITE), 25000)
	if not check(wilds.sites.has(REUNION.LEDGER_SITE), "A2-11: acampamento montado"): return
	await frames(30)
	await approach(center + Vector3(0, .1, 6))
	check(session.desert.nearest_action().get("target", "") != "act2:ledger", "A2-11: caderno não sai com fora-da-lei de pé")
	for outlaw in wilds.sites[REUNION.LEDGER_SITE].actors:
		if is_instance_valid(outlaw) and not outlaw.dead: world.gameplay._damage(outlaw, 10000.0, world.player)
	await frames(20)
	if not await use_point(center, "act2:ledger", [Vector3(0, 0, 2.0), Vector3(2.0, 0, 0), Vector3(-2.0, 0, 0), Vector3(0, 0, -2.0), Vector3(0, 0, 3.5)], ACT2_LINES.ledger().size()): return
	check(REUNION.chain_at(state, "salt") == "home", "A2-11: caderno leva à casa da Helena")
	if not await visit("santa_lua"): return
	if not await talk("santa_lua", ACT2_LINES.helena_home().size()): return
	chain_done("salt", "A2-11")

func teodoro_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	check(session.desert.objective() == "Dona Lurdes chamou: vá ao Motel Oásis.", "A2-12: objetivo aponta o motel")
	if not await visit("motel"): return
	check(session.desert.story.reunion.actor.identity_id == "teodoro", "A2-12: Teodoro no motel")
	if not await talk("motel", ACT2_LINES.teodoro_motel().size()): return
	check(REUNION.chain_at(state, "teodoro") == "fight", "A2-12: Vicente parte pra cima")
	var reunion = session.desert.story.reunion
	await wait_until(func(): return is_instance_valid(reunion.actor) and reunion.actor is REUNION.BrotherFighter, 15000)
	if not check(is_instance_valid(reunion.actor) and reunion.actor is REUNION.BrotherFighter, "A2-12: Vicente na briga"): return
	var fighter = reunion.actor
	check(session.desert.nearest_action().get("target", "") != "vicente_reunion", "A2-12: sem conversa no meio da briga")
	world.player.teleport(fighter.global_position + Vector3(1.0, .08, 0))
	var hits := 0
	while not fighter.down and hits < 20:
		world.gameplay._damage(fighter, 12.0, world.player)
		hits += 1
		await frames(6)
	check(fighter.down and not fighter.dead and is_instance_valid(fighter), "A2-12: Vicente cai sem morrer (%d golpes)" % hits)
	await photo("13-briga")
	if not await talk("motel", ACT2_LINES.brothers_fight_after().size()): return
	check(REUNION.chain_at(state, "teodoro") == "chase", "A2-12: Teodoro foge para a obra")
	if not await visit("gate"): return
	check(reunion.actor.identity_id == "teodoro", "A2-12: chegou a tempo, Teodoro ainda na obra")
	await photo("13-teodoro-obra")
	# O caminho de quem chega tarde: tempo esgotado, Teodoro some e fica a pasta no chão.
	reunion._chase_deadline_msec = 1
	await wait_until(func(): return not is_instance_valid(reunion.actor), 3000)
	check(not is_instance_valid(reunion.actor), "A2-12: tempo esgotado, Teodoro passou pela obra")
	if not await use_point(REUNION.folder_point(), "act2:folder", [Vector3(0, 0, 1.2), Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, -1.2)], ACT2_LINES.teodoro_gate(false).size()): return
	chain_done("teodoro", "A2-12")
	check(not NORTH.completed(state), "A2-12: a obra continua fechada")

func finale_mission() -> void:
	var session = world.session
	var state: Dictionary = session.state.world_state
	var reunion = session.desert.story.reunion
	check(session.desert.objective() == "Encontre Vicente na Arquibancada da reta.", "A2-13: objetivo aponta a Arquibancada")
	if not await visit("grandstand"): return
	if not await talk("grandstand", ACT2_LINES.finale_grandstand().size()): return
	check(REUNION.chain_at(state, "finale") == "defend", "A2-13: Cobras atacam o encontro")
	await approach(REUNION.RAID_CENTER + Vector3(0, .1, 12))
	await wait_until(func(): return reunion.raiders.size() == REUNION.RAID_POINTS.size(), 20000)
	check(reunion.raiders.size() == REUNION.RAID_POINTS.size(), "A2-13: quatro Cobras no encontro")
	check(not session.save_block_reason().is_empty(), "A2-13: salvar bloqueado durante o ataque")
	await photo("14-ataque")
	await die()
	check(reunion.raiders.is_empty() and REUNION.chain_at(state, "finale") == "defend", "A2-13: morte desfaz o ataque e mantém a etapa")
	world.gameplay.god_mode = true
	await approach(REUNION.RAID_CENTER + Vector3(0, .1, 12))
	await wait_until(func(): return reunion.raiders.size() == REUNION.RAID_POINTS.size(), 20000)
	check(reunion.raiders.size() == REUNION.RAID_POINTS.size(), "A2-13: o ataque volta inteiro")
	for raider in reunion.raiders:
		if is_instance_valid(raider) and not raider.dead: world.gameplay._damage(raider, 10000.0, world.player)
	await wait_until(func(): return REUNION.chain_at(state, "finale") == "gate", 5000)
	check(REUNION.chain_at(state, "finale") == "gate", "A2-13: Cobras derrotados, Vicente vai à passagem norte")
	if not await visit("gate"): return
	if not await talk("gate", ACT2_LINES.finale_gate().size()): return
	chain_done("finale", "A2-13")
	check(STORY.data(state).delivered and NORTH.completed(state), "A2-13: passagem norte aberta (gatilho do ato 3)")
	check(preload("res://runtime/desert/DesertCampaign.gd").act_complete(state), "A2-13: ato 2 concluído no diário")
	check(session.desert.objective() == "Explore o deserto e complete o campeonato de arrancada.", "A2-13: objetivo volta ao deserto livre")
	await frames(30)
	await photo("15-passagem-norte")

## Recarga fria do Main com o save final: tudo do ato 2 volta do disco.
func final_reload(path: String) -> void:
	var session = world.session
	var reason: String = session.save_block_reason()
	print("ACT2_REUNION INFO save final: bloqueio=\"%s\" estrelas=%d" % [reason, int(world.gameplay.stars)])
	# Matar os Cobras do ataque pode deixar procurado; com estrelas o jogo segura o save na fila até
	# despistar (como em qualquer crime). Aqui a polícia é despistada à força para gravar.
	if world.gameplay.stars > 0:
		world.gameplay.stars = 0
		await frames(30)
	var saved_ok: bool = session.save_game()
	if not saved_ok: diagnose_save(session)
	check(saved_ok, "save final gravado (%s)" % session.last_save_error)
	var saved_state: Dictionary = session.state.world_state.duplicate(true)
	world.queue_free()
	for i in 4: await process_frame
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await ready_world(): return
	var state: Dictionary = world.session.state.world_state
	for id in STATE.ORDER: check(STATE.chain_complete(state, id), "recarga: %s concluída" % id)
	check(STATE.monaliza_lost(state) and STATE.trunk_car(state) == STATE.NONATO_CAR_ID, "recarga: Monaliza perdida e armazém no Bison")
	check(NORTH.completed(state), "recarga: passagem norte aberta")
	check(CONTRACT.valid(state, world.session.state.economy._data), "recarga: save do deserto válido")
	check(saved_state.get("desert_fleet", {}).has(STATE.NONATO_CAR_ID) == state.get("desert_fleet", {}).has(STATE.NONATO_CAR_ID), "recarga: Bison na frota")

## Save recusado pela validação completa: tira uma parte por vez e diz qual parte libera o save.
func diagnose_save(session) -> void:
	var GS := preload("res://runtime/GameState.gd")
	var snap: Dictionary = session.state.snapshot()
	print("ACT2_REUNION INFO diagnóstico: válido=%s chaves=%s" % [str(GS.new().restore_snapshot(snap)), str(snap.keys())])
	for key in snap.keys():
		if key == "world": continue
		var copy: Dictionary = snap.duplicate(true)
		copy.erase(key)
		if GS.new().restore_snapshot(copy): print("ACT2_REUNION INFO diagnóstico: sem '%s' fica válido" % key)
	for key in snap.world.keys():
		var copy: Dictionary = snap.duplicate(true)
		copy.world.erase(key)
		if GS.new().restore_snapshot(copy): print("ACT2_REUNION INFO diagnóstico: sem world.%s fica válido" % key)

# --- Teste leve: começar no meio do ato ------------------------------------------------------------

const DIGO_PROGRESS := preload("res://systems/campaign/DigoProgress.gd")
const MISSION_STEPS := ["order", "brothers", "cave", "letters", "bet", "trunk", "convoy", "salt", "teodoro", "finale"]

func arg_value(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with(name + "="): return str(argument).trim_prefix(name + "=")
	return ""

func run_from(from: String, to: String) -> void:
	if not check(from in MISSION_STEPS, "--from conhecido (%s)" % from): return
	await seed_until(from)
	world.gameplay.god_mode = true
	var started := false
	for id in MISSION_STEPS:
		if id == from: started = true
		if not started: continue
		match id:
			"order": await order_mission()
			"brothers": await brothers_mission()
			"cave": await cave_mission()
			"letters": await letters_mission()
			"bet": await bet_mission()
			"trunk": await trunk_mission()
			"convoy": await convoy_mission()
			"salt": await salt_mission()
			"teodoro": await teodoro_mission()
			"finale": await finale_mission()
		if id == to: return

## Marca as missões anteriores como feitas pelo próprio livro de etapas, com os recibos que elas pagam.
func seed_until(stop: String) -> void:
	var session = world.session
	var w: Dictionary = session.state.world_state
	var e = session.state.economy
	if STATE.stage(w) != "done":
		STATE.advance(w, "motel")
		STATE.advance(w, "chapel")
		e.grant_world_reward({"id": STATE.ENVELOPE_RECEIPT, "kind": "cash", "amount": STATE.ENVELOPE_AMOUNT})
		STATE.advance(w, "done")
		STORY.mark(w, "met_vicente")
	if not STATE.track_complete(w):
		STATE.track_advance(w, "race")
		DIGO_PROGRESS.complete_desert_race(w, DIGO_PROGRESS.DESERT_RACE_ID, true)
		STATE.track_advance(w, "done")
	for id in STATE.ORDER:
		if id == stop: break
		await seed_chain(id)
	check(CONTRACT.valid(w, e._data), "estado montado até %s é válido" % stop)
	session.save_game()

func seed_chain(id: String) -> void:
	var session = world.session
	var w: Dictionary = session.state.world_state
	var e = session.state.economy
	if STATE.chain_complete(w, id): return
	if id == "bet": STORY.mark(w, "jessica_met")
	var path: Array = STATE.CHAIN[id].stages.filter(func(st): return st != "" and st != "done")
	if id == "brothers": path = ["race", "won"]
	if id == "trunk": path = ["car"]
	for st in path: STATE.chain_advance(w, id, st)
	var extra := {}
	if id == "trunk":
		var point: Vector3 = world.player.global_position + Vector3(6, .2, 0)
		session.controller.region.prepare_collision_at(point)
		await frames(2)
		var car = session.controller.spawn_vehicle(STATE.NONATO_CAR_ARCHETYPE, point, 0.0)
		if check(is_instance_valid(car), "carro do Nonato montado para o estado"):
			car.vehicle_id = STATE.NONATO_CAR_ID
			if not w.has("desert_fleet"): w.desert_fleet = {}
			w.desert_fleet[STATE.NONATO_CAR_ID] = preload("res://runtime/FleetState.gd").capture(car, "desert")
			e.grant_reward(STATE.NONATO_CAR_RECEIPT, 0)
			session.desert._track_owned(car)
			extra = {"trunk_car": STATE.NONATO_CAR_ID}
	var result: Dictionary = STATE.chain_finish(w, e, id, extra)
	check(result.ok, "estado: %s marcada como feita" % id)
