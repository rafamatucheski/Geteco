extends Node3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const LOADING_TURBO := preload("res://runtime/LoadingTurbo.gd")
## Native production geography. Geometry/physics load only near the player.
const MOUNTAIN_FACTORY := preload("res://world/mountain_detail/MountainDetailFactory.gd")
const MOUNTAIN_FORGE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const FORGE_HERMIT := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
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
# Cell 5 contains the Harbor-side curved approach. Loading mountain terrain
# there while both regions are resident creates an elevated wall across the lane.
const MOUNTAIN_BRIDGE_VOID_CELLS := [Vector2i(5,-5),Vector2i(6,-5),Vector2i(7,-5),Vector2i(8,-5)]
# Mountain terrain belongs to Mountain's logical territory (WorldConnection3D.logical_region):
# east of the seam and north of Harbor's northern limit. Harbor owns the ground west of the seam,
# where Mountain has no authored geography; building procedural hills there covered Harbor roads
# (island_esplanade at 292.6,-114.2) whenever Mountain became resident near the bridge.
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

## Constrói e descarta uma vez cada célula com conteúdo, sob a cortina de
## carregamento: texturas/malhas procedurais geradas na primeira aparição
## (acabamento urbano até 226 ms, porto sul 399 ms) ficam em cache e não
## travam a direção. Células já carregadas são preservadas.
func prewarm() -> void:
	for key in records.keys():
		if chunks.has(key): continue
		_build_chunk(key)
		var chunk: Node3D = chunks[key]
		_hold_file_resources(chunk)
		_suspend_chunk_mechanisms(chunk)
		_detach_cached_records(chunk)
		chunks.erase(key)
		chunk.free()
	chairlifts = chairlifts.filter(func(lift): return is_instance_valid(lift))

## Warm shared resources using the existing streaming budget and resident cells.
## The menu must keep drawing/input alive while these offscreen cells warm up.
func prewarm_incremental() -> void:
	# Finish resident jobs first. Otherwise an offscreen warm-up cell could
	# consume a pending resident key, then discard geometry the camera needs.
	while not is_streaming_idle():
		await get_tree().process_frame
	for key in records.keys():
		if chunks.has(key): continue
		_build_chunk(key, false, true)
		var chunk: Node3D = chunks[key]
		while build_jobs.any(func(job): return job.key == key):
			await get_tree().process_frame
		if region_id == "harbor": TUNNEL_CUTAWAY.prime(chunk, self, Rect2(key.x*CELL,key.y*CELL,CELL,CELL))
		_hold_file_resources(chunk)
		_suspend_chunk_mechanisms(chunk)
		_detach_cached_records(chunk)
		chunks.erase(key)
		chunk.queue_free()
		await get_tree().process_frame
	chairlifts = chairlifts.filter(func(lift): return is_instance_valid(lift))

## Os poucos trechos construídos para aquecer o túnel sobrevivem escondidos e sem física.
## A primeira visita usa os mesmos nós; não paga outra construção completa.
const MAX_WARM_TUNNEL_CHUNKS := 8
var _warm_tunnel_chunks: Dictionary = {}
var _tunnel_corridor_primed := false
func prime_tunnel_corridor() -> void:
	if _tunnel_corridor_primed: return
	var began := STALL_WORK.begin()
	while not is_streaming_idle():
		await get_tree().process_frame
	var reach: Rect2 = TUNNEL_CUTAWAY.corridor_rect()
	var primed_chunks := 0
	var keys: Array[Vector2i] = []
	for x in range(floori(reach.position.x/CELL), ceili(reach.end.x/CELL)):
		for z in range(floori(reach.position.y/CELL), ceili(reach.end.y/CELL)):
			keys.append(Vector2i(x,z))
	for key in keys:
		var rect := Rect2(key.x*CELL,key.y*CELL,CELL,CELL)
		if chunks.has(key): continue
		_build_chunk(key, false, true)
		var chunk: Node3D = chunks[key]
		while build_jobs.any(func(job): return job.key == key):
			await get_tree().process_frame
			if not is_inside_tree() or is_queued_for_deletion(): return
		TUNNEL_CUTAWAY.prime(chunk, self, rect)
		_hold_file_resources(chunk)
		_suspend_chunk_mechanisms(chunk)
		chunks.erase(key)
		if _warm_tunnel_chunks.size() < MAX_WARM_TUNNEL_CHUNKS:
			chunk.set_meta("warm_tunnel_key", key)
			_keep_warm_tunnel_chunk(chunk)
		else:
			_detach_cached_records(chunk)
			chunk.queue_free()
		primed_chunks += 1
		await get_tree().process_frame
	_tunnel_corridor_primed = true
	STALL_WORK.finish("tunnel.cutaway.prime_corridor", began, {"chunks": primed_chunks})

func _keep_warm_tunnel_chunk(chunk: Node3D) -> void:
	chunk.set_meta("warm_tunnel_process_mode", chunk.process_mode)
	chunk.process_mode = Node.PROCESS_MODE_DISABLED
	chunk.hide()
	_warm_tunnel_chunks[chunk.get_meta("warm_tunnel_key")] = chunk

