extends RefCounted
## Residência das regiões do ProductionWorld (montar/desmontar região, cache fora da árvore, apoio dos
## veículos persistentes e do despacho, conexão da ponte, troca de região lógica), separada em 01/11
## (Onda 3) só para o ProductionWorld.gd caber na leitura. Não tem estado próprio: `regions`, `region`,
## `connection`, `_parked_connection`, `_region_cache`, `_pending_unmounts`, `_route_refresh_pending`,
## `_seam_retention`, as constantes de distância e o sinal `logical_region_changed` (emitido daqui por
## `g.`) continuam no ProductionWorld, que mantém cada função antiga como delegação de uma linha:
## `_update_physical_residency` é chamada por ~66 testes e `_commit_logical_region` por 8 arquivos.
## `g` fica como Node, e não como o script do ProductionWorld, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: quem sobrescreve uma delas (ou
## _trace_cost, _refresh_route_consumers...) continua sendo despachado igual. As `static var` do dono
## (_seam_hold_enabled, _connection_park_enabled) são lidas por `g.get_script()`.
## Roda na thread principal (streaming, viagem e carga), como antes.

const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const HEAVY_FRAME := preload("res://runtime/HeavyFrameClaim.gd")
const REGION := preload("res://world/editing/EditableRegion.gd")
const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _physical_focus() -> Vector3:
	if g.session != null and is_instance_valid(g.session.regional_coach) and g.session.regional_coach.riding and is_instance_valid(g.session.regional_coach.train): return g.session.regional_coach.train.global_position
	if g.session != null and is_instance_valid(g.session.jessica) and g.session.jessica.riding and is_instance_valid(g.session.jessica.car): return g.session.jessica.car.global_position
	if g.session != null and is_instance_valid(g.session.arrival) and g.session.arrival.riding and is_instance_valid(g.session.arrival.car): return g.session.arrival.car.global_position
	if is_instance_valid(g.world.driving) and g.world.driving.occupied and is_instance_valid(g.world.driving.car):
		return g.world.driving.car.global_position
	if g.session != null and is_instance_valid(g.session.passenger_transport) and g.session.passenger_transport.riding and is_instance_valid(g.session.passenger_transport.car):
		return g.session.passenger_transport.car.global_position
	return g.world.player.global_position if is_instance_valid(g.world.player) else Vector3.ZERO

