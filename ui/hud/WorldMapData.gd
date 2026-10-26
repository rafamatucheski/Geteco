extends RefCounted
## Read-only snapshot of prepared production geography. Never mounts a region,
## creates a physics body, modifies the route graph or changes campaign state.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const GATE := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const SYMBOLS := preload("res://ui/hud/MapSymbols.gd")
const RELIEF := preload("res://ui/hud/MapRelief.gd")
const NAV_PLACES := preload("res://ui/hud/NavigationPlaces.gd")
var roads: Array[Dictionary]=[]
var lands: Array[Dictionary]=[]
var buildings: Array[PackedVector2Array]=[]
var markers: Array[Dictionary]=[]
var bounds := Rect2()
var region_bounds := {}
var _definitions := {}
var _first := true
var relief := RELIEF.new()
var relief_cache_hit := false

static func planar(point: Vector3) -> Vector2: return Vector2(point.x,point.z)
static func rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

func collect(controller, prepare_relief := true) -> void:
	for definition in CATALOG.definitions(): _definitions[definition.id]=definition
	var regions := {}
	if controller.world is Node and is_instance_valid(controller.world.get("production")):
		var production = controller.world.production
		regions=production._region_cache.duplicate()
		regions.merge(production.regions,true)
	regions[str(controller.state.region_id)]=controller.region
	for id in regions:
		var region = regions[id]
		_read_region(str(id),region)
	if regions.has("harbor"):
		_add_road({"points":GATE.centerline(),"width":GATE.ROAD_HALF_WIDTH*2},"harbor")
		var completed := preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(controller.state.campaign.snapshot())
		if not completed: add_marker("north_gate","Passagem fechada",GATE.WORK_POSITION,"lock","harbor")
	if regions.has("mountain"): _mountain_markers(regions.mountain)
	if regions.has("desert"): _desert_markers()
	_forge_markers(controller.state,regions)
	if regions.has("desert"): _roadside_markers(controller.state)
	for station in preload("res://runtime/regional/RegionalCoachRoute.gd").stations():
		if regions.has(station.region): add_marker("coach_"+str(station.id),str(station.label),station.arrival,"bus",str(station.region))
	if "--railway-baseline" not in OS.get_cmdline_user_args(): _railway_markers(controller.state)
	if controller.world is Node and is_instance_valid(controller.world.get("maciota_place")):
		add_marker("maciota","Maciota",controller.world.maciota_place.exterior_return,"workshop","harbor")
	if controller.world is Node and controller.world.get("session") != null and controller.world.session.has_method("navigation_destination"):
		for place in NAV_PLACES.harbor(controller.world.session):
			if not markers.any(func(marker): return marker.id==place.id): markers.append(place)
	if regions.has("harbor"):
		add_marker("motocross","Motocross",Vector3(-224,0,-37),"race","harbor")
		add_marker("fishing","Lago Sereno",preload("res://runtime/FishingLocation.gd").ENTRY,"fishing","harbor")
		if preload("res://world/places/amusement_park/AmusementParkLayout.gd").enabled():
			add_marker("amusement_park","Parque Lume",preload("res://world/places/amusement_park/AmusementParkLayout.gd").ENTRY,"place","harbor")
		add_marker("south_port","Porto",Vector3(296,0,288),"port","harbor")
	for marker in markers:
		if region_bounds.has(marker.region): region_bounds[marker.region]=region_bounds[marker.region].expand(marker.point).grow(1)
	for id in region_bounds:
		var rect: Rect2=region_bounds[id]
		if _first: bounds=rect; _first=false
		else: bounds=bounds.merge(rect)
	# Presentation is prepared once from this snapshot. Navigation bounds and
	# the authoritative land/road/marker arrays remain independent of the relief.
	# Only the immutable presentation package is reused. Roads and markers above
	# are still collected afresh, including editor geometry and quest discovery.
	if not prepare_relief: return
	var signature_parts: Array=[lands,roads,region_bounds]
	for id in regions:
		var region: Variant=regions[id]
		if region is Node:
			signature_parts.append([str(id),region.get_instance_id(),region.get("records")])
	var signature := hash(signature_parts)
	var owner_node: Node=controller.world if controller.world is Node else null
	var cached: Dictionary=owner_node.get_meta("map_relief_cache",{}) if owner_node!=null else {}
	if int(cached.get("signature",-1))==signature and cached.get("relief")!=null:
		relief=cached.relief
		relief_cache_hit=true
	else:
		relief.prepare(lands,regions,region_bounds)
		# The world owns at most one package; ending the session releases its
		# meshes. The package never retains the world/terrain nodes themselves.
		if owner_node!=null: owner_node.set_meta("map_relief_cache",{"signature":signature,"relief":relief})

