extends RefCounted
## Trânsito do ProductionWorld (rede de rotas das regiões residentes, grade da pista, nascimento e
## admissão de carros, trechos reservados), separado em 01/11 (Onda 2) só para o ProductionWorld.gd
## caber na leitura. É componente com estado próprio só no que ninguém de fora lê: a grade da pista
## (`_carriageway_grid`/`_carriageway_key`) e as constantes CARRIAGEWAY_CELL e WRECK_LINGER_MSEC moram
## aqui. O que testes, a interface e outros sistemas leem (`_route_cache`, `traffic_holds`,
## `traffic_hold_removed`, `traffic_routes`, `ambient_roads_cache`, `vehicles`...) continua no
## ProductionWorld, que mantém cada função antiga como delegação de uma linha (as estáticas também,
## porque os testes chamam ProductionWorld.carriageway_grid/_graph_snapshot); set/clear_traffic_hold, de
## uma linha só, ficam lá inteiras.
## `g` fica como Node, e não como o script do ProductionWorld, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: quem sobrescreve uma delas (ou
## _on_screen, _trace_cost...) continua sendo despachado igual. As `static var` do dono
## (population_vc_enabled) são lidas por `g.get_script()`.

const PIPELINE_PROBE := preload("res://runtime/PipelineProbe.gd")
const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const TRAFFIC_ROSTER := preload("res://runtime/TrafficFleetRoster.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _resident_roads() -> Array:
	var result: Array = []
	for id in ["harbor","mountain","desert"]:
		if not g.regions.has(id) or not is_instance_valid(g.regions[id]): continue
		for road in g.regions[id].roads:
			if road.get("traffic",true): result.append(road)
	if g.regions.has("harbor") and g.regions.has("mountain"):
		result.append_array(WORLD_CONNECTION.traffic_connectors())
	# Túnel do canal: rua virtual só no grafo, com a altura do piso (ver CanalTunnel3D).
	if g.regions.has("harbor") and is_instance_valid(g.regions.harbor):
		result.append_array(preload("res://world/urban_detail/CanalTunnel3D.gd").traffic_roads(g.regions.harbor.roads))
	return result

func _route_key() -> String:
	var ids: Array = []
	for id in ["harbor","mountain","desert"]:
		if g.regions.has(id) and is_instance_valid(g.regions[id]): ids.append(id)
	return ",".join(ids)

static func _graph_snapshot(graph) -> Array:
	return [graph.segments.duplicate(),graph.vertices.duplicate(),graph.edges.duplicate(),graph._vertex_ids.duplicate()]

static func _graph_restore(graph, snapshot: Array) -> void:
	graph.segments = snapshot[0].duplicate()
	graph.vertices = snapshot[1].duplicate()
	graph.edges = snapshot[2].duplicate()
	graph._vertex_ids = snapshot[3].duplicate()

func _configure_routes() -> void:
	_carriageway_grid = {}
	var key: String = g._route_key()
	var cached: Dictionary = g._route_cache.get(key,{})
	if not cached.is_empty():
		_graph_restore(g.traffic_routes,cached.traffic)
		_graph_restore(g.ambient_traffic_routes,cached.ambient)
		g.ambient_roads_cache = cached.ambient_roads.duplicate()
		return
	var roads: Array = g._resident_roads()
	g.traffic_routes.configure(roads)
	g.ambient_roads_cache = PORT_POLICY.ambient_roads(roads)
	g.ambient_traffic_routes.configure(g.ambient_roads_cache)
	g._route_cache[key] = {"traffic":_graph_snapshot(g.traffic_routes),"ambient":_graph_snapshot(g.ambient_traffic_routes),"ambient_roads":g.ambient_roads_cache.duplicate()}

func _refresh_route_consumers() -> void:
	if g.traffic_routes == null: return
	var traced := Time.get_ticks_usec() if is_instance_valid(g.world) and (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	# Spans por etapa (22/10): a desmontagem do porto custava 46 ms no deserto e só 6 eram remove_child.
	var stage := STALL_WORK.begin()
	g._configure_routes()
	STALL_WORK.finish_slow("routes.configure", stage, 2000)
	stage = STALL_WORK.begin()
	g.population_layout.configure(g.ambient_roads_cache)
	STALL_WORK.finish_slow("routes.population_layout", stage, 2000)
	var layouts: Array = []
	if g.regions.has("harbor") and g.regions.harbor.harbor_road_geometry != null:
		layouts = g.regions.harbor.harbor_road_geometry.crossing_layout
	stage = STALL_WORK.begin()
	preload("res://gameplay/traffic_junctions/TrafficJunctions.gd").configure(g.ambient_traffic_routes,layouts)
	STALL_WORK.finish_slow("routes.junctions", stage, 2000)
	g._trace_cost("route_graphs",traced)
	stage = STALL_WORK.begin()
	if is_instance_valid(g.world) and is_instance_valid(g.world.dispatch): g.world.dispatch.refresh_roads()
	STALL_WORK.finish_slow("routes.dispatch", stage, 2000)
	stage = STALL_WORK.begin()
	if is_instance_valid(g.world) and is_instance_valid(g.world.traffic_yield): g.world.traffic_yield.refresh_roads(g.traffic_routes)
	STALL_WORK.finish_slow("routes.traffic_yield", stage, 2000)

func vehicle_position_clear(car: CharacterBody3D, point: Vector3, yaw: float) -> bool:
	var space: PhysicsDirectSpaceState3D = g.world.get_world_3d().direct_space_state
	if car.has_method("placement_poses"):
		var poses: Array[Transform3D] = car.placement_poses(point,yaw)
		for index in poses.size():
			if g.session!=null and g.session.cold!=null and not g.session.cold.prepare_collision_at(poses[index].origin): return false
			for x in [-1.0,1.0]:
				for z in [-float(car.LENGTHS[index])*.4,float(car.LENGTHS[index])*.4]:
					var support: Vector3 = poses[index]*Vector3(x,0,z)
					if space.intersect_ray(PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1)).is_empty(): return false
		return car.admits(poses,false)
	var basis := Basis(Vector3.UP,yaw)
	# Carros salvos distantes esperam o terreno antes de pedir objetos em streaming.
	for x in [-car.half_width*.8,car.half_width*.8]:
		for z in [-car.half_length*.8,car.half_length*.8]:
			var support: Vector3 = point+basis*Vector3(x,0,z)
			# Começa a 0,6 m: numa rampa (túnel do canal) a quina da frente fica até
			# ~0,3 m abaixo do piso e o raio de 0,3 m nascia dentro dele.
			var ray := PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1)
			if space.intersect_ray(ray).is_empty(): return false
	if g.session != null and g.session.cold != null and not g.session.cold.prepare_collision_at(point): return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.shape.shape
	query.transform = Transform3D(basis,point+basis*car.shape.position)
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	# Caixa horizontal numa rampa (túnel do canal) entra ~28 cm no piso: sem esta
	# exceção o carro suspenso ali nunca era liberado.
	for hit in space.intersect_shape(query,4):
		if is_instance_valid(hit.collider) and hit.collider.has_meta("vehicle_ramp_structure"): continue
		return false
	return true

