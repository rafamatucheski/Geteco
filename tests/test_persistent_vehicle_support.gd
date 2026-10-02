extends SceneTree
## Contrato funcional: Main + NativeRegion reais, dois caminhões em rua remota.
## Só esta fixture controla temporariamente os callbacks de streaming para
## ordenar união/poda/construção; a suspensão é produzida por _trim_chunks.
## Nenhuma flag awaiting_ground é atribuída pelo teste. Não mede FPS.
const CATALOG = preload("res://runtime/FleetCatalog.gd")
var world: Node3D
var region: Node3D
var trucks: Array[CharacterBody3D] = []
var failures: Array[String] = []
var checks := 0
var production_processing := true
var region_processing := true
var callbacks_owned := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("SUPPORT PASS " if ok else "SUPPORT FAIL ") + label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / 64.0), floori(point.z / 64.0))

func completed(key: Vector2i) -> bool:
	if not region.chunks.has(key): return false
	var chunk: Node3D = region.chunks[key]
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return false
	if region.build_jobs.any(func(job): return job.key == key): return false
	var built: int = chunk.get_meta("vegetation_ready_frame", -1)
	return built >= 0 and built < Engine.get_physics_frames()

func finish_supported(keys: Array[Vector2i]) -> void:
	# A fixture suspende callbacks automaticos; avance o scheduler produtivo,
	# sem exigir que so dois quadros concluam o acabamento fatiado.
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and not keys.all(func(key): return completed(key)):
		region._process(0.0)
		await physics_frame
	print("SUPPORT_SCHEDULER ", JSON.stringify({"keys": keys, "completed": keys.map(func(key): return completed(key))}))

func floor_under(car: CharacterBody3D) -> bool:
	for x in [-car.half_width * .8, car.half_width * .8]:
		for z in [-car.half_length * .8, car.half_length * .8]:
			var point: Vector3 = car.to_global(Vector3(x, 0, z))
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * .5, point - Vector3.UP * .6, 1))
			if hit.is_empty(): return false
	return true

func requests_for(car: CharacterBody3D) -> Array:
	var result: Array = []
	var ahead: Vector3 = car.global_position - car.global_basis.z * (car.half_length + 3.0)
	for request in world.production._persistent_vehicle_support().harbor:
		var point: Vector3 = request.position
		if point.distance_to(car.global_position) < .01 or point.distance_to(ahead) < .01: result.append(request)
	return result

func covers(requests: Array, point: Vector3) -> bool:
	var key := cell(point)
	for request in requests:
		var p: Vector3 = request.position
		var radius: float = request.radius
		if key.x >= floori((p.x-radius)/64.0) and key.x <= floori((p.x+radius)/64.0) and key.y >= floori((p.z-radius)/64.0) and key.y <= floori((p.z+radius)/64.0): return true
	return false

func residency_snapshot(label: String) -> Dictionary:
	var mounted: Dictionary = {}
	for id in world.production.regions:
		var entry: Node3D = world.production.regions[id]
		var jobs: Array = []
		for job in entry.build_jobs: jobs.append({"key":str(job.key), "stage":job.stage, "chunk_valid":is_instance_valid(job.chunk) and not job.chunk.is_queued_for_deletion()})
		mounted[id] = {"id":entry.get_instance_id(), "focus":str(entry.current_cell), "radius":entry.retention_radius, "chunks":entry.chunks.keys(), "support":entry.vehicle_support_cells.keys(), "pending":entry.pending.duplicate(), "jobs":jobs}
	var vehicles: Array = []
	for vehicle in world.production.vehicles:
		if not is_instance_valid(vehicle): continue
		vehicles.append({"id":vehicle.get_instance_id(), "vehicle_id":vehicle.vehicle_id, "position":str(vehicle.global_position), "region":vehicle.get_meta("region_id", ""), "visible":vehicle.visible, "physics":vehicle.is_physics_processing(), "awaiting":vehicle.has_meta("awaiting_ground"), "queued":vehicle.is_queued_for_deletion(), "driver_car":vehicle == world.driving.car, "port_work":vehicle.get_meta("port_work_vehicle",false), "residence":vehicle.get_meta("residence_vehicle",false), "reward":vehicle.get_meta("garage_reward",false)})
	# Coleta produtiva: registra o conjunto proposto, não inventa ownership.
	var requests: Dictionary = world.production._persistent_vehicle_support()
	var snapshot := {"label":label, "region":world.session.state.region_id, "focus":str(world.production._physical_focus()), "mounted":mounted, "cached":world.production._region_cache.keys(), "vehicles":vehicles, "requests":requests}
	print("SUPPORT_RESIDENCY ", JSON.stringify(snapshot))
	return snapshot

