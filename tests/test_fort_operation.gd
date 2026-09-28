extends SceneTree
## Operação do forte no jogo real: terminal e porta, percepção (parede bloqueia),
## combate tático (abrigo escondido, espia, tiro), alarme com reforço e flanqueadores,
## saque persistido e fim da operação. Exige --no-save.

var world
var session
var passage
var tunnel
var progression
var op
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("FORT_OP ","PASS " if ok else "FAIL ",label)
	if ok: return
	failures += 1
	push_error("FORT_OP FAIL "+label)

func settle(frames := 10) -> void:
	for _frame in frames: await physics_frame

func seconds(value: float) -> void:
	# Mantém o jogador vivo: o teste mede comportamento, não sobrevivência.
	for frame in int(value*60.0):
		await physics_frame
		if frame%10 == 0: heal()

func heal() -> void:
	session.world.gameplay.health = 100.0

func fort_local(point: Vector3) -> Vector3:
	return session.room.to_global(point)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	seed(195107)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 420:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("FORT_OP Main did not become ready")
		quit(1)
		return
	session = world.session
	await settle(120)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	if is_instance_valid(session.world.hud): session.world.hud.hide()
	passage = session.urban_operations.secret_passage
	tunnel = passage.tunnel
	progression = session.urban_operations.secret_network
	tunnel.set_return_camera(world.camera)
	check(await session.enter_place("mountain_fort",false,"secret_network"),"entra no forte")
	await settle(30)
	op = session.room.operation
	check(op != null and op.soldiers.size() == 5,"primeiro esquadrão de 5 soldados")
	check(not session.room.model.blast_open and session.room.model.blast_body.collision_layer == 1,"porta blindada fechada e sólida")
	check(op.covers.size() == 14,"14 pontos de abrigo (7 coberturas, 2 lados)")

	# Parede/porta bloqueia a visão: na ante-sala ninguém percebe o jogador.
	heal()
	world.player.teleport(fort_local(Vector3(0,.04,-3.0)))
	await seconds(3.0)
	check(op.alive_soldiers().all(func(soldier): return soldier.state == "idle"),"porta fechada: soldados seguem em guarda")

	# Terminal libera a porta.
	world.player.teleport(fort_local(session.room.model.DOOR_TERMINAL))
	await settle(6)
	var action: Dictionary = passage.nearest_action()
	check(action.get("target","").ends_with("fort_open_door"),"terminal oferece abrir a porta")
	check(passage.perform(action.target),"abre a porta blindada")
	await seconds(3.0)
	check(session.room.model.blast_body.collision_layer == 0,"colisor da porta some ao abrir")
	check(op.find_path(fort_local(Vector3(0,.04,-3.0)),fort_local(Vector3(0,.04,-19.0))).size() > 10,"rota da ante-sala até o fundo existe")

	# Percepção: dentro do campo de visão de uma sentinela, a consciência sobe até o combate.
	heal()
	world.player.teleport(fort_local(Vector3(0,.04,-9.5)))
	var started := Time.get_ticks_msec()
	var alerted := false
	while Time.get_ticks_msec()-started < 9000:
		await physics_frame
		heal()
		if op.alive_soldiers().any(func(soldier): return soldier.state == "combat"):
			alerted = true
			break
	check(alerted,"jogador à vista de soldados leva ao combate")
	await seconds(1.0)
	check(op.alive_soldiers().all(func(soldier): return soldier.state == "combat"),"rádio: todo o esquadrão entra em combate")

	# Tática: abrigos reais, escondidos da linha do jogador, e tiros.
	heal()
	await physics_frame
	var health_before: float = session.world.gameplay.health
	var covered := 0
	var hidden_ok := 0
	var fired := 0
	var lowest := health_before
	for tick in 60*12:
		await physics_frame
		lowest = minf(lowest,session.world.gameplay.health)
		heal()
		if tick%30 == 0:
			for soldier in op.alive_soldiers():
				if not soldier.cover.is_empty(): covered += 1
				if soldier.phase == "hidden" and not soldier.cover.is_empty() \
					and soldier.global_position.distance_to(soldier.cover.hide) < 1.3 \
					and op.blocked(world.player.global_position+Vector3.UP*1.6,soldier.global_position+Vector3.UP*1.45): hidden_ok += 1
	for soldier in op.soldiers: fired += soldier.shots_fired
	check(covered > 0,"soldados assumem abrigo")
	check(hidden_ok > 0,"há soldado realmente escondido atrás de cobertura")
	check(fired > 0,"soldados espiam e atiram (%d tiros)"%fired)
	check(lowest < health_before,"tiros chegam ao jogador (vida mínima %.0f)"%lowest)
	var keys := {}
	for soldier in op.alive_soldiers():
		if not soldier.cover.is_empty():
			check(not keys.has(soldier.cover.key),"abrigo %s não é dividido"%soldier.cover.key)
			keys[soldier.cover.key] = true

	# Alarme (câmeras) chama reforço com flanqueadores.
	op.reinforcement_delay = .5
	op.trigger_alarm(world.player.global_position)
	await seconds(2.5)
	check(op.alarm_active and op.reinforced and op.soldiers.size() == 9,"alarme chama o segundo esquadrão (9 soldados)")
	check(op.model.beacons.all(func(light): return light.visible),"giroflex do alarme aceso")
	await seconds(8.0)
	heal()
	var flankers: Array = op.alive_soldiers().filter(func(soldier): return soldier.role == "flanker")
	check(flankers.size() == 2 and flankers.all(func(soldier): return soldier.state == "combat"),"dois flanqueadores em combate")
	check(flankers.any(func(soldier): return not soldier.cover.is_empty() and absf(soldier.cover.x-world.player.position.x) > 0.0),"flanqueadores escolhem abrigo")

	# Ferido recua para abrigo longe do jogador.
	var wounded: Node = op.alive_soldiers()[0]
	wounded.health = wounded.max_health*.2
	await seconds(3.0)
	check(wounded.cover.get("retreat",false),"soldado ferido recua")

	# Derrota do esquadrão.
	for soldier in op.alive_soldiers(): soldier.receive_damage(999.0,world.player)
	await settle(10)
	check(op.alive_soldiers().is_empty() and op.cleared_announced,"sala neutralizada")

	# Saque: recompensa persistida; segunda visita sem soldados e porta aberta.
	heal()
	var money_before := 0.0
	if session.state.economy.has_method("balance"): money_before = float(session.state.economy.balance())
	world.player.teleport(fort_local(Vector3(7.3,.04,-22.2)))
	await seconds(1.0)
	check(session.state.world_state.rewards.has("mountain_fort_stash_cash"),"saque coletado e registrado")
	await session.leave_place()
	await seconds(1.0)
	check(session.state.place_id.is_empty(),"saiu do forte")
	tunnel.set_return_camera(world.camera)
	check(await session.enter_place("mountain_fort",false,"secret_network"),"reentra no forte")
	await settle(30)
	check(session.room.operation.soldiers.is_empty() and session.room.model.blast_open,"operação concluída: sem soldados, porta aberta")
	print("FORT_OP PASS checks=%d failures=%d"%[checks,failures])
	world.free()
	await process_frame
	quit(1 if failures else 0)