func spawn_vehicle(id: String, point: Vector3, yaw: float = 0.0, crush_ratio: float = 1.0) -> CharacterBody3D:
	if preload("res://runtime/FleetCatalog.gd").spec(id).is_empty(): return null
	var car = VEHICLE.new()
	if id=="biarticulated_510":
		car.free()
		car=preload("res://runtime/transit/BiarticulatedBus.gd").new()
		car.stolen=true
	car.archetype = id
	car.vehicle_id = "vehicle_"+str(Time.get_ticks_usec())
	car.position = point
	car.set_meta("region_id",g.state.region_id)
	car.rotation.y = yaw
	var traced := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	g.world.add_child(car)
	PIPELINE_PROBE.note("spawn_vehicle", car)
	if id=="biarticulated_510":
		car.place(point,yaw)
		if is_instance_valid(g.urban_transit) and is_instance_valid(g.urban_transit.urban_service) and not g.urban_transit.urban_service.fleet.has(car): g.urban_transit.urban_service.fleet.append(car)
	g._trace_cost("spawn_vehicle_add_child:"+id,traced)
	if is_finite(crush_ratio) and crush_ratio >= .18 and crush_ratio <= .55:
		preload("res://gameplay/street_physics/HeavyVehicleCrush.gd").apply_saved(car,crush_ratio)
	traced = Time.get_ticks_usec() if traced != 0 else 0
	var clear: bool = g.vehicle_position_clear(car,point,yaw)
	g._trace_cost("spawn_vehicle_position_clear",traced)
	if not clear:
		if point.distance_to(g.world.player.position) < 75:
			car.queue_free()
			return null
		car.set_meta("awaiting_ground",true)
		car.set_physics_process(false)
	car.destroyed.connect(func():
		if is_instance_valid(g.world.gameplay):
			g.world.gameplay.explode(car.global_position+Vector3.UP*.4,5.0,35.0,car,false)
			if is_instance_valid(g.world.gameplay.emergency):
				g.world.gameplay.emergency.ignite(car.global_position,car))
	g.vehicles.append(car)
	return car

