extends "res://tests/dispatch/test_dispatch_vehicle_theft.gd"
## R4: Main, Driving, DispatchOfficer e interiores produtivos.
## Reutiliza somente os helpers físicos de estacionamento do teste de roubo.
## Portas/atores são posicionados na preparação: não certifica caminhada até
## a loja nem observação visual humana. Não desliga os diretores do mundo.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const RULES = preload("res://gameplay/dispatch/DispatchRules.gd")

func _prepare_access(id: String) -> bool:
	var door: Vector3 = world.maciota_place.exterior_return if id == "maciota" else PLACES.get_definition(id).return_position
	world.production.region.prepare_collision_at(door)
	await settle(3)
	check(world.session.position_clear(door + Vector3.UP * .06), id + " porta exterior fisicamente livre")
	if not world.session.position_clear(door + Vector3.UP * .06): return false
	world.player.teleport(door + Vector3.UP * .06)
	world.gameplay.report_contact(world.player.global_position)
	# O consumidor real observa o contato exterior antes da troca de contexto.
	await settle(2)
	return true

func _check_budget_context() -> Dictionary:
	var legacy := 0
	var dispatched := 0
	for officer in world.gameplay.police:
		if is_instance_valid(officer) and not officer.dead: legacy += 1
	for unit in world.dispatch.units:
		for officer in unit.officers:
			if is_instance_valid(officer) and not officer.dead: dispatched += 1
	var air: int = world.gameplay.get_meta("police_air_reserved_slots", 0)
	var actual: int = world.dispatch.foot_officer_count()
	check(actual == legacy + dispatched + air, "orçamento inclui Gameplay.police, equipes de despacho e reservas aéreas")
	return {"stars": world.gameplay.stars, "limit": RULES.FOOT_LIMIT[clampi(world.gameplay.stars, 0, 6)], "foot": actual, "gameplay_police": legacy, "unit_officers": dispatched, "air_reserved": air}

