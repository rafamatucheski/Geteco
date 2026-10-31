extends RefCounted
## Quatro cômodos nativos distintos. Posições em metros locais; o acesso é autorado pelo vilarejo.
const MODEL := "res://world/desert/village/DesertVillageHomeInterior.gd"
const IDS := ["santa_lua_home_1", "santa_lua_home_2", "santa_lua_home_3", "santa_lua_home_4"]

static func specification(index: int) -> Dictionary:
	var rows: Array[Dictionary] = [
		{"size":Vector2(12,9), "bed":Vector3(-3.8,0,-1.65), "kitchen":Vector3(3.4,0,-3.1), "table":Vector3(2.9,0,.2), "sofa":Vector3(-3.5,0,1.8), "sofa_yaw":0.0,
		 "partitions":[Rect2(-1.8,-4.25,.2,4.05)], "floor_point":Vector3(0,0,0), "cooking_point":Vector3(3.98,0,-2.2), "activity":"cook", "resident_name":"Rosa", "cloth":"985d4c", "wall":"c6ad87", "cash":240,
		 "loot":[Vector3(0,0,-2.7),Vector3(4.85,0,2.5),Vector3(1,0,1.8)]},
		{"size":Vector2(13,8.5), "bed":Vector3(4.2,0,-1.6), "kitchen":Vector3(-4,0,-2.9), "table":Vector3(-3.2,0,1), "sofa":Vector3(.4,0,-2.6), "sofa_yaw":0.0,
		 "partitions":[Rect2(2.35,-4,.2,3.5)], "floor_point":Vector3(3,0,.4), "cooking_point":Vector3(-4,0,-1.65), "activity":"sleep", "resident_name":"Bento", "cloth":"668081", "wall":"bfb49a", "cash":375,
		 "loot":[Vector3(1.2,0,.6),Vector3(5.35,0,1.65),Vector3(-1,0,2.7)]},
		{"size":Vector2(10.8,11), "bed":Vector3(3.1,0,-2.7), "kitchen":Vector3(-2.3,0,-4.2), "table":Vector3(-2.8,0,-.2), "sofa":Vector3(3,0,2.8), "sofa_yaw":PI*.5,
		 "partitions":[Rect2(1.35,-1.3,3.75,.2)], "floor_point":Vector3(-1,0,1), "cooking_point":Vector3(-2.3,0,-2.8), "activity":"read", "resident_name":"Lia", "cloth":"a58b4f", "wall":"c0b697", "cash":180,
		 "loot":[Vector3(0,0,-4),Vector3(3.8,0,.8),Vector3(-.4,0,2.3)]},
		{"size":Vector2(13.8,10), "bed":Vector3(-4.6,0,-2.7), "kitchen":Vector3(3.8,0,-3.9), "table":Vector3(1.7,0,-.3), "sofa":Vector3(-4.5,0,2.4), "sofa_yaw":0.0,
		 "partitions":[Rect2(-2.4,-4.7,.2,3.3),Rect2(-6.55,-.7,2.45,.2)], "floor_point":Vector3(-3.15,0,-2.1), "cooking_point":Vector3(3.8,0,-2.55), "activity":"sleep", "resident_name":"Nilo", "cloth":"65735b", "wall":"bda486", "cash":620,
		 "loot":[Vector3(-.5,0,-3.8),Vector3(5.45,0,.7),Vector3(1.4,0,2.5)]},
	]
	return rows[clampi(index,0,3)].duplicate(true)

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in 4: result.append(home_data(IDS[index]))
	return result

static func home_data(id: String) -> Dictionary:
	var index := IDS.find(id)
	if index < 0: return {}
	var data := specification(index)
	var size: Vector2 = data.size
	var exterior: Vector3 = [Vector3(-550,0,-502),Vector3(-506,0,-502),Vector3(-550,0,-476),Vector3(-506,0,-476)][index]
	var side := 1.0 if index % 2 == 0 else -1.0
	var rewards: Array[Dictionary] = [
		{"id":id+"_cash", "kind":"cash", "amount":data.cash, "local_position":data.loot[0]},
		{"id":id+"_water", "kind":"item", "item":"water", "amount":1, "local_position":data.loot[1]},
		{"id":id+"_sandwich", "kind":"item", "item":"sandwich", "amount":1, "local_position":data.loot[2]},
	]
	return {"id":id, "original_name":"Casa de "+str(data.resident_name), "region":"desert", "model":MODEL, "source_id":MODEL,
		"exterior_rotation":side*PI*.5, "walkup_door_position":exterior+Vector3(side*4.24,.08,0),
		"variant":index, "size":size, "service":"village_home", "integration_status":"native_geometry",
		"exterior_position":exterior, "entry_position":exterior+Vector3(side*5.05,.08,0), "return_position":exterior+Vector3(side*6.15,.08,0),
		"spawn":Vector3(0,.04,size.y*.5-1.4), "exit":Vector3(0,.04,size.y*.5-.65), "camera_target":Vector3(0,.65,-.1), "camera_size":maxf(size.x*1.04,size.y*1.32),
		"reward":{}, "rewards":rewards, "npcs":[], "npc_model":"", "npc_point":Vector3.ZERO,
		"resident_data":{"id":id+"_resident", "name":data.resident_name, "floor_point":data.floor_point,
			"sleep_point":data.bed+Vector3(0,.63,0), "sleep_yaw":0.0, "cooking_point":data.cooking_point, "cooking_yaw":PI, "cook_target":data.kitchen+Vector3(.58,1.22,.30),
			"activity":data.activity, "appearance":{"shirt":data.cloth, "pants":"494d50", "skin":"b98d70", "variant":9730+index, "female":index in [0,2]}}}