func _ambient_traffic_count() -> int:
	var count := 0
	for car in g.vehicles:
		if is_instance_valid(car) and g._is_ambient_traffic(car) and car.traffic and car.health > 0.0: count += 1
	return count

func _is_ambient_traffic(car: Variant) -> bool:
	if not is_instance_valid(car) or not car is Node or car.get_meta("ambient_traffic",false) != true: return false
	# O carro tomado pelo jogador e os persistentes não entram no orçamento civil.
	if g.get_script().population_vc_enabled and (car.is_queued_for_deletion() or g._is_persistent_vehicle(car)): return false
	return true

func _repath_ambient_traffic() -> void:
	for car in g.vehicles:
		if not g._is_ambient_traffic(car) or not car.traffic or car.health <= 0.0: continue
		if car.has_meta("ambient_next_route"): car.remove_meta("ambient_next_route")
		var route: Curve3D = g.ambient_traffic_routes.route_near(car.global_position,int(car.route.get_meta("lane_index",0)) if car.route!=null else 0,-car.global_basis.z)
		if route == null or route.get_baked_length() < 12.0 or not PORT_POLICY.route_is_ambient_safe(route):
			car.queue_free()
			continue
		car.route = route
		car.route_distance = route.get_closest_offset(car.global_position)

## Grade de trechos de pista para _on_carriageway. A admissão de um pedestre testa ~20-40
## pontos da calçada e cada um varria todos os trechos de todas as ruas residentes (e
## remontava _resident_roads, com conectores e túnel): é o grosso de population_spawn
## (p99 4,2 ms no porto, release 13-15/10). Mesmo teste exato, só nos trechos da célula.
## Refeita quando o conjunto residente muda (_configure_routes), como os grafos de rota.
const CARRIAGEWAY_CELL := 16.0
var _carriageway_grid: Dictionary = {}
var _carriageway_key := ""

func _carriageway_cells() -> Dictionary:
	var key: String = g._route_key()
	if key == _carriageway_key and not _carriageway_grid.is_empty(): return _carriageway_grid
	_carriageway_key = key
	_carriageway_grid = carriageway_grid(g._resident_roads())
	return _carriageway_grid

func _on_carriageway(point: Vector3) -> bool:
	var bridge = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	if bridge.owns_east_point(Vector2(point.x,point.z)) and Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),bridge.east_asphalt_footprint()):
		return true
	return grid_on_carriageway(g._carriageway_cells(), point)

static func carriageway_grid(roads: Array) -> Dictionary:
	var grid := {}
	for road in roads:
		var points: PackedVector3Array = road.points
		var half := float(road.width)*.5+.3
		for i in range(points.size()-1):
			var a := Vector2(points[i].x,points[i].z)
			var b := Vector2(points[i+1].x,points[i+1].z)
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(half)
			for x in range(floori(bounds.position.x/CARRIAGEWAY_CELL),floori(bounds.end.x/CARRIAGEWAY_CELL)+1):
				for z in range(floori(bounds.position.y/CARRIAGEWAY_CELL),floori(bounds.end.y/CARRIAGEWAY_CELL)+1):
					var cell := Vector2i(x,z)
					if not grid.has(cell): grid[cell] = []
					grid[cell].append([a,b,half])
	return grid

static func grid_on_carriageway(grid: Dictionary, point: Vector3) -> bool:
	var flat := Vector2(point.x,point.z)
	var cell := Vector2i(floori(flat.x/CARRIAGEWAY_CELL),floori(flat.y/CARRIAGEWAY_CELL))
	for segment in grid.get(cell,[]):
		var nearest := Geometry2D.get_closest_point_to_segment(flat,segment[0],segment[1])
		if flat.distance_to(nearest) < segment[2]: return true
	return false

const WRECK_LINGER_MSEC := 6000

func _wreck_expired(car: Node) -> bool:
	if not car.has_meta("wrecked_msec"): car.set_meta("wrecked_msec",Time.get_ticks_msec())
	return Time.get_ticks_msec()-int(car.get_meta("wrecked_msec")) > WRECK_LINGER_MSEC

## Tira o trânsito ambiente de perto destes pontos já, mesmo à vista: só para quem chama sob a cortina
## (largada da descida), onde o jogador não vê o carro sumir. Devolve quantos saíram.
func clear_ambient_traffic_near(points: PackedVector3Array, radius: float) -> int:
	var removed := 0
	for index in range(g.vehicles.size()-1,-1,-1):
		var car = g.vehicles[index]
		if not g._is_ambient_traffic(car) or not car.traffic or car == g.world.driving.car: continue
		for p: Vector3 in points:
			if car.global_position.distance_to(p) > radius: continue
			g.vehicles.remove_at(index)
			# Sem colisão já: a vaga é consultada neste mesmo quadro, antes do queue_free valer.
			car.collision_layer = 0
			car.queue_free()
			removed += 1
			break
	return removed

