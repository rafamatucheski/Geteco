extends RefCounted
## Roof destinations for buildings whose ground floor has an existing owner.
## These are additional floors, never duplicate service interiors or gate bypasses.
const PLACE_IDS := ["harbor_bank","harbor_supermarket","harbor_ammunation","harbor_clothing","harbor_fuel","maciota","harbor_police","harbor_hospital","harbor_fire_station","canal_north","cobra_leader_house","westgate_garden","quayside_house","cemetery_keeper","port_boss_garage"]
const SOURCE_IDS := {"NorthFrontage0":"harbor_bank","NorthFrontage1":"harbor_supermarket","NorthFrontage2":"harbor_ammunation","NorthFrontage3":"harbor_clothing","NorthFrontage4":"harbor_fuel","Police":"harbor_police","Clinic":"harbor_hospital","NorthFireStation":"harbor_fire_station","CanalHomesWest":"canal_north","CourtyardHouse":"cobra_leader_house","MotorWorkshop":"northgate_auto_roof"}
static var _cache: Array[Dictionary] = []
static var _cache_signature := -1
const SERVICES := preload("res://world/editing/WorldServiceBuildings.gd")
const URBAN_BUILDING_FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")

static func definitions(include_deleted := false) -> Array[Dictionary]:
	var edits := SERVICES.changes()
	var relevant: Array = []
	for source in SOURCE_IDS: relevant.append(edits.get("building/"+str(source),{}))
	var signature := hash(relevant)
	if signature != _cache_signature:
		_cache.clear()
		_cache_signature = signature
	if not _cache.is_empty(): return _available(edits,include_deleted)
	var places = preload("res://world/places/PlaceCatalog.gd")
	var originals: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var original_by_id := {}
	for row: Dictionary in originals.harbor_buildings: original_by_id[str(row.id)] = row
	var mapping := {"harbor_bank":"NorthFrontage0","harbor_supermarket":"NorthFrontage1","harbor_ammunation":"NorthFrontage2","harbor_clothing":"NorthFrontage3","harbor_fuel":"NorthFrontage4","harbor_police":"Police","harbor_hospital":"Clinic","harbor_fire_station":"NorthFireStation","canal_north":"CanalHomesWest","cobra_leader_house":"CourtyardHouse"}
	for id in PLACE_IDS:
		var source: Dictionary = places.get_definition(id) if id!="maciota" else {}
		var center: Vector3 = source.get("exterior_position",Vector3(168.5,0,101.5))
		var size: Vector2 = Vector2(9,6.2)
		var height := 4.35
		var yaw := float(source.get("editor_rotation",0.0))
		var ladder_fraction := NAN
		match id:
			"harbor_bank":
				size=Vector2(14.375,11.25); height=4.93
				# Banco pintado: largura natural do estilo e a altura da pintura (como a delegacia).
				if not PaintedHarborHouses.style_for("NorthFrontage0","bank_branch").is_empty():
					size.x=PaintedHarborHouses.footprint_width("NorthFrontage0",size.x)
					height=PaintedBankBranch.roof_height()
			"harbor_supermarket":
				size=Vector2(14.2,11); height=4.40
				# Boa Praça pintado: largura natural da pintura e laje na altura dela.
				var painted_market := preload("res://world/places/supermarket/PaintedSupermarketFacade.gd")
				if painted_market.available():
					size=Vector2(painted_market.size().x,painted_market.DEPTH)
					height=painted_market.roof_height()
			"harbor_ammunation": size=Vector2(14.20,10.70); height=3.13
			"harbor_clothing": size=Vector2(14.375,11.25); height=6.94
			"harbor_fuel": size=Vector2(14.375,11.25); height=5.33
			"maciota": center+=Vector3(-2.5,0,4.6875); size=Vector2(7.8,6.25); height=4.64
			"harbor_police","harbor_fire_station":
				var record: Dictionary = original_by_id[mapping[id]]
				size=Vector2(record.size[0],record.size[1])/16.0
				height=URBAN_BUILDING_FACTORY.resolved_height(record)+.14
				# Delegacia pintada: a parede tem a altura da pintura, menos o que afunda até a soleira.
				if id=="harbor_police" and not PaintedHarborHouses.style_for("Police","police_precinct").is_empty(): height=PaintedPoliceStation.roof_height()
				# Quartel pintado: a escada de marinheiro da lateral leste chega ao telhado;
				# a saída (casinha) fica no topo dela, não no canto oeste (playtest 29/10).
				if id=="harbor_fire_station" and not PaintedHarborHouses.style_for("NorthFireStation","fire_station").is_empty():
					ladder_fraction = PaintedFacadeKit.side_ladder_z(PaintedFireStation.STYLE,size.y)/size.y
			"harbor_hospital": center+=Vector3(-50.0/18.0,0,0); size=Vector2(151.0/18.0,221.0/(18*.76822128)); height=5.35
			"canal_north": size=Vector2(9.3,6.65); height=5.34
			"cobra_leader_house":
				var row: Dictionary = preload("res://world/editing/WorldServiceBuildings.gd").changes().get("building/CourtyardHouse",{})
				size = Vector2(12.3,8.8)
				height = 9.20
				if not row.is_empty():
					center = Vector3(row.position[0],0,row.position[1])
					yaw = deg_to_rad(float(row.rotation))
					size = Vector2(row.size[0],float(row.size[1])-1.8)
					height = float(row.height)+1.7
				center += Vector3(0,0,-.9).rotated(Vector3.UP,yaw)
			"westgate_garden": size=Vector2(9.0,6.20); height=4.50
			"quayside_house": size=Vector2(9.25,6.55); height=3.38
			"cemetery_keeper": size=Vector2(7.1,5.4); height=4.04
			"port_boss_garage": center+=Vector3(-13.8,0,0); size=Vector2(15,6); height=3.43
		if source.has("editor_scale"):
			var stretch: Vector3 = source.editor_scale
			size *= Vector2(stretch.x,stretch.z)
			height *= stretch.y
		_append(id,id,center,size,height,yaw)
		if is_finite(ladder_fraction):
			# Patamar alinhado ao topo da escada, casinha logo atrás (para o norte).
			_set_stair(_cache[-1],Vector3(size.x*.5-1.45,0,ladder_fraction*size.y))
	var village = preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
	for index in village.HOME_LAYOUT.size():
		var home: Array = village.HOME_LAYOUT[index]
		_append("truckers_home_%d"%(index+1),"",village.ORIGIN+home[0],Vector2(12.6,8.6),4.58,float(home[2]),"village_home",index)
	_append("truckers_tire_shop","",Vector3(-269,0,104),Vector2(15,10),4.17,0,"tire_shop")
	_append("vertice_roof","",Vector3(-340,0,-81),Vector2(55.5,37.5),11.40,0,"vertice")
	var motor: Dictionary = original_by_id.MotorWorkshop
	_append("northgate_auto_roof","",Vector3(motor.position[0]/16.0,0,motor.position[1]/16.0),Vector2(motor.size[0],motor.size[1])/16.0,URBAN_BUILDING_FACTORY.resolved_height(motor)+.45,0,"northgate")
	return _available(edits,include_deleted)

