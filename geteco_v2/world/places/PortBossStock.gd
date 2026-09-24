extends RefCounted
## PortBossGarage stock is independent of CobraBossReward / Ironback at Maciota.
const SOURCE := "world/harbor/PortBossGarage.gd"
static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := ["sedan_classic","sport_estate","porto_rosso","winter_suv_heavy","sport_coupe"]
	for index in ids.size():
		result.append({"id":"PortGarageCar%d"%index,"vehicle_id":"port_garage_stock_%d"%index,"archetype":ids[index],"model":"res://assets/fleet/"+ids[index]+".scn","local_position":Vector3(-8+index*4,.04,-4),"yaw":-PI,"source":SOURCE,"source_rotation_2d":PI/2,"port_boss_garage_stock":true,"exclusive":index==2,"spawn_condition":"port_boss.status == parked" if index==2 else "stock_not_persisted_elsewhere"})
	return result
static func rules() -> Dictionary:
	return {"source":SOURCE,"open_hour":1.0,"close_hour":5.0,"exclusive_archetype":"porto_rosso","initial_status":"parked","statuses":["parked","stolen","delivered","destroyed"],"alarm_delay":15.0,"crime_score":60,"minimum_wanted":3,"delivery_reward":50000,"delivery_service":"neco","reward_owner":"session_progression","guards":[Vector3(7.3,0,5.7),Vector3(-8,0,1)],"independent_cobra_reward":{"id":"cobra_boss_ironback","source":"world/harbor/campaign/CobraBossReward.gd","location":"maciota","requires":["defeated","completed.cobra_finale"],"aftermath_unlocks_map2":false}}
