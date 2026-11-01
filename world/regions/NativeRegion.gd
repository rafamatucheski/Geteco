extends Node3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const LOADING_TURBO := preload("res://runtime/LoadingTurbo.gd")
## Geografia nativa de produção. Geometria/física só carregam perto do jogador.
const MOUNTAIN_FACTORY := preload("res://world/mountain_detail/MountainDetailFactory.gd")
const MOUNTAIN_FORGE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const FORGE_HERMIT := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const MOUNTAIN_REFUGE := preload("res://world/mountain_detail/MountainRefuge.gd")
## A/B de desempenho: GETECO_BLADE_FORGE=0 deixa a clareira da forja e a da cabana vazias (terreno e trilhas iguais).
static var _blade_forge_enabled := OS.get_environment("GETECO_BLADE_FORGE") != "0"
const MOUNTAIN_SHADOW := preload("res://world/mountain_detail/MountainShadowFinish.gd")
const URBAN_FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
## Estrada de terra: a malha visível é a faixa com borda esmaecida (edge_alpha), por isso a variante de borda.
const NATURAL_GROUND := preload("res://world/regions/natural_ground_edge.gdshader")
const HARBOR_ROUTE_FACTORY := preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd")
const HARBOR_PUBLIC_REALM := preload("res://world/urban_detail/HarborPublicRealm3D.gd")
const HARBOR_BRIDGE := preload("res://world/urban_detail/HarborBridge3D.gd")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const HARBOR_PROP := preload("res://world/urban_detail/HarborProp3D.gd")
const SOUTH_PORT := preload("res://world/regions/OriginalSouthPort.gd")
const HARBOR_COAST := preload("res://world/shape/HarborCoast.gd")
const HARBOR_COAST_WOODLAND := preload("res://world/shape/HarborCoastWoodland.gd")
const SOUTH_PORT_LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const PORT_SHIP_DRESSING := preload("res://world/regions/PortShipDressing3D.gd")
const PORT_SHIP_PAINT := preload("res://world/regions/PortShipMaterials3D.gd")
const NORTHSTAR_HOIST := preload("res://world/regions/NorthstarCargoHoist3D.gd")
const PORT_CONTAINER_BATCH := preload("res://world/regions/PortContainerBatch.gd")
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const HARBOR_DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const RESTAURANT_TERRACE := preload("res://world/urban_detail/HarborRestaurantTerrace3D.gd")
const HARBOR_ROAD_GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const HARBOR_URBAN_SURFACE := preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
const CITY_DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const TUNNEL_CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const ROUTE_GEOMETRY := preload("res://world/mountain_detail/MountainRouteGeometry.gd")
const ROUTE_LAYOUT := preload("res://world/mountain_detail/MountainRouteLayout.gd")
const MOUNTAIN_JEEP_COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const MOUNTAIN_JEEP_SCENERY := preload("res://world/mountain_jeep/MountainJeepScenery.gd")
const DRESSING := preload("res://world/regions/TerrainDressing3D.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const WALKUP_DOOR := preload("res://world/places/WalkupFacadeDoor.gd")
const PAINTED_MOUNTAIN := preload("res://world/mountain_detail/PaintedMountainPlaces.gd")
const DATA_PATH := "res://world/regions/OriginalWorldData.json"
const CELL := 64.0
const SCALE := 1.0/16.0
# A célula 5 contém a aproximação curva do lado do Harbor. Carregar o terreno da montanha
# ali com as duas regiões residentes cria uma parede elevada atravessando a faixa.
const MOUNTAIN_BRIDGE_VOID_CELLS := [Vector2i(5,-5),Vector2i(6,-5),Vector2i(7,-5),Vector2i(8,-5)]
# O terreno da montanha pertence ao território lógico da Mountain (WorldConnection3D.logical_region):
# a leste da emenda e ao norte do limite norte do Harbor. O Harbor é dono do chão a oeste da emenda,
# onde a Mountain não tem geografia autorada; montar morros procedurais ali cobria ruas do Harbor
# (island_esplanade em 292.6,-114.2) sempre que a Mountain ficava residente perto da ponte.
const WORLD_CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var region_id := "harbor"
var chunks: Dictionary = {}
var records: Dictionary = {}
var roads: Array[Dictionary] = []
var walkways: Array[Dictionary] = []
var route_geometry := ROUTE_GEOMETRY.new()
var buildings: Array[Dictionary] = []
var entries: Array[Dictionary] = []
var source_data: Dictionary
var focus := Vector3.ZERO
var initial_focus := Vector3.INF
# Somente para preparar a regiao distante sob a cortina; montagem real exige foco.
var initial_prewarm_only := false
var pending: Array[Vector2i] = []
var build_jobs: Array[Dictionary] = []
# Orçamento de construção fatiada por quadro (µs); um passo sozinho pode excedê-lo.
# 1 ms (era 3 ms): a 30 m/s pela ponte porto-montanha o pior quadro caiu de 62-159 ms para
# 46-57 ms e o p99 de ~10 ms para ~4,8 ms (tests/measure/probe_driving_hitches.gd, 2 execuções
# cada). A 45 m/s não mudou. Com a fila grande o orçamento dobra (ver _process).
const BUILD_BUDGET_USEC := 1000.0
var current_cell := Vector2i(100000,100000)
var retention_radius := 2
var vehicle_support_cells: Dictionary = {}
var developer_view_cells: Dictionary = {}
var _developer_bounds := Rect2()
var _residency_dirty := false
var _chairlift_cleanup_pending := false
var prepared := false
var elapsed := 0.0
var materials := {}
var extra_land: Array[PackedVector2Array] = []
var terrain: TERRAIN
## Tarefas do WorkerThreadPool que calculam o terreno da serra (MountainTerrain3D.chunk_data), id -> true.
## Toda tarefa precisa de wait_for_task_completion; trecho descartado antes de usar o resultado deixa a sua
## aqui, recolhida por _collect_terrain_tasks quando termina ou na destruição da região.
var _terrain_tasks: Dictionary = {}
## Quantos trechos da fila já começam o cálculo do terreno no trabalhador, à frente da vez deles.
const TERRAIN_PREFETCH_JOBS := 6
## Resultado do trabalhador para o _build_surfaces em andamento (vazio: build_chunk calcula na hora).
var _surface_terrain_data: Dictionary = {}
var chairlifts: Array[Node3D] = []
var chairlift_operating := false
var mountain_night_level := 0.0
var harbor_road_geometry: HARBOR_ROAD_GEOMETRY
var harbor_urban_surface: HARBOR_URBAN_SURFACE
var harbor_ocean: RefCounted
var harbor_dressing_ground: Array[PackedVector2Array] = []
var harbor_facade_ground: Array[PackedVector2Array] = []
var coastal_protection: RefCounted
## Auxiliares sem estado (01/11, só para este arquivo caber na leitura): o estado continua aqui, e cada
## função antiga virou delegação de uma linha, então subclasses (EditableRegion) e testes que chamam
## `_land_piece`, `_box` etc. por nome não mudam. Criados na declaração, e não em _ready, porque
## testes usam NativeRegion.new() fora da árvore e chamam _land_piece direto.
const LAND_PART := preload("res://world/regions/NativeLand.gd")
const ROAD_SURFACES_PART := preload("res://world/regions/NativeRoadSurfaces.gd")
var _land_part: LAND_PART = LAND_PART.new(self)
var _road_surfaces_part: ROAD_SURFACES_PART = ROAD_SURFACES_PART.new(self)
## Pré-aquecimento e tarefas do terreno da serra no trabalhador (01/11, Onda 1): mesmo padrão, estado aqui.
const PREWARM_PART := preload("res://world/regions/NativePrewarm.gd")
const TERRAIN_TASKS_PART := preload("res://world/regions/NativeTerrainTasks.gd")
var _prewarm_part: PREWARM_PART = PREWARM_PART.new(self)
var _terrain_tasks_part: TERRAIN_TASKS_PART = TERRAIN_TASKS_PART.new(self)
## Cache de registros e aposentadoria de trechos (01/11, Onda 2): estado aqui (lido por testes e por
## RetainedRegionPreparation), as listas CACHED_* e o corpo lá; cada função antiga delega em uma linha.
const RECORD_CACHE_PART := preload("res://world/regions/NativeRecordCache.gd")
var _record_cache_part: RECORD_CACHE_PART = RECORD_CACHE_PART.new(self)
## Construtores de registro (montanha, porto, prédio, fachada, floresta, navio, guindaste; 01/11, Onda 2):
## corpo lá, sem estado próprio; cada função antiga delega em uma linha (EditableRegion e testes sobrescrevem).
const RECORD_BUILDERS_PART := preload("res://world/regions/NativeRecordBuilders.gd")
var _record_builders_part: RECORD_BUILDERS_PART = RECORD_BUILDERS_PART.new(self)
## Preparação dos dados (_prepare em etapas; 01/11, Onda 3): corpo lá, sem estado próprio; _prepare fica
## aqui como delegação de uma linha (EditableRegion a sobrescreve e chama super).
const PREPARE_PART := preload("res://world/regions/NativePrepare.gd")
var _prepare_part: PREPARE_PART = PREPARE_PART.new(self)
var spawn_position: Vector3:
	get: return CATALOG._at(Vector2(715,1800) if region_id == "harbor" else Vector2(3260,400),region_id)
static func build_region(id: String, first_focus: Vector3 = Vector3.INF) -> Node3D:
	if id not in ["harbor","mountain"]: return null
	var region = load("res://world/regions/NativeRegion.gd").new()
	region.region_id = id
	region.initial_focus = first_focus
	return region
static func get_definition(id: String) -> Dictionary:
	return {"id":id,"source_id":"world/harbor/HarborPreview.tscn" if id == "harbor" else "world/mountain_pass/MountainPass.tscn","unit_scale":SCALE,"offset":Vector2.ZERO if id == "harbor" else CATALOG.MOUNTAIN_OFFSET}
var data_prepared := false

func _ready() -> void:
	name = region_id.capitalize()+"NativeRegion"
	prepare_data()
	prepared = true
	if not initial_prewarm_only:
		set_focus(initial_focus if initial_focus.is_finite() else spawn_position)
## Geografia (registros, vias, floresta, terreno): ~340 ms em Mountain. Pode ser
## chamada no carregamento, antes de a região entrar na árvore.
func prepare_data() -> void:
	if data_prepared: return
	var preparation_started := STALL_WORK.begin()
	source_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_prepare()
	STALL_WORK.finish("region.prepare_data." + region_id, preparation_started, {})
	data_prepared = true

## Pré-aquecimento: corpo em NativePrewarm.gd (delegação de uma linha; mesmos nomes).
func prewarm() -> void: _prewarm_part.prewarm()
func prewarm_incremental() -> void: await _prewarm_part.prewarm_incremental()

## Os poucos trechos construídos para aquecer o túnel sobrevivem escondidos e sem física.
## A primeira visita usa os mesmos nós; não paga outra construção completa.
const MAX_WARM_TUNNEL_CHUNKS := 8
var _warm_tunnel_chunks: Dictionary = {}
var _tunnel_corridor_primed := false
func prime_tunnel_corridor() -> void: await _prewarm_part.prime_tunnel_corridor()
func _keep_warm_tunnel_chunk(chunk: Node3D) -> void: _prewarm_part._keep_warm_tunnel_chunk(chunk)
func _hold_file_resources(root: Node) -> void: _prewarm_part._hold_file_resources(root)
func _hold_resource(resource: Variant) -> void: _prewarm_part._hold_resource(resource)

## Descarrega tudo mantendo os dados preparados (região reaproveitada).
func release_chunks() -> void:
	var stall_began := STALL_WORK.begin()
	var released_chunks := chunks.size()
	for job in build_jobs: _cancel_record_build(job)
	build_jobs.clear()
	developer_view_cells.clear()
	pending.clear()
	for key in chunks.keys():
		_suspend_chunk_vehicles(key)
		_suspend_chunk_mechanisms(chunks[key])
		_retire_chunk(chunks[key])
	chunks.clear()
	vehicle_support_cells.clear()
	current_cell = Vector2i(100000,100000)
	_residency_dirty = false
	_chairlift_cleanup_pending = false
	chairlifts.clear()
	STALL_WORK.finish("region.release_chunks", stall_began, {"region": region_id, "chunks": released_chunks, "retiring": _retiring.size()})

func _exit_tree() -> void:
	for job in build_jobs: _cancel_record_build(job)
	var stall_began := STALL_WORK.begin()
	var retiring_chunks := _retiring.size()
	for chunk in _retiring:
		if is_instance_valid(chunk): chunk.free()
	_retiring.clear()
	_retire_stack.clear()
	for chunk in chunks.values(): _suspend_chunk_mechanisms(chunk)
	STALL_WORK.finish("region.exit_tree", stall_began, {"region": region_id, "retiring_chunks": retiring_chunks})
## Unmount mantém a região para reuso; só a destruição libera o cache.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for job in build_jobs: _cancel_record_build(job)
		for task in _terrain_tasks.keys(): WorkerThreadPool.wait_for_task_completion(task)
		_terrain_tasks.clear()
		for nodes in _record_cache.values():
			for node in nodes:
				# Nós com pai pertencem à árvore; não disputar sua destruição.
				if is_instance_valid(node) and node.get_parent() == null: node.free()
		_record_cache.clear()
		_held_resources.clear()

func _cell(point: Vector3) -> Vector2i: return Vector2i(floori(point.x/CELL),floori(point.z/CELL))
func _record(point: Vector3, item: Dictionary) -> void:
	if region_id == "harbor":
		var kind: String = item.get("kind","")
		var skate_layout := preload("res://activities/skate/SkateParkLayout.gd")
		if kind == "tree" and skate_layout.reserved(Vector2(point.x,point.z),3.5): return
		if kind == "harbor_prop":
			var prop_kind: String = item.get("data",{}).get("kind","")
			var clearance := 3.5 if prop_kind == "tree" else (2.4 if prop_kind == "bench" else 1.2)
			if skate_layout.reserved(Vector2(point.x,point.z),clearance): return
	if region_id == "harbor" and item.get("kind","") == "tree" and preload("res://runtime/FishingLocation.gd").reserved(Vector2(point.x,point.z),2.0): return
	if region_id == "harbor" and item.get("kind","") == "tree" and preload("res://world/places/amusement_park/AmusementParkLayout.gd").reserved(Vector2(point.x,point.z),3.5): return
	var key := _cell(point)
	if not records.has(key): records[key] = []
	records[key].append(item)
func _prepare() -> void: _prepare_part._prepare()

## Clareiras dos lugares da serra que não vêm do catálogo (forja, eremita, refúgio) e os pátios
## pisados do refúgio e do eremita, que entram só na máscara do terreno (fora do mapa). Uma lista
## só para o gerador e para o EditableRegion: a cópia do editor tinha esquecido o refúgio.
func _mountain_site_terrain(terrain_roads: Array[Dictionary]) -> Array:
	terrain_roads.append_array(MOUNTAIN_REFUGE.yard_trails())
	if _blade_forge_enabled: terrain_roads.append_array(FORGE_HERMIT.yard_trails())
	return [MOUNTAIN_FORGE.FOOTPRINT,FORGE_HERMIT.FOOTPRINT,MOUNTAIN_REFUGE.FOOTPRINT]

func map_routes() -> Array[Dictionary]:
	return roads + walkways

func _revise_mountain_routes() -> void:
	# Gera primeiro a floresta original e depois limpa só os corredores mudados.
	# Rejeitar durante o posicionamento com semente moveria árvores pela região inteira.
	for key in records:
		records[key] = records[key].filter(func(record): return record.kind != "road")
	roads.clear()
	var main := ROUTE_LAYOUT.main_route(source_data.mountain_control_points)
	_add_road("mountain_pass",main,140*SCALE)
	for road in ROUTE_LAYOUT.branches(main):
		_add_road(road.id,road.points,road.width,road.surface)
	walkways = ROUTE_LAYOUT.paths()
	walkways.append_array(MOUNTAIN_JEEP_COURSE.paths(main))
	walkways.append(MOUNTAIN_FORGE.approach())
	walkways.append(FORGE_HERMIT.approach())
	walkways.append(MOUNTAIN_REFUGE.approach())
	for path in walkways:
		if path.id in ["cave_trail","forest_shop_walk"]: path.points = ROUTE_LAYOUT.snap_start(path.points,main)
		_record_path(path)
	route_geometry.configure(roads + walkways)
	for record in MOUNTAIN_JEEP_COURSE.records():
		_record(record.position, record)
	for key in records:
		records[key] = records[key].filter(func(record):
			return record.kind != "tree" or (not route_geometry.contains(record.position,3.0) and not MOUNTAIN_JEEP_COURSE.is_reserved(Vector2(record.position.x,record.position.z),3.0)))
	var cover := CATALOG._at(Vector2(6190,-95),region_id)
	_record(cover,{"kind":"cave_approach","position":cover})

func _record_path(path: Dictionary) -> void:
	var points: PackedVector3Array = path.points
	var outline := ROUTE_GEOMETRY.edges(points,float(path.width))
	for i in range(points.size()-1):
		var steps := maxi(1,ceili(points[i].distance_to(points[i+1])/16.0))
		for step in steps:
			var start := float(step)/steps
			var finish := float(step+1)/steps
			var a := points[i].lerp(points[i+1],start)
			var b := points[i].lerp(points[i+1],finish)
			_record((a+b)*.5,{"kind":"road","road_id":path.id,"a":a,"b":b,"width":path.width,"surface":"footpath",
				"left_a":outline[i].left.lerp(outline[i+1].left,start),"right_a":outline[i].right.lerp(outline[i+1].right,start),
				"left_b":outline[i].left.lerp(outline[i+1].left,finish),"right_b":outline[i].right.lerp(outline[i+1].right,finish)})

func _add_road(id: String,points: PackedVector3Array,width: float,surface: String = "asphalt") -> void:
	roads.append({"id":id,"points":points,"width":width,"surface":surface})
	# Um beco sem saída acessível ao jogador com estacionamento, nunca rota ambiente de ônibus/caminhão.
	# Mantido aqui para a reconstrução do editor de mundo preservar a mesma política.
	if id==preload("res://world/places/fishing/FishingRuralLayout.gd").ROAD_ID:
		roads[-1]["traffic"] = false
		roads[-1]["crossings"] = false
		roads[-1]["sidewalk_width"] = 0.0
	var edges: Array[Dictionary] = []
	if region_id == "mountain" and surface == "asphalt":
		for point_index in points.size():
			var incoming: Vector3 = (points[point_index]-points[maxi(0,point_index-1)]).normalized() if point_index>0 else (points[1]-points[0]).normalized()
			var outgoing: Vector3 = (points[mini(points.size()-1,point_index+1)]-points[point_index]).normalized() if point_index<points.size()-1 else incoming
			var previous_normal := Vector3(incoming.z,0,-incoming.x)
			var next_normal := Vector3(outgoing.z,0,-outgoing.x)
			var miter := (previous_normal+next_normal).normalized()
			if miter.is_zero_approx(): miter = next_normal
			var reach := width*.5/maxf(.45,miter.dot(next_normal))
			if id == "mountain_pass":
				# Casa as duas faixas de 3.875 m do Harbor, suavizando até a largura autorada do passo.
				var join := smoothstep(WORLD_CONNECTION.SEAM.x, WORLD_CONNECTION.TRAFFIC_MERGE_X, points[point_index].x)
				reach *= lerpf(7.75 / width, 1.0, join)
			edges.append({"left":points[point_index]+miter*reach,"right":points[point_index]-miter*reach})
	if region_id == "mountain" and id != "mountain_pass": edges = ROUTE_GEOMETRY.edges(points,width)
	for i in range(points.size()-1):
		var distance := points[i].distance_to(points[i+1])
		var steps := maxi(1,ceili(distance/16.0))
		for step in steps:
			var a := points[i].lerp(points[i+1],float(step)/steps)
			var b := points[i].lerp(points[i+1],float(step+1)/steps)
			var record := {"kind":"road","road_id":id,"a":a,"b":b,"width":width,"surface":surface}
			if not edges.is_empty():
				var from_weight := float(step)/steps
				var to_weight := float(step+1)/steps
				record["left_a"] = edges[i].left.lerp(edges[i+1].left,from_weight)
				record["right_a"] = edges[i].right.lerp(edges[i+1].right,from_weight)
				record["left_b"] = edges[i].left.lerp(edges[i+1].left,to_weight)
				record["right_b"] = edges[i].right.lerp(edges[i+1].right,to_weight)
			_record((a+b)*.5,record)
func set_focus(point: Vector3, complete_focus_chunk := false) -> void:
	var focus_began := STALL_WORK.begin()
	_set_focus(point,complete_focus_chunk)
	STALL_WORK.finish_slow("stream.%s.set_focus"%region_id,focus_began,2000)

func _set_focus(point: Vector3, complete_focus_chunk: bool) -> void:
	focus = point
	if not prepared: return
	var cell := _cell(point)
	if cell == current_cell:
		if complete_focus_chunk: _ensure_chunk(cell)
		return
	current_cell = cell
	_residency_dirty = true
	pending.clear()
	# O orçamento de streaming de produção pede a célula ocupada e as oito
	# vizinhas. retention_radius continua sendo uma faixa de tolerância maior em movimento.
	for x in range(-1,2):
		for z in range(-1,2):
			var key := cell+Vector2i(x,z)
			if not chunks.has(key): pending.append(key)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return Vector2(a-cell).length_squared()<Vector2(b-cell).length_squared())
	# A célula ocupada recebe colisão antes da admissão; registros e mobiliário ficam
	# na fila para que cruzar uma borda de célula não monte o chunk inteiro de forma síncrona.
	pending.erase(cell)
	if complete_focus_chunk: _ensure_chunk(cell)
	else: _ensure_chunk_surfaces(cell)
	preload("res://world/regions/DeveloperViewCells.gd").enqueue(self)
	_trim_chunks(cell)

