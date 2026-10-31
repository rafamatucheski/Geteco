extends RefCounted
## As mesmas entradas nomeadas nos dois mapas, em cache com a geografia regional preparada.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
static var _definitions: Dictionary = {}

static func entrance(entry: Dictionary, region: String) -> Dictionary:
	if _definitions.is_empty():
		for definition in CATALOG.definitions(): _definitions[definition.id]=definition
	var definition: Dictionary = _definitions.get(str(entry.get("place_id","")),{})
	return {"id":str(entry.get("id","")),"title":str(definition.get("original_name",entry.get("label","Local"))),"point":Vector2(entry.position.x,entry.position.z),"kind":service_icon(str(definition.get("service",""))),"region":region}

static func service_icon(service: String) -> String:
	match service:
		"bank","hospital","police","clothing","weapons","fuel": return service
		"fire_station": return "fire"
		"supermarket","wine": return "shop"
		"ski_rental": return "ski"
		"expedition","bunker","desert_underground": return "cave"
		"sewer": return "sewer"
		"cargo_hold": return "port"
		"restricted_garage","desert_tuning","garage": return "workshop"
		"shelter","residence","cemetery","exploration": return "home"
		"restaurant","food": return "food"
	return "place"

static func harbor(session) -> Array[Dictionary]:
	var mission = session.mission_world
	var rows: Array[Dictionary] = []
	for id in ["neco","ferrugem"]:
		var point: Vector3 = mission.targets[id]
		rows.append({"id":id,"title":"Neco" if id=="neco" else "Ferrugem","kind":"workshop","point":Vector2(point.x,point.z),"region":"harbor"})
	var point: Vector3 = session.world.maciota_place.entry_position
	rows.append({"id":"maciota","title":"Maciota","kind":"workshop","point":Vector2(point.x,point.z),"region":"harbor"})
	for row in rows:
		row["detail"]=""
		row["objective"]=false
	return rows