## Recursos vindos de arquivo (scripts, malhas, materiais, fontes) usados pelo chunk
## pré-aquecido. Sem referência viva eles saíam do cache ao descartar o chunk e a
## primeira visita real relia do disco. Recursos procedurais (sem caminho) não entram.
func _hold_file_resources(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		_hold_resource(node.get_script())
		# Modelo instanciado de .tscn: as malhas embutidas vivem enquanto a cena vive.
		if not node.scene_file_path.is_empty() and not _held_resources.has(node.scene_file_path):
			_held_resources[node.scene_file_path] = load(node.scene_file_path)
		if node is MeshInstance3D:
			_hold_resource(node.mesh)
			_hold_resource(node.material_override)
		elif node is Label3D:
			_hold_resource(node.font)
		for child in node.get_children(): stack.append(child)

func _hold_resource(resource: Variant) -> void:
	if resource is Resource and not (resource as Resource).resource_path.is_empty() and not (resource as Resource).resource_path.contains("::"):
		_held_resources[(resource as Resource).resource_path] = resource

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
func _prepare() -> void:
	var records_started := STALL_WORK.begin()
	CITY_DRESSING.invalidate_context(self)
	if region_id == "harbor":
		_record(CEMETERY.world_position(),{"kind":"cemetery","position":CEMETERY.world_position()})
		_record(CEMETERY.world_position(),{"kind":"harbor_dressing","zone_id":"cemetery","position":CEMETERY.world_position()})
		for polygon in SOUTH_PORT.extra_surfaces(source_data.harbor_land):
			var metric := PackedVector2Array()
			for point in polygon: metric.append(point*SCALE)
			extra_land.append(metric)
		extra_land.append_array(preload("res://world/places/fishing/FishingRuralLayout.gd").extra_surfaces())
		for record in SOUTH_PORT.records(): _record(record.position,record)
		var south_ship_center: Vector2 = SOUTH_PORT_LAYOUT.SHIP.get_center()*SCALE
		_record(Vector3(south_ship_center.x,0,south_ship_center.y),{"kind":"south_port_ship_detail"})
		for rail in SOUTH_PORT.rails():
			var a := CATALOG._at(rail[0],region_id)
			var b := CATALOG._at(rail[1],region_id)
			var steps := maxi(1,ceili(a.distance_to(b)/16.0))
			for i in steps:
				var start := a.lerp(b,float(i)/steps)
				var end := a.lerp(b,float(i+1)/steps)
				_record((start+end)*.5,{"kind":"south_port_rail","a":start,"b":end})
		for row in source_data.harbor_roads:
			var points := PackedVector3Array()
			for point in row.points: points.append(CATALOG._at(Vector2(point[0],point[1]),region_id))
			_add_road(row.id,points,float(row.width)*SCALE)
		if preload("res://runtime/FishingLocation.gd").enabled():
			var fishing_access := preload("res://world/places/fishing/FishingRuralLayout.gd")
			_add_road(fishing_access.ROAD_ID,fishing_access.road_points(),preload("res://runtime/FishingLocation.gd").ROAD_WIDTH,"earth")
		for building in source_data.harbor_buildings:
			var point := CATALOG._at(Vector2(building.position[0],building.position[1]),region_id)
			var size := Vector2(building.size[0],building.size[1])*SCALE
			var entry: Dictionary = building.duplicate()
			entry["position"] = point
			entry["size"] = size
			buildings.append(entry)
			_record(point,{"kind":"building","data":entry})
		if not Engine.get_meta("curitiba_cellar_baseline",false):
			var cellar := preload("res://world/places/curitiba_cellar/CuritibaCellarPlace.gd").definition_data()
			var cellar_building := {"id":"CuritibaCellar","position":cellar.exterior_position,"size":cellar.size,"height":4.1,"name":"Curitiba Cellar","kind":"shop"}
			buildings.append(cellar_building)
			_record(cellar.exterior_position,{"kind":"building","data":cellar_building})
		if not Engine.get_meta("arcade_baseline",false):
			var arcade := preload("res://world/places/arcade/ArcadePlace.gd").definition_data()
			var arcade_building := {"id":"Fagulha","position":arcade.exterior_position,"size":arcade.size,"height":3.9,"name":"Fagulha","kind":"shop"}
			buildings.append(arcade_building)
			_record(arcade.exterior_position,{"kind":"building","data":arcade_building})
		_record(CATALOG._at(Vector2(-750,550),region_id),{"kind":"salvage","position":CATALOG._at(Vector2(-750,550),region_id)})
		_record(CATALOG._at(Vector2(-750,550),region_id),{"kind":"harbor_dressing","zone_id":"salvage","position":CATALOG._at(Vector2(-750,550),region_id)})
		_record(CATALOG._at(Vector2(7700,1700),region_id),{"kind":"harbor_dressing","zone_id":"cobra","position":CATALOG._at(Vector2(7700,1700),region_id)})
		_record(CATALOG._at(Vector2(3790,400),region_id),{"kind":"harbor_bridge","position":CATALOG._at(Vector2(3790,400),region_id)})
		for prop_data in HARBOR_PROP.records():
			var prop_position:=CATALOG._at(prop_data.point,region_id)
			_record(prop_position,{"kind":"harbor_prop","position":prop_position,"data":prop_data})
		_record(CATALOG._at(Vector2(3570,1400),region_id),{"kind":"ship"})
		# A 2ª mesa da Anchor (685,1132) e a da Early Shift (6255,-1238) ficavam na frente das portas da
		# Corner Diner e da Service Cafe e travavam a entrada (test_door_audit, 18/10); foram para o lado.
		for venue in [
			["anchor",Color("b96a46"),Vector2(555,1132),Vector2(615,1140)],
			["tideline",Color("477f7d"),Vector2(5735,1644),Vector2(5845,1644)],
			["early_shift",Color("68784a"),Vector2(6145,-1238),Vector2(6200,-1250)]]:
			for table_index in 2:
				var table_position := CATALOG._at(venue[2+table_index],region_id)
				_record(table_position,{"kind":"harbor_restaurant","venue_id":venue[0],"fabric":venue[1],"table_index":table_index,"position":table_position})
		for container in source_data.port_containers:
			var point := CATALOG._at(Vector2(container.position[0],container.position[1]),region_id)
			_record(point,{"kind":"container","position":point,"size":Vector2(container.size[0],container.size[1])*SCALE})
	else:
		var controls := PackedVector2Array()
		for point in source_data.mountain_control_points: controls.append(Vector2(point[0],point[1]))
		var curve := Curve2D.new()
		curve.bake_interval = 16
		for i in controls.size():
			var tangent := Vector2.ZERO
			if i > 0 and i < controls.size()-1: tangent = (controls[i+1]-controls[i-1]).normalized()*minf(controls[i-1].distance_to(controls[i]),controls[i+1].distance_to(controls[i]))*.38
			curve.add_point(controls[i],-tangent,tangent)
		var points := PackedVector3Array()
		for distance in range(0,int(curve.get_baked_length()),64): points.append(CATALOG._at(curve.sample_baked(distance,true),region_id))
		points.append(CATALOG._at(controls[-1],region_id))
		_add_road("mountain_pass",points,140*SCALE)
		# Service tracks meet the pass at its authored centreline; the dirt bed is
		# visually clipped to the asphalt edge when its first segment is built.
		for track in [
			[Vector2(6250,340),Vector2(6850,690),Vector2(7350,620),Vector2(7850,580),Vector2(8350,480),Vector2(8700,460)],
			[Vector2(6950,-250),Vector2(7150,-350),Vector2(7450,-320),Vector2(7750,-220)],
			[Vector2(6120,320),Vector2(6040,100),Vector2(6060,-150),Vector2(6200,-320)],
			[Vector2(6850,-2450),Vector2(7020,-2500),Vector2(7140,-2545),Vector2(7140,-2700)],
			[Vector2(6901,-1566),Vector2(6840,-1740),Vector2(7010,-1870),Vector2(7240,-1760),Vector2(7500,-1760),Vector2(7700,-1760),Vector2(7790,-1850),Vector2(7700,-1940)]
		]:
			var branch := PackedVector3Array()
			for point in track: branch.append(CATALOG._at(point,region_id))
			_add_road("mountain_track_%d"%roads.size(),branch,60*SCALE if roads.size()==1 else 3.25,"earth" if roads.size()==1 else "asphalt")
		for definition in CATALOG.definitions():
			if definition.region == region_id: _record(definition.exterior_position,{"kind":"mountain_place","data":definition})
		# Three physical entrances share the bunkhouse interior, never their return origin.
		for index in 2:
			var shelter := CATALOG.get_definition("lumberjack_shelter")
			shelter["access_id"] = "lumberjack_shelter_%d" % (index + 2)
			shelter.exterior_position = CATALOG.shelter_access_exterior(index)
			_record(shelter.exterior_position, {"kind":"mountain_place", "data":shelter})
		for lamp_point in [Vector2(6340,500),Vector2(6910,755),Vector2(7140,-455)]:
			var lamp_position := CATALOG._at(lamp_point,region_id)
			_record(lamp_position,{"kind":"mountain_road_lamp","position":lamp_position})
	if region_id == "harbor":
		for definition in CATALOG.definitions():
			if definition.region == region_id and definition.id in ["westgate_garden","quayside_house","cemetery_keeper","port_boss_garage"] + CATALOG.SEWERS.ids(): _record(definition.exterior_position,{"kind":"original_facade","data":definition})
		for zone_record in HARBOR_ROUTE_FACTORY.get_zone_records():
			_record(zone_record.position, zone_record)
		for public_record in HARBOR_PUBLIC_REALM.records():
			var public_position := CATALOG._at(public_record.point, region_id)
			_record(public_position, {"kind":"harbor_public_realm", "zone_id":public_record.zone_id, "position":public_position})
	if region_id == "mountain":
		for lake in [["secret",Vector2(5450,-1150)],["alpine",Vector2(7000,0)]]:
			_record(CATALOG._at(lake[1],region_id),{"kind":"lake","variant":lake[0],"position":CATALOG._at(lake[1],region_id)})
		_record(CATALOG._at(Vector2(5450,-1150),region_id),{"kind":"cargo_plane","position":CATALOG._at(Vector2(5450,-1150),region_id)})
		_record(CATALOG._at(Vector2(6350,560),region_id),{"kind":"sawmill_yard"})
		_record(CATALOG._at(Vector2(7560,-1650),region_id),{"kind":"mountain_village"})
		_record(MOUNTAIN_FORGE.CENTER,{"kind":"mountain_forge","position":MOUNTAIN_FORGE.CENTER})
		_record(FORGE_HERMIT.CENTER,{"kind":"forge_hermit_cabin","position":FORGE_HERMIT.CENTER})
		for record in MOUNTAIN_FACTORY.get_environmental_records():
			_record(record.position,record)
		_prepare_forest()
		_revise_mountain_routes()
	for entry in CATALOG.access_points():
		if entry.region == region_id: entries.append(entry)
	STALL_WORK.finish("region.prepare.records." + region_id, records_started, {})
	if region_id == "harbor":
		harbor_road_geometry = HARBOR_ROAD_GEOMETRY.new()
		var geometry_started := STALL_WORK.begin()
		harbor_road_geometry.configure(roads)
		STALL_WORK.finish("region.prepare.roads", geometry_started, {})
		harbor_urban_surface = HARBOR_URBAN_SURFACE.new()
		geometry_started = STALL_WORK.begin()
		harbor_urban_surface.configure()
		STALL_WORK.finish("region.prepare.urban_surfaces", geometry_started, {})
		geometry_started = STALL_WORK.begin()
		harbor_facade_ground = preload("res://world/urban_detail/HarborFacadeGround.gd").footprints()
		harbor_dressing_ground.clear()
		for cell_records in records.values():
			for record in cell_records:
				if record.get("kind","") == "harbor_dressing":
					var origin: Vector3 = record.position
					harbor_dressing_ground.append_array(HARBOR_DRESSING.ground_footprints(record.zone_id,Vector2(origin.x,origin.z)))
		harbor_ocean = preload("res://world/regions/HarborOcean.gd").new()
		STALL_WORK.finish("region.prepare.footprints", geometry_started, {})
		geometry_started = STALL_WORK.begin()
		harbor_ocean.configure(source_data.harbor_land,extra_land)
		STALL_WORK.finish("region.prepare.ocean", geometry_started, {})
		coastal_protection = preload("res://world/regions/CoastalProtection.gd").new()
		geometry_started = STALL_WORK.begin()
		coastal_protection.configure(source_data,extra_land,harbor_road_geometry._layers[0].polygons)
		STALL_WORK.finish("region.prepare.coast", geometry_started, {})
	if region_id == "mountain":
		terrain = TERRAIN.new()
		var reservations: Array = CATALOG.definitions().duplicate()
		reservations.append_array(entries)
		var terrain_roads: Array[Dictionary] = roads + walkways
		# These Harbor routes enter Mountain's resident terrain at the northbank
		# gateway. Reserve the authored roadway so its hillside mesh/collider
		# cannot rise into the approach while both regions are loaded.
		for avenue in source_data.harbor_roads:
			if avenue.id not in ["northbank_gateway_avenue","eastgate_drive","map2_highway_outbound"]: continue
			var avenue_points := PackedVector3Array()
			for point in avenue.points:
				avenue_points.append(CATALOG._at(Vector2(point[0],point[1]),"harbor"))
			terrain_roads.append({"id":avenue.id,"points":avenue_points,"width":float(avenue.width)*SCALE})
		terrain.configure(terrain_roads,reservations,[MOUNTAIN_FORGE.FOOTPRINT,FORGE_HERMIT.FOOTPRINT])
func map_routes() -> Array[Dictionary]:
	return roads + walkways

func _revise_mountain_routes() -> void:
	# Generate the original forest first, then clear only the changed corridors.
	# Rejection during seeded placement would move trees throughout the region.
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
	# A player-accessible dead end with parking, never an ambient bus/truck route.
	# Kept here so the world-editor reconstruction preserves the same policy.
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
				# Match the two 3.875 m Harbor lanes, easing to the authored pass width.
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
	# The production streaming budget requests the occupied cell and its eight
	# neighbours. retention_radius remains a wider grace band while moving.
	for x in range(-1,2):
		for z in range(-1,2):
			var key := cell+Vector2i(x,z)
			if not chunks.has(key): pending.append(key)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return Vector2(a-cell).length_squared()<Vector2(b-cell).length_squared())
	# The occupied cell gets collision before admission; records and dressing remain
	# queued so crossing a cell boundary cannot synchronously build the whole chunk.
	pending.erase(cell)
	if complete_focus_chunk: _ensure_chunk(cell)
	else: _ensure_chunk_surfaces(cell)
	preload("res://world/regions/DeveloperViewCells.gd").enqueue(self)
	_trim_chunks(cell)

func prepare_collision_at(point: Vector3) -> bool:
	# Emergency vehicles are physical actors and may briefly take a neighbouring
	# route while the player remains still.  Admit their occupied/next cell before
	# physics instead of letting them drive over a road whose streamed floor is
	# still absent.
	var key := _cell(point)
	var had_chunk := chunks.has(key)
	var collision_began := STALL_WORK.begin()
	_ensure_chunk_surfaces(key)
	STALL_WORK.finish_slow("stream.%s.prepare_collision"%region_id,collision_began,2000)
	if not had_chunk and chunks.has(key): _residency_dirty = true
	return chunks.has(key)

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
	# Suspend before removing support; ProductionWorld resumes after its ground check.
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

