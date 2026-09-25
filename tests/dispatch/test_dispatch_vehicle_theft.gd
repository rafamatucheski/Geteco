extends SceneTree
## Roubo da viatura de despacho na Main real: embarque, desembarque e ciclo de vida.
## Executar com --no-save; o cenário usa ruas, colisores e Driving verdadeiros.

var world: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)

func settle(frames: int) -> void:
	for frame in frames: await physics_frame

func find_road_pose(car: CharacterBody3D, road: Curve3D, origin: Vector3, start_distance: float, with_player: bool) -> bool:
	var offset: float = road.get_closest_offset(origin)
	for attempt in 28:
		var distance: float = fposmod(offset + start_distance + attempt * 5.0, road.get_baked_length())
		var point: Vector3 = road.sample_baked(distance, true)
		var ahead: Vector3 = road.sample_baked(minf(distance + 1.0, road.get_baked_length()), true) - point
		var yaw := atan2(-ahead.x, -ahead.z)
		var pose := point + Vector3.UP * 0.12
		if not world.production.vehicle_position_clear(car, pose, yaw): continue
		car.place(pose, yaw)
		await settle(2)
		if with_player:
			for side in [-1, 1]:
				world.player.teleport(car.driver_door_anchor(side) + Vector3.UP * 0.05)
				await settle(2)
				if world.driving._entry_option().get("car") != car: continue
				if two_exits_clear(car): return true
		else:
			if two_exits_clear(car): return true
	return false

func two_exits_clear(car: CharacterBody3D) -> bool:
	var reserved: Array[Vector3] = []
	for occupant in 2:
		var exit: Dictionary = world.dispatch.exit_point(car, reserved, false)
		if exit.is_empty(): return false
		reserved.append(exit.point)
	return true