func _read_region(id: String, region) -> void:
	var extent := Rect2(); var first := true
	for road in region.map_routes():
		_add_road(road,id)
		for point: Vector3 in road.points:
			var p := planar(point)
			extent=Rect2(p,Vector2.ONE) if first else extent.expand(p); first=false
	region_bounds[id]=extent.grow(32)
	for entry in region.entries:
		var definition: Dictionary=_definitions.get(entry.get("place_id",""),{})
		var title := str(definition.get("original_name",entry.get("label","Destino")))
		add_marker(str(entry.get("id",title)),title,entry.position,_service_icon(str(definition.get("service",""))),id)
	if not region is Node: return # Small contract fixture; production always supplies Nodes.
	for building in region.buildings:
		var polygon := rectangle(Rect2(-building.size*.5,building.size))
		var angle := float(building.get("editor_rotation",0.0))
		for i in polygon.size(): polygon[i]=polygon[i].rotated(angle)+planar(building.position)
		buildings.append(polygon)
	if id=="harbor":
		for row in region.source_data.harbor_land:
			var rect := Rect2(row[0]/16.0,row[1]/16.0,row[2]/16.0,row[3]/16.0)
			lands.append({"polygon":rectangle(rect),"biome":"forest" if rect.position.x< -90 else "city"})
		for polygon in region.extra_land:
			var fishing_forest: bool = polygon==preload("res://world/places/fishing/FishingRuralLayout.gd").outline()
			lands.append({"polygon":polygon,"biome":"forest" if fishing_forest else "city"})
	elif id=="desert":
		lands.append({"polygon":rectangle(DESERT.BOUNDS),"biome":"desert"})
	elif id=="mountain":
		# The terrain is continuous east of the bridge. Its cartographic extent
		# follows authored records, excluding the sea-spanning entry road.
		var points := PackedVector2Array()
		for key in region.records:
			if key.x<9 or key.y>=-2: continue
			points.append_array(rectangle(Rect2(Vector2(key)*64,Vector2.ONE*64)))
		for road in roads:
			if road.region!="mountain": continue
			for point in road.points:
				if point.x>456.25 and (point.y< -320 or point.x>559.375):
					points.append_array(rectangle(Rect2(point-Vector2.ONE*18,Vector2.ONE*36)))
		if points.size()>2: lands.append({"polygon":Geometry2D.convex_hull(points),"biome":"mountain"})
		for definition in _definitions.values():
			if definition.region!="mountain" or definition.get("hidden_access",false): continue
			buildings.append(rectangle(Rect2(planar(definition.exterior_position)-definition.size*.5,definition.size)))
		var lakes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalLakeData.json"))
		for key in lakes:
			var polygon := PackedVector2Array()
			var lake_points: Array=lakes[key].get("lake_shore",lakes[key].get("shallow",[]))
			for p in lake_points:
				var point := Vector2(p[0],p[1])
				if key=="secret": point+=Vector2(5450,-1150)
				polygon.append(planar(CATALOG._at(point,"mountain")))
			if polygon.size()>2: lands.append({"polygon":polygon,"biome":"water"})

func _add_road(source: Dictionary, region: String) -> void:
	var points := PackedVector2Array()
	for point: Vector3 in source.points: points.append(planar(point))
	if points.size()<2: return
	var rect := Rect2(points[0],Vector2.ZERO)
	for point in points: rect=rect.expand(point)
	roads.append({"points":points,"width":float(source.get("width",5)),"surface":str(source.get("surface","asphalt")),"region":region,"bounds":rect.grow(16),"id":str(source.get("id",""))})

func add_marker(id: String, title: String, point: Vector3, kind: String, region: String) -> void:
	markers.append({"id":id,"title":title,"point":planar(point),"kind":kind,"region":region,"detail":"","objective":false})

