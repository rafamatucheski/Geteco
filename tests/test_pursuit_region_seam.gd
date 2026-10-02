extends SceneTree
## R3: posição inicial explícita + resposta real preparada; travessia por Input.
## Não mede latência natural do despacho. Não teleporta durante a travessia.
## Sem save pessoal; executor fornece APPDATA isolado. Sem certificação de FPS.
const CONNECTION = preload("res://world/regions/WorldConnection3D.gd")
const OFFICER = preload("res://gameplay/PoliceAgent.gd")
var world: Node3D
var car: CharacterBody3D
var failures: Array[String] = []
var checks := 0
var trace: Array[Dictionary] = []
var seam_events: Array[Dictionary] = []
var routing_events: Array[Dictionary] = []
var before_seam: Dictionary = {}
var last_observation: Dictionary = {}
var crossing := false
var handling_frames := 0
var worst_physics_step := 0.0
var travelled := 0.0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("R3 PASS " if ok else "R3 FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func _release_input() -> void:
	for action in ["move_up", "move_down", "move_left", "move_right", "handbrake"]: Input.action_release(action)

func _snapshot(graph_detail := false) -> Dictionary:
	var air: Node3D = world.gameplay.police_air
	var helicopter: CharacterBody3D = air.helicopter
	var dogs: Array[Dictionary] = []
	var ropes: Array[int] = []
	for dog in air.dogs:
		if is_instance_valid(dog):
			dogs.append({"id": dog.get_instance_id(), "mode": dog.mode, "withdrawing": dog.withdrawing, "dead": dog.dead, "handler_alive": is_instance_valid(dog.handler) and not dog.handler.dead})
	if is_instance_valid(helicopter):
		for entry in helicopter.rappellers:
			if is_instance_valid(entry.officer): ropes.append(entry.officer.get_instance_id())
	var residents: Array = world.production.regions.keys()
	residents.sort()
	var result: Dictionary = {
		"usec": Time.get_ticks_usec(), "physics_frame": Engine.get_physics_frames(),
		"region": world.session.state.region_id, "residents": residents,
		"position": [car.global_position.x, car.global_position.y, car.global_position.z],
		"speed": car.speed, "occupied": world.driving.occupied, "handling": car._handling_frame,
		"stars": world.gameplay.stars, "health": world.gameplay.health,
		"helicopter_id": helicopter.get_instance_id() if is_instance_valid(helicopter) else 0,
		"helicopter_mode": str(helicopter.mode) if is_instance_valid(helicopter) else "absent",
		"helicopter_dead": helicopter.dead if is_instance_valid(helicopter) else false,
		"helicopter_timer": air.helicopter_timer, "ropes": ropes, "dogs": dogs,
	}
	if graph_detail:
		var graph: RefCounted = world.production.traffic_routes
		result["graph_signature"] = hash([graph.vertices, graph.edges])
		result["vertices"] = graph.vertices.size()
		result["edge_origins"] = graph.edges.size()
		result["blocked"] = world.dispatch.router.blocked.duplicate()
		var units: Array[Dictionary] = []
		for unit in world.dispatch.units:
			if not is_instance_valid(unit.vehicle): continue
			var nearest: Dictionary = world.dispatch.router.nearest_edge(unit.vehicle.global_position)
			units.append({"id": unit.get_instance_id(), "state": unit.state, "position": str(unit.vehicle.global_position), "nearest_edge_distance": nearest.get("distance", -1.0)})
		result["units"] = units
	return result

func _logical_change(previous: String, next: String) -> void:
	if not crossing: return
	before_seam = last_observation.duplicate(true)
	seam_events.append({"previous": previous, "next": next, "at_signal": _snapshot(true)})

func _dispatch_event(event_name: String, data: Dictionary) -> void:
	if event_name not in ["replanned", "no_route", "route_blocked", "unit_finished", "dispatched"]: return
	var unit: Variant = data.get("unit")
	routing_events.append({"usec": Time.get_ticks_usec(), "name": event_name, "region": world.session.state.region_id, "unit_id": unit.get_instance_id() if is_instance_valid(unit) else 0, "reason": str(data.get("reason", ""))})

func _prepare_car() -> bool:
	car = world.driving.car
	check(is_instance_valid(car), "veículo inicial real disponível")
	if not is_instance_valid(car): return false
	var origin := Vector3(CONNECTION.SEAM.x - 8.0, .12, CONNECTION.CENTER_Z + 1.9375)
	# Único posicionamento inicial. Monta piso real dos dois lados antes de
	# admitir a carroceria e o motorista; nenhum collider é removido.
	world.player.teleport(origin + Vector3(0, 0, 4.0))
	world.production._update_physical_residency(origin)
	for region in world.production.regions.values():
		region.prepare_collision_at(origin)
		region.prepare_collision_at(origin + Vector3(18, 0, 0))
	await frames(4)
	check(world.production.vehicle_position_clear(car, origin, -PI * .5), "carroceria admitida sobre piso livre do conector")
	if not world.production.vehicle_position_clear(car, origin, -PI * .5): return false
	car.place(origin, -PI * .5)
	car.set_meta("region_id", "harbor")
	car.set_meta("garage_place", "")
	# Mesma folga lateral da restauração exterior produtiva. O anchor sozinho
	# pode sobrepor a cápsula à carroceria de um carro comum.
	var door := Vector3.INF
	for side in [-1, 1]:
		var candidate: Vector3 = car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		if car.boarding_class() in ["truck", "bus"]:
			candidate = car.driver_door_anchor(side) + car.global_basis.x*float(side)*.11 + Vector3.UP*.01
		if world.session.position_clear(candidate): door = candidate; break
	check(door.is_finite(), "porta do motorista tem cápsula livre")
	if not door.is_finite(): return false
	world.player.teleport(door)
	await frames(3)
	var boarded: bool = await world.session.restore_garage_driver(car)
	check(boarded and world.driving.occupied and car.controlled and not car.external_input, "embarque real habilita Input/V1Handling")
	check(world.session.state.region_id == "harbor" and car.global_position.x < CONNECTION.SEAM.x, "preparação terminou antes da costura")
	return boarded and world.driving.occupied and car.controlled and not car.external_input

func _handler_point(air: Node3D) -> Vector3:
	# O deslocamento fixo anterior não garantia o contrato fora da câmera.
	# Busca finita, dentro dos 55 m produtivos, sem mover câmera ou colisores.
	for radius in [52.0, 40.0]:
		for index in 12:
			var angle: float = TAU*float(index)/12.0
			var point: Vector3 = car.global_position + Vector3(cos(angle)*radius,0,sin(angle)*radius)
			if air.point_on_screen(point, 3.0): continue
			for mounted in world.production.regions.values(): mounted.prepare_collision_at(point)
			await frames(3)
			var hit: Dictionary = air.ground_hit(point,3.0)
			if hit.is_empty(): continue
			point = hit.position + Vector3.UP*.06
			if air.capsule_clear(point): return point
	return Vector3.INF

func _prepare_response() -> bool:
	# Três estrelas já ativam aeronave e K9. O cenário testa continuidade,
	# sem exigir que o jogador absorva uma preparação longa a cinco estrelas.
	world.gameplay.register_crime(80, car.global_position)
	check(world.gameplay.stars >= 3, "procura ativa para fixture de continuidade")
	var air: Node3D = world.gameplay.police_air
	var zone: Dictionary = {}
	for attempt in 3:
		zone = air.find_landing_zone(car.global_position)
		if not zone.is_empty(): break
	check(not zone.is_empty(), "zona de inserção passa verificações produtivas")
	if zone.is_empty(): return false
	if not is_instance_valid(air.helicopter): check(air.launch_helicopter(zone), "helicóptero lançado por API produtiva")
	var deadline := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.gameplay.health <= 0 or not world.driving.occupied: break
		if is_instance_valid(air.helicopter) and air.helicopter.mode == "rappel" and not air.helicopter.rappellers.is_empty(): break
	check(world.gameplay.health > 0 and world.driving.occupied, "jogador sobreviveu à preparação aérea sem reposição de saúde")
	if world.gameplay.health <= 0 or not world.driving.occupied: return false
	# Só prepara o handler adicional depois da chegada física da aeronave.
	# Não segura agentes naturais nem altera dano, saúde, timers ou diretores.
	if air.dogs.is_empty():
		var point: Vector3 = await _handler_point(air)
		check(point.is_finite(), "handler encontra piso e cápsula livres fora da câmera")
		if not point.is_finite(): return false
		var handler := OFFICER.new()
		handler.controller = world.gameplay
		handler.tier = 2
		world.gameplay.add_child(handler)
		handler.global_position = point
		world.gameplay.police.append(handler)
		await frames(12)
		check(handler.is_on_floor(), "handler real apoiado antes do K9")
		air._try_deploy_dog()
	check(not air.dogs.is_empty(), "K9 admitido pelo diretor fora da câmera")
	var ready: bool = is_instance_valid(air.helicopter) and air.helicopter.mode == "rappel" and not air.helicopter.rappellers.is_empty() and not air.dogs.is_empty()
	check(ready, "aeronave, rapel físico e K9 ativos antes da travessia")
	return ready

func _cross_seam() -> bool:
	world.production.logical_region_changed.connect(_logical_change)
	world.dispatch.dispatch_event.connect(_dispatch_event)
	var initial := _snapshot(true)
	trace.append(initial)
	last_observation = initial
	var previous: Vector3 = car.global_position
	var deadline := Time.get_ticks_msec() + 12000
	var sample_clock := Time.get_ticks_msec()
	crossing = true
	while Time.get_ticks_msec() < deadline and seam_events.is_empty():
		_release_input()
		if absf(car.speed) < 3.5: Input.action_press("move_up")
		elif absf(car.speed) > 4.5: Input.action_press("handbrake")
		await physics_frame
		var step: float = car.global_position.distance_to(previous)
		worst_physics_step = maxf(worst_physics_step, step)
		travelled += step
		previous = car.global_position
		handling_frames += int(car._handling_frame)
		# Keep the last graph observation before the logical callback as well as
		# its post-refresh graph. Restrict the detailed sampling to the seam.
		last_observation = _snapshot(absf(car.global_position.x-CONNECTION.SEAM.x) <= 1.0)
		if Time.get_ticks_msec() >= sample_clock:
			trace.append(last_observation)
			sample_clock = Time.get_ticks_msec() + 200
		if world.gameplay.health <= 0 or not world.driving.occupied: break
	_release_input()
	Input.action_press("handbrake")
	await frames(2)
	var after := _snapshot(true)
	trace.append(after)
	crossing = false
	check(seam_events.size() == 1 and world.session.state.region_id == "mountain", "condução física cruzou Harbor→Mountain uma vez")
	check(handling_frames > 0 and not car.external_input and world.driving.occupied, "controle passou pelo V1Handling real")
	check(travelled > 7.0 and worst_physics_step < .6, "deslocamento contínuo sem teleporte: %.2f m, passo máximo %.3f m" % [travelled, worst_physics_step])
	if seam_events.size() != 1: return false
	check(int(before_seam.stars) >= 3 and float(before_seam.health) > 0 and str(before_seam.helicopter_mode) != "depart", "resposta estava ativa, sem retirada normal antes da costura")
	check(int(after.helicopter_id) != 0 and int(after.helicopter_id) == int(before_seam.helicopter_id), "mudança lógica preserva a mesma aeronave")
	var dogs_after: Array[int] = []
	for dog in after.dogs: dogs_after.append(int(dog.id))
	check(not before_seam.dogs.is_empty(), "costura efetivamente exercitada com K9 ativo")
	for dog in before_seam.dogs:
		check(not bool(dog.dead) and bool(dog.handler_alive) and not bool(dog.withdrawing), "K9 válido antes da costura")
		check(dogs_after.has(int(dog.id)), "mudança lógica preserva K9 %d" % int(dog.id))
	check(not before_seam.ropes.is_empty(), "costura efetivamente exercitada com policial na corda")
	for id in before_seam.ropes:
		check(is_instance_valid(instance_from_id(int(id))), "policial na corda continua físico após costura: %d" % int(id))
	print("R3_SEAM ", JSON.stringify({"before": before_seam, "events": seam_events, "after": after}))
	return true

func _travel_control() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while absf(car.speed) > .3 and Time.get_ticks_msec() < deadline: await physics_frame
	_release_input()
	check(world.driving.leave(), "controle de viagem desembarca fisicamente")
	deadline = Time.get_ticks_msec() + 6000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline: await physics_frame
	check(not world.driving.occupied and world.gameplay.health > 0, "viagem explícita começa a pé e vivo")
	if world.driving.occupied or world.gameplay.health <= 0: return
	# Após a correção, os mesmos corpos ainda existem e devem ser limpos pela
	# viagem explícita. Antes dela, o defeito pode tê-los apagado na costura;
	# nesse caso a observação declara controle sem carga aérea, sem fingir prova.
	var air: Node3D = world.gameplay.police_air
	var ids: Array[int] = []
	if is_instance_valid(air.helicopter): ids.append(air.helicopter.get_instance_id())
	for dog in air.dogs:
		if is_instance_valid(dog): ids.append(dog.get_instance_id())
	for officer in world.gameplay.police:
		if is_instance_valid(officer): ids.append(officer.get_instance_id())
	var aerial_loaded: bool = is_instance_valid(air.helicopter) and not air.dogs.is_empty()
	check(aerial_loaded, "controle de limpeza ainda tem aeronave e K9 reais")
	# A saida fisica pode recolocar o pedestre do outro lado da costura.
	# Este controle exercita limpeza por viagem, nao uma segunda conducao dirigida.
	var origin_region: String = world.session.state.region_id
	var destination := "harbor" if origin_region == "mountain" else "mountain"
	print("R3_TRAVEL_PRECONDITIONS ", JSON.stringify({"origin": origin_region, "destination": destination, "player": world.player.position, "blocked": world.session.is_transition_blocked(), "transition": world.session.transition_kind}))
	var admitted: bool = world.production.travel(destination)
	check(admitted, "viagem explícita foi admitida")
	if not admitted: return
	deadline = Time.get_ticks_msec() + 12000
	while world.production.travel_busy and Time.get_ticks_msec() < deadline: await process_frame
	await frames(3)
	check(world.session.state.region_id == destination and not world.production.travel_busy, "viagem explícita concluiu")
	check(not is_instance_valid(air.helicopter) and air.dogs.is_empty() and world.dispatch.units.is_empty(), "viagem explícita limpa resposta produtiva")
	for id in ids: check(not is_instance_valid(instance_from_id(id)), "viagem remove corpo de resposta %d" % id)
	check(not world.player.input_locked and not world.session.is_transition_blocked(), "viagem restaura controles")

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): push_error("R3 exige --no-save e APPDATA temporário"); quit(2); return
	create_timer(240.0).timeout.connect(func(): _release_input(); print("R3 TIMEOUT"); quit(2))
	# Fixa somente RNG global; RNGs privados produtivos continuam seus contratos.
	seed(20260929)
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
	check(world.production.no_save, "save pessoal isolado")
	if not world.production.no_save: _finish(); return
	if not await _prepare_car(): _finish(); return
	if not await _prepare_response(): _finish(); return
	if await _cross_seam(): await _travel_control()
	_finish()

func _finish() -> void:
	_release_input()
	var report := {"checks": checks, "failures": failures, "trace": trace, "seam_events": seam_events, "routing_events": routing_events, "handling_frames": handling_frames, "travelled": travelled, "worst_physics_step": worst_physics_step, "limits": "Resposta inicial preparada; travessia por Input sem teleporte. R3b registra grafo/eventos e não comprova atalhos. Não é benchmark FPS nem retorno dirigido Mountain→Harbor."}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			var destination := argument.trim_prefix("--evidence-dir=").path_join("pursuit-region-seam.json")
			var file := FileAccess.open(destination, FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("PURSUIT_REGION_SEAM ", JSON.stringify(report))
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)