func region_release_valid(requests: Array) -> bool:
	if not world.production.regions.has("harbor"):
		return region.vehicle_support_cells.is_empty() and region.pending.is_empty() and region.build_jobs.is_empty() and region.chunks.is_empty()
	# Viagem pode conservar uma região montada pela costura ou outro veículo.
	# Nela, jobs/pending legítimos não são órfãos só por permanecerem presentes.
	var expected: Dictionary = {}
	for request in requests:
		var p: Vector3 = request.position
		var radius: float = request.radius
		for x in range(floori((p.x-radius)/64.0),floori((p.x+radius)/64.0)+1):
			for z in range(floori((p.z-radius)/64.0),floori((p.z+radius)/64.0)+1): expected[Vector2i(x,z)] = true
	if region.vehicle_support_cells != expected: return false
	for job in region.build_jobs:
		if not region.chunks.has(job.key) or not is_instance_valid(job.chunk) or job.chunk.is_queued_for_deletion(): return false
	for key in region.pending:
		if not expected.has(key) and (absi(key.x-region.current_cell.x)>region.retention_radius or absi(key.y-region.current_cell.y)>region.retention_radius): return false
	return true

func candidate_poses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var graph: RefCounted = world.production.traffic_routes
	var length: float = float(CATALOG.spec("cargo_flatbed_truck").bounds_size[2]) * .5
	for from in graph.edges:
		for edge in graph.edges[from]:
			var a: Vector3 = graph.vertices[edge.from]
			var b: Vector3 = graph.vertices[edge.to]
			var direction := (b-a).normalized()
			var lane: Vector3 = graph._lane_offset(direction, edge)
			for along in range(24, int(a.distance_to(b))-10, 2):
				var point: Vector3 = a + direction * float(along) + lane + Vector3.UP * .12
				var second: Vector3 = point - direction * 12.0
				var ahead: Vector3 = point + direction * (length+3.0)
				# Evita o porto ativo e a região Mountain; o par deve compartilhar
				# célula corporal, mas o primeiro já pede outra célula adiante.
				if point.z > 150 or point.x > 400 or point.distance_to(world.player.global_position) < 220: continue
				var offset: Vector2i = cell(point) - region.current_cell
				if absi(offset.x) <= region.retention_radius and absi(offset.y) <= region.retention_radius: continue
				if cell(point) != cell(second) or cell(point) == cell(ahead): continue
				var radius: float = Vector2(float(CATALOG.spec("cargo_flatbed_truck").bounds_size[0])*.5, length).length()+.5
				if covers([{"position":point,"radius":radius}], ahead): continue
				result.append({"first": point, "second": second, "ahead": ahead, "yaw": atan2(-direction.x,-direction.z)})
				if result.size() >= 12: return result
	return result

