extends Node3D
## Native production geography. Geometry/physics load only near the player.
const MOUNTAIN_FACTORY := preload("res://world/mountain_detail/MountainDetailFactory.gd")
const MOUNTAIN_SHADOW := preload("res://world/mountain_detail/MountainShadowFinish.gd")
const URBAN_FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const NATURAL_GROUND := preload("res://world/regions/natural_ground.gdshader")
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
const CEMETERY := preload("res://world/regions/OriginalCemetery3D.gd")
const HARBOR_DRESSING := preload("res://world/urban_detail/HarborAreaDressing3D.gd")
const RESTAURANT_TERRACE := preload("res://world/urban_detail/HarborRestaurantTerrace3D.gd")
const HARBOR_ROAD_GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const HARBOR_URBAN_SURFACE := preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
const CITY_DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")
const ROUTE_GEOMETRY := preload("res://world/mountain_detail/MountainRouteGeometry.gd")
const ROUTE_LAYOUT := preload("res://world/mountain_detail/MountainRouteLayout.gd")
const DRESSING := preload("res://world/regions/TerrainDressing3D.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const WALKUP_DOOR := preload("res://world/places/WalkupFacadeDoor.gd")
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
var pending: Array[Vector2i] = []
var build_jobs: Array[Dictionary] = []
# Orçamento de construção fatiada por quadro (µs); um passo sozinho pode excedê-lo.
const BUILD_BUDGET_USEC := 3000.0
var current_cell := Vector2i(100000,100000)
var retention_radius := 2
var vehicle_support_cells: Dictionary = {}
var prepared := false
var elapsed := 0.0
var materials := {}
var extra_land: Array[PackedVector2Array] = []
var terrain: TERRAIN
var chairlifts: Array[Node3D] = []
var chairlift_operating := false
var mountain_night_level := 0.0
var harbor_road_geometry: HARBOR_ROAD_GEOMETRY
var harbor_urban_surface: HARBOR_URBAN_SURFACE
var harbor_ocean: RefCounted
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
	set_focus(initial_focus if initial_focus.is_finite() else spawn_position)
## Geografia (registros, vias, floresta, terreno): ~340 ms em Mountain. Pode ser
## chamada no carregamento, antes de a região entrar na árvore.
func prepare_data() -> void:
	if data_prepared: return
	source_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	_prepare()
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
		_hold_file_resources(chunk)
		_suspend_chunk_mechanisms(chunk)
		_detach_cached_records(chunk)
		chunks.erase(key)
		chunk.queue_free()
		await get_tree().process_frame
	chairlifts = chairlifts.filter(func(lift): return is_instance_valid(lift))

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

static func _hold_resource(resource: Variant) -> void:
	if resource is Resource and not (resource as Resource).resource_path.is_empty() and not (resource as Resource).resource_path.contains("::"):
		_held_resources[(resource as Resource).resource_path] = resource

## Descarrega tudo mantendo os dados preparados (região reaproveitada).
func release_chunks() -> void:
	build_jobs.clear()
	pending.clear()
	for key in chunks.keys():
		_suspend_chunk_vehicles(key)
		_suspend_chunk_mechanisms(chunks[key])
		_retire_chunk(chunks[key])
	chunks.clear()
	vehicle_support_cells.clear()
	current_cell = Vector2i(100000,100000)
	chairlifts.clear()

func _exit_tree() -> void:
	for chunk in _retiring:
		if is_instance_valid(chunk): chunk.free()
	_retiring.clear()
	for chunk in chunks.values(): _suspend_chunk_mechanisms(chunk)
func _cell(point: Vector3) -> Vector2i: return Vector2i(floori(point.x/CELL),floori(point.z/CELL))
func _record(point: Vector3, item: Dictionary) -> void:
	var key := _cell(point)
	if not records.has(key): records[key] = []
	records[key].append(item)
func _prepare() -> void:
	if region_id == "harbor":
		_record(CEMETERY.world_position(),{"kind":"cemetery","position":CEMETERY.world_position()})
		_record(CEMETERY.world_position(),{"kind":"harbor_dressing","zone_id":"cemetery","position":CEMETERY.world_position()})
		for polygon in SOUTH_PORT.extra_surfaces():
			var metric := PackedVector2Array()
			for point in polygon: metric.append(point*SCALE)
			extra_land.append(metric)
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
		for building in source_data.harbor_buildings:
			var point := CATALOG._at(Vector2(building.position[0],building.position[1]),region_id)
			var size := Vector2(building.size[0],building.size[1])*SCALE
			var entry: Dictionary = building.duplicate()
			entry["position"] = point
			entry["size"] = size
			buildings.append(entry)
			_record(point,{"kind":"building","data":entry})
		_record(CATALOG._at(Vector2(-750,550),region_id),{"kind":"salvage","position":CATALOG._at(Vector2(-750,550),region_id)})
		_record(CATALOG._at(Vector2(-750,550),region_id),{"kind":"harbor_dressing","zone_id":"salvage","position":CATALOG._at(Vector2(-750,550),region_id)})
		_record(CATALOG._at(Vector2(7700,1700),region_id),{"kind":"harbor_dressing","zone_id":"cobra","position":CATALOG._at(Vector2(7700,1700),region_id)})
		_record(CATALOG._at(Vector2(3790,400),region_id),{"kind":"harbor_bridge","position":CATALOG._at(Vector2(3790,400),region_id)})
		for prop_data in HARBOR_PROP.records():
			var prop_position:=CATALOG._at(prop_data.point,region_id)
			_record(prop_position,{"kind":"harbor_prop","position":prop_position,"data":prop_data})
		_record(CATALOG._at(Vector2(3570,1400),region_id),{"kind":"ship"})
		for venue in [
			["anchor",Color("b96a46"),Vector2(555,1132),Vector2(685,1132)],
			["tideline",Color("477f7d"),Vector2(5735,1644),Vector2(5845,1644)],
			["early_shift",Color("68784a"),Vector2(6145,-1238),Vector2(6255,-1238)]]:
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
			if definition.region == region_id and definition.id in ["westgate_garden","quayside_house","cemetery_keeper","port_boss_garage","harbor_sewer"]: _record(definition.exterior_position,{"kind":"original_facade","data":definition})
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
		for record in MOUNTAIN_FACTORY.get_environmental_records():
			_record(record.position,record)
		_prepare_forest()
		_revise_mountain_routes()
	for entry in CATALOG.access_points():
		if entry.region == region_id: entries.append(entry)
	if region_id == "harbor":
		harbor_road_geometry = HARBOR_ROAD_GEOMETRY.new()
		harbor_road_geometry.configure(roads)
		harbor_urban_surface = HARBOR_URBAN_SURFACE.new()
		harbor_urban_surface.configure()
		harbor_ocean = preload("res://world/regions/HarborOcean.gd").new()
		harbor_ocean.configure(source_data.harbor_land,extra_land)
		coastal_protection = preload("res://world/regions/CoastalProtection.gd").new()
		coastal_protection.configure(source_data,extra_land,harbor_road_geometry._layers[0].polygons)
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
		terrain.configure(terrain_roads,reservations,[])
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
	for path in walkways:
		if path.id in ["cave_trail","forest_shop_walk"]: path.points = ROUTE_LAYOUT.snap_start(path.points,main)
		_record_path(path)
	route_geometry.configure(roads + walkways)
	for key in records:
		records[key] = records[key].filter(func(record):
			return record.kind != "tree" or not route_geometry.contains(record.position,3.0))
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
func set_focus(point: Vector3) -> void:
	focus = point
	if not prepared: return
	var cell := _cell(point)
	if cell == current_cell: return
	current_cell = cell
	pending.clear()
	# The production streaming budget requests the occupied cell and its eight
	# neighbours. retention_radius remains a wider grace band while moving.
	for x in range(-1,2):
		for z in range(-1,2):
			var key := cell+Vector2i(x,z)
			if not chunks.has(key): pending.append(key)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return Vector2(a-cell).length_squared()<Vector2(b-cell).length_squared())
	# The occupied cell gets collision before admission; neighbouring cells spread across frames.
	pending.erase(cell)
	_ensure_chunk(cell)
	_trim_chunks(cell)