func _mount_region(id: String, requested_focus: Vector3 = Vector3.INF) -> Node3D:
	# Voltou a ser preciso antes da desmontagem adiada: fica montada.
	g._pending_unmounts.erase(id)
	if g.regions.has(id) and is_instance_valid(g.regions[id]): return g.regions[id]
	var traced := Time.get_ticks_usec() if is_instance_valid(g.world) and (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	var mount_token := SESSION_OPS.begin(g, "streaming", "mount_region", {"region":id, "cached":g._region_cache.has(id)})
	var mounted_region: Node3D = g._mount_region_now(id,requested_focus)
	SESSION_OPS.finish(mount_token, "mounted" if mounted_region != null else "missing")
	g._trace_cost("mount_region:"+id,traced)
	return mounted_region

func _build_region(id: String, first_focus: Vector3 = Vector3.INF) -> Node3D:
	if id == "desert": return preload("res://world/editing/EditableDesertRegion.gd").build_region(id,first_focus)
	return REGION.build_region(id,first_focus)

func _mount_region_now(id: String, requested_focus: Vector3) -> Node3D:
	if is_instance_valid(g.background_preparation): g.background_preparation.take(id)
	var first_focus: Vector3 = requested_focus if requested_focus.is_finite() else (g._physical_focus() if is_instance_valid(g.world.player) else Vector3.INF)
	var mounted: Node3D = null
	if g._region_cache.has(id) and is_instance_valid(g._region_cache[id]):
		mounted = g._region_cache[id]
		g._region_cache.erase(id)
		mounted.initial_focus = first_focus
	else:
		mounted = g._build_region(id,first_focus)
	if mounted == null: return null
	if id=="desert": mounted.set_north_pass_completed(preload("res://world/desert/north_pass/DesertNorthPassLayout.gd").completed(g.state.world_state))
	g.regions[id] = mounted
	# Spans (22/10): remontar o porto guardado custava 13 ms num quadro na serra, perto da ponte.
	var stage := STALL_WORK.begin()
	g.world.add_child(mounted)
	STALL_WORK.finish_slow("mount.add_child", stage, 2000)
	if stage != 0 and OS.get_environment("GETECO_MOUNT_CENSUS") == "1": g._mount_census(mounted)
	if g.chairlift_schedule_initialized and mounted.has_method("set_chairlift_operating"): mounted.set_chairlift_operating(g.chairlift_operating)
	stage = STALL_WORK.begin()
	if first_focus.is_finite(): mounted.set_focus(first_focus)
	STALL_WORK.finish_slow("mount.set_focus", stage, 2000)
	g._request_route_refresh()
	return mounted

func _request_route_refresh() -> void:
	if OS.get_environment("GETECO_ROUTE_REFRESH_DEFER") != "0" and g.ready_for_play and DisplayServer.get_name() != "headless":
		g._route_refresh_pending = true
	else:
		g._refresh_route_consumers()

## Diagnóstico (GETECO_MOUNT_CENSUS=1 com o log ligado): quantos nós cada filho direto da região remontada traz.
func _mount_census(mounted: Node) -> void:
	var rows: Array = []
	for child in mounted.get_children():
		rows.append([str(child.name), child.get_class(), child.get_child_count(), child.find_children("*", "", true, false).size()])
	rows.sort_custom(func(a, b): return a[3] > b[3])
	print("MOUNT_CENSUS ", mounted.name, " ", JSON.stringify(rows.slice(0, 20)))

func _queue_unmount(id: String) -> void:
	if OS.get_environment("GETECO_UNMOUNT_DEFER") != "0" and g.ready_for_play and DisplayServer.get_name() != "headless":
		if g.regions.has(id): g._pending_unmounts[id] = true
	else:
		g._unmount_region(id)

func _drain_pending_unmount() -> void:
	if g._pending_unmounts.is_empty() or not HEAVY_FRAME.claim("world.unmount"): return
	var id: String = g._pending_unmounts.keys()[0]
	g._pending_unmounts.erase(id)
	g._unmount_region(id)

func _unmount_region(id: String) -> void:
	g._pending_unmounts.erase(id)
	if id == g.state.region_id or not g.regions.has(id): return
	var stall_began := STALL_WORK.begin()
	var mounted: Node3D = g.regions[id]
	g.regions.erase(id)
	if is_instance_valid(mounted):
		mounted.release_chunks()
		if mounted.has_method("hand_off_retiring"): mounted.hand_off_retiring()
		var detach_began := STALL_WORK.begin()
		g.world.remove_child(mounted)
		STALL_WORK.finish("unmount.remove_child", detach_began, {"region": id})
		g._region_cache[id] = mounted
	g._request_route_refresh()
	STALL_WORK.finish("world.unmount_region", stall_began, {"region": id})

func _persistent_vehicle_support() -> Dictionary:
	var support := {"harbor":[],"mountain":[],"desert":[]}
	if is_instance_valid(g.urban_transit) and is_instance_valid(g.urban_transit.urban_service):
		for bus in g.urban_transit.urban_service.fleet:
			if not is_instance_valid(bus) or not bus.active: continue
			var bus_region: String = bus.get_meta("region_id","harbor")
			if not support.has(bus_region): continue
			for index in bus.sections.size():
				support[bus_region].append({"position":bus.sections[index].global_position,"radius":bus.LENGTHS[index]*.5+1.0})
			# Retém a célula de antecipação admitida e também o casco atual.
			# Senão o streaming pode despejá-la antes do próximo passo de física.
			support[bus_region].append({"position":bus.global_position-bus.global_basis.z*8,"radius":2.0})
	for car in g.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.visible: continue
		# Um corpo suspenso pelo streaming ainda é dono do pedido de chão. Excluí-lo
		# aqui despejaria o chunk antes de a checagem de chão poder retomá-lo.
		if not car.is_physics_processing() and not car.has_meta("awaiting_ground") and not car.has_meta("desert_drag_physics") and not car.get_meta("armored_transport",false): continue
		if g._is_ambient_traffic(car) and car != g.world.driving.car and not car.get_meta("gang_hostile",false): continue
		var persistent: bool = g._is_persistent_vehicle(car)
		if not persistent:
			if car.traffic: continue
			if car.global_position.distance_to(g.world.player.global_position) > 145:
				# Aposenta antes de soltar o chão, não no tick de população até
				# .25 s depois. Donos de save nunca podem ver um carro estacionado caindo.
				car.set_meta("distance_despawn", true)
				car.set_physics_process(false)
				car.queue_free()
				continue
		# Nearby parked cars need support too, including across a cell boundary.
		var id: String = WORLD_CONNECTION.logical_region(car.global_position)
		var radius: float = Vector2(car.half_width,car.half_length).length()+0.5
		support[id].append({"position":car.global_position,"radius":radius})
		if car.get_meta("port_work_vehicle",false) or car.get_meta("race_owned",false) or car.get_meta("armored_transport",false):
			# O PortLogistics admite este mesmo ponto antes de mover. Mantém o chunk
			# até o pedido seguir adiante; só o raio do casco não o cobre.
			support[id].append({"position":car.global_position-car.global_basis.z*(car.half_length+3),"radius":0.0})
	return support

func _is_persistent_vehicle(car: Node) -> bool:
	return car == g.world.driving.car or car.vehicle_id in ["neco_tow_truck","story_tow_vehicle"] or car.get_meta("residence_vehicle",false) or car.get_meta("garage_reward",false) or car.get_meta("port_work_vehicle",false) or car.get_meta("secret_discovery_vehicle",false) or car.get_meta("race_owned",false) or car.has_meta("desert_drag_physics") or car.get_meta("armored_transport",false)

func _active_dispatch_support() -> Dictionary:
	var support := {"harbor":[],"mountain":[],"desert":[]}
	var dispatch: Variant = g.world.get("dispatch") if is_instance_valid(g.world) else null
	if not is_instance_valid(dispatch): return support
	for unit in dispatch.units:
		if unit.finished: continue
		var car: CharacterBody3D = unit.vehicle
		if not is_instance_valid(car) or car.is_queued_for_deletion(): continue
		var resume_requested: bool = unit.suspended and dispatch.distance_to_player(car.global_position) <= preload("res://gameplay/dispatch/DispatchRules.gd").RESUME_DISTANCE
		if unit.suspended and not resume_requested: continue
		if not resume_requested and not car.is_visible_in_tree(): continue
		if not resume_requested and not car.is_physics_processing() and not car.get_meta("awaiting_ground",false): continue
		var radius: float = Vector2(car.half_width,car.half_length).length()+0.5
		var ahead := car.global_position-car.global_basis.z*12.0
		for point: Vector3 in [car.global_position,ahead]:
			var source_owner := WORLD_CONNECTION.logical_region(point)
			# Este pedido só retém células num dono já residente. Não pode
			# montar regiões distantes nem mudar a política de residência do jogador.
			if not g.regions.has(source_owner) or not is_instance_valid(g.regions[source_owner]): continue
			support[source_owner].append({"position":point,"radius":radius if point == car.global_position else 0.0})
	# Recalculado a partir das unidades vivas: suspensão, conclusão e remoção o soltam.
	return support

func _update_physical_residency(point: Vector3) -> void:
	var physical_region := WORLD_CONNECTION.logical_region(point)
	var support: Dictionary = g._persistent_vehicle_support()
	g._mount_region(physical_region,point)
	var seam_distance := Vector2(point.x-WORLD_CONNECTION.SEAM.x,point.z-WORLD_CONNECTION.SEAM.z).length()
	var north_distance := Vector2(point.x-g.NORTH_CONNECTION_ANCHOR.x,point.z-g.NORTH_CONNECTION_ANCHOR.z).length()
	var north_preload: bool = north_distance<g.NORTH_CONNECTION_PRELOAD
	var north_keep := north_distance<230.0
	if north_preload:
		g._mount_region("harbor",point)
		g._mount_region("desert",point)
	var seam_anchor := point
	var seam_preload: bool = seam_distance <= g.CONNECTION_PRELOAD_DISTANCE
	var seam_keep: bool = seam_distance <= g.CONNECTION_RELEASE_DISTANCE
	# Folga da emenda: perto da ponte porto e serra guardam o raio maior. Antes o raio trocava 2<->1
	# entre as duas ao cruzar a divisa no meio da ponte: uma descartava uma faixa de trechos e a outra
	# carregava outra no mesmo instante, e andar perto da divisa repetia isso (relato do jogador, 16/10).
	# Liga a CONNECTION_PRELOAD_DISTANCE e só desliga depois de CONNECTION_RELEASE_DISTANCE.
	if g.get_script()._seam_hold_enabled:
		if seam_preload: g._seam_retention = true
		elif not seam_keep: g._seam_retention = false
	for id in ["harbor","mountain","desert"]:
		for vehicle in support[id]:
			var position: Vector3 = vehicle.position
			var distance := Vector2(position.x-WORLD_CONNECTION.SEAM.x,position.z-WORLD_CONNECTION.SEAM.z).length()
			if distance <= g.CONNECTION_PRELOAD_DISTANCE and not seam_preload:
				seam_anchor = position
				seam_preload = true
			if distance <= g.CONNECTION_RELEASE_DISTANCE: seam_keep = true
		if not support[id].is_empty(): g._mount_region(id,support[id][0].position)
	if seam_preload:
		g._mount_region("harbor",seam_anchor)
		g._mount_region("mountain",seam_anchor)
	if seam_preload or north_preload: g._mount_connection()
	elif not seam_keep and not north_keep:
		for id in ["harbor","mountain","desert"]:
			if id != physical_region and support[id].is_empty(): g._queue_unmount(id)
		if is_instance_valid(g.connection):
			if g.get_script()._connection_park_enabled and not is_instance_valid(g._parked_connection):
				# Estacionada (22/10): a mesma conexão volta na próxima aproximação da ponte, sem remontar.
				g.world.remove_child(g.connection)
				g._parked_connection = g.connection
			else:
				# Conexão da ponte (dezenas de malhas e colisões) sai pela fila de vídeo, aos poucos (16/10).
				GPU_RELEASE.retire(g.connection)
			g.connection = null
	var dispatch_support: Dictionary = g._active_dispatch_support()
	for id in g.regions:
		var mounted: Node3D = g.regions[id]
		if not is_instance_valid(mounted): continue
		mounted.set_vehicle_support(support[id]+dispatch_support[id])
		var seam_side: bool = g._seam_retention and (id == "harbor" or id == "mountain")
		mounted.set_retention_radius(2 if id == physical_region or seam_side else 1)
		var region_focus := point
		if id != physical_region and seam_distance > g.CONNECTION_PRELOAD_DISTANCE:
			if not support[id].is_empty(): region_focus = support[id][0].position
			elif seam_preload: region_focus = seam_anchor
		mounted.set_focus(region_focus)

func _mount_connection() -> void:
	if is_instance_valid(g.connection): return
	var traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	if is_instance_valid(g._parked_connection):
		g.connection = g._parked_connection
		g._parked_connection = null
	else:
		g.connection = WORLD_CONNECTION.new()
	g.world.add_child(g.connection)
	g._trace_cost("world_connection",traced)

## Desde a ponte unificada (6079bffd, 16/10) o piso do corredor é só da conexão: as regiões recortam a
## pegada dela. O ponto de partida da serra (spawn_position) fica nesse tabuleiro. Viagem e resgate
## conferem o chão antes de _update_physical_residency chegar lá, então montam a conexão aqui; sem
## isso a viagem padrão para a serra dava "sem solo" e o resgate na serra longe da emenda ficava
## preso em "Local de resgate ocupado" (sonda de 18/10). É o mesmo custo de logo depois do teleporte.
func prepare_connection_at(point: Vector3) -> void:
	var seam_distance := Vector2(point.x-WORLD_CONNECTION.SEAM.x,point.z-WORLD_CONNECTION.SEAM.z).length()
	var north_distance := Vector2(point.x-g.NORTH_CONNECTION_ANCHOR.x,point.z-g.NORTH_CONNECTION_ANCHOR.z).length()
	if seam_distance <= g.CONNECTION_PRELOAD_DISTANCE or north_distance < g.NORTH_CONNECTION_PRELOAD: g._mount_connection()

func _update_logical_region(point: Vector3) -> void:
	if not g.state.place_id.is_empty(): return
	var next_region := WORLD_CONNECTION.logical_region(point)
	if next_region == g.state.region_id or not g.regions.has(next_region): return
	if g._inside_logical_hysteresis(point, next_region): return
	g._commit_logical_region(next_region)

## Entre porto e serra a troca só vale quando o ponto continua do outro lado mesmo recuado pela folga.
func _inside_logical_hysteresis(point: Vector3, next_region: String) -> bool:
	var pair: Array = [g.state.region_id, next_region]
	if not ("harbor" in pair and "mountain" in pair): return false
	var back: Vector3 = Vector3(-g.LOGICAL_REGION_HYSTERESIS, 0.0, g.LOGICAL_REGION_HYSTERESIS) if next_region == "mountain" else Vector3(g.LOGICAL_REGION_HYSTERESIS, 0.0, -g.LOGICAL_REGION_HYSTERESIS)
	return WORLD_CONNECTION.logical_region(point + back) != next_region

func _commit_logical_region(next_region: String) -> void:
	if next_region == g.state.region_id or not g.regions.has(next_region): return
	var previous: String = g.state.region_id
	g.state.set_location(next_region)
	g.region = g.regions[next_region]
	g.world.street = g.region
	# Veículos do jogador e com passageiro mantêm as mesmas instâncias,
	# velocidade, ocupantes e acessórios; só o contexto lógico de rota muda.
	if g.world.driving.occupied and is_instance_valid(g.world.driving.car): g.world.driving.car.set_meta("region_id",next_region)
	if g.session != null and is_instance_valid(g.session.passenger_transport) and g.session.passenger_transport.riding and is_instance_valid(g.session.passenger_transport.car):
		g.session.passenger_transport.car.set_meta("region_id",next_region)
	g._repath_ambient_traffic()
	g._refresh_route_consumers()
	if is_instance_valid(g.urban_transit): g.urban_transit.on_region_changed()
	if g.session != null:
		g.session.sync_dispatch_location()
		g.session.refresh_routine_context()
		if is_instance_valid(g.session.weather): g.session.weather._update()
	if is_instance_valid(g.world_audio) and g.world_audio.has_method("on_region_changed"):
		g.world_audio.on_region_changed(previous,next_region)
	g.logical_region_changed.emit(previous,next_region)

func _update_mobile_region_metadata() -> void:
	for car in g.vehicles:
		if not is_instance_valid(car) or not car.is_visible_in_tree(): continue
		car.set_meta("region_id",WORLD_CONNECTION.logical_region(car.global_position))