## Registros que custam 40-80 ms para montar (a vila e a serraria da montanha): o nó pronto é
## guardado ao liberar o chunk e reaproveitado na próxima visita; o pré-aquecimento monta cada um
## uma vez. Só entra em cache quem ainda não tem pai (não está em uso em outro chunk).
## south_port_ship_detail (cordame e acabamento do Santa Mare): 32-59 ms ao entrar no cais (release, 15/10).
const CACHED_RECORDS := ["mountain_village","mountain_forge","forge_hermit_cabin","sawmill_yard","harbor_public_realm","lake","ship","south_port_ship_detail"]
## A carga do Santa Mare custava 590 ms num quadro ao chegar perto (release, 2026-10-13). Montada uma vez
## no pré-aquecimento e reaproveitada como os registros acima. Paletes e tambores (supplies, 50-87 ms cada)
## e os guindastes do cais (crane, 15-28 ms) pesavam igual na travessia e no porto do release de 15/10;
## são estáticos (sem processo, sem saque, sem luz), como a carga.
const CACHED_PORT_MODELS := ["ship_cargo","supplies","crane"]
## Medido em 8 sessões de release (2026-10-12/13): tudo que montou em 50 ms ou mais num quadro.
## Tipos inteiros quando são poucos registros; dos 66 prédios e 131 props só os medidos, para não
## segurar a cidade inteira na memória nem alongar demais o carregamento.
## harbor_dressing entra porque a grama da Cobra agora é espalhada antes de o nó ser guardado
## (RetainedRegionPreparation cede um quadro) e espera a árvore se for chamada fora dela.
## mountain_jeep_scenery (portais e lombadas da trilha do jipe): 24-32 ms num quadro já jogável, na serra e
## na travessia (release, fase 2 de 16/10); estático, sem processo nem luz.
const CACHED_KINDS_MEASURED := ["container","salvage","mountain_place","harbor_dressing","mountain_jeep_scenery","harbor_route_zone"]
const CACHED_BUILDING_IDS := ["NorthFireStation","BridgeCourtWest","PorchHouse","BridgeQuayHouse","BridgeCourtEast",
	"NorthbankFront0","NorthbankFront1","NorthFrontage2","NorthFrontage3","new_1790432236_682_2325181222"]
## harbor_prop medido a 381 ms (posição do registro no chão, x/z).
const CACHED_PROP_POINTS := [Vector2(391.9375,-247.5)]

func _is_cached_record(record: Dictionary) -> bool:
	var kind := str(record.kind)
	if kind in CACHED_RECORDS or kind in CACHED_KINDS_MEASURED: return true
	if kind == "building" and record.get("data") is Dictionary:
		return str(record.data.get("id","")) in CACHED_BUILDING_IDS
	if kind == "harbor_prop" and record.get("position") is Vector3:
		var at := Vector2(record.position.x, record.position.z)
		return CACHED_PROP_POINTS.any(func(point: Vector2): return point.distance_to(at) < 0.5)
	return str(record.kind) == "south_port_model" and str(record.get("model_kind","")) in CACHED_PORT_MODELS
var _record_cache: Dictionary = {}

func _record_cache_key(record: Dictionary) -> String:
	var key := "%s|%s|%s"%[region_id,str(record.kind),str(record.get("position",Vector3.ZERO))]
	# Prédios guardam id e posição em `data`: sem isto todos caíam na chave (0, 0, 0) e um reaproveitaria
	# os nós de outro.
	if record.get("data") is Dictionary:
		key += "|%s|%s"%[str(record.data.get("id","")),str(record.data.get("position",""))]
	var pieces: Array = [record.get("editor_piece_only", []), record.get("editor_piece_exclude", []), record.get("editor_piece_ids", [])]
	if pieces.any(func(ids): return not ids.is_empty()):
		key += "|pieces=" + JSON.stringify(pieces).sha256_text()
	return key

func _build_record_cached(chunk: Node3D, record: Dictionary) -> void:
	if not _is_cached_record(record):
		_build_record(chunk,record)
		return
	var key := _record_cache_key(record)
	if _record_cache.has(key):
		var nodes: Array = _record_cache[key]
		var usable := not nodes.is_empty()
		for node in nodes:
			if not is_instance_valid(node) or node.get_parent() != null: usable = false
		if usable:
			for node in nodes: chunk.add_child(node)
			return
		# Entrada substituída: limpar só restos detached, nunca o grupo ativo.
		for node in nodes:
			if is_instance_valid(node) and node.get_parent() == null: node.free()
	var before := chunk.get_child_count()
	_build_record(chunk,record)
	var built: Array = []
	for index in range(before,chunk.get_child_count()):
		var node := chunk.get_child(index)
		node.set_meta("record_cache_key",key)
		built.append(node)
	_record_cache[key] = built

## Um registro caro também precisa ceder o quadro; limitar só a fila não limita seu construtor.
## O nó completo passa pelo mesmo editor/cache, sem publicar móveis ou colisões pela metade.
func _step_record_build(chunk: Node3D, record: Dictionary, job: Dictionary, budget_usec: float) -> bool:
	if str(record.kind) != "harbor_route_zone":
		_build_record_cached(chunk, record)
		return true
	var cached: Array = _record_cache.get(_record_cache_key(record), [])
	if not cached.is_empty() and cached.all(func(node): return is_instance_valid(node) and node.get_parent() == null):
		_cancel_record_build(job)
		_build_record_cached(chunk, record)
		return true
	if not job.has("route_zone"):
		job.route_zone = HARBOR_ROUTE_FACTORY.begin_zone(str(record.zone_id))
	if job.route_zone.is_empty():
		job.erase("route_zone")
		return true
	var began := STALL_WORK.begin()
	var done: bool = HARBOR_ROUTE_FACTORY.step_zone(job.route_zone, budget_usec)
	STALL_WORK.finish_slow("stream.harbor.route_zone_step", began, 2000)
	if not done: return false
	var prepared: Dictionary = record.duplicate()
	prepared["prepared_route_zone"] = job.route_zone.root
	_build_record_cached(chunk, prepared)
	job.erase("route_zone")
	return true

func _cancel_record_build(job: Dictionary) -> void:
	if job.has("route_zone"):
		HARBOR_ROUTE_FACTORY.cancel_zone(job.route_zone)
		job.erase("route_zone")

## Tira do chunk os nós em cache antes de liberá-lo, para que sobrevivam.
func _detach_cached_records(chunk: Node3D) -> void:
	if not is_instance_valid(chunk): return
	for child in chunk.get_children():
		if not child.has_meta("record_cache_key"): continue
		var key: String = child.get_meta("record_cache_key")
		# Grupo superseded segue a liberação normal do chunk, sem virar órfão.
		if _record_cache.get(key, []).has(child):
			preload("res://world/chunk_bake/ChunkCellMerge.gd").restore_sources(child)
			chunk.remove_child(child)

## Chunk que sai do raio de retenção: liberar 1000-3000 nós de uma vez custava 40-150 ms
## num quadro (medido dirigindo). O chunk é tirado da lista já e seus filhos são liberados
## em fatias de `RETIRE_BUDGET_USEC` por quadro.
const RETIRE_BUDGET_USEC := 1500.0
var _retiring: Array[Node3D] = []
var _retire_stack: Array[Node] = []

func _retire_chunk(chunk: Node3D) -> void:
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return
	if chunk.has_meta("warm_tunnel_key") and _warm_tunnel_chunks.size() < MAX_WARM_TUNNEL_CHUNKS:
		_keep_warm_tunnel_chunk(chunk)
		return
	var stall_began := STALL_WORK.begin()
	_detach_cached_records(chunk)
	STALL_WORK.finish("retire.detach_cached_records", stall_began, {"region": region_id})
	stall_began = STALL_WORK.begin()
	# Leaf-by-leaf disposal spans frames. Retired rigs must stop animating
	# before a joint is freed while its model still exists in the scene tree.
	chunk.process_mode = Node.PROCESS_MODE_DISABLED
	chunk.hide()
	# Fusão e casca de sombra em andamento param ao ver a marca (o trecho continua na árvore escondido).
	chunk.set_meta(GPU_RELEASE.RETIRED_META, true)
	_retiring.append(chunk)
	STALL_WORK.finish("retire.hide_and_enqueue", stall_began, {"region": region_id})

func _drain_retired() -> void:
	if _retiring.is_empty():
		_cleanup_retired_chairlifts_if_idle()
		return
	var stall_began := STALL_WORK.begin()
	var queued_before := _retiring.size()
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT) if STALL_WORK.session_enabled else 0.0
	_drain_retired_slice()
	_cleanup_retired_chairlifts_if_idle()
	STALL_WORK.finish("retire.drain", stall_began, {"region": region_id, "budget_ms": RETIRE_BUDGET_USEC / 1000.0, "queued_before": queued_before, "queued_after": _retiring.size(), "stack_after":_retire_stack.size(),
		"nodes_removed_during_slice":nodes_before - Performance.get_monitor(Performance.OBJECT_NODE_COUNT) if STALL_WORK.session_enabled else 0.0,
		"destruction_scope":"synchronous_slice; queued_chunk_deletion_runs_later"})

func _drain_retired_slice() -> void:
	var began := Time.get_ticks_usec()
	while not _retiring.is_empty():
		var chunk: Node3D = _retiring[0]
		if not is_instance_valid(chunk):
			_retiring.pop_front()
			_retire_stack.clear()
			continue
		if _retire_stack.is_empty(): _retire_stack.append(chunk)
		# Só libera folhas: poucos filhos diretos não limitam o tamanho da
		# subárvore (um wrapper pode conter um prédio inteiro).
		while not _retire_stack.is_empty():
			var top: Node = _retire_stack.back()
			if not is_instance_valid(top):
				_retire_stack.pop_back()
				continue
			var count := top.get_child_count()
			if count == 0:
				_retire_stack.pop_back()
				if top != chunk:
					top.get_parent().remove_child(top)
					# Dona única de malha vai para a fila de vídeo: soltar centenas de buffers juntos
					# prende a thread principal no driver (emenda da ponte, 16/10).
					if not GPU_RELEASE.adopt_detached_leaf(top): top.free()
			else:
				var last := top.get_child(count-1)
				if last.get_child_count() > 0: _retire_stack.append(last)
				else:
					top.remove_child(last)
					if not GPU_RELEASE.adopt_detached_leaf(last): last.free()
			if Time.get_ticks_usec()-began >= RETIRE_BUDGET_USEC: return
		chunk.queue_free()
		_retiring.pop_front()