func prepare_collision_at(point: Vector3) -> bool:
	# Emergency vehicles are physical actors and may briefly take a neighbouring
	# route while the player remains still.  Admit their occupied/next cell before
	# physics instead of letting them drive over a road whose streamed floor is
	# still absent.
	var key := _cell(point)
	_ensure_chunk_surfaces(key)
	return chunks.has(key)

func set_retention_radius(value: int) -> void:
	retention_radius = clampi(value,1,2)
	if current_cell.x < 100000: _trim_chunks(current_cell)

func set_vehicle_support(vehicles_to_support: Array) -> void:
	var next_cells: Dictionary = {}
	for vehicle in vehicles_to_support:
		var point: Vector3 = vehicle.position
		var radius: float = maxf(0.0,vehicle.radius)
		for x in range(floori((point.x-radius)/CELL),floori((point.x+radius)/CELL)+1):
			for z in range(floori((point.z-radius)/CELL),floori((point.z+radius)/CELL)+1):
				next_cells[Vector2i(x,z)] = true
	if next_cells == vehicle_support_cells: return
	vehicle_support_cells = next_cells
	for key in vehicle_support_cells:
		pending.erase(key)
		_ensure_chunk_surfaces(key)
	if current_cell.x < 100000: _trim_chunks(current_cell)