func prepare_collision_at(point: Vector3) -> bool:
	# Veículos de emergência são atores físicos e podem pegar por um instante uma rota
	# vizinha enquanto o jogador fica parado.  Admite a célula ocupada/seguinte deles antes
	# da física em vez de deixá-los dirigir sobre uma rua cujo piso em streaming
	# ainda não existe.
	var key := _cell(point)
	var had_chunk := chunks.has(key)
	var collision_began := STALL_WORK.begin()
	_ensure_chunk_surfaces(key)
	STALL_WORK.finish_slow("stream.%s.prepare_collision"%region_id,collision_began,2000)
	if not had_chunk and chunks.has(key): _residency_dirty = true
	return chunks.has(key)

## Antecipação para ator físico (viatura do despacho, ônibus): pede o chão da célula à frente pela fila
## fatiada, sem montar nada agora. Quando o ator chega, prepare_collision_at já encontra o chão pronto;
## antes ele montava as superfícies da célula inteira no quadro (13–27 ms, `stream.harbor.prepare_collision`,
## rodada de 24/10). GETECO_COLLISION_LOOKAHEAD=0 desliga (quem chama checa `collision_lookahead`).
static var collision_lookahead := OS.get_environment("GETECO_COLLISION_LOOKAHEAD") != "0"
func request_collision_soon(point: Vector3) -> void:
	if not prepared: return
	var key := _cell(point)
	if chunks.has(key):
		# Já existe mas talvez só com o pedido: o estágio do chão vai para a frente da fila.
		for index in range(1, build_jobs.size()):
			if build_jobs[index].key == key and int(build_jobs[index].stage) == 0:
				var job: Dictionary = build_jobs[index]
				build_jobs.remove_at(index)
				build_jobs.push_front(job)
				return
		return
	var at := pending.find(key)
	if at == 0: return
	if at > 0: pending.remove_at(at)
	pending.push_front(key)

