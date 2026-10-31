extends RefCounted
## Identidades estáveis e layouts em espaço de metros para dois bares autorados de forma independente.
const IDS := ["harbor_bar", "desert_bar"]
static func definitions() -> Array[Dictionary]:
	if Engine.get_meta("bars_baseline", false): return []
	return [definition("harbor_bar"), definition("desert_bar")]

static func definition(id: String) -> Dictionary:
	if id not in IDS: return {}
	var desert := id == "desert_bar"
	var exterior := Vector3(-420,0,-583) if desert else Vector3(3,0,52)
	var reward := {"id":id+"_first_aid", "kind":"item", "item":"first_aid", "amount":1, "local_position":Vector3(-6.2,0,4.4) if desert else Vector3(-5.4,0,4.5)}
	var positions: Array = [Vector3(-4.2,0,-2),Vector3(-4.2,0,0),Vector3(-4.9,0,1.8),Vector3(-6.8,0,-1.5)] if desert else [Vector3(-4.6,0,-2.1),Vector3(-2.5,0,-2.1),Vector3(-5.8,0,1.0),Vector3(-3.7,0,-4.8)]
	var residents: Array[Dictionary] = []
	for i in positions.size():
		residents.append({"id":id+"_patron_"+str(i), "name":(["Tião","Cida","Bento","Nara"] if desert else ["Rui","Marta","Joel","Lena"])[i], "model":"res://world/places/bars/BarPatronModel.gd", "appearance":{"patron_variant":i+(4 if desert else 0)}, "local_position":positions[i]})
	return {"id":id, "original_name":"Sede" if desert else "Lastro", "region":"desert" if desert else "harbor", "source_id":id,
		"model":"res://world/places/bars/DesertBarModel.gd" if desert else "res://world/places/bars/HarborBarModel.gd",
		"exterior_position":exterior,"entry_position":exterior+Vector3(0,0,7.3),"return_position":exterior+Vector3(0,0,8.3),
		"spawn":Vector3(0,0,4.5),"exit":Vector3(0,0,5.3),"size":Vector2(16,12),"camera_target":Vector3(0,.7,0),"camera_size":17.4,
		"variant":0,"service":"bar","reward":reward,"rewards":[reward],"npc_model":"","npc_point":Vector3.ZERO,"integration_status":"native",
		"npcs":residents,"bar_drinker_yaws":[PI*.5+.35,PI*.5-.35,0.0,-PI*.5] if desert else [-.35,.35,PI*.5,PI],
		"bar_stations":{"bar_pool":Vector3(1,0,1.4),"bar_darts":Vector3(5.3,0,-3)} if desert else {"bar_pool":Vector3(3.5,0,2.1),"bar_darts":Vector3(5.3,0,-2.95)}}



