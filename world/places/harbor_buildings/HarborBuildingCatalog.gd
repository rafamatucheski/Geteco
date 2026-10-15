extends RefCounted
## Effective city inventory, including editor additions and port buildings.
const EXISTING := {
	"NorthFrontage0":"harbor_bank", "NorthFrontage1":"harbor_supermarket",
	"NorthFrontage2":"harbor_ammunation", "NorthFrontage3":"harbor_clothing",
	"NorthFrontage4":"harbor_fuel", "Garage":"maciota_garage",
	"Police":"harbor_police", "Clinic":"harbor_hospital",
	"NorthFireStation":"harbor_fire_station", "CanalHomesWest":"canal_north",
	"CourtyardHouse":"cobra_leader_house", "MotorWorkshop":"northgate_auto",
}
const LEGACY_IDS := {"NorthFrontage5":"harbor_customs_house", "Apartments":"harbor_union_apartments"}
static var _cache: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _by_source: Dictionary = {}
static var _stamp := ""

static func definitions() -> Array[Dictionary]:
	if Engine.get_meta("harbor_buildings_measure_baseline",false): return []
	var edits: Dictionary = preload("res://world/editing/WorldServiceBuildings.gd").changes()
	var stamp := str(FileAccess.get_modified_time("res://world/regions/OriginalWorldData.json"))+":"+str(hash(edits))
	if stamp == _stamp: return _cache
	_stamp = stamp
	_cache.clear()
	_by_id.clear()
	_by_source.clear()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	for record: Dictionary in source.get("harbor_buildings",[]):
		var id := str(record.id)
		if EXISTING.has(id) or bool(record.get("exterior_only", false)): continue
		var edit: Dictionary = edits.get("building/"+id,{})
		if edit.get("deleted",false): continue
		var row := record.duplicate(true)
		row.position = Vector3(float(record.position[0])/16.0,0,float(record.position[1])/16.0)
		row.size = Vector2(float(record.size[0])/16.0,float(record.size[1])/16.0)
		_apply_edit(row,edit)
		_append(row)
	for key in edits:
		var edit: Dictionary = edits[key]
		if not str(key).begins_with("new/") or edit.get("type","") != "building" or edit.get("deleted",false): continue
		var row := {"id":str(key).replace("/","_"),"name":"","kind":str(edit.model)}
		_apply_edit(row,edit)
		_append(row)
	for record: Dictionary in preload("res://world/regions/OriginalSouthPort.gd").records():
		if not str(record.id).begins_with("PortBuilding"): continue
		var size: Vector2 = record.footprint.size/16.0
		var height := (7.5 if size.x/1.25 > 20.0 else 4.5) if record.model_kind == "warehouse" else (4.8 if int(record.variant) == 2 else 3.2)
		_append({"id":record.id,"name":"","kind":record.model_kind,"position":record.position,"size":size,"height_override":height,"port_building":true,"variant_seed":int(record.variant)})
	_append({"id":"TorqueStore","name":"Torque","kind":"shop","position":Vector3(419.5,0,134),"size":Vector2(19,8),"height_override":4.26,"editor_rotation":PI,"entrance_x":-.5})
	_append({"id":"TruckersStationStore","name":"Tonico","kind":"shop","position":Vector3(-359.56,0,78.68),"size":Vector2(18.72,7.4),"height_override":2.91})
	return _cache

static func _apply_edit(row: Dictionary, edit: Dictionary) -> void:
	if edit.has("position"): row.position = Vector3(float(edit.position[0]),0,float(edit.position[1]))
	if edit.has("size"): row.size = Vector2(float(edit.size[0]),float(edit.size[1]))
	if edit.has("model"): row.kind = str(edit.model)
	if edit.has("height"): row.height_override = float(edit.height)
	row.editor_rotation = deg_to_rad(float(edit.get("rotation",0.0)))