func set_developer_view(view: Rect2, enabled: bool, full_map := false) -> void:
	if enabled and not _developer_bounds.has_area():
		_developer_bounds = preload("res://world/regions/DeveloperViewCells.gd").record_bounds(records, CELL)
	var next: Dictionary = preload("res://world/regions/DeveloperViewCells.gd").select_cells(_developer_bounds if full_map else view, _developer_bounds, CELL) if enabled else {}
	if next == developer_view_cells: return
	developer_view_cells = next
	# Remove obsolete overview requests while preserving physical support and ordinary neighbours.
	for index in range(pending.size()-1, -1, -1):
		var key: Vector2i = pending[index]
		if developer_view_cells.has(key) or vehicle_support_cells.has(key): continue
		if absi(key.x-current_cell.x)>1 or absi(key.y-current_cell.y)>1: pending.remove_at(index)
	preload("res://world/regions/DeveloperViewCells.gd").enqueue(self)
	_residency_dirty = true
	_trim_chunks(current_cell)

func set_retention_radius(value: int) -> void:
	var next_radius := clampi(value,1,2)
	if next_radius != retention_radius:
		retention_radius = next_radius
		_residency_dirty = true
	if current_cell.x < 100000: _trim_chunks(current_cell)

func set_vehicle_support(vehicles_to_support: Array) -> void:
	var next_cells: Dictionary = {}
	for vehicle in vehicles_to_support:
		var point: Vector3 = vehicle.position
		var radius: float = maxf(0.0,vehicle.radius)
		for x in range(floori((point.x-radius)/CELL),floori((point.x+radius)/CELL)+1):
			for z in range(floori((point.z-radius)/CELL),floori((point.z+radius)/CELL)+1):
				next_cells[Vector2i(x,z)] = true
	if next_cells != vehicle_support_cells:
		vehicle_support_cells = next_cells
		_residency_dirty = true
		for key in vehicle_support_cells:
			pending.erase(key)
			_ensure_chunk_surfaces(key)
	if current_cell.x < 100000: _trim_chunks(current_cell)

