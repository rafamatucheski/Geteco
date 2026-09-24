extends SceneTree
## Validacao integrada e sem save das rotinas especificas trazidas do V1.
## Uso completo: godot --headless --path geteco_v2 --script res://gameplay/routines_v1/RoutineValidation.gd -- --no-save --skip-arrival
## Recorte urbano: acrescente --urban-only para nao carregar a serra.

const CATALOG := preload("res://gameplay/routines_v1/RoutineCatalog.gd")

var world
var session
var director
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if value: return
	failures.append(label)
	push_error(label)

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--no-save" not in arguments or "--skip-arrival" not in arguments:
		push_error("ROUTINE_VALIDATION recusada: use --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for _frame in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.session.weather != null: break
	_check(world.session != null and world.session.ready_for_play, "Mundo produtivo V2 inicia")
	if not failures.is_empty():
		_finish()
		return
	session = world.session
	director = world.get_node_or_null("V1RoutineDirector")
	_check(world.production.no_save, "Fixture nao le nem grava save pessoal")
	_check(director != null, "RoutineDirector conectado uma unica vez")
	_check(world.find_children("V1RoutineDirector", "Node", true, false).size() == 1, "Sem segunda instancia do RoutineDirector")
	_catalog_contract()
	if "--mountain-only" not in arguments:
		await _dock_scenario()
		await _south_port_scenario()
	if "--urban-only" not in arguments:
		await _mountain_scenario()
		if "--audit-mountain-spawns" in arguments: await _audit_mountain_spawns()
		await _lodge_scenario()
	_finish()

func _catalog_contract() -> void:
	var definitions: Array[Dictionary] = CATALOG.definitions()
	var ship := definitions.filter(func(item): return str(item.id).begins_with("harbor_ship_dock_operator_"))
	var south := definitions.filter(func(item): return str(item.id).begins_with("south_port_worker_"))
	var mountain := definitions.filter(func(item): return str(item.id).begins_with("mountain_resident_"))
	var lodge := definitions.filter(func(item): return str(item.place_id) == "ski_lodge")
	_check(ship.size() == 3, "Catalogo conserva os 3 operadores do cais")
	_check(south.size() == 32, "Catalogo conserva os 32 postos do Porto Sul")
	_check(mountain.size() == 23, "Catalogo conserva os 23 moradores da serra")
	_check(lodge.size() == 3, "Catalogo conserva os 3 residentes do lodge")
	_check(definitions.all(func(item): return not str(item.id).contains("maciota") and not str(item.id).contains("mechanic")), "Maciota e mecanico fora da populacao")

func _focus(point: Vector3, frames := 36) -> void:
	world.production.region.set_focus(point)
	world.player.teleport(point + Vector3.UP * .08)
	for _frame in frames: await physics_frame
	director.refresh_context()
	for _frame in 4: await physics_frame

func _active(prefix: String) -> Array:
	var result: Array = []
	for id in director.active_ids():
		if str(id).begins_with(prefix): result.append(director.actors[id])
	return result

func _unique_active_ids(label: String) -> void:
	var ids: Array[String] = director.active_ids()
	var unique := {}
	for id in ids: unique[id] = true
	_check(ids.size() == unique.size(), label + ": IDs sem duplicacao")
	_check(ids.size() <= 12 or not session.state.place_id.is_empty(), label + ": limite externo de 12")

func _solid_overlap(actor: CharacterBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP * .90)
	query.collision_mask = 1
	query.exclude = [actor.get_rid(), world.player.get_rid()]
	return not world.get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()

func _has_ground(actor: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * .3, actor.global_position - Vector3.UP * .55, 1)
	query.exclude = [actor.get_rid(), world.player.get_rid()]
	return not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _static_point_clear(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	query.shape = capsule
	# Match FullSession.position_clear(point + Vector3.UP * .04): the shared
	# admission query adds another .90 m to the authored floor point.
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .94)
	query.collision_mask = 1
	if not world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	var ground := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .3, point - Vector3.UP * .55, 1)
	return not world.get_world_3d().direct_space_state.intersect_ray(ground).is_empty()