func _trim_chunks(cell: Vector2i) -> void:
	for key in chunks.keys():
		if vehicle_support_cells.has(key): continue
		if absi(key.x-cell.x)>retention_radius or absi(key.y-cell.y)>retention_radius:
			_suspend_chunk_vehicles(key)
			_suspend_chunk_mechanisms(chunks[key])
			_retire_chunk(chunks[key])
			chunks.erase(key)
			for index in range(build_jobs.size()-1,-1,-1):
				if build_jobs[index].key == key: build_jobs.remove_at(index)
	chairlifts = chairlifts.filter(func(lift): return is_instance_valid(lift) and not lift.is_queued_for_deletion())

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
		if light.is_in_group("mountain_night_light"):
			light.light_energy = float(light.get_meta("night_energy",1.0))*mountain_night_level
func _process(_delta: float) -> void:
	var drain_began := Time.get_ticks_usec()
	_drain_retired()
	_note_slow("liberação", drain_began, 100000)
	var began := Time.get_ticks_usec()
	# Com fila grande (dirigindo rápido) a construção ganha mais tempo por quadro, senão
	# o chunk em que o carro entra ainda não existe e `set_focus` o constrói inteiro de uma vez.
	var budget := BUILD_BUDGET_USEC if pending.size()+build_jobs.size() < 4 else BUILD_BUDGET_USEC*2.0
	while true:
		if build_jobs.is_empty():
			if pending.is_empty(): return
			var key: Vector2i = pending.pop_front()
			if chunks.has(key): continue
			var chunk_began := Time.get_ticks_usec()
			_build_chunk(key,false)
			_note_slow("novo chunk",chunk_began,50000)
		var left: float = budget-(Time.get_ticks_usec()-began)
		if left <= 0.0: return
		var job_began := Time.get_ticks_usec()
		var job_done := _run_build_job(build_jobs[0],left)
		_note_slow("etapa estágio %d"%int(build_jobs[0].stage),job_began,100000)
		if job_done: build_jobs.pop_front()
		if Time.get_ticks_usec()-began >= budget: return

