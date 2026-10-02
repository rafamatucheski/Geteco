extends "res://tests/dispatch/test_dispatch_vehicle_theft.gd"
## Diagnóstico R4: população física preparada até FOOT_LIMIT, depois roubo real.
## Conservação de ocupantes é verificada; exceder teto é REGISTRADO, não aprovado.
## _make_unit prepara frota dentro de MAX_ACTIVE/MAX_UNITS; não mede despacho
## espontâneo ou sua latência. Desembarque, colisão, roubo e ownership são reais.
const RULES = preload("res://gameplay/dispatch/DispatchRules.gd")
var budget_report: Dictionary = {}

func _parked_unit(archetype: String, road: Curve3D, offset: float, at_player: bool) -> RefCounted:
	check(world.dispatch.units.size() < RULES.MAX_ACTIVE[6] and world.dispatch.units.size() < RULES.MAX_UNITS, "fixture respeita limite de unidades antes da criação")
	if world.dispatch.units.size() >= RULES.MAX_ACTIVE[6] or world.dispatch.units.size() >= RULES.MAX_UNITS: return null
	var vehicle: CharacterBody3D = world.dispatch._create_vehicle("police", world.player.global_position + Vector3(8, 0, 0), 0.0, archetype)
	var admitted: bool = await find_road_pose(vehicle, road, world.player.global_position, offset, at_player)
	check(admitted, "carroceria e saídas livres: " + archetype)
	if not admitted: return null
	var unit: RefCounted = world.dispatch._make_unit("police", vehicle, 8.0, 60.0)
	unit.level = 6
	unit.variant = "tactical" if archetype == "police_transport" else "patrol"
	unit.crew_capacity = RULES.crew_size(archetype)
	unit.crew_remaining = unit.crew_capacity
	unit._set_state("parked")
	return unit