func _audit_routes(prefix: String, label: String) -> void:
	for definition in director.definitions:
		if not str(definition.id).begins_with(prefix): continue
		world.player.teleport(definition.position + Vector3(2, .08, 2))
		world.production.region.set_focus(definition.position)
		for _frame in 3: await physics_frame
		var route: Array = definition.get("route", [])
		var samples: Array[Vector3] = []
		for index in route.size():
			var start: Vector3 = route[index]
			var finish: Vector3 = route[(index + 1) % route.size()]
			var steps := maxi(1, ceili(start.distance_to(finish) / .5))
			for step in steps: samples.append(start.lerp(finish, float(step) / steps))
		for route_point in samples:
			var clear := _static_point_clear(route_point)
			if not clear:
				var alternatives: Array[Vector3] = []
				for offset in [Vector3(.5, 0, 0), Vector3(-.5, 0, 0), Vector3(0, 0, .5), Vector3(0, 0, -.5), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
					if _static_point_clear(route_point + offset): alternatives.append(route_point + offset)
				print("ROUTINE_BLOCKED_POINT id=", definition.id, " point=", route_point, " alternatives=", alternatives)
			_check(clear, label + ": rota livre " + str(definition.id) + " " + str(route_point))

func _observe(actors: Array, frames: int, label: String) -> Dictionary:
	var starts := {}
	var activities := {}
	for actor in actors:
		starts[actor.name] = actor.global_position
		activities[actor.name] = {}
	for frame in frames:
		await physics_frame
		for actor in actors:
			if not is_instance_valid(actor): continue
			activities[actor.name][actor.activity] = true
			if frame % 30 == 0:
				_check(not _solid_overlap(actor), label + ": " + actor.name + " fora de solidos")
				_check(_has_ground(actor), label + ": " + actor.name + " com piso")
	var moved := false
	for actor in actors:
		if is_instance_valid(actor) and actor.global_position.distance_to(starts[actor.name]) > .6: moved = true
	print("ROUTINE_SCENARIO ", label, " created=", actors.size(), " activities=", activities)
	return {"activities": activities, "moved": moved}

func _dock_scenario() -> void:
	var home := Vector3(3442.0 / 16.0, 0, 1702.0 / 16.0)
	await _focus(home + Vector3(-1.2, 0, -1.2))
	var actors := _active("harbor_ship_dock_operator_")
	_check(actors.size() == 3, "Cais cria os 3 operadores proximos")
	_unique_active_ids("Cais")
	if actors.is_empty(): return
	var observed := await _observe(actors, 540, "Cais")
	_check(observed.moved, "Cais observa deslocamento nas rotas autoradas")
	var first = actors[0]
	_check(first.get("crate_stock") != null, "Cais conserva lote/estoque especifico do V1")
	if first.get("crate_stock") != null:
		_check(first.crate_total() == 3, "Cais conserva total de 3 caixas por operador")
	var saved_position: Vector3 = first.global_position
	var first_id: String = str(first.definition.id)
	await _focus(saved_position + Vector3(55, 0, 0), 20)
	_check(director.active_ids().has(first_id), "Histerese mantem ator entre 48 m e 62 m")
	first = director.actors.get(first_id)
	saved_position = first.global_position
	var saved_route_index: int = first.route_index
	var saved_carrying: bool = first.carrying
	await _focus(saved_position + Vector3(70, 0, 0), 20)
	_check(not director.active_ids().has(first_id), "Ator distante e suspenso apos 62 m")
	await _focus(home + Vector3(-1.2, 0, -1.2), 24)
	var restored = director.actors.get(first_id)
	_check(is_instance_valid(restored), "Operador retorna apos reaproximacao")
	if is_instance_valid(restored):
		var progress_kept: bool = restored.global_position.distance_to(saved_position) < 1.0 and restored.route_index == saved_route_index and restored.carrying == saved_carrying
		_check(progress_kept, "Operador retoma progresso apos descarregamento")

func _south_port_scenario() -> void:
	await _audit_routes("south_port_worker_", "Porto Sul")
	var point := Vector3(3890.0 / 16.0, 0, 4180.0 / 16.0)
	session.weather.time_of_day = .50
	session.state.world_state.time = .50
	await _focus(point + Vector3(-1, 0, -1))
	var day := _active("south_port_worker_")
	_check(not day.is_empty(), "Porto Sul cria equipe diurna por proximidade")
	_unique_active_ids("Porto Sul dia")
	if not day.is_empty():
		var observed := await _observe(day.slice(0, mini(3, day.size())), 360, "Porto Sul dia")
		_check(observed.moved, "Porto Sul observa movimento e atividade de carga")
	session.weather.time_of_day = .85
	session.state.world_state.time = .85
	director.refresh_context()
	for _frame in 24: await physics_frame
	var night := _active("south_port_worker_")
	var night_indexes := [6, 7, 13, 19, 20, 22, 24, 27, 29, 31]
	_check(not night.is_empty(), "Porto Sul mantem equipe noturna de manutencao")
	for actor in night:
		var index := str(actor.definition.id).trim_prefix("south_port_worker_").to_int()
		_check(index in night_indexes, "Porto Sul noite remove posto diurno %02d" % index)
	_unique_active_ids("Porto Sul noite")

func _wait_region(region_id: String) -> bool:
	for _frame in 900:
		await physics_frame
		if session.state.region_id == region_id and session.ready_for_play: return true
	return false

func _mountain_scenario() -> void:
	_check(world.production.travel("mountain"), "Mudanca real para regiao da serra admitida")
	_check(await _wait_region("mountain"), "Mudanca real para serra concluida")
	_check(director.active_ids().all(func(id): return str(id).begins_with("mountain_resident_")), "Troca regional remove atores do porto")
	var village := Vector3((8030.0 + 4300.0) / 16.0, 0, (895.0 - 4960.0) / 16.0)
	await _focus(village + Vector3(-1, 0, -1), 48)
	var residents := _active("mountain_resident_")
	_check(not residents.is_empty(), "Serra cria moradores nomeados por proximidade")
	_unique_active_ids("Moradores da serra")
	if not residents.is_empty():
		var observed := await _observe(residents.slice(0, mini(4, residents.size())), 720, "Moradores da serra")
		_check(observed.moved, "Serra observa caminhada autorada e atividades")
	var iris_point := Vector3((6900.0 + 4300.0) / 16.0, 0, (-2695.0 - 4960.0) / 16.0)
	await _focus(iris_point + Vector3(0, 0, 1.1), 48)
	var iris = director.actors.get("mountain_resident_iris")
	_check(is_instance_valid(iris), "IRIS estacionaria criada no resort")
	if is_instance_valid(iris):
		world.player.teleport(iris.global_position + Vector3(0, 0, 1.05))
		for _frame in 3: await physics_frame
		var action: Dictionary = director.nearest_action()
		_check(action.get("target", "") == "mountain_resident_iris", "Conversa da serra descoberta por proximidade")
		_check(director.perform("mountain_resident_iris"), "Conversa da serra executada")
		_check(session.dialogue_open, "Conversa da serra realmente exibida")
		_check(session.lines.is_empty(), "Conversa preserva uma fala por interacao como no V1")
		session.close_menu()

func _audit_mountain_spawns() -> void:
	var mountain: Array[Dictionary] = director.definitions.filter(func(item): return str(item.id).begins_with("mountain_resident_"))
	for audit_pass in 2:
		var sequence := mountain.duplicate()
		if audit_pass == 1: sequence.reverse()
		for definition in sequence:
			await _focus(definition.position + Vector3(2, 0, 2), 48)
			var actor = director.actors.get(definition.id)
			var label := "Serra passagem %d: %s" % [audit_pass + 1, definition.id]
			_check(is_instance_valid(actor), label + " presente")
			if is_instance_valid(actor):
				_check(_has_ground(actor), label + " com piso")
				_check(not _solid_overlap(actor), label + " fora de solidos")

func _lodge_scenario() -> void:
	_check(await session.enter_place("ski_lodge", false), "Entrada real no lodge")
	for _frame in 8: await physics_frame
	var lodge := _active("ski_")
	_check(lodge.size() == 3, "Lodge cria MATIAS, HELENA e LUCAS")
	_unique_active_ids("Lodge")
	for actor in lodge:
		_check(not _solid_overlap(actor), "Lodge: " + actor.name + " fora de moveis/solidos")
		_check(_has_ground(actor), "Lodge: " + actor.name + " com piso")
	_check(session.room_npcs.is_empty(), "Lodge sem residente generico duplicado")
	var matias = director.actors.get("ski_clerk_matias")
	if is_instance_valid(matias):
		world.player.teleport(matias.global_position + Vector3(0, 0, 1.05))
		for _frame in 3: await physics_frame
		_check(director.nearest_action().get("target", "") == "ski_clerk_matias", "Conversa de MATIAS descoberta")
		_check(director.perform("ski_clerk_matias"), "Conversa de MATIAS executada")
		_check(session.lines.is_empty(), "MATIAS entrega uma fala por interacao")
		session.close_menu()
	_check(session.leave_place(), "Saida real do lodge")
	for _frame in 4: await physics_frame
	_check(_active("ski_").is_empty(), "Saida do lodge nao deixa ator orfao")
	_check(await session.enter_place("ski_lodge", false), "Reentrada real no lodge")
	for _frame in 8: await physics_frame
	_check(_active("ski_").size() == 3, "Reentrada recria exatamente os 3 residentes")
	_unique_active_ids("Lodge reentrada")
	_check(session.leave_place(), "Saida final do lodge")

func _finish() -> void:
	if is_instance_valid(world): world.free()
	await process_frame
	print("ROUTINE_VALIDATION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