## Registros que custam 40-80 ms para montar (a vila e a serraria da montanha): o nó pronto é
## guardado ao liberar o chunk e reaproveitado na próxima visita; o pré-aquecimento monta cada um
## uma vez. Só entra em cache quem ainda não tem pai (não está em uso em outro chunk).
const CACHED_RECORDS := ["mountain_village","sawmill_yard","harbor_public_realm","lake"]
static var _record_cache: Dictionary = {}

func _build_record_cached(chunk: Node3D, record: Dictionary) -> void:
	if str(record.kind) not in CACHED_RECORDS:
		_build_record(chunk,record)
		return
	var key := "%s|%s|%s"%[region_id,str(record.kind),str(record.get("position",Vector3.ZERO))]
	if _record_cache.has(key):
		var nodes: Array = _record_cache[key]
		var usable := not nodes.is_empty()
		for node in nodes:
			if not is_instance_valid(node) or node.get_parent() != null: usable = false
		if usable:
			for node in nodes: chunk.add_child(node)
			return
	var before := chunk.get_child_count()
	_build_record(chunk,record)
	var built: Array = []
	for index in range(before,chunk.get_child_count()):
		var node := chunk.get_child(index)
		node.set_meta("record_cache_key",key)
		built.append(node)
	_record_cache[key] = built

## Tira do chunk os nós em cache antes de liberá-lo, para que sobrevivam.
func _detach_cached_records(chunk: Node3D) -> void:
	if not is_instance_valid(chunk): return
	for child in chunk.get_children():
		if child.has_meta("record_cache_key"): chunk.remove_child(child)

## Chunk que sai do raio de retenção: liberar 1000-3000 nós de uma vez custava 40-150 ms
## num quadro (medido dirigindo). O chunk é tirado da lista já e seus filhos são liberados
## em fatias de `RETIRE_BUDGET_USEC` por quadro.
const RETIRE_BUDGET_USEC := 1500.0
var _retiring: Array[Node3D] = []
var _retire_stack: Array[Node] = []

func _retire_chunk(chunk: Node3D) -> void:
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return
	_detach_cached_records(chunk)
	chunk.hide()
	_retiring.append(chunk)

func _drain_retired() -> void:
	if _retiring.is_empty(): return
	var began := Time.get_ticks_usec()
	while not _retiring.is_empty():
		var chunk: Node3D = _retiring[0]
		if not is_instance_valid(chunk):
			_retiring.pop_front()
			_retire_stack.clear()
			continue
		if _retire_stack.is_empty(): _retire_stack.append(chunk)
		# Desce até subárvores pequenas antes de liberar: um filho do chunk (prédio, pátio)
		# pode ter centenas de nós, e liberá-lo inteiro custava 100+ ms num quadro só.
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
					top.free()
			else:
				var last := top.get_child(count-1)
				if last.get_child_count() > 4: _retire_stack.append(last)
				else:
					top.remove_child(last)
					last.free()
			if Time.get_ticks_usec()-began >= RETIRE_BUDGET_USEC: return
		chunk.queue_free()
		_retiring.pop_front()
func _material(color: Color) -> StandardMaterial3D:
	if materials.has(color): return materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .86
	materials[color] = material
	return material
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

func _build_road_surfaces(chunk: Node3D) -> void:
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
			mesh.material_override = harbor_road_geometry._material(color)
		else:
			# Estrada de terra ganha o mesmo chão procedural das peças do editor.
			var dirt := ShaderMaterial.new()
			dirt.shader = NATURAL_GROUND
			dirt.set_shader_parameter("base_color",color)
			dirt.set_shader_parameter("uv_meters",4.0)
			mesh.material_override = dirt
			mesh.set_instance_shader_parameter("uv_origin",(Vector2(by_color[color][0].x,by_color[color][0].z)/256.0).floor()*64.0)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mesh)
		# Support uses the same outline as the surface, at terrain height.
		mesh.create_trimesh_collision()
		mesh.get_child(0).position.y = -.026
	chunk.remove_meta("road_surface_rows")