func prepare_pair() -> bool:
	for pose in candidate_poses():
		region.prepare_collision_at(pose.first)
		region.prepare_collision_at(pose.second)
		region.prepare_collision_at(pose.ahead)
		await frames(3)
		var attempt: Array[CharacterBody3D] = []
		var clear := true
		for point in [pose.first, pose.second]:
			var truck: CharacterBody3D = world.production.spawn_vehicle("cargo_flatbed_truck", point, pose.yaw)
			if not is_instance_valid(truck): clear = false; break
			truck.set_meta("port_work_vehicle", true)
			truck.vehicle_id = "support_fixture_%d" % attempt.size()
			truck.traffic = false
			truck.brake_input = true
			attempt.append(truck)
			if not world.production.vehicle_position_clear(truck, point, pose.yaw) or not floor_under(truck): clear = false; break
		if clear and attempt.size() == 2:
			trucks = attempt
			print("SUPPORT_FIXTURE ", JSON.stringify({"first": str(pose.first), "second": str(pose.second), "ahead": str(pose.ahead), "focus": str(region.current_cell)}))
			return true
		for truck in attempt: truck.queue_free()
		await frames(2)
	return false

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): push_error("Suporte exige --no-save e APPDATA temporário"); quit(2); return
	create_timer(180.0).timeout.connect(func(): _restore_callbacks(); print("SUPPORT TIMEOUT"); quit(2))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main pronto")
	if world.session == null or not world.session.ready_for_play: _finish(); return
	check(world.production.no_save, "save pessoal desativado")
	if not world.production.no_save: _finish(); return
	region = world.production.region
	production_processing = world.production.is_processing()
	region_processing = region.is_processing()
	world.production.set_process(false)
	region.set_process(false)
	callbacks_owned = true
	var prepared: bool = await prepare_pair()
	check(prepared, "dois caminhões reais admitidos sem colisão em célula remota compartilhada")
	if not prepared: _finish(); return
	var first: CharacterBody3D = trucks[0]
	var second: CharacterBody3D = trucks[1]
	var key := cell(second.global_position)
	var ahead: Vector3 = first.global_position - first.global_basis.z * (first.half_length+3.0)
	var first_requests := requests_for(first)
	var second_requests := requests_for(second)
	check(covers(first_requests, first.global_position), "casco ativo fornece suporte")
	check(covers(first_requests, ahead), "look-ahead exato do caminhão também é retido")
	region.set_vehicle_support(first_requests + second_requests)
	await finish_supported([key, cell(ahead)])
	check(completed(key) and floor_under(second), "chunk concluído, passo físico e quatro apoios reais")
	check(completed(cell(ahead)), "pedido adiante tem job concluído e passo físico")
	var original_id: int = region.chunks[key].get_instance_id() if region.chunks.has(key) else 0
	region.set_vehicle_support(second_requests)
	await frames(2)
	check(region.chunks.has(key) and region.chunks[key].get_instance_id() == original_id and completed(key) and floor_under(second), "soltar primeiro pedido conserva célula e piso do segundo")
	# Retirada deliberada dos dois pedidos simula cancelamento; o runtime deve
	# suspender os corpos antes de destruir o piso. Não atribuímos as flags.
	region.set_vehicle_support([])
	check(first.has_meta("awaiting_ground") and second.has_meta("awaiting_ground") and not first.is_physics_processing() and not second.is_physics_processing(), "poda produtiva suspende ambos antes de remover piso")
	await frames(2)
	var held_first := requests_for(first)
	var held_second := requests_for(second)
	check(covers(held_first, first.global_position) and covers(held_second, second.global_position), "awaiting_ground mantém pedido mesmo com física suspensa")
	var restore_requests: Array = held_first + held_second
	# Um erro de coleta não deve impedir os checks independentes de prontidão:
	# mantém o FAIL e reutiliza pedidos válidos anteriores nesta fixture.
	if restore_requests.is_empty(): restore_requests = first_requests + second_requests
	region.set_vehicle_support(restore_requests)
	check(not completed(key), "registro recém-criado não prova prontidão antes do próximo passo físico")
	await finish_supported([key])
	check(completed(key) and floor_under(first) and floor_under(second), "piso físico só certificado com conclusão e sincronização")
	# Executa o consumidor produtivo que retoma awaiting_ground. A callback
	# continua desativada apenas para ordenar este passo, sem mock do método.
	world.production._process(.3)
	check(first.is_physics_processing() and second.is_physics_processing() and not first.has_meta("awaiting_ground") and not second.has_meta("awaiting_ground"), "retomada produtiva libera espera após piso válido")
	first.queue_free()
	await frames(2)
	# Usa o pedido já coletado para que falha de retomada não impeça verificar
	# independentemente a união/liberação no NativeRegion.
	region.set_vehicle_support(second_requests)
	await frames(2)
	check(completed(key) and floor_under(second), "remoção de um veículo não libera piso compartilhado")
	# Job parcial fora da retenção: sua mera presença em chunks não é pronto.
	var cancel_key: Vector2i = region.current_cell + Vector2i(8, 8)
	while region.chunks.has(cancel_key): cancel_key += Vector2i(1, 0)
	region._build_chunk(cancel_key, false)
	check(region.chunks.has(cancel_key) and not completed(cancel_key), "job enfileirado permanece não pronto")
	region.set_vehicle_support([])
	region.set_retention_radius(region.retention_radius)
	await frames(2)
	check(not region.chunks.has(cancel_key) and not region.build_jobs.any(func(job): return job.key == cancel_key), "cancelamento remove chunk parcial e job sem órfãos")
	second.queue_free()
	await frames(2)
	region.set_vehicle_support([])
	region.set_retention_radius(region.retention_radius)
	check(not region.chunks.has(key) and not region.vehicle_support_cells.has(key), "remoção final libera célula fora do foco")
	_restore_callbacks()
	residency_snapshot("before_travel")
	var admitted: bool = world.production.travel("mountain")
	check(admitted, "viagem produtiva admitida após liberar pedidos")
	deadline = Time.get_ticks_msec()+15000
	while world.production.travel_busy and Time.get_ticks_msec() < deadline: await process_frame
	await frames(3)
	check(world.session.state.region_id == "mountain" and not world.production.travel_busy, "viagem conclui sem espera pendurada")
	var after := residency_snapshot("after_travel")
	check(region_release_valid(after.requests.harbor), "viagem libera região descarregada ou conserva apenas suporte/filas com ownership válido")
	_finish()

func _restore_callbacks() -> void:
	if not callbacks_owned: return
	if is_instance_valid(world) and is_instance_valid(world.production): world.production.set_process(production_processing)
	if is_instance_valid(region): region.set_process(region_processing)
	callbacks_owned = false

func _finish() -> void:
	_restore_callbacks()
	print("PERSISTENT_VEHICLE_SUPPORT checks=", checks, " failures=", JSON.stringify(failures))
	if is_instance_valid(world): world.queue_free()
	quit(0 if failures.is_empty() else 1)
