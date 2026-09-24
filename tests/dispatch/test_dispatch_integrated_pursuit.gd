extends SceneTree
## Perseguição no Main real: crime percebido, busca, despacho, deslocamento físico,
## desembarque, perda/retomada de contato, reação a pé e encerramento sem órfãos.
## Exige --no-save --skip-arrival para nunca tocar no save pessoal.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--no-save" not in args or "--skip-arrival" not in args:
		push_error("Integração policial exige --no-save --skip-arrival")
		quit(2)
		return
	var world: Node = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for index in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "mundo produtivo iniciou")
	if not failures.is_empty():
		world.queue_free()
		quit(1)
		return
	check(world.production.no_save, "sessão integrada está isolada de saves pessoais")
	var controller: Node3D = world.dispatch
	check(is_instance_valid(controller) and controller.enabled and world.gameplay.dispatch_owned, "despacho produtivo está ativo e é o único proprietário")
	if not is_instance_valid(controller):
		world.queue_free()
		quit(1)
		return
	world.player.controlled_automatically = true
	var edge: Dictionary = controller.router.nearest_edge(world.player.global_position)
	check(not edge.is_empty(), "há rua produtiva junto do jogador")
	if edge.is_empty():
		world.queue_free()
		quit(1)
		return
	world.player.teleport(edge.closest + Vector3.UP * 0.08)
	await frames(5)
	world.gameplay.register_crime(60, world.player.global_position)
	check(world.gameplay.stars == 3 and world.gameplay.last_known_valid, "crime percebido inicia procura de três estrelas com posição conhecida")
	var unit: RefCounted = null
	for tick in 1200:
		await physics_frame
		if not controller.units.is_empty():
			unit = controller.units[0]
			break
	check(unit != null, "viatura foi despachada no mundo produtivo")
	if unit == null:
		world.queue_free()
		quit(1)
		return
	# Sem novo observador por mais de um segundo, a unidade busca a última posição.
	world.player.hide()
	await frames(90)
	check(world.gameplay.contact_age > 1.0 and unit.state == "enroute", "perda de contato muda a aproximação para busca da última posição")
	world.player.show()
	var start: Vector3 = unit.vehicle.global_position
	var last := start
	var travelled := 0.0
	var worst_step := 0.0
	var working := false
	for tick in 7200:
		await physics_frame
		# Testemunhas continuam atualizando o local enquanto este cenário mede a
		# aproximação; a perda de contato dos policiais é exercitada depois.
		if tick % 30 == 0: world.gameplay.report_contact(world.player.global_position)
		if is_instance_valid(unit.vehicle):
			var step: float = unit.vehicle.global_position.distance_to(last)
			travelled += step
			worst_step = maxf(worst_step, step)
			last = unit.vehicle.global_position
		if unit.state == "working" and not unit.officers.is_empty():
			working = true
			break
		if unit.finished: break
	check(working, "viatura aproximou, parou e desembarcou policiais no mapa real (%s)" % unit.state)
	check(travelled > 8.0 and worst_step < 0.6, "aproximação foi física, sem teletransporte (%.1f m; passo %.2f m)" % [travelled, worst_step])
	if working:
		world.player.hide()
		world.gameplay.health = 100.0
		await frames(90)
		check(world.gameplay.contact_age > 1.0 and unit.officers.all(func(officer): return not officer.sees_player), "policiais a pé perdem o alvo real sem mirar através do contexto")
		world.player.show()
		var reacted := false
		for tick in 900:
			await physics_frame
			if world.gameplay.health < 100.0:
				reacted = true
				break
		check(reacted, "policial a pé readquire e age contra o procurado")
	world.gameplay.clear_wanted()
	var cleared := false
	for tick in 5400:
		await physics_frame
		var police_left: Array = controller.units.filter(func(active): return active.is_police())
		if police_left.is_empty() and controller.foot_officer_count() == 0:
			cleared = true
			break
	check(not controller.events_named("officer_boarded").is_empty(), "encerramento registrou o embarque a pé")
	var remaining_police: Array = controller.units.filter(func(active): return active.is_police())
	var police_recalled: bool = remaining_police.all(func(active): return active.state in ["recall", "departing"] and active.officers.is_empty())
	check(cleared or (controller.foot_officer_count() == 0 and police_recalled), "fim da procura embarca a equipe e deixa apenas polícia em recall/partida física (%s)" % str(controller.status()))
	# Troca de contexto é o encerramento forte dos casos que permanecem visíveis e
	# fisicamente presos; deve remover inclusive pessoas já destacadas da unidade.
	controller.dismiss_all("integrated_test_cleanup")
	await frames(3)
	check(controller.units.is_empty() and controller.foot_officer_count() == 0, "troca de contexto encerra a perseguição sem unidade ou equipe órfã")
	world.queue_free()
	await process_frame
	print("DISPATCH_INTEGRATION checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