## Desmontagem da região (22/10): os trechos em descarte ficavam como filhos escondidos da região, que sai
## da árvore e para de rodar o _process que os liberava. Na volta (a serra perto da ponte remonta o porto a
## cada aproximação) ~2.400 nós de trechos velhos reentravam com ela: mount.add_child 7,8 ms. Antes de a
## região sair, cada um vai inteiro para a fila de vídeo (GpuReleaseQueue), que libera aos poucos fora da
## árvore. Os trechos do túnel guardados de propósito ficam. GETECO_RETIRE_HANDOFF=0 desliga.
func hand_off_retiring() -> int:
	if OS.get_environment("GETECO_RETIRE_HANDOFF") == "0": return 0
	var handed := 0
	for chunk in _retiring:
		if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): continue
		if chunk.get_parent() == self: remove_child(chunk)
		# A fila recusa subárvore já marcada; a marca volta na mesma chamada.
		chunk.remove_meta(GPU_RELEASE.RETIRED_META)
		GPU_RELEASE.retire_detached_subtree(chunk)
		handed += 1
	_retiring.clear()
	_retire_stack.clear()
	_cleanup_retired_chairlifts_if_idle()
	return handed

func _cleanup_retired_chairlifts_if_idle() -> void:
	if _retiring.is_empty() and _chairlift_cleanup_pending:
		chairlifts = chairlifts.filter(func(lift): return is_instance_valid(lift) and not lift.is_queued_for_deletion())
		_chairlift_cleanup_pending = false
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
func _tree_collision(tree: Node3D, chunk: Node3D) -> void:
	var trunk := _box(tree,"TrunkSolid",Vector3(0,1.4,0),Vector3(.4,2.8,.4),Color("00000000"),true)
	trunk.visible = false
	if region_id == "mountain":
		# Keep only the physical trunk: its hidden proxy must not become a visible shard.
		trunk.get_child(0).reparent(tree)
		trunk.free()
		var radius := .4 * maxf(tree.global_basis.x.length(),tree.global_basis.z.length())
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("desert_tree",tree,chunk,{},[],radius)

## Chão base do porto: colisão em caixa de 0,3 m como antes; o visual é o topo só onde nenhum piso de cima
## (`cover`) cobre, mais as quatro laterais (a margem com o mar continua igual).
func _land_piece(chunk: Node3D, piece: Rect2, cover: Array[PackedVector2Array]) -> void:
	# A ponte é dona também do chão físico. Recortar só o visual deixava a
	# caixa integral em y=0 atravessando o tronco e a boca do ramal norte.
	var bridge_kit = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	if region_id == "harbor" and bridge_kit.enabled():
		var cuts: Array[PackedVector2Array] = []
		var outline := GROUND_CUT.rect_polygon(piece)
		if piece.intersects(bridge_kit.east_bounds(),true):
			if not Geometry2D.intersect_polygons(outline,bridge_kit.east_footprint()).is_empty(): cuts.append(bridge_kit.east_footprint())
		if piece.intersects(Rect2(328.75,-374.25,36.55,126.0),true):
			if not Geometry2D.intersect_polygons(outline,bridge_kit.north_footprint()).is_empty(): cuts.append(bridge_kit.north_footprint())
		if not cuts.is_empty():
			_land_outside_bridge(chunk,piece,cover,cuts)
			return
	var mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract([GROUND_CUT.rect_polygon(piece)],cover),0.0,1.0)
	if mesh == null: mesh = ArrayMesh.new()
	var corners := [Vector2(piece.position.x,piece.position.y),Vector2(piece.end.x,piece.position.y),Vector2(piece.end.x,piece.end.y),Vector2(piece.position.x,piece.end.y)]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side+1)%4]
		var edge := b-a
		var normal := Vector3(edge.y,0,-edge.x).normalized()
		for point in [Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(b.x,-.3,b.y),Vector3(a.x,0,a.y),Vector3(b.x,-.3,b.y),Vector3(a.x,-.3,a.y)]:
			vertices.append(point)
			normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var land := MeshInstance3D.new()
	land.name = "Land"
	land.mesh = mesh
	# Native clipped top replaces FreightOutskirts' old y=.001 overlay.
	# Authored woodland land matches this rectangle, already split by chunk.
	var woodland := Rect2(-430,-160,350,318).encloses(piece)
	land.material_override = preload("res://activities/motocross/MotocrossGroundDetail.gd").ground_material() if woodland else _material(Color("737b69"))
	if woodland: land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(land)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(piece.get_center().x,-.15,piece.get_center().y)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(piece.size.x,.3,piece.size.y)
	collider.shape = shape
	body.add_child(collider)
	land.add_child(body)

func _land_outside_bridge(chunk: Node3D, piece: Rect2, cover: Array[PackedVector2Array], cuts: Array[PackedVector2Array]) -> void:
	# Ownership é obrigatório inclusive no diagnóstico de pisos empilhados.
	# A mesma borda recortada gera paredes visíveis e colisão sem ler a GPU.
	var polygons := GROUND_CUT.subtract_exact([GROUND_CUT.rect_polygon(piece)],cuts)
	if polygons.is_empty(): return
	var mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract(polygons,cover),0.0,1.0)
	if mesh == null: mesh = ArrayMesh.new()
	var walls := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces := PackedVector3Array()
	for polygon in polygons:
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.is_empty():
			push_error("Poligono de chao da ponte sem triangulacao: %s"%piece)
			return
		# O contorno anti-horário XZ dá faces superiores horárias vistas de cima.
		for index in range(0,indices.size(),3):
			var a: Vector2 = polygon[indices[index]]
			var b: Vector2 = polygon[indices[index+1]]
			var c: Vector2 = polygon[indices[index+2]]
			if (b-a).cross(c-a) == 0.0: continue
			faces.append_array(PackedVector3Array([Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(c.x,0,c.y),
				Vector3(c.x,-.3,c.y),Vector3(b.x,-.3,b.y),Vector3(a.x,-.3,a.y)]))
		for side in polygon.size():
			var a: Vector2 = polygon[side]
			var b: Vector2 = polygon[(side+1)%polygon.size()]
			var edge := b-a
			if edge.length_squared() == 0.0: continue
			var normal := Vector3(edge.y,0,-edge.x).normalized()
			var wall := PackedVector3Array([Vector3(a.x,0,a.y),Vector3(b.x,-.3,b.y),Vector3(b.x,0,b.y),
				Vector3(a.x,0,a.y),Vector3(a.x,-.3,a.y),Vector3(b.x,-.3,b.y)])
			walls.append_array(wall)
			faces.append_array(wall)
			for _point in wall: normals.append(normal)
	if faces.is_empty():
		push_error("Chão da ponte sem triangulação válida: %s"%piece)
		return
	if not walls.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = walls
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var land := MeshInstance3D.new()
	land.name = "LandOutsideUnifiedBridge"
	land.mesh = mesh
	land.material_override = _material(Color("737b69"))
	chunk.add_child(land)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collider.shape = shape
	body.add_child(collider)
	land.add_child(body)

func _box(parent: Node3D,label: String,point: Vector3,size: Vector3,color: Color,solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.material_override = _material(color)
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		mesh.add_child(body)
	return mesh

func _build_road_surfaces(chunk: Node3D, rect: Rect2) -> void:
	var rows: Array = chunk.get_meta("road_surface_rows",[])
	if rows.is_empty(): return
	var by_color: Dictionary = {}
	for row in rows:
		var color: Color = row.color
		if not by_color.has(color): by_color[color] = PackedVector3Array()
		var vertices: PackedVector3Array = by_color[color]
		var y: float = row.top
		var polygon: PackedVector2Array = row.polygon
		for index in Geometry2D.triangulate_polygon(polygon):
			var point := polygon[index]
			vertices.append(Vector3(point.x,y,point.y))
		by_color[color] = vertices
	for color in by_color:
		if by_color[color].is_empty(): continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for vertex in by_color[color]:
			surface.set_uv(Vector2(vertex.x, vertex.z) / 4.0)
			surface.add_vertex(vertex)
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "RoadSurface"
		mesh.set_meta("vehicle_surface", "hard" if color == HARBOR_ROAD_GEOMETRY.ROAD_COLOR else "dirt")
		mesh.mesh = surface.commit()
		if color == HARBOR_ROAD_GEOMETRY.ROAD_COLOR:
			if harbor_road_geometry == null: harbor_road_geometry = HARBOR_ROAD_GEOMETRY.new()
			var unified_bridge := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
			mesh.material_override = unified_bridge.material("asphalt") if unified_bridge.enabled() else harbor_road_geometry._material(color)
		else:
			# Estrada de terra ganha o mesmo chão procedural das peças do editor.
			var dirt := ShaderMaterial.new()
			dirt.shader = NATURAL_GROUND
			dirt.set_shader_parameter("base_color",color)
			dirt.set_shader_parameter("uv_meters",4.0)
			dirt.set_shader_parameter("base_color",Color("5d4e3d"))
			dirt.set_shader_parameter("surface_softness",.6)
			mesh.material_override = dirt
			mesh.set_instance_shader_parameter("uv_origin",(Vector2(by_color[color][0].x,by_color[color][0].z)/256.0).floor()*64.0)
			# Preserve the authored support exactly; replace only the hard cutout
			# with a wider visual shoulder that dissolves into the real ground.
			mesh.hide()
			if terrain == null: _build_soft_road_surface(chunk,rect,dirt)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mesh)
		# Support uses the same outline as the surface, at terrain height.
		mesh.create_trimesh_collision()
		mesh.get_child(0).position.y = -.026
	chunk.remove_meta("road_surface_rows")