## The cemetery provides its own floor and collision at y=0. Harbor land has
## the same top face there; drawing both causes depth fighting and light flicker.
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
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion(): return true
	var began := Time.get_ticks_usec()
	var key: Vector2i = job.key
	var rect: Rect2 = job.rect
	var chunk_records: Array = records.get(key,[])
	while true:
		match int(job.stage):
			0:
				_build_surfaces(chunk,rect,key)
				job.stage = 1
			1:
				# Vegetação/pedras do terreno: passo próprio, o terreno sozinho já custa 40–95 ms.
				if region_id == "mountain" and _mountain_owns_terrain(key):
					if not job.has("terrain_dressing"): job.terrain_dressing = DRESSING.begin(rect,region_id,terrain.surface_height_at,_dressing_reserved)
					if not DRESSING.step(job.terrain_dressing,maxf(1500.0,budget_usec-(Time.get_ticks_usec()-began))): return false
					chunk.add_child(job.terrain_dressing.root)
					job.erase("terrain_dressing")
				job.stage = 2
			2:
				if int(job.index) < chunk_records.size():
					var record: Dictionary = chunk_records[int(job.index)]
					# This batch regenerates fourteen containers and normals every time
					# (~1.7 s); none of its geometry survives discarded warm-up cells.
					# Shared paints are warmed by the other port records. Live streaming
					# always builds the full cargo and its original collision.
					if not (job.get("warming", false) and record.kind == "south_port_model" and record.model_kind == "ship_cargo"):
						var record_began := Time.get_ticks_usec()
						_build_record_cached(chunk,record)
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
					if not CITY_DRESSING.build_chunk_step(job.dressing): continue
					# Depois de todo o acabamento de chão: abre as rampas do Túnel do canal.
					CANAL_TUNNEL.carve_chunk(chunk,rect)
				elif region_id == "mountain":
					_build_road_surfaces(chunk)
					_apply_night_lights(chunk)
				job.stage = 4
				chunk.set_meta("vegetation_ready_frame", Engine.get_physics_frames())
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
				return
		return
	_build_chunk(key,false)
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

func _build_surfaces(chunk: Node3D, rect: Rect2, key: Vector2i) -> void:
	if region_id == "harbor":
		if harbor_urban_surface != null:
			harbor_urban_surface.build_chunk(chunk,rect)
		if harbor_road_geometry != null:
			harbor_road_geometry.build_chunk(chunk,rect)
		var cemetery_half: Vector2 = CEMETERY.LOT_SIZE * SCALE * 0.5
		var cemetery_floor := Rect2(CEMETERY.SOURCE_CENTER * SCALE - cemetery_half, cemetery_half * 2.0)
		var sewer_opening := Rect2(CATALOG.HARBOR_SEWER_OPENING.position * SCALE, CATALOG.HARBOR_SEWER_OPENING.size * SCALE)
		var secret_cellar_opening := Rect2(-413.25,85.35,6.10,3.30)
		for land in source_data.harbor_land:
			var surface := rect.intersection(Rect2(land[0]*SCALE,land[1]*SCALE,land[2]*SCALE,land[3]*SCALE))
			for piece in _rect_outside(surface, cemetery_floor):
				for sewer_piece in _rect_outside(piece, sewer_opening):
					for cellar_piece in _rect_outside(sewer_piece, secret_cellar_opening):
						# Rampas e trechos cobertos do Túnel do canal têm piso e laje próprios.
						for land_piece in CANAL_TUNNEL.outside_land(cellar_piece):
							_box(chunk,"Land",Vector3(land_piece.get_center().x,-.15,land_piece.get_center().y),Vector3(land_piece.size.x,.3,land_piece.size.y),Color("737b69"),true)
		harbor_ocean.build_chunk(chunk,rect)
		CANAL_TUNNEL.build_chunk(chunk,rect)
		coastal_protection.build_chunk(chunk,rect)
		var clip := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		for polygon in extra_land:
			for piece in Geometry2D.intersect_polygons(polygon,clip): _authored_surface(chunk,piece)
		var port_land := Rect2(SOUTH_PORT_LAYOUT.LAND.position*SCALE,SOUTH_PORT_LAYOUT.LAND.size*SCALE)
		var port_surface := rect.intersection(port_land)
		if port_surface.has_area():
			# Visual finish only: OriginalSouthPort/land already own physical support.
			var apron := _box(chunk,"SouthPortConcrete",Vector3(port_surface.get_center().x,.007,port_surface.get_center().y),Vector3(port_surface.size.x,.014,port_surface.size.y),Color("4f5552"))
			apron.material_override = preload("res://world/regions/PortYardMaterials3D.gd").concrete()
	else:
		# These authored cells are the water spans of HarborMountainConnector and
		# HarborBridgeCrossing.
		# WorldConnection3D supplies the shared deck/abutment while Harbor owns
		# the water below. Building generic mountain terrain here would create a
		# solid wall through the original bridge route when both regions reside.
		if _mountain_owns_terrain(key):
			terrain.build_chunk(chunk,rect)