func run() -> void:
	create_timer(240.0).timeout.connect(func(): print("R4_BUDGET TIMEOUT"); quit(2))
	if not "--no-save" in OS.get_cmdline_user_args():
		push_error("R4 orçamento exige --no-save e APPDATA temporário")
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
	world.gameplay.register_crime(420, world.player.global_position)
	check(world.gameplay.stars == 6, "seis estrelas mantêm o mesmo limite antes/depois do roubo")
	var road: Curve3D = world.production.traffic_routes.route_near(world.player.global_position)
	check(road != null, "malha real próxima")
	if road == null: _finish(); return
	var prepared: Array[RefCounted] = []
	var archetypes: Array[String] = ["police_transport", "police_transport", "police_cruiser", "police_cruiser"]
	for index in archetypes.size():
		if world.dispatch.foot_officer_count() >= RULES.FOOT_LIMIT[6]: break
		var unit: RefCounted = await _parked_unit(archetypes[index], road, 12.0 + index * 22.0, false)
		if unit == null: _finish(); return
		prepared.append(unit)
		# A mesma rotina usada pelo estado parked reserva pontos e cria cada
		# DispatchOfficer dentro da viatura, sem trocar a contagem por um mock.
		unit._deploy_police_crew()
		await settle(3)
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if world.dispatch.foot_officer_count() >= RULES.FOOT_LIMIT[6]: break
		for unit in prepared:
			if not unit.finished and unit.crew_remaining > 0: unit._deploy_police_crew()
		await physics_frame
	var count: int = world.dispatch.foot_officer_count()
	check(count == RULES.FOOT_LIMIT[6], "desembarque produtivo preenche orçamento: %d" % count)
	if count != RULES.FOOT_LIMIT[6]: _finish(); return
	var target: RefCounted = await _parked_unit("police_cruiser", road, 4.0, true)
	if target == null: _finish(); return
	var patrol: CharacterBody3D = target.vehicle
	# O teto cheio mantém essa dupla embarcada; o roubo deve preservar ambos.
	var crew_before: int = target.crew_remaining
	var foot_before: int = world.dispatch.foot_officer_count()
	var air_before: int = world.gameplay.get_meta("police_air_reserved_slots", 0)
	var stars_before: int = world.gameplay.stars
	var limit_before: int = RULES.FOOT_LIMIT[stars_before]
	var owners_before: Array = world.gameplay.police.duplicate()
	check(foot_before == limit_before and crew_before == 2 and target.officers.is_empty(), "alvo conserva dupla sentada com orçamento a pé saturado")
	if foot_before != limit_before or crew_before != 2: _finish(); return
	check(world.driving.interact(), "roubo imediato continua disponível com orçamento cheio")
	check(world.driving.occupied and world.driving.car == patrol and target.finished, "viatura realmente transferida ao jogador")
	var foot_after: int = world.dispatch.foot_officer_count()
	var air_after: int = world.gameplay.get_meta("police_air_reserved_slots", 0)
	var stars_after: int = world.gameplay.stars
	var limit_after: int = RULES.FOOT_LIMIT[stars_after]
	var transferred: Array[CharacterBody3D] = []
	for officer in world.gameplay.police:
		if not owners_before.has(officer): transferred.append(officer)
	check(transferred.size() == crew_before and target.crew_remaining == 0 and target.officers.is_empty(), "nenhum ocupante apagado ou duplicado para caber no teto")
	check(foot_after == foot_before + crew_before, "contagem conserva os agentes existentes mais os ocupantes")
	check(stars_before == 6 and stars_after == 6 and limit_before == limit_after and air_before == air_after, "comparação síncrona mantém estrelas, teto e reservas aéreas")
	check(transferred.all(func(officer): return officer.controller == world.gameplay and officer.dispatch_controller == null and officer.vehicle == patrol and officer.mode == "disembark"), "ownership passa a Gameplay preservando veículo durante desembarque")
	budget_report = {"stars_before": stars_before, "stars_after": stars_after, "limit_before": limit_before, "limit_after": limit_after, "foot_before": foot_before, "foot_after": foot_after, "air_reserved_before": air_before, "air_reserved_after": air_after, "living_ground_before": foot_before - air_before, "living_ground_after": foot_after - air_after, "crew": crew_before, "over_limit": maxi(0, foot_after - limit_after), "allocation_cap_satisfied": foot_after <= RULES.MAX_FOOT_OFFICERS, "absolute_ground_cap_satisfied": foot_after - air_after <= RULES.MAX_FOOT_OFFICERS, "absolute_ground_excess": maxi(0,foot_after-air_after-RULES.MAX_FOOT_OFFICERS), "population_prepared": true, "budget_approved": false, "budget_status": "forced_exit_excess_observed" if foot_after > limit_after else "saturation_not_reproduced"}
	check(foot_after == limit_after + crew_before and not budget_report.allocation_cap_satisfied, "reproduz excesso de alocação após saída forçada; teto global permanece pendente")
	print("R4_SATURATION ", JSON.stringify(budget_report))
	deadline = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if transferred.all(func(officer): return is_instance_valid(officer) and officer.mode == "combat"): break
		await physics_frame
	check(transferred.all(func(officer): return is_instance_valid(officer) and not officer.dead and officer.mode == "combat" and officer.is_on_floor()), "dupla forçada termina desembarque físico e permanece viva")
	# Outra equipe real comprova o sentido atual de FOOT_LIMIT: admissão
	# voluntária não aumenta a dívida gerada pela saída forçada do carro roubado.
	var reserve: RefCounted = await _parked_unit("police_cruiser", road, 108.0, false)
	if reserve != null:
		var before_attempt: int = world.dispatch.foot_officer_count()
		check(before_attempt >= limit_after, "controle voluntário ainda está sem vagas")
		var remaining: int = reserve.crew_remaining
		check(not reserve._deploy_police_crew() and reserve.crew_remaining == remaining and reserve.officers.is_empty(), "saída voluntária aguarda vaga e preserva ocupantes sentados")
		check(world.dispatch.foot_officer_count() == before_attempt, "tentativa voluntária não amplia excesso")
	world.gameplay.clear_wanted()
	world.dispatch.dismiss_all("saturation_cleanup")
	await settle(3)
	check(world.dispatch.foot_officer_count() == 0 and transferred.all(func(officer): return not is_instance_valid(officer)), "limpeza produtiva não deixa agentes transferidos órfãos")
	check(is_instance_valid(patrol) and not patrol.is_queued_for_deletion(), "limpeza preserva viatura roubada")
	_finish()

func _finish() -> void:
	print("STOLEN_OFFICER_BUDGET checks=", checks, " failures=", JSON.stringify(failures), " observation=", JSON.stringify(budget_report))
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)