func _build_soft_road_surface(chunk: Node3D, rect: Rect2, material: ShaderMaterial) -> void:
	const SHOULDER := 1.4
	var boundary := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var paved: Dictionary = {}
	for road in roads+walkways:
		if road.get("surface","asphalt") == "asphalt": paved[road.id] = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var first := Vector2.ZERO
	for road in roads+walkways:
		if road.get("surface","asphalt") == "asphalt": continue
		var points: PackedVector3Array = road.points
		var reach: float = float(road.width)*.5+SHOULDER
		var edges := ROUTE_GEOMETRY.edges(points,float(road.width)+SHOULDER*2.0)
		for index in range(edges.size()-1):
			var shape := ROUTE_GEOMETRY.polygon(edges[index].left,edges[index+1].left,edges[index+1].right,edges[index].right)
			if not ROUTE_GEOMETRY.bounds(shape).intersects(rect): continue
			var pieces: Array[PackedVector2Array] = []
			for part in Geometry2D.intersect_polygons(shape,boundary): pieces.append(part)
			# Never paint loose soil over an asphalt lane or its intentional edge.
			for footprint in route_geometry.footprints:
				if not paved.has(footprint.id) or not footprint.bounds.intersects(rect): continue
				var remaining: Array[PackedVector2Array] = []
				for piece in pieces:
					for part in Geometry2D.clip_polygons(piece,footprint.polygon):
						if part.size()>=3: remaining.append(part)
				pieces = remaining
			for piece in pieces:
				if Geometry2D.is_polygon_clockwise(piece): piece.reverse()
				# Triangulate first: clipping a winding asphalt edge can leave a
				# concave piece. Mid-edge samples retain the opaque path axis.
				var triangles := Geometry2D.triangulate_polygon(piece)
				var samples := PackedVector2Array()
				for triangle in range(0,triangles.size(),3):
					var a := piece[triangles[triangle]]
					var b := piece[triangles[triangle+1]]
					var c := piece[triangles[triangle+2]]
					var ab := (a+b)*.5
					var bc := (b+c)*.5
					var ca := (c+a)*.5
					samples.append_array(PackedVector2Array([a,ab,ca,ab,b,bc,ca,bc,c,ab,bc,ca]))
				for point in samples:
					var distance := INF
					for segment in range(points.size()-1):
						var a := Vector2(points[segment].x,points[segment].z)
						var b := Vector2(points[segment+1].x,points[segment+1].z)
						distance = minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
					var alpha := clampf(1.0-distance/reach,0.0,1.0)
					surface.set_normal(Vector3.UP)
					surface.set_uv(point/4.0)
					surface.set_color(Color(1,1,1,alpha))
					surface.add_vertex(Vector3(point.x,.026,point.y))
					if count == 0: first = point
					count += 1
	if count == 0: return
	var soft := MeshInstance3D.new()
	soft.name = "SoftMountainTrail"
	soft.mesh = surface.commit()
	material.set_shader_parameter("edge_alpha",true)
	soft.material_override = material
	soft.set_instance_shader_parameter("uv_origin",(first/256.0).floor()*64.0)
	soft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(soft)

## The cemetery provides its own floor and collision at y=0. Harbor land has
## the same top face there; drawing both causes depth fighting and light flicker.
## `_rect_outside` contra vários recortes (os bueiros), peça a peça.
func _rects_outside_all(rect: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var pieces: Array[Rect2] = [rect]
	for hole in holes:
		var next: Array[Rect2] = []
		for piece in pieces: next.append_array(_rect_outside(piece, hole))
		pieces = next
	return pieces

func _rect_outside(surface: Rect2, hole: Rect2) -> Array[Rect2]:
	if not surface.has_area(): return []
	var overlap := surface.intersection(hole)
	if not overlap.has_area(): return [surface]
	var pieces: Array[Rect2] = []
	if overlap.position.y > surface.position.y:
		pieces.append(Rect2(surface.position, Vector2(surface.size.x, overlap.position.y - surface.position.y)))
	if overlap.end.y < surface.end.y:
		pieces.append(Rect2(Vector2(surface.position.x, overlap.end.y), Vector2(surface.size.x, surface.end.y - overlap.end.y)))
	if overlap.position.x > surface.position.x:
		pieces.append(Rect2(Vector2(surface.position.x, overlap.position.y), Vector2(overlap.position.x - surface.position.x, overlap.size.y)))
	if overlap.end.x < surface.end.x:
		pieces.append(Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(surface.end.x - overlap.end.x, overlap.size.y)))
	return pieces

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
				_build_surfaces(chunk,rect,key)
				_surface_terrain_data = {}
				job.erase("terrain_data")
				STALL_WORK.finish_slow("stream.%s.surfaces"%region_id,stage_began,2000)
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

## Estágio 0 da serra: alturas, malha e máscara das trilhas saem prontas de um WorkerThreadPool
## (MountainTerrain3D.chunk_data) e aqui fica só a montagem (malha, colisão, nós). Devolve true enquanto o
## trabalhador calcula: o trecho cede a vez sem gastar o orçamento esperando. Sem orçamento (0 ou INF: chão
## agora para um veículo, ou trecho imediato) espera a tarefa já começada ou deixa build_chunk calcular aqui.
func _terrain_chunk_pending(job: Dictionary, budget_usec: float) -> bool:
	if job.has("terrain_data") or not _terrain_task_wanted(job): return false
	var now := budget_usec <= 0.0 or is_inf(budget_usec)
	if not job.has("terrain_task"):
		if now: return false
		_start_terrain_task(job)
	var task: int = job.terrain_task
	if _terrain_tasks.has(task):
		if not now and not WorkerThreadPool.is_task_completed(task):
			job.waiting_worker = true
			return true
		WorkerThreadPool.wait_for_task_completion(task)
		_terrain_tasks.erase(task)
	job.terrain_data = job.terrain_result
	job.erase("terrain_task")
	job.erase("terrain_result")
	job.erase("waiting_worker")
	return false

func _terrain_task_wanted(job: Dictionary) -> bool:
	return region_id == "mountain" and terrain != null and int(job.stage) == 0 and _mountain_owns_terrain(job.key)

func _start_terrain_task(job: Dictionary) -> void:
	if job.has("terrain_task") or job.has("terrain_data") or not _terrain_task_wanted(job): return
	var result := {}
	var task := WorkerThreadPool.add_task(Callable(TERRAIN,"prepare_task").bind(terrain,job.rect,result),false,"mountain terrain chunk")
	_terrain_tasks[task] = true
	job.terrain_task = task
	job.terrain_result = result

## Os próximos trechos da fila já calculam no trabalhador enquanto o da frente monta.
func _prefetch_terrain_tasks() -> void:
	if region_id != "mountain" or terrain == null: return
	for index in mini(build_jobs.size(),TERRAIN_PREFETCH_JOBS): _start_terrain_task(build_jobs[index])

## Libera as tarefas terminadas (inclusive as de trechos já descartados); o resultado fica no job.
func _collect_terrain_tasks() -> void:
	if _terrain_tasks.is_empty(): return
	for task in _terrain_tasks.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_terrain_tasks.erase(task)