func _build_record(chunk: Node3D, record: Dictionary) -> void:
	match record.kind:
		"cemetery":
			var cemetery := CEMETERY.new()
			cemetery.position = record.position
			chunk.add_child(cemetery)
		"south_port_model": SOUTH_PORT.mount(chunk,record)
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
			var prop:=HARBOR_PROP.new()
			prop.configure(record.data)
			prop.position=record.position
			chunk.add_child(prop)
		"harbor_restaurant":
			var terrace := RESTAURANT_TERRACE.new()
			terrace.configure(record.venue_id,record.table_index,record.fabric)
			terrace.position = record.position
			chunk.add_child(terrace)
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
			_box(tree,"TrunkSolid",Vector3(0,1.4,0),Vector3(.4,2.8,.4),Color("00000000"),true).visible=false
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
			_build_sawmill_yard(chunk)
			MOUNTAIN_FACTORY.populate_sawmill_chunk(chunk,record)
		"mountain_village": MOUNTAIN_FACTORY.populate_village_chunk(chunk,record)
		"environmental_parity":
			var mechanism := MOUNTAIN_FACTORY.populate_environmental_chunk(chunk,record)
			if mechanism != null:
				mechanism.set_operating(chairlift_operating)
				mechanism.set_animation_active(true)
				chairlifts.append(mechanism)
		"harbor_route_zone": HARBOR_ROUTE_FACTORY.populate_zone_chunk(chunk, record.zone_id)
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
			var rows: Array = chunk.get_meta("road_surface_rows",[])
			for piece in pieces: rows.append({"polygon":piece,"top":.026,"color":road_color})
			chunk.set_meta("road_surface_rows",rows)
			# Only the main two-lane pass needs a centre stripe.
			if mountain_pass_road:
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
static var _held_resources: Dictionary = {}
static func _held_load(path: String) -> Resource:
	if not _held_resources.has(path): _held_resources[path] = load(path)
	return _held_resources[path]

func _dressing_reserved(point: Vector2, radius: float) -> bool:
	if terrain == null or terrain.is_reserved(point,radius): return true
	var key := _cell(Vector3(point.x,0,point.y))
	for x in range(-1,2):
		for z in range(-1,2):
			for record in records.get(key+Vector2i(x,z),[]):
				if record.kind != "tree": continue
				var tree_point := Vector2(record.position.x,record.position.z)
				if point.distance_to(tree_point) < radius+1.2: return true
	return false