static func _available(edits: Dictionary, include_deleted: bool) -> Array[Dictionary]:
	if include_deleted: return _cache
	return _cache.filter(func(row):
		var source: Variant = SOURCE_IDS.find_key(str(row.id))
		return source == null or not edits.get("building/"+str(source),{}).get("deleted",false))

static func _append(id: String, place: String, center: Vector3, size: Vector2, height: float, yaw: float, owner := "service", index := -1) -> void:
	_cache.append({"id":id,"place":place,"owner":owner,"index":index,"exterior_position":center,"exterior_rotation":yaw,"size":size,"roof_height":height,
		"floor_count":1,"storey_height":height,"variant":0,"archetype":"office","building_kind":"service",
		"spawn":Vector3(-size.x*.5+2.80,0,1.45),"exit":Vector3(-size.x*.5+1.45,0,1.45),
		"camera_target":Vector3(0,.65,0),"camera_size":clampf(maxf(size.x,size.y)*1.7,32.0,64.0),
		"reward":{},"rewards":[],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO})
	# The fire station's authored emergency siren owns the southeast corner.
	# Its roof exit is a separate bay to the left, preserving that solid detail.
	if id=="harbor_fire_station": _cache[-1].jump_x = maxf(.7,size.x*.5-3.8)

## Saída do telhado fora do canto oeste padrão: patamar em `stair`, chegada (spawn) 1,35 m
## para dentro do telhado, nunca para fora da platibanda.
static func _set_stair(definition: Dictionary, stair: Vector3) -> void:
	var inward := Vector3.RIGHT if stair.x < 0.0 else Vector3.LEFT
	definition["stair"] = stair
	definition["exit"] = stair
	definition["spawn"] = stair+inward*1.35

static func find(id: String, include_deleted := false) -> Dictionary:
	for definition in definitions(include_deleted):
		if str(definition.id)==id: return definition
	return {}

static func for_source(id: String) -> Dictionary:
	return find(str(SOURCE_IDS[id])) if SOURCE_IDS.has(id) else {}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if value.size()!=3 or not value.has("id") or not value.has("place") or not value.has("return"): return false
	if not value.id is String or not value.place is String: return false
	var definition := find(value.id,true)
	if definition.is_empty() or str(definition.place)!=value.place: return false
	if not value["return"] is Array or value["return"].size()!=3: return false
	for coordinate in value["return"]:
		if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(coordinate)) or absf(float(coordinate))>100000: return false
	return true