func _build_surfaces(chunk: Node3D, rect: Rect2, key: Vector2i) -> void:
	if region_id == "harbor":
		# Uma camada de chão só (2026-10-13): quem está por cima é montado primeiro e quem fica por baixo
		# perde a área coberta. Ruas > lotes e concreto do porto > chão base (Land).
		var ground_cover: Array[PackedVector2Array] = []
		if harbor_road_geometry != null:
			harbor_road_geometry.build_chunk(chunk,rect)
			ground_cover.append_array(harbor_road_geometry.chunk_cover)
			# The opaque earth-to-grass strip already supplies its own finish.
			# Reserve only the actual clipped triangles, never their bounding box.
			var chunk_outline := GROUND_CUT.rect_polygon(rect)
			for triangle in harbor_road_geometry._earth_verge_triangles:
				if not GROUND_CUT.bounds(triangle.points).intersects(rect): continue
				ground_cover.append_array(Geometry2D.intersect_polygons(triangle.points,chunk_outline))
		for footprint in harbor_facade_ground:
			if GROUND_CUT.bounds(footprint).intersects(rect): ground_cover.append(footprint)
		for footprint in harbor_dressing_ground:
			if GROUND_CUT.bounds(footprint).intersects(rect): ground_cover.append(footprint)
		# Santa Mare owns the visible deck. Land and authored surfaces keep their
		# colliders, but must not render a second floor underneath the ship.
		var santa_deck := PackedVector2Array()
		for point in SOUTH_PORT_LAYOUT.ship_hull(): santa_deck.append(point*SCALE)
		if GROUND_CUT.bounds(santa_deck).intersects(rect): ground_cover.append(santa_deck)
		for footprint in CEMETERY.path_footprints(CEMETERY.SOURCE_CENTER*SCALE):
			if GROUND_CUT.bounds(footprint).intersects(rect): ground_cover.append(footprint)
		if harbor_urban_surface != null:
			for lot in harbor_urban_surface.build_chunk(chunk,rect,ground_cover): ground_cover.append(GROUND_CUT.rect_polygon(lot))
		var port_land := Rect2(SOUTH_PORT_LAYOUT.LAND.position*SCALE,SOUTH_PORT_LAYOUT.LAND.size*SCALE)
		var port_surface := rect.intersection(port_land)
		var port_cover := ground_cover.duplicate()
		if port_surface.has_area(): ground_cover.append(GROUND_CUT.rect_polygon(port_surface))
		var cemetery_half: Vector2 = CEMETERY.LOT_SIZE * SCALE * 0.5
		var cemetery_floor := Rect2(CEMETERY.SOURCE_CENTER * SCALE - cemetery_half, cemetery_half * 2.0)
		var sewer_openings: Array[Rect2] = []
		for opening in CATALOG.sewer_openings(): sewer_openings.append(Rect2(opening.position * SCALE, opening.size * SCALE))
		var secret_cellar_opening := Rect2(-413.25,85.35,6.10,3.30)
		var owned_land: Array[Rect2] = []
		for land in source_data.harbor_land:
			var surface := rect.intersection(Rect2(land[0]*SCALE,land[1]*SCALE,land[2]*SCALE,land[3]*SCALE))
			var land_holes: Array[Rect2] = owned_land.duplicate()
			land_holes.append(cemetery_floor)
			for piece in _rects_outside_all(surface,land_holes):
				for sewer_piece in _rects_outside_all(piece, sewer_openings):
					for cellar_piece in _rect_outside(sewer_piece, secret_cellar_opening):
						# Rampas e trechos cobertos do Túnel do canal têm piso e laje próprios.
						for land_piece in CANAL_TUNNEL.outside_land(cellar_piece):
							for skate_piece in preload("res://activities/skate/SkateParkLayout.gd").outside(land_piece):
								_land_piece(chunk,skate_piece,ground_cover)
			if surface.has_area(): owned_land.append(surface)
		harbor_ocean.build_chunk(chunk,rect)
		CANAL_TUNNEL.build_chunk(chunk,rect)
		var skate_center := preload("res://activities/skate/SkateParkLayout.gd").CENTER
		if preload("res://activities/skate/SkateParkLayout.gd").enabled() and rect.has_point(Vector2(skate_center.x, skate_center.z)):
			chunk.add_child(preload("res://activities/skate/SkatePark.gd").new())
		coastal_protection.build_chunk(chunk,rect)
		var clip := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		var extra_support: Array[PackedVector2Array] = []
		for land_rect in owned_land: extra_support.append(GROUND_CUT.rect_polygon(land_rect))
		for polygon in extra_land:
			var woodland: bool = polygon==preload("res://world/places/fishing/FishingRuralLayout.gd").outline()
			var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(polygon,clip)
			for piece in GROUND_CUT.subtract_exact(pieces,extra_support): _authored_surface(chunk,piece,woodland,ground_cover)
			extra_support.append(polygon)
		preload("res://world/places/fishing/FishingWoodland.gd").build_chunk(chunk,rect)
		if port_surface.has_area():
			# Visual finish only: OriginalSouthPort/land already own physical support.
			# Keep the apron below every road finish. Its former .014 top was
			# exactly coplanar with CURB_COLOR, causing flickering along the roads.
			# Sem a área das ruas: antes o concreto inteiro ficava por baixo delas.
			var apron_mesh := GROUND_CUT.flat_mesh(GROUND_CUT.subtract([GROUND_CUT.rect_polygon(port_surface)],port_cover),.004,1.0)
			if apron_mesh != null:
				var apron := MeshInstance3D.new()
				apron.name = "SouthPortConcrete"
				apron.mesh = apron_mesh
				apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				apron.material_override = preload("res://world/regions/PortYardMaterials3D.gd").concrete()
				chunk.add_child(apron)
	else:
		# These authored cells are the water spans of HarborMountainConnector and
		# HarborBridgeCrossing.
		# WorldConnection3D supplies the shared deck/abutment while Harbor owns
		# the water below. Building generic mountain terrain here would create a
		# solid wall through the original bridge route when both regions reside.
		if _mountain_owns_terrain(key):
			var shore_edges := preload("res://world/regions/MountainBridgeShore.gd").frontiers(key,MOUNTAIN_BRIDGE_VOID_CELLS,_mountain_owns_terrain)
			terrain.build_chunk(chunk,rect,shore_edges,_surface_terrain_data)
			preload("res://world/regions/ScenarioBoundary3D.gd").build_mountain(chunk,rect,terrain.surface_height_at)

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	match record.kind:
		"cemetery":
			var cemetery := CEMETERY.new()
			cemetery.position = record.position
			chunk.add_child(cemetery)
		"south_port_model":
			# Prédio do porto com fachada pintada (galpão, oficina, garagem: PaintedHarborHouses.LOWRISE)
			# monta pela fábrica, com a mesma pegada e altura do catálogo, no lugar do modelo antigo.
			if str(record.id).begins_with("PortBuilding") and not PaintedHarborHouses.style_for(str(record.id), str(record.model_kind)).is_empty():
				var def: Dictionary = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source(str(record.id))
				var painted_port := URBAN_FACTORY.populate_chunk(chunk, {"id": str(record.id), "kind": str(record.model_kind), "position": record.position,
					"size": (record.footprint as Rect2).size / 16.0, "height_override": float(def.get("roof_height", 4.6)) - .10, "variant_seed": int(record.variant)})
				if painted_port != null:
					painted_port.add_to_group("exterior_reveal_building")
					preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").install(painted_port,str(record.id))
				return
			var port_art: Node3D = SOUTH_PORT.mount(chunk,record)
			if str(record.id).begins_with("PortBuilding"):
				port_art.add_to_group("exterior_reveal_building")
				preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").install(port_art,str(record.id))
		"south_port_ship_detail":
			var ship_detail := PORT_SHIP_DRESSING.new()
			chunk.add_child(ship_detail)
			ship_detail.build_santa_mare(SOUTH_PORT_LAYOUT.ship_hull())
		"south_port_rail":
			var delta: Vector3 = record.b-record.a
			var rail := _box(chunk,"SantaMareRail",(record.a+record.b)*.5+Vector3.UP*.45,Vector3(.25,.9,delta.length()),Color("a0a49a"),true)
			rail.rotation.y = atan2(delta.x,delta.z)
		"salvage":
			var yard = preload("res://world/places/SalvageYardNative.gd").new()
			yard.position = record.position
			chunk.add_child(yard)
		"harbor_dressing":
			var dressing := HARBOR_DRESSING.new()
			dressing.configure(record.zone_id)
			dressing.position = record.position
			chunk.add_child(dressing)
		"harbor_bridge":
			var bridge:=HARBOR_BRIDGE.new()
			bridge.position=record.position
			chunk.add_child(bridge)
		"harbor_prop":
			# Banco/árvore/poste do pátio da ilha caía dentro da rampa aberta do túnel.
			if region_id == "harbor" and CANAL_TUNNEL.reserves(Vector2(record.position.x,record.position.z),0.8): return
			var skate_layout := preload("res://activities/skate/SkateParkLayout.gd")
			if region_id == "harbor" and skate_layout.enabled() and skate_layout.FOOTPRINT.grow(.3).has_point(Vector2(record.position.x, record.position.z)): return
			var prop:=HARBOR_PROP.new()
			prop.configure(record.data)
			prop.position=record.position
			chunk.add_child(prop)
		"harbor_restaurant":
			var terrace := RESTAURANT_TERRACE.new()
			terrace.configure(record.venue_id,record.table_index,record.fabric)
			terrace.position = record.position
			chunk.add_child(terrace)
			terrace.add_to_group("harbor_restaurant_terrace")
		"ship": _build_ship(chunk)
		"lake":
			var lake = preload("res://world/regions/NativeLake.gd").new()
			lake.variant = record.variant
			lake.position = record.position
			chunk.add_child(lake)
		"cargo_plane":
			var aircraft = preload("res://world/places/CargoPlaneNative.gd").new()
			aircraft.name = "SmugglerCargoPlane"
			aircraft.position = record.position
			chunk.add_child(aircraft)
		"tree":
			var tree = preload("res://world/regions/NativePine.gd").create(record.variant,record.snow)
			tree.position = record.position
			if terrain != null: tree.position.y = terrain.surface_height_at(Vector2(tree.position.x,tree.position.z))
			chunk.add_child(tree)
			_tree_collision(tree,chunk)
		"mountain_jeep_scenery": MOUNTAIN_JEEP_SCENERY.build(chunk,record)
		"cave_approach":
			var cover := preload("res://world/mountain_detail/MountainCaveApproach.gd").new()
			cover.position = record.position
			chunk.add_child(cover)
		"mountain_road_lamp":
			var lamp = preload("res://world/mountain_detail/MountainRoadLamp3D.gd").new()
			lamp.position = record.position
			if terrain != null: lamp.position.y = terrain.surface_height_at(Vector2(lamp.position.x,lamp.position.z))
			chunk.add_child(lamp)
		"sawmill_yard":
			MOUNTAIN_FACTORY.populate_sawmill_chunk(chunk,record)
		"mountain_village": MOUNTAIN_FACTORY.populate_village_chunk(chunk,record)
		"mountain_forge":
			if not _blade_forge_enabled: return
			var forge := MOUNTAIN_FORGE.new()
			forge.position = record.position
			chunk.add_child(forge)
		"forge_hermit_cabin":
			if not _blade_forge_enabled: return
			var cabin := FORGE_HERMIT.new()
			cabin.position = record.position
			chunk.add_child(cabin)
		"environmental_parity":
			var mechanism := MOUNTAIN_FACTORY.populate_environmental_chunk(chunk,record)
			if mechanism != null:
				mechanism.set_operating(chairlift_operating)
				mechanism.set_animation_active(true)
				chairlifts.append(mechanism)
		"harbor_route_zone": HARBOR_ROUTE_FACTORY.populate_zone_chunk(chunk, record.zone_id, record.get("prepared_route_zone"))
		"harbor_public_realm":
			var public_realm := HARBOR_PUBLIC_REALM.new()
			public_realm.zone_id = record.zone_id
			public_realm.position = record.position
			chunk.add_child(public_realm)
		"road":
			if region_id == "harbor": return
			var road_a: Vector3 = record.a
			var road_b: Vector3 = record.b
			var mountain_pass_road: bool = record.get("road_id","") == "mountain_pass"
			var bridge_join: bool = mountain_pass_road and road_a.distance_to(CATALOG._at(Vector2(3000,400),"mountain")) < 0.1
			# MountainPass is authored at deck height. Lower its 5 cm road slab so
			# every segment top is coplanar with the bridge and has no raised end lip.
			# The first segment also overlaps the deck; the traffic curve still
			# starts at the authored seam.
			if bridge_join:
				road_a -= (road_b-road_a).normalized()*5.0
			var offset: Vector3 = road_b-road_a
			var center: Vector3 = (road_a+road_b)*.5
			var surface_kind: String = record.get("surface","asphalt")
			var road_color := HARBOR_ROAD_GEOMETRY.ROAD_COLOR if surface_kind == "asphalt" else Color("544a3b")
			var shape := ROUTE_GEOMETRY.polygon(record.left_a,record.left_b,record.right_b,record.right_a)
			var pieces := route_geometry.outside_roads(shape,record.road_id,true)
			var unified_bridge := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
			if unified_bridge.enabled() and ROUTE_GEOMETRY.bounds(shape).intersects(unified_bridge.east_bounds()):
				pieces = GROUND_CUT.subtract_exact(pieces,[unified_bridge.east_footprint()])
			var rows: Array = chunk.get_meta("road_surface_rows",[])
			for piece in pieces: rows.append({"polygon":piece,"top":.026,"color":road_color})
			chunk.set_meta("road_surface_rows",rows)
			# Only the main two-lane pass needs a centre stripe.
			if mountain_pass_road:
				if unified_bridge.enabled(): _mountain_center_marking(chunk,center,offset)
				else:
					var line := _box(chunk,"CenterLine",center+Vector3(0,.034,0),Vector3(.09,.008,offset.length()*.64),Color("b6aa71"))
					line.rotation.y = atan2(offset.x,offset.z)
			# Rural pass/track shoulders are terrain. The generic 2.5 m sidewalks
			# crossed junction asphalt and made wide floating ribbons on the bends.
		"building": _building(chunk,record.data)
		"original_facade": _original_facade(chunk,record.data)
		"container":
			var art = _held_load("res://world/regions/LootablePortContainer.gd").new()
			chunk.add_child(art)
			art.build(record.position,record.size)
		"mountain_place": _mountain_place(chunk,record.data)