func _authored_surface(chunk: Node3D, polygon: PackedVector2Array) -> void:
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
		surface.set_normal(Vector3.UP)
		surface.add_vertex(a)
		if (b-a).cross(c-a).y > 0:
			surface.add_vertex(c); surface.add_vertex(b)
		else:
			surface.add_vertex(b); surface.add_vertex(c)
	var mesh := MeshInstance3D.new()
	mesh.name = "OriginalPortSurface"
	mesh.mesh = surface.commit()
	mesh.material_override = _material(Color("737b69"))
	chunk.add_child(mesh)
	mesh.create_trimesh_collision()
	for body in mesh.get_children():
		if body is StaticBody3D: body.collision_layer = 1; body.collision_mask = 0
func _building(chunk: Node3D, data: Dictionary) -> void:
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
	if str(data.id).begins_with("mountain_cabin") or data.id == "lumberjack_shelter":
		var art = _held_load("res://assets/regions/source/world/mountain_pass/art/winter_props/LumberjackCabin3D.gd").new()
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id == "mountain_bunker":
		var art = preload("res://world/places/BunkerExteriorNative.gd").new()
		art.position = data.exterior_position
		chunk.add_child(art)
		WALKUP_DOOR.install(art, data)
	elif data.id == "ski_lodge":
		var art = _held_load("res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd").new()
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
		var art := URBAN_FACTORY.populate_chunk(chunk,data)
		if art != null: WALKUP_DOOR.install(art, data)
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
			return not _helipad_reserved(original) and not preload("res://world/mountain_detail/OriginalVillageLayout.gd").is_reserved(original))

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
	var gangway := Rect2(3130*SCALE,1742*SCALE,288*SCALE,40*SCALE)
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
		var cargo_color: Color = [Color("a95e4e"),Color("426b78"),Color("bca26d")][absi(roundi(center.x*7.0+center.z*11.0))%3]
		_box(chunk,"NorthstarCargo",center,size,cargo_color,true)
		for rib_index in 4:
			var rib_z := center.z-size.z*.36+size.z*.24*rib_index
			_box(chunk,"NorthstarCargoRib",Vector3(center.x,2.215,rib_z),Vector3(size.x*.94,.03,.045),cargo_color.darkened(.22))
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
	# Exact MountainSceneryBuilder._is_helipad_reserved, including canopy/corridor clearance.
	if point.distance_to(Vector2(6335,-2795))<125: return true
	var walk := PackedVector2Array([Vector2(6335,-2765),Vector2(6335,-2735),Vector2(6365,-2720),Vector2(6440,-2720)])
	for i in range(walk.size()-1):
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,walk[i],walk[i+1]))<65: return true
	return false
func _build_sawmill_yard(chunk: Node3D) -> void:
	# Original yard polygons overlay the earth road in V1(z1 over z0); no source moved.
	var origin := CATALOG._at(Vector2(6350,560),"mountain")
	var polygons := [PackedVector2Array([Vector2(-180,-110),Vector2(180,-110),Vector2(200,130),Vector2(-170,140)]),PackedVector2Array([Vector2(-35,-165),Vector2(35,-165),Vector2(55,-100),Vector2(-55,-100)])]
	for i in polygons.size():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in Geometry2D.triangulate_polygon(polygons[i]):
			var point: Vector2 = polygons[i][index]*SCALE
			surface.add_vertex(Vector3(point.x,.024,point.y))
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "OriginalSawmillYard" if i==0 else "OriginalSawmillDriveway"
		mesh.mesh = surface.commit()
		mesh.material_override = _material(Color("382e22"))
		mesh.position = origin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(mesh)
		mesh.create_trimesh_collision()

## Registra em `slow_stream_records` uma etapa do streaming que passou de `limit_usec`
## (só para diagnóstico com a sonda; não tem efeito sem a meta).
func _note_slow(what: String, since_usec: int, limit_usec: int) -> void:
	var spent := Time.get_ticks_usec()-since_usec
	if spent < limit_usec or not Engine.has_meta("slow_stream_records"): return
	var slow: Array = Engine.get_meta("slow_stream_records")
	slow.append("PROCESS %s %.0f ms"%[what,spent/1000.0])
	Engine.set_meta("slow_stream_records",slow)
