extends RefCounted
## Authored batches. Existing services and mission gates keep their own owners.
const SITES := [
	{"building":"NorthFrontage5","id":"harbor_customs_house","name":"Customs House","at":Vector3(173.75,0,8.75),"size":Vector2(14,11),"depth":11.25,"variant":0},
	{"building":"Apartments","id":"harbor_union_apartments","name":"Union Lofts","at":Vector3(96.875,0,95.625),"size":Vector2(11,14),"depth":14.375,"variant":4},
]

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	# Measurement-only A/B: same current checkout with this new batch absent.
	if Engine.get_meta("harbor_buildings_measure_baseline",false): return result
	var edits: Dictionary=preload("res://world/editing/WorldServiceBuildings.gd").changes()
	for site in SITES:
		var edit: Dictionary=edits.get("building/"+site.building,{})
		if edit.get("deleted",false): continue
		var at: Vector3=site.at
		var depth: float=site.depth
		var yaw:=0.0
		if edit.has("position"): at=Vector3(edit.position[0],0,edit.position[1])
		if edit.has("size"): depth=float(edit.size[1])
		if edit.has("rotation"): yaw=deg_to_rad(float(edit.rotation))
		var outward:=Basis(Vector3.UP,yaw)*Vector3.BACK
		var entry:=at+outward*(depth*.5+.95)
		result.append({"id":site.id,"original_name":site.name,"region":"harbor","source_id":site.building,
			"model":"res://world/places/harbor_buildings/HarborBuildingInterior.gd","variant":site.variant,"floor_count":4,
			"exterior_position":at,"entry_position":entry,"return_position":entry+outward*.65,
			"spawn":Vector3(0,0,site.size.y*.5-1.6),"exit":Vector3(0,0,site.size.y*.5-.65),
			"size":site.size,"camera_target":Vector3(0,.65,0),"camera_size":maxf(site.size.x*1.05,site.size.y*1.15),
			"service":"exploration","reward":{},"rewards":[],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO,
			"integration_status":"batch_1_pending_validation"})
	return result

static func is_building(id: String) -> bool:
	for site in SITES:
		if site.id==id: return true
	return false

static func valid_floors(value: Variant) -> bool:
	if not value is Dictionary: return false
	for id in value:
		if not is_building(str(id)): return false
		if typeof(value[id]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[id])): return false
		if value[id]<0 or value[id]>3 or float(value[id])!=floorf(float(value[id])): return false
	return true