func _mountain_center_marking(chunk: Node3D, center: Vector3, offset: Vector3) -> void:
	var bridge_kit = preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
	var direction := offset.normalized()
	var side := Vector3(-direction.z,0,direction.x)*.045
	var a := center-direction*offset.length()*.32
	var b := center+direction*offset.length()*.32
	var polygon := PackedVector2Array()
	for point in [a+side,b+side,b-side,a-side]: polygon.append(Vector2(point.x,point.z))
	var bounds := GROUND_CUT.bounds(polygon)
	if not bounds.intersects(bridge_kit.east_bounds().grow(.75),true):
		var line := _box(chunk,"CenterLine",center+Vector3(0,.034,0),Vector3(.09,.008,offset.length()*.64),Color("b6aa71"))
		line.rotation.y = atan2(offset.x,offset.z)
		return
	# O centro do segmento nao prova ownership da faixa inteira. Recortar o
	# desenho real e reservar 75 cm apos a cabeceira evita fundir dupla e traco.
	var terminal_gap := GROUND_CUT.rect_polygon(Rect2(bridge_kit.EAST_END-.001,bridge_kit.EAST_Z-1.0,.751,2.0))
	var pieces := GROUND_CUT.subtract_exact([polygon],[bridge_kit.east_footprint(),terminal_gap])
	var mesh := GROUND_CUT.flat_mesh(pieces,.038,1.0)
	if mesh == null: return
	var clipped_line := MeshInstance3D.new()
	clipped_line.name = "CenterLineClippedAtBridge"
	clipped_line.mesh = mesh
	clipped_line.material_override = _material(Color("b6aa71"))
	clipped_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(clipped_line)

func _mountain_owns_terrain(key: Vector2i) -> bool:
	# MountainTerrain3D only builds whole 64 m cells. A cell is Mountain's when its centre is:
	# "touches Mountain" also claimed row -2, whose Mountain share is a 3 m strip south of
	# LOGICAL_NORTH_LIMIT_Z while the rest is Harbor. Column 7 keeps 8 m west of the seam, where
	# Harbor authors no ground, road or sidewalk (tests/test_bridge_approach_terrain.gd).
	if key in MOUNTAIN_BRIDGE_VOID_CELLS: return false
	var center := (Vector2(key)+Vector2.ONE*.5)*CELL
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
		# Hole clipping may retain coincident bridge vertices before the cover cut.
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
	mesh.material_override = preload("res://world/places/fishing/FishingGround.gd").material() if woodland else _material(Color("737b69"))
	if woodland: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(mesh)
	mesh.create_trimesh_collision()
	for body in mesh.get_children():
		if body is StaticBody3D: body.collision_layer = 1; body.collision_mask = 0
	# Support remains continuous under road/lot finishes; only exposed ground
	# is rendered. The collider was built before replacing the visual mesh.
	if not cover.is_empty():
		var exposed := GROUND_CUT.flat_mesh(GROUND_CUT.subtract_exact([polygon],cover),0.0,1.0)
		if exposed == null: mesh.visible = false
		else: mesh.mesh = exposed