func _trim_chunks(cell: Vector2i) -> void:
	if not _residency_dirty: return
	_residency_dirty = false
	for key in chunks.keys():
		if vehicle_support_cells.has(key) or developer_view_cells.has(key): continue
		if absi(key.x-cell.x)>retention_radius or absi(key.y-cell.y)>retention_radius:
			_suspend_chunk_vehicles(key)
			_suspend_chunk_mechanisms(chunks[key])
			_retire_chunk(chunks[key])
			chunks.erase(key)
			for index in range(build_jobs.size()-1,-1,-1):
				if build_jobs[index].key == key:
					_cancel_record_build(build_jobs[index])
					build_jobs.remove_at(index)
			_chairlift_cleanup_pending = true

func _suspend_chunk_vehicles(key: Vector2i) -> void:
	# Suspende antes de remover o apoio; o ProductionWorld retoma depois da checagem de chão.
	for car in get_tree().get_nodes_in_group("drivable"):
		if car is CharacterBody3D and car.is_visible_in_tree() and car.is_physics_processing() and _cell(car.global_position) == key:
			# Células de Harbor e Mountain se sobrepõem na costura: cada região só suspende o
			# que está do seu lado (tests/test_region_vehicle_suspension.gd).
			if WORLD_CONNECTION.logical_region(car.global_position) != region_id: continue
			car.set_meta("awaiting_ground", true)
			car.velocity.y = 0.0
			car.set_physics_process(false)

func _suspend_chunk_mechanisms(chunk: Node3D) -> void:
	if not is_instance_valid(chunk): return
	for lift in chairlifts:
		if is_instance_valid(lift) and chunk.is_ancestor_of(lift): lift.set_animation_active(false)

func set_chairlift_operating(value: bool) -> void:
	chairlift_operating = value
	chairlifts = chairlifts.filter(func(lift): return is_instance_valid(lift) and not lift.is_queued_for_deletion())
	for lift in chairlifts: lift.set_operating(value)
func set_night_lights(level: float) -> void:
	if region_id != "mountain": return
	level = clampf(level,0.0,1.0)
	if absf(mountain_night_level-level) < .005: return
	mountain_night_level = level
	for chunk in chunks.values():
		if is_instance_valid(chunk): _apply_night_lights(chunk)
func _apply_night_lights(chunk: Node3D) -> void:
	for light in chunk.find_children("*","OmniLight3D",true,false):
		if light.is_in_group("mountain_night_light") and not light.get_meta("street_destroyed",false):
			light.light_energy = float(light.get_meta("night_energy",1.0))*mountain_night_level