func in_traffic_hold(point: Vector3) -> bool:
	for hold: Array in g.traffic_holds.values():
		var limit: float = hold[1]*hold[1]
		for p: Vector3 in hold[0]:
			if Vector2(point.x-p.x,point.z-p.z).length_squared() <= limit: return true
	return false

func _spawn_point_allowed(point: Vector3, radius: float, minimum: float = g.POPULATION_SPAWN_MIN) -> bool:
	var distance: float = Vector2(point.x-g.world.player.global_position.x,point.z-g.world.player.global_position.z).length()
	# Pedestres comuns usam raio 1; carros mantêm o anel original de admissão.
	var maximum: float = g.VC_PEDESTRIAN_SPAWN_MAX if g.get_script().population_vc_enabled and radius <= 1.0 else g.POPULATION_SPAWN_MAX
	return distance >= minimum and distance <= maximum and not g._on_screen(point,radius)

func road_yaw(point: Vector3) -> float:
	var best := INF
	var yaw := 0.0
	for road in g._resident_roads():
		for index in range(road.points.size()-1):
			var a: Vector3 = road.points[index]
			var b: Vector3 = road.points[index+1]
			var distance := Geometry3D.get_closest_point_to_segment(point,a,b).distance_squared_to(point)
			if distance < best:
				best = distance
				var direction := b-a
				yaw = atan2(-direction.x,-direction.z)
	return yaw

func _spawn_vehicle() -> void:
	var began := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	g._create_traffic_vehicle()
	g._trace_cost("traffic_spawn",began)

func _create_traffic_vehicle() -> void:
	# Shared spatial admission favours quiet stretches and both legal directions.
	for attempt in 2:
		var slot: Dictionary = g.population_layout.select(g,true)
		if slot.is_empty(): return
		var point: Vector3 = slot.point
		var route: Curve3D = g.ambient_traffic_routes.route_near(point,int(slot.lane_index),slot.direction)
		if route == null or route.get_baked_length()<12 or not PORT_POLICY.route_is_ambient_safe(route): continue
		var offset := route.get_closest_offset(point)
		if route.get_meta("traffic_open",false) and route.get_baked_length()-offset<14: continue
		point = route.sample_baked(offset,true)
		if not g._spawn_point_allowed(point,3.0) or (not g.traffic_holds.is_empty() and g.in_traffic_hold(point)): continue
		var ahead := route.sample_baked(minf(offset+.5,route.get_baked_length()),true)-route.sample_baked(maxf(offset-.5,0),true)
		# A rua admitida é dona do contexto, inclusive quando duas regiões estão residentes.
		var spawn_region := str(slot.road.get("region", WORLD_CONNECTION.logical_region(point)))
		var id: String = TRAFFIC_ROSTER.select(spawn_region, str(slot.road.id))
		if spawn_region != "desert" and randi_range(0,9)==0: id=g.TRAFFIC_MOTORCYCLE_TYPES.pick_random()
		var cobra := preload("res://gameplay/urban_v1/CobraPatrol.gd").select_car(g.session,point)
		# Os Cobras rodam com a garagem própria (muscle cars e lowriders), não mais todos no mesmo cupê.
		if cobra: id=preload("res://runtime/MuscleFleet.gd").cobra_pick(randf())
		var car = g.spawn_vehicle(id,point+Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
		if car==null: continue
		car.vehicle_id="street_"+str(Time.get_ticks_usec())
		if id=="courier_van" and preload("res://gameplay/icecream/IceCreamVan.gd").choose(g.vehicles):
			# Etapas medidas à parte: a van de sorvete custou 39-43 ms no traffic_spawn da serra
			# (EXE de 17/10) e a altura do teto, pré-aquecida, não era a causa.
			var paint_began := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
			car.paint_color=Color("fff0dd")
			g._trace_cost("traffic_spawn_icecream_paint",paint_began)
			paint_began = Time.get_ticks_usec() if paint_began != 0 else 0
			car.vehicle_id=preload("res://gameplay/icecream/IceCreamVan.gd").PREFIX+str(Time.get_ticks_usec())
			g._trace_cost("traffic_spawn_icecream_id",paint_began)
		car.route=route
		car.route_distance=offset
		car.set_meta("ambient_traffic",true)
		car.traffic=true
		if cobra: preload("res://gameplay/urban_v1/CobraPatrol.gd").attach(g.session,car)
		return