func _mountain_markers(region) -> void:
	add_marker("forge","Forja da Serra",preload("res://world/mountain_detail/forge/MountainForge.gd").CENTER,"forge","mountain")
	add_marker("jeep","Trilha de jipe",preload("res://world/mountain_jeep/MountainJeepCourse.gd").start(),"jeep","mountain")
	if preload("res://world/mountain_detail/MountainRefuge.gd").enabled():
		add_marker("refuge","Refúgio da Serra",preload("res://world/mountain_detail/MountainRefuge.gd").CENTER,"home","mountain")
	for records in region.records.values():
		for record in records:
			if record.kind=="cargo_plane": add_marker("plane","Avião dos Cobras",record.position,"plane","mountain")
	var lift := preload("res://world/environmental_parity/MountainChairliftParity3D.gd")
	add_marker("lift","Teleférico",CATALOG._at(lift.SOURCE_POINTS[-1],"mountain"),"lift","mountain")
	var cable := PackedVector3Array()
	for point in lift.SOURCE_POINTS: cable.append(CATALOG._at(point,"mountain"))
	_add_road({"id":"chairlift_cable","points":cable,"width":1.0,"surface":"cable"},"mountain")
	region_bounds.mountain=region_bounds.mountain.expand(planar(cable[-1])).grow(12)
	for id in preload("res://activities/MountainProgression.gd").COURSES:
		var course: Dictionary=preload("res://activities/MountainProgression.gd").COURSES[id]
		add_marker(id,course.name,CATALOG._at(course.start,"mountain"),"ski","mountain")
		var line := PackedVector3Array([CATALOG._at(course.start,"mountain")])
		for point in course.points: line.append(CATALOG._at(point,"mountain"))
		_add_road({"id":id,"points":line,"width":1.0,"surface":"ski"},"mountain")
	# Ski terrain extends beyond the road/forest record cells. Include its real
	# activity corridors in the land footprint instead of painting them at sea.
	for land in lands:
		if land.biome!="mountain": continue
		var coverage: PackedVector2Array=land.polygon.duplicate()
		for road in roads:
			if road.region!="mountain" or (road.surface not in ["ski","cable"] and road.id!="forge_hermit_trail"): continue
			for point in road.points: coverage.append_array(rectangle(Rect2(point-Vector2.ONE*18,Vector2.ONE*36)))
		land.polygon=Geometry2D.convex_hull(coverage)
	var downhill := preload("res://activities/mountain_downhill/MountainDownhillCourse.gd").new()
	add_marker("downhill","Descida da Meia Noite",downhill.start_position(),"race","mountain")
	add_marker("village","Vila da montanha",CATALOG._at(preload("res://world/mountain_detail/OriginalVillageLayout.gd").BUS_DOOR,"mountain"),"bus","mountain")

func _desert_markers() -> void:
	add_marker("drag","Arrancada",DESERT.drag_staging_point(),"race","desert")
	add_marker("fuel","Miragem",DESERT.TRUCK_STOP,"fuel","desert")
	add_marker("moon","Santa Lua",preload("res://world/desert/DesertMoonVillage.gd").CENTER,"home","desert")
	add_marker("mining","Mineração",preload("res://world/mining/MiningLayout.gd").GATE,"mine","desert")
	add_marker("wash","Leito seco",preload("res://activities/desert_wash/DesertWashCourse.gd").gate(0),"jeep","desert")
	for b in DESERT.buildings():
		if b.kind in ["motel","diner","shop"]: add_marker(b.id,b.name,b.position,"food" if b.kind=="diner" else "home" if b.kind=="motel" else "place","desert")

## Pista da Forja da Serra: a cabana e o acampamento só entram no mapa depois que alguém
## conta onde ficam (estágio em world_state.blade_forge).
func _forge_markers(state, regions: Dictionary) -> void:
	if not state is Object or not state.get("world_state") is Dictionary: return
	var forge := preload("res://gameplay/forge/BladeForge.gd")
	var saved: Variant = state.world_state.get("blade_forge",{})
	var stage: String = str(saved.get("stage","unknown")) if forge.valid_quest(saved) else "unknown"
	var index := forge.stage_index(stage)
	if regions.has("mountain") and index>=forge.stage_index("seek_hermit"):
		add_marker("forge_hermit","Cabana do Mestre Aurélio",preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd").CENTER,"home","mountain")
		if stage=="seek_hermit": markers.back().detail="O Seu Bento disse que o mestre sabe fazer aço lendário."
	if regions.has("desert") and index>=forge.stage_index("seek_miner"):
		add_marker("forge_miner","Acampamento do Tião",preload("res://world/desert/DesertMinerCamp.gd").CENTER,"mine","desert")
		if stage=="seek_miner": markers.back().detail="O minério negro para a lâmina lendária."

## Beira de estrada do deserto: posto, torre, ferro-velho, lanche e o que a torre de rádio avistou.
func _roadside_markers(state) -> void:
	if not state is Object or not state.get("world_state") is Dictionary or state.get("economy") == null: return
	for entry in preload("res://runtime/desert/roadside/RoadsideSecrets.gd").map_markers(state.world_state,state.economy):
		add_marker(str(entry.id),str(entry.title),entry.point,str(entry.kind),"desert")
		markers.back().detail=str(entry.detail)

func _railway_markers(state) -> void:
	if not state is Object or not state.campaign is Object: return
	var network := preload("res://world/railway/RailwayNetwork.gd")
	var unlocked := preload("res://world/north_gateway/NorthGatewayPolicy.gd").campaign_completed(state.campaign.snapshot())
	for station in network.stations():
		add_marker("railway_"+str(station.id),str(station.label),station.entry,"train",str(station.region))
		if station.requires_act1 and not unlocked:
			markers.back().detail="Conclua a última missão da cidade 1."
	for edge in network.edges():
		_add_road({"id":"railway_"+str(edge.id),"points":edge.points,"width":1.5,"surface":"railway"},"world")

func _service_icon(service: String) -> String:
	return NAV_PLACES.service_icon(service)
