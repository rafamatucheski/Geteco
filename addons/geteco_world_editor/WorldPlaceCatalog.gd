@tool
extends RefCounted
## Lugares montados pelo runtime (supermercado, arcade, parque, pesque-pague...) não estão nos
## registros de região do catálogo gravado. Entram a cada carga como caixas travadas, na posição
## e no tamanho da definição do lugar, para aparecerem no mapa e em "Ir para local".
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const FOOTPRINT_COLOR := "#6f7f78"
const NEAR := 6.0

static func add_missing(catalog: Dictionary) -> void:
	var places: Array = []
	for definition in PLACES.definitions():
		places.append({"id":str(definition.get("id","")),"area":str(definition.get("region","")),"label":str(definition.get("original_name",definition.get("id",""))),"at":definition.get("exterior_position"),"size":definition.get("size")})
	# Parque e pesque-pague têm área própria no código, sem definição em PlaceCatalog.
	var park := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
	if park.enabled(): places.append({"id":"amusement_park","area":"harbor","label":"Parque de diversões","at":Vector2(park.FOOTPRINT.get_center().x,park.FOOTPRINT.get_center().y),"size":park.FOOTPRINT.size})
	var fishing := preload("res://runtime/FishingLocation.gd")
	if fishing.enabled(): places.append({"id":"fishing_pay","area":"harbor","label":"Pesque e pague","at":Vector2(fishing.GROUNDS.get_center().x,fishing.GROUNDS.get_center().y),"size":fishing.GROUNDS.size})
	for place in places:
		if not catalog.has(place.area) or not catalog[place.area] is Dictionary: continue
		var at := _point(place.at)
		if at == Vector2.INF: continue
		var size := _size(place.size)
		var row_id: String = "place/"+str(place.id)
		var context: Dictionary = catalog[place.area].get("context",{})
		if context.has(row_id) or _has_nearby(catalog[place.area],at): continue
		context[row_id] = {"id":row_id,"type":"context","kind":"place","label":place.label,"locked":true,
			"position":[at.x,at.y],"size":[size.x,size.y],
			"parts":[[at.x-size.x*.5,at.y-size.y*.5,size.x,size.y,6.0,FOOTPRINT_COLOR]]}
		catalog[place.area]["context"] = context

static func _point(value: Variant) -> Vector2:
	if value is Vector3: return Vector2(value.x,value.z)
	if value is Vector2: return value
	return Vector2.INF

static func _size(value: Variant) -> Vector2:
	if value is Vector2: return Vector2(maxf(4.0,value.x),maxf(4.0,value.y))
	if value is Vector3: return Vector2(maxf(4.0,value.x),maxf(4.0,value.z))
	return Vector2(12,12)

# Já há um objeto do catálogo ali (prédio, local de contexto): não duplica o mesmo lugar.
static func _has_nearby(area: Dictionary, at: Vector2) -> bool:
	for group in ["context","objects"]:
		for row in area.get(group,{}).values():
			if not row is Dictionary or not row.has("position"): continue
			if row.get("type","") != "context" and row.get("type","") != "building": continue
			if DATA.point(row.position).distance_to(at) < NEAR: return true
	return false
