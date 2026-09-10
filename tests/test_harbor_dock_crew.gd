extends SceneTree
var failures: Array[String] = []
var capture := false
const OUTPUT := "res://docs/measurements/dock-circuit-0910/"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	capture = "--capture" in OS.get_cmdline_user_args()
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	state.set_campaign_flag(&"harbor_arrival_seen",true)
	state.set_campaign_flag(&"harbor_arrival_call_complete",true)
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 25: await process_frame
	var player: Node2D = world.get_node("Player")
	player.set_physics_process(false)
	var waterfront = world.get_node("Waterfront")
	var crew = waterfront.get_node("DockCrew")
	var access: Dictionary = waterfront.get_ship_access_data()
	check(crew.workers.size() == 3, "Três operadores criados no navio")
	check(not crew.active and not crew.gull.playing, "Equipe distante suspensa e gaivotas silenciosas")
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .4
	world.weather.is_dark = false
	player.global_position = Vector2(3402,1762)
	await create_timer(.7).timeout
	check(crew.active, "A aproximação pela passarela ativa a equipe")
	if capture:
		var camera := Camera2D.new()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		world.add_child(camera)
		camera.global_position = Vector2(3580,1735)
		camera.zoom = Vector2.ONE*3.0
		camera.make_current()
	var recorder := AudioEffectRecord.new()
	var slot := AudioServer.get_bus_effect_count(0)
	if capture:
		AudioServer.add_bus_effect(0,recorder)
		recorder.set_recording_active(true)
	var valid_deck := true
	var clear_cargo := true
	var conserved := true
	var saw_carried := false
	var heard_gulls := false
	var hands_aligned := true
	var walked_forward := true
	var saw_empty_return := false
	var prior := []
	for worker in crew.workers:
		prior.append(worker.global_position)
		check(worker.head_node.has_node("SafetyHelmet") and worker.torso_node.has_node("ReflectiveVest"), "EPI no operador " + worker.name)
	var max_step := 0.0
	var start := Time.get_ticks_msec()
	var saved_carry := false
	while Time.get_ticks_msec()-start < 25000:
		await physics_frame
		for i in crew.workers.size():
			var worker = crew.workers[i]
			valid_deck = valid_deck and Geometry2D.is_point_in_polygon(worker.global_position,access.deck_polygon)
			for obstacle in access.obstacles:
				clear_cargo = clear_cargo and not obstacle.grow(10).has_point(worker.global_position)
			conserved = conserved and worker.crate_total() == 3
			saw_carried = saw_carried or (worker.carrying and worker.carried_box.visible)
			saw_empty_return = saw_empty_return or (worker.phase == "return" and not worker.carrying and worker.velocity.length() > 1)
			if worker.carrying and worker.phase == "carry" and worker._viewport_render_active:
				var left: Vector3 = worker.model_root.to_local(worker.left_crate_grip.global_position)
				var right: Vector3 = worker.model_root.to_local(worker.right_crate_grip.global_position)
				hands_aligned = hands_aligned and left.z < -.25 and right.z < -.25 and worker.carried_box.position.distance_to((left+right)*.5) < .06
				if worker.velocity.length() > 1:
					var forward: Vector3 = -worker.model_root.transform.basis.z
					walked_forward = walked_forward and Vector2(forward.x,forward.z).normalized().dot(worker.velocity.normalized()) > .95
			max_step = maxf(max_step,worker.global_position.distance_to(prior[i]))
			prior[i] = worker.global_position
		heard_gulls = heard_gulls or crew.gull.playing
		if capture and saw_carried and not saved_carry and Time.get_ticks_msec()-start > 2800:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT+"01_operadores_carregando.png")
			saved_carry = true
	if capture:
		recorder.set_recording_active(false)
		recorder.get_recording().save_to_wav(OUTPUT+"navio_ambiente.wav")
		AudioServer.remove_bus_effect(0,slot)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT+"02_operacao_de_carga.png")
	check(valid_deck and clear_cargo, "Operadores ficam no convés e fora dos contêineres")
	check(max_step < 10, "Movimento contínuo, sem teletransporte")
	check(conserved and saw_carried, "Caixas visíveis nas mãos e estoque conservado")
	check(hands_aligned, "Caixa apoiada entre as duas luvas, à frente do corpo")
	check(walked_forward, "Operadores giram antes de caminhar, sem transportar de costas")
	check(saw_empty_return, "Depois de entregar, operadores retornam sem carga")
	var delivered := true
	for worker in crew.workers: delivered = delivered and worker.deliveries >= 1
	check(delivered, "Cada operador concluiu pelo menos uma entrega")
	for worker in crew.workers:
		check(worker.completed_circuits >= 1, "Circuito fechado completo: " + worker.name)
	check(heard_gulls and crew.gull.bus == &"SFX", "Gaivotas espaciais tocam na aproximação")
	# Percorre o circuito autoral usando a cápsula e as colisões reais do jogador.
	var passage_clear := true
	for point in access.walk_route:
		var hit = player.move_and_collide(waterfront.to_global(point)-player.global_position)
		if hit != null:
			print("SHIP_PASSAGE_COLLIDER ",hit.get_collider().name," at ",player.global_position)
			passage_clear = false
			break
	check(passage_clear and player.global_position.distance_to(Vector2(3130,1762)) < 1, "Cápsula do jogador cruza passarela, percorre convés e retorna ao cais")
	var worker = crew.workers[0]
	# Exercita uma interrupção enquanto a carga está nas mãos.
	worker.set_physics_process(false)
	worker.carrying = true
	worker.crate_stock = [2,0]
	worker.dropped_crates.clear()
	worker.is_scared = true
	worker.panic_timer = 4
	worker._physics_process(.016)
	check(not worker.carrying and worker.dropped_crates.size() == 1 and worker.crate_total() == 3, "Pânico interrompe o trabalho e deixa a caixa no chão")
	worker.is_scared = false
	player.global_position = Vector2(700,1000)
	await create_timer(.6).timeout
	check(not crew.active and not crew.gull.playing and not crew.handling.playing, "Ao sair do cais, fontes param")
	var deliveries: int = crew.workers[1].deliveries
	await create_timer(.6).timeout
	check(not crew.workers[1].is_physics_processing() and crew.workers[1].deliveries == deliveries, "Equipe distante não continua simulando carga")
	world.queue_free()
	await process_frame
	print("DOCK_CREW: %d falhas" % failures.size())
	quit(0 if failures.is_empty() else 1)