const _SYS_SPAN := preload("res://runtime/StallWorkTrace.gd")
## Span do sistema inteiro (22/10): quadros de 30–60 ms com o tempo em _process sem nenhum span.
func _process(_delta: float) -> void:
	var span := _SYS_SPAN.begin()
	_process_traced(_delta)
	_SYS_SPAN.finish_slow("sys.native_region.process", span, 3000)

func _process_traced(_delta: float) -> void:
	var drain_began := Time.get_ticks_usec()
	_drain_retired()
	_note_slow("liberação", drain_began, 100000)
	_collect_terrain_tasks()
	var began := Time.get_ticks_usec()
	# Com fila grande (dirigindo rápido) a construção ganha mais tempo por quadro, senão
	# o chunk em que o carro entra ainda não existe e `set_focus` o constrói inteiro de uma vez.
	var budget := BUILD_BUDGET_USEC if pending.size()+build_jobs.size() < 4 else BUILD_BUDGET_USEC*2.0
	# Sob a cortina de carregamento o quadro pode ser longo: orçamento maior (runtime/LoadingTurbo.gd).
	budget = LOADING_TURBO.budget(budget)
	while true:
		if build_jobs.is_empty():
			if pending.is_empty(): return
			var key: Vector2i = pending.pop_front()
			if chunks.has(key): continue
			var chunk_began := Time.get_ticks_usec()
			_build_chunk(key,false)
			_note_slow("novo chunk",chunk_began,50000)
			if build_jobs.is_empty():
				if Time.get_ticks_usec()-began >= budget: return
				continue
		var left: float = budget-(Time.get_ticks_usec()-began)
		if left <= 0.0: return
		_prefetch_terrain_tasks()
		var job_began := Time.get_ticks_usec()
		var job_done := _run_build_job(build_jobs[0],left)
		_note_slow("etapa estágio %d"%int(build_jobs[0].stage),job_began,100000)
		if job_done: build_jobs.pop_front()
		# Terreno da serra ainda no trabalhador: tentar de novo neste quadro só giraria o orçamento à toa.
		elif build_jobs[0].get("waiting_worker",false): return
		if Time.get_ticks_usec()-began >= budget: return

func _is_cached_record(record: Dictionary) -> bool: return _record_cache_part._is_cached_record(record)

var _record_cache: Dictionary = {}

func _is_static_editor_skyline(data: Dictionary) -> bool: return _record_cache_part._is_static_editor_skyline(data)

func _record_cache_key(record: Dictionary) -> String: return _record_cache_part._record_cache_key(record)

func _build_record_cached(chunk: Node3D, record: Dictionary) -> void: _record_cache_part._build_record_cached(chunk, record)

func _step_record_build(chunk: Node3D, record: Dictionary, job: Dictionary, budget_usec: float) -> bool: return _record_cache_part._step_record_build(chunk, record, job, budget_usec)

func _cancel_record_build(job: Dictionary) -> void: _record_cache_part._cancel_record_build(job)

func _detach_cached_records(chunk: Node3D) -> void: _record_cache_part._detach_cached_records(chunk)

## Chunk que sai do raio de retenção: liberar 1000-3000 nós de uma vez custava 40-150 ms
## num quadro (medido dirigindo). O chunk é tirado da lista já e seus filhos são liberados
## em fatias de `RETIRE_BUDGET_USEC` por quadro.
const RETIRE_BUDGET_USEC := 1500.0
var _retiring: Array[Node3D] = []
var _retire_stack: Array[Node] = []

func _retire_chunk(chunk: Node3D) -> void: _record_cache_part._retire_chunk(chunk)

func _drain_retired() -> void: _record_cache_part._drain_retired()

func _drain_retired_slice() -> void: _record_cache_part._drain_retired_slice()

func hand_off_retiring() -> int: return _record_cache_part.hand_off_retiring()

func _cleanup_retired_chairlifts_if_idle() -> void: _record_cache_part._cleanup_retired_chairlifts_if_idle()
func _material(color: Color) -> StandardMaterial3D:
	if materials.has(color): return materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .86
	# Cor lisa lia como plano chapado: relevo e rugosidade em espaço de mundo, mesmo tom.
	if color.a >= 1.0:
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(material, "plaster", 2.0, .7)
		material.albedo_color = Color(minf(color.r * material.albedo_color.r, 1.0), minf(color.g * material.albedo_color.g, 1.0), minf(color.b * material.albedo_color.b, 1.0))
		material.roughness = 1.0
	materials[color] = material
	return material
## Chão base, troncos e caixas: corpo em NativeLand.gd (delegação de uma linha; mesmo nome e padrões).
func _tree_collision(tree: Node3D, chunk: Node3D) -> void: _land_part._tree_collision(tree, chunk)
func _land_piece(chunk: Node3D, piece: Rect2, cover: Array[PackedVector2Array]) -> void: _land_part._land_piece(chunk, piece, cover)
func _land_outside_bridge(chunk: Node3D, piece: Rect2, cover: Array[PackedVector2Array], cuts: Array[PackedVector2Array]) -> void: _land_part._land_outside_bridge(chunk, piece, cover, cuts)
func _box(parent: Node3D,label: String,point: Vector3,size: Vector3,color: Color,solid := false) -> MeshInstance3D: return _land_part._box(parent, label, point, size, color, solid)

## Superfícies de rua e estágio fatiado do Harbor: corpo em NativeRoadSurfaces.gd (delegação de uma linha).
func _build_road_surfaces(chunk: Node3D, rect: Rect2) -> void: _road_surfaces_part._build_road_surfaces(chunk, rect)
func _build_soft_road_surface(chunk: Node3D, rect: Rect2, material: ShaderMaterial) -> void: _road_surfaces_part._build_soft_road_surface(chunk, rect, material)
func _rects_outside_all(rect: Rect2, holes: Array[Rect2]) -> Array[Rect2]: return _road_surfaces_part._rects_outside_all(rect, holes)
func _rect_outside(surface: Rect2, hole: Rect2) -> Array[Rect2]: return _road_surfaces_part._rect_outside(surface, hole)

func _build_chunk(key: Vector2i, immediate := true, warming := false) -> void:
	if _warm_tunnel_chunks.has(key):
		var reused: Node3D = _warm_tunnel_chunks[key]
		_warm_tunnel_chunks.erase(key)
		if is_instance_valid(reused) and not reused.is_queued_for_deletion():
			reused.process_mode = int(reused.get_meta("warm_tunnel_process_mode", Node.PROCESS_MODE_INHERIT))
			reused.show()
			chunks[key] = reused
			for lift in chairlifts:
				if is_instance_valid(lift) and reused.is_ancestor_of(lift): lift.set_animation_active(true)
			return
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d"%[key.x,key.y]
	add_child(chunk)
	chunks[key] = chunk
	var job := {"key":key,"chunk":chunk,"rect":Rect2(key.x*CELL,key.y*CELL,CELL,CELL),"stage":0,"index":0,"warming":warming}
	if immediate: _run_build_job(job,INF)
	else: build_jobs.append(job)

