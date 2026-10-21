extends SceneTree
## M06-C "Turno da noite" na sessão real, curto: às 23h, com a missão oferecida, Dante desce
## pelo bueiro, sobe pelo alçapão do galpão, derruba um vigia pelas costas e pega o livro de
## despachos sem alarme. Não cobre o tiroteio, a van, o fogo nem a ligação final (contrato).
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tests/test_vertice_night_session.gd -- --no-save --skip-arrival
const NIGHT := preload("res://gameplay/urban_v1/vertice_night/VerticeNightState.gd")
const SHIFT := preload("res://gameplay/urban_v1/vertice_night/VerticeNightShift.gd")
const PROPS := preload("res://gameplay/urban_v1/vertice_night/VerticeNightProps.gd")
const UNDERCROFT := preload("res://gameplay/urban_v1/VerticeUndercroftPlace.gd")
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): failures.append("watchdog 420 s"); finish())
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("VERTICE_NIGHT_SESSION ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func finish() -> void:
	print("VERTICE_NIGHT_SESSION %s (%d verificações)" % ["OK" if failures.is_empty() else "FALHOU: " + ", ".join(failures), checks])
	quit(0 if failures.is_empty() else 1)

func frames(count: int) -> void:
	for i in count: await physics_frame

## Teletransporte termina num pouso curto; ações esperam o pé no chão.
func landed(player: Node3D) -> void:
	for i in 300:
		await physics_frame
		if not player.get_meta("player_air_busy", false): return

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
	var night = session._vertice_night()
	if not check(night != null, "Vértice tem o Turno da noite"): finish(); return
	session.state.world_state[NIGHT.KEY] = {"version":1, "stage":"offered", "route":"", "safe":false, "closed_until":0}
	session.weather.time_of_day = 23.0/24.0
	var player: Node3D = world.player
	player.teleport(SHIFT.ORIGIN + PROPS.SEWER_POINT + Vector3(0,.1,.6))
	for i in 900:
		await physics_frame
		if night.running and night.nearest_action().get("target","") == "vertice_night_sewer" and not player.get_meta("player_air_busy", false): break
	check(night.running, "segurança da noite monta ao chegar depois das 22h")
	if not check(night.nearest_action().get("target","") == "vertice_night_sewer", "bueiro da calçada oferece descer"): finish(); return
	check(await session.interact(), "desce pelo bueiro")
	for i in 900:
		await physics_frame
		if session.state.place_id == "vertice_undercroft" and not session.is_transition_blocked(): break
	if not check(session.state.place_id == "vertice_undercroft", "chega ao porão"): finish(); return
	check(not session.save_block_reason().is_empty(), "salvar bloqueado durante a invasão")
	check(await session.leave_place(), "sobe pelo alçapão")
	await frames(30)
	var landing: float = Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(UNDERCROFT.RETURN.x, UNDERCROFT.RETURN.z))
	check(session.state.place_id.is_empty() and landing < 3.0, "sai dentro do galpão, junto ao alçapão (%.1f m)" % landing)
	for i in 900:
		await physics_frame
		if night.guards.size() >= SHIFT.CREW.size(): break
	if not check(night.guards.size() == SHIFT.CREW.size(), "dois na ronda e um na guarita"): finish(); return
	check(not night.alarm, "sem alarme ao subir escondido")
	# Derrubada: atrás do Brito, que anda a ronda oeste.
	var guard = night.guards[0]
	guard.set_physics_process(false)
	player.teleport(guard.global_position - guard.facing() * 1.0 + Vector3.UP * .1)
	await landed(player)
	guard.set_physics_process(true)
	var action: Dictionary = night.nearest_action()
	check(action.get("target","") == "vertice_night_takedown", "pelas costas oferece derrubar (%s)" % action.get("target",""))
	check(await session.interact() and guard.dead and guard.knocked, "derruba o vigia sem tiro")
	check(not night.alarm and night.bodies.size() == 1, "derrubada não liga o alarme; corpo fica no chão")
	# Livro: arquivo de aço do escritório.
	player.teleport(SHIFT.ORIGIN + PROPS.BOOK_POINT + Vector3(-.4,.1,0))
	await landed(player)
	check(night.nearest_action().get("target","") == "vertice_night_book", "arquivo do escritório oferece o livro")
	check(await session.interact(), "abre o arquivo")
	for i in 40:
		if not session.dialogue_open: break
		session._advance_dialogue()
		await process_frame
	var state: Dictionary = session.state.world_state[NIGHT.KEY]
	check(state.stage == "escaping" and state.route == "stealth" and not night.alarm, "página no bolso, rota escondida, sem alarme")
	check(NIGHT.valid(state), "estado continua no contrato")
	await frames(10)
	check(str(session.objective.text).begins_with("Saia da Vértice"), "objetivo de saída na tela: %s" % session.objective.text)
	finish()