static func _append(row: Dictionary) -> void:
	var source_id := str(row.id)
	var id: String = LEGACY_IDS.get(source_id,"harbor_building_"+source_id.to_snake_case())
	var kind := str(row.get("kind","office"))
	var size: Vector2 = row.size
	var base_position: Vector3 = row.position
	var yaw := float(row.get("editor_rotation",0.0))+(PI if row.get("entrance_north",false) else 0.0)
	if source_id == "new_1790426066_503_97028106":
		# The east frontage meets the edited BRT tube. Its north side opens
		# onto the public walkway, with the same physical footprint and height.
		size = Vector2(size.y,size.x)
		yaw += PI*.5
	var basis := Basis(Vector3.UP,yaw)
	var at := base_position
	at.y += .12 # Match the urban pavement; the native floor top is 2cm below.
	# Preserve the open L-shaped courtyard and the covered Cobra porches.
	if kind == "l_shaped_block":
		at += basis*Vector3(0,0,-size.y*.225)
		size.y *= .55
	elif kind == "cobra_house":
		at += basis*Vector3(0,0,-.9)
		size.y -= 1.8
	var height: float = load("res://world/urban_detail/UrbanBuildingFactory.gd").resolved_height(row)
	if kind == "rowhouse_terrace": height = 7.05 if "East" in source_id else 6.85
	var roof_height := height+.10
	var inhabited_height := height
	if kind == "house_gable": inhabited_height *= .72
	elif kind == "house_duplex": inhabited_height *= .67
	elif kind == "warehouse_sawtooth": inhabited_height *= .75
	elif kind == "warehouse_loading": inhabited_height *= .79
	var floor_count := maxi(1,floori(inhabited_height/2.85))
	if kind == "cobra_house": roof_height += 1.55
	var proper: String = load("res://world/urban_detail/UrbanSignage.gd").extract_proper_name(source_id,str(row.get("name","")))
	var entry_local := Vector3(float(row.get("entrance_x",0.0)),0,size.y*.5)
	if kind == "l_shaped_block": entry_local.x = -size.x*.25
	# Aligned to the pedestrian gate beside Maciota's M8 parking bay.
	if source_id == "FreightOffice": entry_local.x = 4.0
	# Sobrado pintado: a entrada de verdade vai para o vão de porta desenhado mais
	# próximo; senão o corte da porta real abria no meio das janelas pintadas.
	if kind in ["brownstone", "rowhouse_terrace"] and PaintedFacadeKit.enabled():
		entry_local.x = PaintedFacadeKit.nearest_door_x(PaintedFacadeKit.residential_style(source_id), size.x, entry_local.x)
	var entry := at+basis*(entry_local+Vector3.BACK*.9)
	var def := {
		"id":id,"original_name":proper,"region":"harbor","source_id":source_id,
		"model":"res://world/places/harbor_buildings/HarborBuildingInterior.gd",
		"building_kind":kind,"archetype":_archetype(source_id,kind),
		"variant":posmod(hash(source_id),104729),"floor_count":floor_count,
		"storey_height":inhabited_height/float(floor_count),"roof_height":roof_height,
		"exterior_position":at,"facade_position":base_position,"exterior_rotation":yaw,
		"entry_position":entry,"return_position":entry+basis*Vector3.BACK*.8,
		"entrance_local":entry_local,"spawn":entry_local+Vector3.FORWARD*1.45,
		"exit":entry_local+Vector3.FORWARD*.5,"size":size,
		"camera_target":Vector3(0,.65,0),"camera_size":clampf(maxf(size.x*.86,size.y*1.04),10,24),
		"service":"exploration","reward":{},"rewards":[],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO,
		"continuous_access":true,"port_building":bool(row.get("port_building",false)),
		"pitched_roof":kind in ["cobra_house","house_gable","house_duplex","warehouse_sawtooth"],
		"integration_status":"continuous_access_pending_validation",
	}
	# The elevated road in front of Customs must remain real while the ground
	# floor stays readable. A steeper interior angle looks over that foreground.
	if source_id == "NorthFrontage5": def["ground_camera_offset"] = Vector3(0,22,9)
	# Slab towers have fixed ventilation boxes in the front-right roof bay.
	# Keep the discoverable cache on the open central service aisle instead.
	if kind == "urban_slab": def["roof_cache_position"] = Vector3(0,.03,-size.y*.1)
	if source_id == "TorqueStore": def["facade_cut_front"] = 2.4
	def.rewards = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd").all_rewards(def)
	_cache.append(def)
	_by_id[id] = def
	_by_source[source_id] = def

static func _archetype(id: String, kind: String) -> String:
	if id in ["MaritimeMuseum","Aquarium","CommunityHall","CivicTower"]: return "civic"
	if id in ["CornerDiner","PromenadeCafe","ServiceCafe","NorthbankFront3","ServiceLodge"]: return "hospitality"
	if id in ["Apartments","UnionApartments","FoundryLofts"] or kind in ["brownstone","rowhouse","rowhouse_terrace","cobra_house","house_gable","house_duplex","urban_slab","urban_infill"]: return "residential"
	if kind in ["warehouse","artisan_workshop","warehouse_sawtooth","warehouse_loading"]: return "industrial"
	if kind in ["corner_shop","shop","commercial_laundromat","warehouse_shop","bank_branch"]: return "retail"
	return "office"

static func find(id: String) -> Dictionary:
	definitions()
	return _by_id.get(id,{})

static func for_source(id: String) -> Dictionary:
	definitions()
	return _by_source.get(id,{})

static func is_building(id: String) -> bool:
	return id in LEGACY_IDS.values() or id.begins_with("harbor_building_")

static func valid_floors(value: Variant) -> bool:
	if not value is Dictionary: return false
	for id in value:
		var definition := find(str(id))
		if definition.is_empty(): return false
		if typeof(value[id]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[id])): return false
		# Batch-one saves had four floors: admission clamps to the physical roof.
		var maximum := maxi(3,int(definition.floor_count)) if id in LEGACY_IDS.values() else int(definition.floor_count)
		if value[id]<0 or value[id]>maximum or float(value[id])!=floorf(float(value[id])): return false
	return true