## Streaming em fatias: um chunk custava 8–219 ms num quadro só (medido 2026-09-23),
## o que travava a direção. A colisão (superfícies) sai primeiro; depois um registro
## por vez e o acabamento, até `budget_usec` por quadro. Devolve true ao terminar.
func _run_build_job(job: Dictionary, budget_usec: float) -> bool:
	var chunk: Node3D = job.chunk
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
		_cancel_record_build(job)
		return true
	var began := Time.get_ticks_usec()
	var key: Vector2i = job.key
	var rect: Rect2 = job.rect
	var chunk_records: Array = records.get(key,[])
	while true:
		match int(job.stage):
			0:
				if _terrain_chunk_pending(job,budget_usec): return false
				var stage_began := STALL_WORK.begin()
				# Pelo membro, não por parâmetro: testes sobrescrevem _build_surfaces com a assinatura de 3 argumentos.
				_surface_terrain_data = job.get("terrain_data",{})
				# O Harbor retoma o estágio pelo cursor em job.harbor_surfaces (ver _harbor_surfaces_step).
				# Orçamento 0 ou INF (chão para veículo já, chunk imediato) termina o estágio aqui.
				_surface_slice_job = job
				_surface_slice_budget = budget_usec
				_surface_slice_began = began
				_build_surfaces(chunk,rect,key)
				_surface_slice_job = {}
				_surface_slice_budget = INF
				_surface_terrain_data = {}
				STALL_WORK.finish_slow("stream.%s.surfaces"%region_id,stage_began,2000)
				if job.has("harbor_surfaces"): return false
				job.erase("terrain_data")
				job.stage = 1
			1:
				# Vegetação/pedras do terreno: passo próprio, o terreno sozinho já custa 40–95 ms.
				if region_id == "mountain" and _mountain_owns_terrain(key):
					# Spans próprios: nos logs de 15/10 a maior parte dos quadros >33 ms da serra caía no processo sem
					# span nenhum; vegetação e acabamento do trecho eram os passos do streaming sem medição.
					var dressing_began := STALL_WORK.begin()
					if not job.has("terrain_dressing"): job.terrain_dressing = DRESSING.begin(rect,region_id,terrain.surface_height_at,_dressing_reserved)
					var dressing_done: bool = DRESSING.step(job.terrain_dressing,maxf(1500.0,budget_usec-(Time.get_ticks_usec()-began)))
					STALL_WORK.finish_slow("stream.mountain.terrain_dressing",dressing_began,2000)
					if not dressing_done: return false
					chunk.add_child(job.terrain_dressing.root)
					job.erase("terrain_dressing")
				job.stage = 2
			2:
				if int(job.index) < chunk_records.size():
					var record: Dictionary = chunk_records[int(job.index)]
					# A carga do navio (~1,7 s em debug, 590 ms no release) agora é montada uma vez
					# aqui, atrás da tela de carregamento, e fica no cache de registros: a geometria
					# sobrevive ao chunk de aquecimento descartado e a visita real só a reaproveita.
					var record_began := Time.get_ticks_usec()
					var record_stall := STALL_WORK.begin()
					if not _step_record_build(chunk,record,job,maxf(0.0,budget_usec-(Time.get_ticks_usec()-began))):
						return false
					# Com detalhes: o log mostra QUAL registro pesou (os de 200-600 ms do release de 13/10).
					STALL_WORK.finish("stream.%s.record.%s"%[region_id,record.get("kind","?")],record_stall,
						{"id":str(record.get("id",record.data.get("id",record.data.get("name",record.get("name",""))) if record.get("data") is Dictionary else record.get("name",""))),"model_kind":str(record.get("model_kind","")),
						"zone_id":str(record.get("zone_id","")),"at":str(record.get("position",""))})
					var record_ms := float(Time.get_ticks_usec()-record_began)/1000.0
					if record_ms >= 8.0:
						var slow: Array = Engine.get_meta("slow_stream_records",[])
						if slow.size() < 64: slow.append("%s/%s %.0f ms"%[record.get("kind","?"),record.get("model_kind",record.get("zone_id","")),record_ms])
						Engine.set_meta("slow_stream_records",slow)
					job.index = int(job.index)+1
				else: job.stage = 3
			3:
				# Acabamento "cidade de jogo" (luz noturna, mobiliário, chão, telhados).
				# Só acrescenta/troca material depois que a fonte V1 já montou o chunk.
				if region_id == "harbor":
					if not job.has("dressing"): job.dressing = {"step": 0, "region": self, "chunk": chunk, "rect": rect}
					var dressing_began := STALL_WORK.begin()
					var dressing_step := int(job.dressing.get("step",0))
					var dressing_more: bool = CITY_DRESSING.build_chunk_step(job.dressing)
					# Com o número do passo: na fase 2 (16/10) passos de 42-148 ms apareciam sem dizer qual
					# (noite, postes, escadas, paredes, telhados, lote, lixo...). O prefixo antigo continua igual.
					STALL_WORK.finish_slow("stream.harbor.dressing_step.%d"%dressing_step,dressing_began,2000)
					if not dressing_more:
						# O continue tambem precisa devolver o controle ao esgotar o orcamento.
						if Time.get_ticks_usec()-began >= budget_usec: return false
						continue
					# Depois de todo o acabamento de chão: abre as rampas do Túnel do canal.
					var carve_began := STALL_WORK.begin()
					CANAL_TUNNEL.carve_chunk(chunk,rect)
					STALL_WORK.finish_slow("stream.harbor.carve_tunnel",carve_began,2000)
				elif region_id == "mountain":
					var finish_began := STALL_WORK.begin()
					_build_road_surfaces(chunk,rect)
					_apply_night_lights(chunk)
					STALL_WORK.finish_slow("stream.mountain.road_surfaces",finish_began,2000)
				job.stage = 4
				chunk.set_meta("vegetation_ready_frame", Engine.get_physics_frames())
				# A serra também: a vila e a serraria tinham 1.200+ superfícies por trecho, 97% com sombra (censo 14/10).
				if region_id in ["harbor", "mountain"]: preload("res://world/chunk_shadow/ChunkShadowShell.gd").schedule(chunk)
			_: return true
		if Time.get_ticks_usec()-began >= budget_usec: return int(job.stage) >= 4
	return true

## Sem células pendentes nem construção fatiada em andamento. Testes e ferramentas
## que inspecionam o conteúdo das células vizinhas esperam por isto, não por um
## número fixo de quadros (a construção é espalhada em até 3 ms por quadro).
func is_streaming_idle() -> bool:
	return pending.is_empty() and build_jobs.is_empty()

## Só o chão e a colisão das superfícies (estágio 0) saem já; o resto do chunk vai para a
## frente da fila fatiada. Quem só precisa de chão firme (veículo que vai nascer ou andar
## ali) não deve pagar o chunk inteiro: `_ground_ready` custava 41-73 ms por chamada.
func _ensure_chunk_surfaces(key: Vector2i) -> void:
	if chunks.has(key):
		for index in range(build_jobs.size()):
			if build_jobs[index].key == key:
				if index > 0:
					var job: Dictionary = build_jobs[index]
					build_jobs.remove_at(index)
					build_jobs.push_front(job)
				if int(build_jobs[0].stage) == 0: _run_build_job(build_jobs[0],0.0)
				return
		return
	_build_chunk(key,false)
	# Um trecho aquecido já está completo e não acrescenta job à fila.
	if not build_jobs.any(func(job): return job.key == key): return
	var created: Dictionary = build_jobs.pop_back()
	build_jobs.push_front(created)
	_run_build_job(created,0.0)