func run() -> void:
	create_timer(180).timeout.connect(func(): print("TIMEOUT dispatch vehicle theft"); quit(2))
	if not "--no-save" in OS.get_cmdline_user_args():
		print("Use --no-save para este teste integrado")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 900:
		await physics_frame
		if is_instance_valid(world.session) and world.session.ready_for_play: break
	check(is_instance_valid(world.session) and world.session.ready_for_play, "Sessão integrada inicia")
	if not failures.is_empty(): quit(1); return
	var initial_car: CharacterBody3D = world.driving.car
	var road: Curve3D = world.production.traffic_routes.route_near(world.player.global_position)
	check(road != null, "Rua física próxima da sessão")
	if road == null: quit(1); return
	world.gameplay.register_crime(12, world.player.global_position)
	world.dispatch._police_clock = 1000.0
	world.dispatch._last_stars = world.gameplay.stars
	var patrol: CharacterBody3D = world.dispatch._create_vehicle("police", world.player.global_position + Vector3(8, 0, 0), 0.0)
	check(not patrol.player_damage_attribution and not patrol.is_player_damage_source(), "Viatura em serviço não atribui colisão ao jogador")
	check(await find_road_pose(patrol, road, world.player.global_position, 8.0, true), "Viatura estaciona com porta e duas saídas livres")
	if not failures.is_empty(): quit(1); return
	var unit: RefCounted = world.dispatch._make_unit("police", patrol, 8.0, 60.0)
	unit._set_state("parked")
	check(unit.crew_remaining == 2 and unit.officers.is_empty(), "Dupla policial ainda a bordo")
	check(world.driving._entry_option().get("car") == patrol, "Jogador alcança fisicamente a porta")
	var entry_side: int = int(world.driving._entry_option().get("side", -1))
	var barriers: Array[StaticBody3D] = []
	for side in [-1, 1]:
		var barrier := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 2.0, 7.0)
		shape.shape = box
		barrier.add_child(shape)
		world.add_child(barrier)
		barrier.global_transform = patrol.global_transform * Transform3D(Basis.IDENTITY, Vector3(side * (patrol.half_width + 0.75), 0.9, 0.0))
		barriers.append(barrier)
	await settle(2)
	check(not two_exits_clear(patrol), "Barreiras físicas impedem o desembarque")
	check(not world.driving._begin_entry(patrol, entry_side), "Embarque aborta quando a equipe não consegue sair")
	check(not world.driving.occupied and world.driving.car == initial_car and not unit.finished and unit.crew_remaining == 2 and patrol.has_meta("dispatch_unit"), "Recusa preserva jogador, equipe e viatura")
	for barrier in barriers: barrier.queue_free()
	await settle(3)
	world.player.teleport(patrol.driver_door_anchor(entry_side) + Vector3.UP * 0.05)
	await settle(2)
	check(world.driving.interact(), "Jogador entra na viatura em serviço")
	check(world.driving.occupied and world.driving.car == patrol and unit.finished, "Viatura é transferida sem perder a posse")
	check(unit.crew_remaining == 0 and unit.officers.is_empty() and world.gameplay.police.size() == 2, "Dois ocupantes saem e entram no ciclo de vida policial")
	var officers: Array[CharacterBody3D] = world.gameplay.police.duplicate()
	if officers.size() == 2:
		check(officers[0] != officers[1] and officers[0]._disembark_target.distance_to(officers[1]._disembark_target) >= 0.9, "Saídas físicas distintas")
		check(officers[0].mode == "disembark" and officers[1].mode == "disembark", "Ambos começam o desembarque animado")
	for frame in 240:
		if officers.size() == 2 and officers.all(func(o): return is_instance_valid(o) and o.mode == "combat") and not world.driving.is_body_transition_active(): break
		world.gameplay.health = 100
		await physics_frame
	if officers.size() == 2:
		check(officers.all(func(o): return is_instance_valid(o) and o.mode == "combat" and o.collision_layer != 0 and o.is_on_floor()), "Dupla completa a saída sobre o piso com colisão")
	check(is_instance_valid(patrol) and patrol.controlled and patrol.is_in_group("drivable") and not patrol.has_meta("dispatch_unit"), "Carro roubado continua dirigível")
	check(patrol.player_damage_attribution and patrol.is_player_damage_source(), "Viatura roubada atribui colisões ao jogador")
	check(world.dispatch.foot_officer_count() == 2, "Busca contabiliza os dois policiais")
	check(is_instance_valid(initial_car) and not initial_car.is_queued_for_deletion(), "Carro anterior do jogador preservado")
	world.gameplay.clear_wanted()
	await settle(3)
	check(world.gameplay.police.is_empty() and officers.all(func(o): return not is_instance_valid(o)), "Limpar procurado remove a dupla sem órfãos")
	check(is_instance_valid(patrol) and patrol.controlled, "Limpar procurado não remove a viatura do jogador")

	# Um policial já desembarcou, e o outro ainda está a bordo quando o carro é tomado.
	world.gameplay.register_crime(12, world.player.global_position)
	var second_car: CharacterBody3D = world.dispatch._create_vehicle("police", world.player.global_position + Vector3(12, 0, 0), 0.0)
	check(await find_road_pose(second_car, road, world.player.global_position, 28.0, false), "Segunda viatura encontra saídas físicas livres")
	if not failures.is_empty(): quit(1); return
	var second_unit: RefCounted = world.dispatch._make_unit("police", second_car, 8.0, 60.0)
	second_unit._set_state("parked")
	var reserved: Array[Vector3] = []
	var first_exit: Dictionary = world.dispatch.exit_point(second_car, reserved, false)
	var outside: CharacterBody3D = world.dispatch.spawn_officer(second_unit, first_exit.point, float(first_exit.side))
	second_unit.officers.append(outside)
	second_unit.crew_remaining -= 1
	second_unit._set_state("working")
	for frame in 180:
		if outside.mode == "combat" and outside.is_on_floor(): break
		await physics_frame
	check(outside.mode == "combat" and outside.is_on_floor() and outside.global_position.distance_to(first_exit.point) < 1.0, "Primeiro policial conclui desembarque físico do lado de fora")
	if not failures.is_empty(): quit(1); return
	outside.begin_return(second_car)
	check(world.dispatch.vehicle_stolen(second_car, -1), "Roubo com um policial já do lado de fora")
	check(second_unit.crew_remaining == 0 and second_unit.officers.is_empty() and world.gameplay.police.has(outside), "Policial externo também muda de dono")
	check(outside.mode == "combat" and not outside.boarded.is_connected(second_unit.on_officer_boarded), "Retorno e ligação com unidade encerrados")
	check(world.gameplay.police.size() == 2, "Ocupante restante também sai da segunda viatura")
	world.gameplay.clear_wanted()
	await settle(3)
	check(not is_instance_valid(outside) and is_instance_valid(second_car) and not second_car.is_queued_for_deletion(), "Limpeza remove policial e preserva segundo carro")
	print("DISPATCH_VEHICLE_THEFT checks=", checks, " failures=", JSON.stringify(failures))
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