func _building(chunk: Node3D, data: Dictionary) -> void:
	if data.id == "Fagulha":
		var arcade := preload("res://world/places/arcade/ArcadeFacade.gd").new()
		arcade.add_to_group("exterior_reveal_building")
		arcade.position = data.position
		chunk.add_child(arcade)
		return
	if data.id == "CuritibaCellar":
		var cellar := preload("res://world/places/curitiba_cellar/CuritibaCellarFacade.gd").new()
		cellar.add_to_group("exterior_reveal_building")
		cellar.position = data.position
		chunk.add_child(cellar)
		return
	if data.id == "NorthFrontage1":
		var market := preload("res://world/places/supermarket/SupermarketFacade.gd").new()
		market.add_to_group("exterior_reveal_building")
		market.position = CATALOG.get_definition("harbor_supermarket").exterior_position
		chunk.add_child(market)
		return
	# Exactly one exterior per authored building record; Maciota belongs to ProductionWorld.
	if data.id == "Garage": return
	var facade: Dictionary = data.duplicate(true)
	var place_ids := {"NorthFrontage0":"harbor_bank","NorthFrontage2":"harbor_ammunation","NorthFrontage3":"harbor_clothing","NorthFrontage4":"harbor_fuel","Police":"harbor_police","Clinic":"harbor_hospital","NorthFireStation":"harbor_fire_station","CanalHomesWest":"canal_north"}
	if place_ids.has(data.id):
		var definition: Dictionary = CATALOG.get_definition(place_ids[data.id])
		facade["place_id"] = definition.id
		facade["original_name"] = definition.original_name
		facade["name"] = definition.original_name
		facade["entry_position"] = definition.entry_position
		facade["return_position"] = definition.return_position
		facade["variant"] = definition.variant
		# The catalog is authoritative for replaced original facades and transition origins.
		facade.position = definition.exterior_position
	var art := URBAN_FACTORY.populate_chunk(chunk,facade)
	if art != null:
		art.add_to_group("exterior_reveal_building")
		preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").install(art,str(data.id))
		art.set_meta("source_id",data.get("source",""))
		art.set_meta("place_id",facade.get("place_id",""))
		if facade.get("place_id", "") in ["harbor_ammunation", "harbor_police", "harbor_bank", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station"]:
			art.add_to_group("v2_walkin_facade")
			if facade.place_id in ["harbor_bank", "harbor_clothing", "harbor_fuel", "harbor_hospital", "harbor_fire_station"]: art.set_open_amount(0.0)
		if facade.has("entry_position"):
			art.set_meta("entry_position",facade.entry_position)
			art.set_meta("return_position",facade.return_position)
		if facade.get("place_id", "") == "canal_north": WALKUP_DOOR.install(art, CATALOG.get_definition("canal_north"))

func _mountain_place(chunk: Node3D, data: Dictionary) -> void:
	if PAINTED_MOUNTAIN.handles(str(data.id)):
		# Chalés e loja da vila pintados; a porta de acesso continua a do WalkupFacadeDoor.
		var painted: Node3D = PAINTED_MOUNTAIN.build(chunk, data)
		painted.add_to_group("exterior_reveal_building")
		WALKUP_DOOR.install(painted, data)
	elif str(data.id).begins_with("mountain_cabin") or data.id == "lumberjack_shelter":
		var art = _held_load("res://assets/regions/source/world/mountain_pass/art/winter_props/LumberjackCabin3D.gd").new()
		art.add_to_group("exterior_reveal_building")
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id == "mountain_bunker":
		var art = preload("res://world/places/BunkerExteriorNative.gd").new()
		art.add_to_group("exterior_reveal_building")
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id == "ski_lodge":
		var art = _held_load("res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd").new()
		art.add_to_group("exterior_reveal_building")
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id in ["mountain_outfitters","mountain_boutique","mountain_village_outfitters","mountain_gunshop","mountain_mystery_cave"]:
		_original_facade(chunk,data)
	else:
		# Remaining facades are deliberately absent until their original geometry is ported.
		var marker := Marker3D.new()
		marker.name = data.id
		marker.position = data.entry_position
		chunk.add_child(marker)
	# Pegada da construção exterior, derivada dos modelos existentes. Esses
	# planos visuais não participam da colisão nem bloqueiam as entradas.
	var contact_size := Vector2.ZERO
	if str(data.id).begins_with("mountain_cabin") or data.id == "lumberjack_shelter": contact_size = Vector2(3.6, 4.2)
	elif data.id == "ski_lodge": contact_size = Vector2(13.8, 8.4)
	elif data.id == "mountain_bunker": contact_size = Vector2(18.0, 12.0)
	elif data.id in ["mountain_outfitters", "mountain_boutique", "mountain_village_outfitters"]: contact_size = Vector2(6.7, 4.0)
	elif data.id == "mountain_gunshop": contact_size = Vector2(7.0, 4.0)
	if contact_size != Vector2.ZERO: MOUNTAIN_SHADOW.attach(chunk, contact_size, data.exterior_position)

func _original_facade(chunk: Node3D,data: Dictionary) -> void:
	if data.region == "harbor":
		# Catalog-only residences/cemetery are not duplicated in harbor_buildings.
		var branch_art := URBAN_FACTORY.populate_chunk(chunk,data)
		if branch_art != null:
			branch_art.add_to_group("exterior_reveal_building")
			WALKUP_DOOR.install(branch_art, data)
		return
	var path := ""
	match str(data.id):
		"harbor_hospital": path = "world/harbor/hospital/HarborHospitalModel3D.gd"
		"westgate_garden","quayside_house","canal_north": path = "world/harbor/residences/ResidenceExterior3D.gd"
		"cemetery_keeper": path = "world/harbor/cemetery/CemeteryHouseExterior3D.gd"
		"harbor_ammunation": path = "guns/ammunation/AmmunationFacade3D.gd"
		"mountain_gunshop": path = "world/mountain_pass/art/review_0908/MountainGunShop3D.gd"
		"mountain_outfitters","mountain_boutique","mountain_village_outfitters": path = "world/mountain_pass/ResortShop3D.gd"
		"mountain_mystery_cave": path = "world/mountain_pass/MountainWaterfallCave3D.gd"
	if path.is_empty(): return
	var art = _held_load("res://assets/regions/source/"+path).new()
	art.add_to_group("exterior_reveal_building")
	if data.service == "residence": art.variant_index = data.variant
	art.position = data.exterior_position
	chunk.add_child(art)
	if data.id == "mountain_gunshop":
		art.set_meta("place_id", data.id)
		art.add_to_group("v2_weapon_shop_facade")
		art.add_to_group("v2_walkin_facade")
	if data.id == "harbor_hospital":
		art.set_public_door_amount(1.0)
		art.set_door_amount(1.0)
		for mesh in art.find_children("*","MeshInstance3D",true,false): mesh.layers = 1
	for label in art.find_children("*","Label3D",true,false): label.text = data.original_name
	# Native collision follows each original structural mesh, keeping open approaches.
	for mesh in art.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = mesh.mesh.get_aabb()
		var center: Vector3 = mesh.global_transform * bounds.get_center()
		if center.y > 2.4 or bounds.size.y < .4: continue
		if mesh.get_meta("interior_solid_id","") != "" or bounds.size.x > 2 and bounds.size.z > 2:
			mesh.create_trimesh_collision()
	WALKUP_DOOR.install(art, data)

func _prepare_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3913
	var places := CATALOG.definitions()
	for grove in source_data.forest_clusters:
		var center := Vector2(grove.center[0],grove.center[1])
		var placed := 0
		for attempt in int(grove.count)*6:
			if placed >= int(grove.count): break
			var original := center+Vector2.from_angle(rng.randf()*TAU)*sqrt(rng.randf())*float(grove.radius)
			var point := CATALOG._at(original,region_id)
			var blocked := false
			for place in places:
				if place.region == region_id and point.distance_to(place.exterior_position)<12: blocked=true
			for lake in [Rect2(6680,-320,800,700),Rect2(5080,-1500,740,680)]:
				if lake.has_point(original): blocked=true
			var key := _cell(point)
			for x in range(-1,2):
				for z in range(-1,2):
					for record in records.get(key+Vector2i(x,z),[]):
						if record.kind == "road":
							var nearest := Geometry3D.get_closest_point_to_segment(point,record.a,record.b)
							# Keep the pre-migration5.625m exclusion for EastVale: widening its
							# visual dirt bed by0.5m must not reroll unrelated groves.
							var clearance: float = 5.625 if record.get("surface","")=="earth" else record.width*.5+4
							if point.distance_to(nearest)<clearance: blocked=true
						elif record.kind == "tree" and point.distance_to(record.position)<2.4: blocked=true
			if blocked: continue
			_record(point,{"kind":"tree","position":point,"variant":placed%8,"snow":grove.snow})
			placed+=1
	# Filter after deterministic generation: preserve every tree outside the authored clearing.
	# Rejecting during RNG placement would reroll later groves across the whole mountain.
	for key in records:
		records[key] = records[key].filter(func(record):
			if record.kind != "tree": return true
			var original := Vector2(record.position.x,record.position.z)/SCALE-CATALOG.MOUNTAIN_OFFSET
			var planar := Vector2(record.position.x,record.position.z)
			if MOUNTAIN_FORGE.FOOTPRINT.grow(2.0).has_point(planar) or FORGE_HERMIT.FOOTPRINT.grow(2.0).has_point(planar): return false
			return not _helipad_reserved(original) and not _fort_exit_reserved(Vector2(record.position.x,record.position.z)) and not preload("res://world/mountain_detail/OriginalVillageLayout.gd").is_reserved(original))

func _build_ship(chunk: Node3D) -> void:
	var outline := PackedVector2Array()
	for point in source_data.ship_deck: outline.append(Vector2(point[0],point[1])*SCALE)
	var triangles := Geometry2D.triangulate_polygon(outline)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		var point: Vector2 = outline[index]
		surface.add_vertex(Vector3(point.x,0,point.y))
	surface.generate_normals()
	var deck := MeshInstance3D.new()
	deck.name = "NorthstarDeck"
	deck.mesh = surface.commit()
	deck.material_override = PORT_SHIP_PAINT.material("deck")
	chunk.add_child(deck)
	deck.create_trimesh_collision()
	# Hull walls make the productive Northstar silhouette readable from the
	# oblique game camera instead of leaving a paper-thin deck over water.
	for index in outline.size():
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index+1)%outline.size()]
		var delta := b-a
		var wall := _box(chunk,"NorthstarHull",Vector3((a.x+b.x)*.5,-.65,(a.y+b.y)*.5),Vector3(.18,1.3,delta.length()),Color("35464b"),true)
		wall.rotation.y = atan2(delta.x,delta.y)
		wall.material_override = PORT_SHIP_PAINT.material("hull")
	# End at the straight port hull edge: the deck supplies finish and support
	# beyond x=3372. The former end at 3418 overlapped the deck.
	var gangway := Rect2(3130*SCALE,1742*SCALE,(3372-3130)*SCALE,40*SCALE)
	_box(chunk,"NorthstarGangway",Vector3(gangway.get_center().x,-.03,gangway.get_center().y),Vector3(gangway.size.x,.06,gangway.size.y),Color("7c8073"),true)
	for side in [1738,1782]:
		_box(chunk,"GangwayRail",Vector3(3251*SCALE,.45,side*SCALE),Vector3(242*SCALE,.9,.10),Color("a0a49a"),true)
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i+1)%outline.size()]
		if is_equal_approx(a.x,3372*SCALE) and is_equal_approx(b.x,3372*SCALE):
			_ship_rail(chunk,Vector2(a.x,990*SCALE),Vector2(a.x,1738*SCALE))
			_ship_rail(chunk,Vector2(a.x,1782*SCALE),Vector2(a.x,2070*SCALE))
		elif is_equal_approx(a.y,2115*SCALE) and is_equal_approx(b.y,2115*SCALE):
			# Preserve the authored south walkway, with rails on both sides of its mouth.
			_ship_rail(chunk,Vector2(3400*SCALE,a.y),Vector2(3534*SCALE,a.y))
			_ship_rail(chunk,Vector2(3606*SCALE,a.y),Vector2(3740*SCALE,a.y))
		else: _ship_rail(chunk,a,b)
	for cargo in source_data.ship_cargo:
		var center := Vector3(cargo.position[0]*SCALE,1.1,cargo.position[1]*SCALE)
		var size := Vector3(cargo.size[0]*SCALE,2.2,cargo.size[1]*SCALE)
		var cargo_seed := absi(roundi(center.x*7.0+center.z*11.0))
		# A caixa lisa continua como colisão do bloco, mas o visual agora são dois
		# contêineres lado a lado, com cor, desgaste e porta voltada alternadamente.
		var cargo_block := _box(chunk,"NorthstarCargo",center,size,Color.WHITE,true)
		cargo_block.mesh = null
		var container_width := (size.x-.16)*.5
		for column in 2:
			var theme := (cargo_seed+column*2)%5
			var visual := PORT_CONTAINER_BATCH.create(theme,Vector3(container_width,size.y,size.z-.1),(cargo_seed+column)%2 == 1)
			visual.position = Vector3(center.x+(column-.5)*(container_width+.08),center.y-size.y*.5,center.z)
			chunk.add_child(visual)
	var cabin := Rect2(3440*SCALE,1795*SCALE,260*SCALE,232*SCALE)
	_box(chunk,"NorthstarAftCabin",Vector3(cabin.get_center().x,1.55,cabin.get_center().y),Vector3(cabin.size.x,3.1,cabin.size.y),Color("bec3b8"),true)
	_box(chunk,"NorthstarWheelhouse",Vector3(cabin.get_center().x,3.55,cabin.get_center().y-.8),Vector3(cabin.size.x*.78,1.25,cabin.size.y*.58),Color("d2d4c8"),true)
	for side in [-1.0,1.0]:
		_box(chunk,"NorthstarWindow",Vector3(cabin.get_center().x+side*cabin.size.x*.25,3.62,cabin.position.y-.02),Vector3(cabin.size.x*.20,.42,.05),Color("213942"))
	_box(chunk,"NorthstarStack",Vector3(cabin.get_center().x,5.0,cabin.get_center().y+.9),Vector3(1.0,2.0,1.0),Color("52625e"),true)
	for source_z in [1052.0,1388.0,1612.0]: _build_northstar_crane(chunk,Vector2(3190,source_z)*SCALE)
	var ship_detail := PORT_SHIP_DRESSING.new()
	chunk.add_child(ship_detail)
	ship_detail.build_northstar(outline)

func _build_northstar_crane(chunk: Node3D, point: Vector2) -> void:
	var steel := Color("c3a24c")
	for z in [-1.15,1.15]: _box(chunk,"NorthstarCraneLeg",Vector3(point.x,2.6,point.y+z),Vector3(.42,5.2,.42),steel,true).material_override = PORT_SHIP_PAINT.material("crane")
	_box(chunk,"NorthstarCraneCrossbeam",Vector3(point.x,5.15,point.y),Vector3(.48,.42,3.0),steel,true).material_override = PORT_SHIP_PAINT.material("crane")
	var boom_start := Vector3(point.x,5.15,point.y)
	var boom_end := Vector3(point.x+18.0,5.15,point.y)
	var boom := _box(chunk,"NorthstarCraneBoom",(boom_start+boom_end)*.5,Vector3(.38,.38,boom_start.distance_to(boom_end)),steel,true)
	boom.name = "NorthstarCraneBoom_%d" % roundi(point.y*16.0)
	boom.rotation.y = PI*.5
	boom.material_override = PORT_SHIP_PAINT.material("crane")
	var rigging := PORT_SHIP_DRESSING.new()
	chunk.add_child(rigging)
	rigging.build_northstar_crane(point)
	var hoist := NORTHSTAR_HOIST.new()
	hoist.configure(point,point.y*.01)
	chunk.add_child(hoist)

func _ship_rail(chunk: Node3D,a: Vector2,b: Vector2) -> void:
	var center := (a+b)*.5
	var delta := b-a
	var rail := _box(chunk,"ShipRail",Vector3(center.x,.5,center.y),Vector3(.15,1,delta.length()),Color("b7bbae"),true)
	rail.rotation.y = atan2(delta.x,delta.y)

static func _helipad_reserved(point: Vector2) -> bool:
	# New landing apron and access corridor, including the pine canopy footprint.
	if point.distance_to(Vector2(6180,-2832))<125: return true
	var walk := PackedVector2Array([Vector2(6410,-2660),Vector2(6270,-2720),Vector2(6180,-2770),Vector2(6180,-2782.4)])
	for i in range(walk.size()-1):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,walk[i],walk[i+1]))<65: return true
	return false

static func _fort_exit_reserved(point: Vector2) -> bool:
	var exit_position: Vector3 = preload("res://gameplay/urban_v1/fort/MountainFortExit3D.gd").WORLD_POSITION
	# Reserve the formation and its full entrance approach before tree placement.
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