## Garante o chunk completo agora (colisão para quem vai pisar nele neste quadro).
func _ensure_chunk(key: Vector2i) -> void:
	if not chunks.has(key):
		_build_chunk(key)
		return
	for index in range(build_jobs.size()-1,-1,-1):
		if build_jobs[index].key == key:
			_run_build_job(build_jobs[index],INF)
			build_jobs.remove_at(index)

## Terreno da serra no trabalhador: corpo em NativeTerrainTasks.gd (delegação de uma linha).
func _terrain_chunk_pending(job: Dictionary, budget_usec: float) -> bool: return _terrain_tasks_part._terrain_chunk_pending(job, budget_usec)
func _terrain_task_wanted(job: Dictionary) -> bool: return _terrain_tasks_part._terrain_task_wanted(job)
func _start_terrain_task(job: Dictionary) -> void: _terrain_tasks_part._start_terrain_task(job)
func _prefetch_terrain_tasks() -> void: _terrain_tasks_part._prefetch_terrain_tasks()
func _collect_terrain_tasks() -> void: _terrain_tasks_part._collect_terrain_tasks()

## Estágio 0 fatiado do Harbor (30/10): `stream.harbor.surfaces` saía inteiro num quadro, 12–34 ms
## dirigindo a 110–120 km/h no export release. Agora cada passo (ruas, lotes, um pedaço de Land, mar,
## túnel, costa, um polígono de extra_land, matas, concreto do porto) roda e o cursor fica no job.
## Mesma ordem, mesmos argumentos, mesmos filhos do chunk: o resultado final é o de antes.
## Pelos membros, como `_surface_terrain_data`: testes sobrescrevem _build_surfaces com 3 argumentos.
## Sem job (chamada direta) ou com orçamento 0/INF (_ensure_chunk_surfaces, chunk imediato) termina tudo.
var _surface_slice_job: Dictionary = {}
var _surface_slice_budget := INF
var _surface_slice_began := 0

func _build_surfaces(chunk: Node3D, rect: Rect2, key: Vector2i) -> void:
	if region_id == "harbor":
		var job: Dictionary = _surface_slice_job
		var state: Dictionary = job.get("harbor_surfaces", {})
		if state.is_empty(): state = {"step": 0, "chunk": chunk, "rect": rect}
		var done := _harbor_surfaces_step(state, _surface_slice_budget, _surface_slice_began)
		if job.is_empty(): return
		if done: job.erase("harbor_surfaces")
		else: job["harbor_surfaces"] = state
	else:
		# Estas células autoradas são os vãos de água do HarborMountainConnector e da
		# HarborBridgeCrossing.
		# O WorldConnection3D fornece o tabuleiro/encontro compartilhado e o Harbor é dono
		# da água embaixo. Montar terreno genérico de montanha aqui criaria uma
		# parede sólida atravessando a rota original da ponte quando as duas regiões residem.
		if _mountain_owns_terrain(key):
			var shore_edges := preload("res://world/regions/MountainBridgeShore.gd").frontiers(key,MOUNTAIN_BRIDGE_VOID_CELLS,_mountain_owns_terrain)
			terrain.build_chunk(chunk,rect,shore_edges,_surface_terrain_data)
			# Serra ilha: o muro abre onde passa estrada ou trilha (na costa, só a ponte leste).
			preload("res://world/regions/ScenarioBoundary3D.gd").build_mountain(chunk,rect,terrain.surface_height_at,func(point: Vector2) -> bool: return route_geometry.contains(Vector3(point.x,0,point.y),8.0))

const HARBOR_SURFACE_STEP_NAMES := ["roads","cover","land","ocean","tunnel","coast","extra_land","woodland","coast_woodland","port_apron"]
const HARBOR_SURFACE_STEPS := 10

## Estágio fatiado das superfícies do Harbor (spans stream.harbor.surfaces.<passo>): corpo em NativeRoadSurfaces.gd.
func _harbor_surfaces_step(state: Dictionary, budget_usec: float, began: int) -> bool: return _road_surfaces_part._harbor_surfaces_step(state, budget_usec, began)
func _harbor_surface_substep(state: Dictionary) -> bool: return _road_surfaces_part._harbor_surface_substep(state)

func _build_record(chunk: Node3D, record: Dictionary) -> void: _record_builders_part._build_record(chunk, record)

func _mountain_center_marking(chunk: Node3D, center: Vector3, offset: Vector3) -> void: _record_builders_part._mountain_center_marking(chunk, center, offset)

func _mountain_owns_terrain(key: Vector2i) -> bool:
	# O MountainTerrain3D só monta células inteiras de 64 m. Uma célula é da Mountain quando o centro dela é:
	# "toca a Mountain" também pegava a fileira -2, cuja parte da Mountain é uma faixa de 3 m ao sul de
	# LOGICAL_NORTH_LIMIT_Z enquanto o resto é Harbor. A coluna 7 mantém 8 m a oeste da emenda, onde
	# o Harbor não autora chão, estrada nem calçada (tests/test_bridge_approach_terrain.gd).
	if key in MOUNTAIN_BRIDGE_VOID_CELLS: return false
	var center := (Vector2(key)+Vector2.ONE*.5)*CELL
	# Serra ilha: célula inteira a mais de 20 m mar adentro não tem terreno (antes ia sem fim para leste
	# e norte). Meia diagonal da célula = 45 m.
	if TERRAIN.island_enabled() and preload("res://world/shape/WorldShape.gd").field_distance("mountain", center) < -(CELL*.71+20.0): return false
	return WORLD_CONNECTION.logical_region(Vector3(center.x,0,center.y)) == "mountain"

## Scripts de arte carregados sob demanda ficam presos aqui. O pré-aquecimento os
## carrega e descarta os chunks; sem referência o recurso saía do cache e a primeira
## visita real relia do disco (travadas de 0,9–1,8 s em Mountain, 2026-09-24).
var _held_resources: Dictionary = {}
func _held_load(path: String) -> Resource:
	if not _held_resources.has(path): _held_resources[path] = load(path)
	return _held_resources[path]

func _dressing_reserved(point: Vector2, radius: float) -> bool:
	if terrain == null or terrain.is_reserved(point,radius): return true
	if region_id == "mountain" and MOUNTAIN_JEEP_COURSE.is_reserved(point,radius): return true
	var key := _cell(Vector3(point.x,0,point.y))
	for x in range(-1,2):
		for z in range(-1,2):
			for record in records.get(key+Vector2i(x,z),[]):
				if record.kind != "tree": continue
				var tree_point := Vector2(record.position.x,record.position.z)
				if point.distance_to(tree_point) < radius+1.2: return true
	return false