func run() -> void:
	create_timer(240.0).timeout.connect(func(): print("R4 TIMEOUT"); quit(2))
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("R4 exige --no-save e APPDATA temporário fornecido pelo executor")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "sessão real pronta")
	if world.session == null or not world.session.ready_for_play: _finish(); return
	check(world.production.no_save, "save pessoal não utilizado")
	if not world.production.no_save: _finish(); return
	var road: Curve3D = world.production.traffic_routes.route_near(world.player.global_position)
	check(road != null, "rua real disponível")
	if road == null: _finish(); return
	world.gameplay.register_crime(12, world.player.global_position)
	var patrol: CharacterBody3D = world.dispatch._create_vehicle("police", world.player.global_position + Vector3(8, 0, 0), 0.0)
	var parked: bool = await find_road_pose(patrol, road, world.player.global_position, 8.0, true)
	check(parked, "viatura com porta e duas saídas físicas livres")
	if not parked: _finish(); return
	var unit: RefCounted = world.dispatch._make_unit("police", patrol, 8.0, 60.0)
	unit._set_state("parked")
	var occupants: int = unit.crew_remaining
	var existing: Array = world.gameplay.police.duplicate()
	var before := _check_budget_context()
	check(world.driving.interact(), "roubo acionado pelo Driving real")
	check(world.driving.occupied and world.driving.car == patrol and unit.finished, "posse da viatura transferida")
	var stolen: Array[CharacterBody3D] = []
	for officer in world.gameplay.police:
		if not existing.has(officer): stolen.append(officer)
	var after := _check_budget_context()
	check(stolen.size() == occupants and unit.crew_remaining == 0 and unit.officers.is_empty(), "todos os ocupantes preservados com proprietário único")
	check(int(after.foot) == int(before.foot) + occupants, "roubo contabiliza cada ocupante uma vez")
	check(int(after.foot) <= int(after.limit), "limite de policiais respeitado depois do crime adicional")
	print("R4_BUDGET ", JSON.stringify({"before": before, "after": after, "occupants": occupants, "saturated_before": int(before.foot) >= int(before.limit)}))
	if stolen.size() < 2: _finish(); return
	var officer: CharacterBody3D = stolen[0]
	var garage_candidate: CharacterBody3D = stolen[1]
	var officer_id := officer.get_instance_id()
	var rig_id: int = officer.visual.get_instance_id()
	deadline = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(officer) or not is_instance_valid(garage_candidate): break
		if officer.mode == "combat" and garage_candidate.mode == "combat" and not world.driving.is_body_transition_active(): break
		await physics_frame
	check(is_instance_valid(officer) and is_instance_valid(garage_candidate), "agentes sobrevivem ao desembarque")
	if not is_instance_valid(officer) or not is_instance_valid(garage_candidate): _finish(); return
	check(officer.mode == "combat" and garage_candidate.mode == "combat" and officer.is_on_floor() and garage_candidate.is_on_floor(), "desembarque físico conclui sobre piso")
	check(not is_instance_valid(officer.dispatch_controller) and not is_instance_valid(garage_candidate.dispatch_controller), "roubo solta vínculo antigo com despacho")
	check(officer.get_instance_id() == officer_id and officer.visual.get_instance_id() == rig_id, "desembarque preserva agente e rig")
	check(world.driving.leave(), "jogador desembarca fisicamente da viatura roubada")
	deadline = Time.get_ticks_msec() + 6000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline: await physics_frame
	check(not world.driving.occupied and not world.player.input_locked, "jogador a pé e destravado")
	if world.driving.occupied or world.player.input_locked: _finish(); return
	if not await _prepare_access("harbor_ammunation"): _finish(); return
	check(await world.session.enter_place("harbor_ammunation", false), "transição produtiva para interior comum")
	await settle(2)
	var pursuit: Node3D = world.gameplay.police_interiors
	check(pursuit.knows_current_interior(), "contato na porta autoriza contexto interior")
	if not is_instance_valid(officer) or officer.dead: check(false, "candidato continua vivo"); _finish(); return
	# Preparação física junto à porta, sem simular admit/take_agent_for_interior.
	officer.global_position = world.session.return_point + Vector3.UP * .06
	officer.velocity = Vector3.ZERO
	await settle(2)
	check(pursuit.admission_point(officer).is_finite(), "interior oferece cápsula de entrada livre")
	var admitted: bool = pursuit.admit(officer)
	check(admitted, "policial da viatura roubada pode entrar na loja")
	if admitted:
		check(officer.get_instance_id() == officer_id and officer.visual.get_instance_id() == rig_id, "admissão preserva corpo e rig originais")
		check(world.gameplay.police.count(officer) == 1 and officer.get_meta("police_place_id", "") == "harbor_ammunation", "propriedade e contexto interior únicos")
		check(officer.collision_mask == 7 and world.session.room.is_floor_clear(world.session.room.to_local(officer.global_position), .34), "admissão preserva colisão e piso livre")
	check(world.session.leave_place(), "saída produtiva da loja")
	await settle(2)
	if admitted:
		var still_owned := false
		for candidate in world.gameplay.police:
			if is_instance_valid(candidate) and candidate.get_instance_id() == officer_id:
				still_owned = true
		check(not is_instance_valid(instance_from_id(officer_id)) and not still_owned, "saída libera visitante sem duplicá-lo no exterior")
	if not is_instance_valid(garage_candidate) or garage_candidate.dead:
		check(false, "segundo ocupante disponível para controle de garagem")
		_finish()
		return
	if not await _prepare_access("maciota"): _finish(); return
	check(await world.session.enter_place("maciota", false), "transição produtiva para Maciota")
	await settle(2)
	pursuit.report_interior("maciota")
	garage_candidate.global_position = world.session.return_point + Vector3.UP * .06
	garage_candidate.velocity = Vector3.ZERO
	await settle(2)
	check(not pursuit.knows_current_interior() and not pursuit.admit(garage_candidate), "garagem não admite policial mesmo após denúncia")
	check(garage_candidate.get_meta("police_place_id", "") != "maciota" and not world.session.state.weapons_allowed(), "controle de garagem mantém contexto exterior e restrição de armas")
	check(world.session.leave_place(), "saída da garagem conclui")
	world.gameplay.clear_wanted()
	await settle(3)
	check(not is_instance_valid(garage_candidate), "fim da procura limpa policial transferido")
	check(is_instance_valid(patrol) and not patrol.is_queued_for_deletion(), "limpeza policial preserva carro roubado")
	_finish()

func _finish() -> void:
	print("STOLEN_OFFICER_INTERIOR checks=", checks, " failures=", JSON.stringify(failures))
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)