## Piso do porto sul (OriginalPortSurface): cais PNG da HarborPaving em vez da cor lisa. A malha e o
## trimesh são os mesmos; o material é triplanar em espaço de mundo, então os UVs não mudam nada.
## GETECO_PAINTED_GROUND=0 volta à cor lisa (mesmo interruptor dos pisos do editor).
func _port_surface_material() -> Material:
	if preload("res://world/editing/WorldGroundFactory.gd").painted_enabled:
		var paving := preload("res://world/urban_detail/HarborPaving.gd")
		return paving.material(paving.FINISH_COLORS.quay,"quay")
	return _material(Color("737b69"))

## Parque Lume e vila dos caminhoneiros descem o próprio chão até o mato no contorno externo da
## faixa/anel. O Land (e o chão autorado) perde essa área, como o skate faz com o retângulo dele;
## no lugar fica um substituto do mesmo mato, visível só enquanto o lugar não está montado (o
## parque só existe a menos de 170 m e a vila some com a região inativa). Sem isso, de longe,
## o recorte viraria um buraco. GETECO_PLACE_GROUND_CUT=0 desliga (o lugar volta a ficar por cima).
func _place_ground_cut(chunk: Node3D, rect: Rect2, ground_cover: Array[PackedVector2Array]) -> void:
	if region_id != "harbor" or not GROUND_CUT.enabled: return
	var clip := GROUND_CUT.counter_clockwise(GROUND_CUT.rect_polygon(rect))
	for place in [preload("res://world/places/amusement_park/ParkLumeGround.gd"), preload("res://gameplay/urban_v1/TruckersVillageGround.gd")]:
		if not place.cut_enabled or not rect.intersects(place.SITE_BOUNDS): continue
		var standin: Array[PackedVector2Array] = []
		for polygon: PackedVector2Array in place.world_cover():
			if not GROUND_CUT.bounds(polygon).intersects(rect): continue
			var pieces: Array[PackedVector2Array] = []
			for piece in Geometry2D.intersect_polygons(GROUND_CUT.counter_clockwise(polygon),clip):
				if piece.size() >= 3 and not Geometry2D.is_polygon_clockwise(piece): pieces.append(piece)
			# O substituto só onde ninguém mais desenha (ruas, lotes) e sem repetir anel já coberto.
			standin.append_array(GROUND_CUT.subtract_exact(pieces,ground_cover))
			ground_cover.append_array(pieces)
		var mesh := GROUND_CUT.flat_mesh(standin,0.0,1.0)
		if mesh == null: continue
		var meadow := MeshInstance3D.new()
		meadow.name = place.STANDIN_NAME
		meadow.mesh = mesh
		# Mesmo mato do Land neste trecho (_land_piece): retângulo da mata ou o chão base.
		var woodland := Rect2(-430,-160,350,318).encloses(rect.intersection(place.SITE_BOUNDS))
		meadow.material_override = preload("res://activities/motocross/MotocrossGroundDetail.gd").ground_material() if woodland else _material(Color("737b69"))
		meadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		meadow.visible = not place.site_shown
		meadow.add_to_group(place.STANDIN_GROUP)
		chunk.add_child(meadow)

func _authored_surface(chunk: Node3D, polygon: PackedVector2Array, woodland := false, cover: Array[PackedVector2Array] = []) -> void:
	polygon = GROUND_CUT._without_degenerate_edges(polygon)
	if polygon.size() < 3: return
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty(): return
	var vertices := PackedVector3Array()
	for index in polygon.size(): vertices.append(Vector3(polygon[index].x,0,polygon[index].y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,indices.size(),3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		# O recorte de buracos pode reter vértices coincidentes da ponte antes do corte de cobertura.
		if (b-a).cross(c-a).length_squared() == 0.0: continue
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(a.x,a.z))
		surface.add_vertex(a)
		if (b-a).cross(c-a).y > 0:
			surface.set_uv(Vector2(c.x,c.z)); surface.add_vertex(c)
			surface.set_uv(Vector2(b.x,b.z)); surface.add_vertex(b)
		else:
			surface.set_uv(Vector2(b.x,b.z)); surface.add_vertex(b)
			surface.set_uv(Vector2(c.x,c.z)); surface.add_vertex(c)
	var mesh := MeshInstance3D.new()
	mesh.name = "SerenoForestFloor" if woodland else "OriginalPortSurface"
	mesh.mesh = surface.commit()
	mesh.material_override = preload("res://world/places/fishing/FishingGround.gd").material() if woodland else _port_surface_material()
	if woodland: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(mesh)
	mesh.create_trimesh_collision()
	for body in mesh.get_children():
		if body is StaticBody3D: body.collision_layer = 1; body.collision_mask = 0
	# O apoio continua contínuo sob os acabamentos de rua/lote; só o chão exposto
	# é renderizado. O colisor foi montado antes de trocar a malha visual.
	if not cover.is_empty():
		var exposed := GROUND_CUT.flat_mesh(GROUND_CUT.subtract_exact([polygon],cover),0.0,1.0)
		if exposed == null: mesh.visible = false
		else: mesh.mesh = exposed
func _building(chunk: Node3D, data: Dictionary) -> void: _record_builders_part._building(chunk, data)

func _mountain_place(chunk: Node3D, data: Dictionary) -> void: _record_builders_part._mountain_place(chunk, data)

func _original_facade(chunk: Node3D,data: Dictionary) -> void: _record_builders_part._original_facade(chunk, data)

func _prepare_forest() -> void: _record_builders_part._prepare_forest()

func _build_ship(chunk: Node3D) -> void: _record_builders_part._build_ship(chunk)

func _build_northstar_crane(chunk: Node3D, point: Vector2) -> void: _record_builders_part._build_northstar_crane(chunk, point)

func _ship_rail(chunk: Node3D,a: Vector2,b: Vector2) -> void: _record_builders_part._ship_rail(chunk, a, b)

static func _helipad_reserved(point: Vector2) -> bool:
	# Novo pátio de pouso e corredor de acesso, incluindo a área da copa dos pinheiros.
	if point.distance_to(Vector2(6180,-2832))<125: return true
	var walk := PackedVector2Array([Vector2(6410,-2660),Vector2(6270,-2720),Vector2(6180,-2770),Vector2(6180,-2782.4)])
	for i in range(walk.size()-1):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,walk[i],walk[i+1]))<65: return true
	return false

static func _fort_exit_reserved(point: Vector2) -> bool:
	var exit_position: Vector3 = preload("res://gameplay/urban_v1/fort/MountainFortExit3D.gd").WORLD_POSITION
	# Reserva a formação e a aproximação inteira da entrada antes de posicionar as árvores.
	return Rect2(Vector2(exit_position.x-6.5,exit_position.z-6.5),Vector2(13.0,13.0)).has_point(point)
## Registra em `slow_stream_records` uma etapa do streaming que passou de `limit_usec`
## (só para diagnóstico com a sonda; não tem efeito sem a meta).
func _note_slow(what: String, since_usec: int, limit_usec: int) -> void:
	var spent := Time.get_ticks_usec()-since_usec
	if spent < limit_usec or not Engine.has_meta("slow_stream_records"): return
	var slow: Array = Engine.get_meta("slow_stream_records")
	slow.append("PROCESS %s %.0f ms"%[what,spent/1000.0])
	Engine.set_meta("slow_stream_records",slow)
# O construtor da ponte fornece o piso do corredor sem mudar o grafo regional.
