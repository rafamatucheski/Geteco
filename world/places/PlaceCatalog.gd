extends RefCounted
## Original production identities. Coordinates retain V1 geography at 16 pixels/metre.
const SCALE := 1.0 / 16.0
const FIRE_STATION_DOOR_OFFSET := Vector3(310.0 / 16.0 * .12, 0, 220.0 / 32.0 + .06)
const HARBOR_SEWER_OPENING := Rect2(1173.0, 2105.0, 18.0, 18.0)
const MOUNTAIN_OFFSET := Vector2(4300,-4960)
const SOURCE := "res://assets/regions/source/"
const WALKUP_DOOR_Z := {"cabin":1.88, "shop":1.82, "residence":3.26, "keeper":2.8, "bunker":2.8625, "lodge":3.98}
static func walkup_family(id: String) -> String:
	if id.begins_with("mountain_cabin") or id.begins_with("lumberjack_shelter"): return "cabin"
	if id in ["mountain_outfitters", "mountain_boutique", "mountain_village_outfitters"]: return "shop"
	if id in ["westgate_garden", "quayside_house", "canal_north"]: return "residence"
	if id == "cemetery_keeper": return "keeper"
	if id == "mountain_bunker": return "bunker"
	if id == "ski_lodge": return "lodge"
	return ""

static func walkup_door_z(family: String) -> float:
	return WALKUP_DOOR_Z.get(family, 0.0)

static func shelter_access_exterior(index: int) -> Vector3:
	return _at([Vector2(8610,700), Vector2(7660,-730)][index], "mountain")

static func _at(point: Vector2, region: String) -> Vector3:
	if region == "mountain": point += MOUNTAIN_OFFSET
	return Vector3(point.x,0,point.y)*SCALE
static func definitions() -> Array[Dictionary]:
	var rows: Array = [
		["harbor_bank","North Pier","harbor",Vector2(650,140),"assets/bank/bank-finished.tscn",Vector2(14,10),3.2,4.4,"bank"],
		["harbor_police","Harbor Patrol","harbor",Vector2(1080,1950),"world/harbor/interiors/HarborPoliceStation3D.gd",Vector2(22.4,15.4),4.8,6.2,"police"],
		["harbor_hospital","Bay Medical","harbor",Vector2(1800,1530),"world/harbor/interiors/HospitalRoom3D.gd",Vector2(20,14),4.4,6.5,"hospital"],
		["harbor_fire_station","Northgate Fire","harbor",Vector2(5880,-1370),"world/harbor/interiors/FireStationArt3D.gd",Vector2(28,20.8),8.0,9.3,"fire_station"],
		["harbor_clothing","Union","harbor",Vector2(1890,140),"world/harbor/interiors/ClothingInteriorArt3D.gd",Vector2(13,9),3.0,4.0,"clothing"],
		["harbor_fuel","Fuel","harbor",Vector2(2460,140),"world/harbor/interiors/FuelStoreArt3D.gd",Vector2(14,10),3.6,4.5,"fuel"],
		["mountain_cabin","ChalÃ© dos Pinhais","mountain",Vector2(7480,760),"world/mountain_pass/MountainCabin3D.gd",Vector2(14,9.5),3.0,4.15,"shelter"],
		["mountain_cabin_encosta","ChalÃ© da Encosta","mountain",Vector2(8350,730),"world/mountain_pass/MountainCabinVariants3D.gd",Vector2(14,9.5),3.0,4.15,"shelter"],
		["mountain_cabin_forest","Posto Florestal","mountain",Vector2(6050,780),"world/mountain_pass/MountainCabinVariants3D.gd",Vector2(14,9.5),3.0,4.15,"shelter"],
		["mountain_bunker","EstaÃ§Ã£o Zero","mountain",Vector2(6500,-2890),"world/mountain_pass/MountainBunker3D.gd",Vector2(18,12),4.3,5.2,"bunker"],
		["lumberjack_shelter","Abrigo dos Lenhadores","mountain",Vector2(7940,850),"world/mountain_pass/LumberjackBunkhouse3D.gd",Vector2(10,9.6),3.0,4.15,"shelter"],
		["ski_lodge","Summit","mountain",Vector2(7140,-2760),"world/mountain_pass/SummitSkiLodgeInterior3D.gd",Vector2(16,10),4.0,4.8,"ski_rental"],
		["mountain_mystery_cave","Caverna da Queda","mountain",Vector2(6200,-320),"world/mountain_pass/MountainMysteryCaveInterior3D.gd",Vector2(16,12),4.0,5.0,"expedition"],
		["mountain_outfitters","Ãšltimo Abrigo","mountain",Vector2(5980,650),"world/harbor/interiors/ClothingInteriorArt3D.gd",Vector2(13,9),3.0,4.0,"clothing"],
		["mountain_boutique","Boutique Alpina","mountain",Vector2(7400,-2735),"world/harbor/interiors/ClothingInteriorArt3D.gd",Vector2(13,9),3.0,4.0,"clothing"],
		["mountain_village_outfitters","Casacos da Vila","mountain",Vector2(7790,-1640),"world/harbor/interiors/ClothingInteriorArt3D.gd",Vector2(13,9),3.0,4.0,"clothing"],
	]
	rows.append_array([
		# Production V1 replaces District/NorthFrontage2, not NorthFrontage1.
		# Keep facade, interaction point and exterior return derived from one source.
		["harbor_ammunation","Ammu-Nation","harbor",Vector2(1550,140),"@AmmunationModel",Vector2(14,10),2.65,4.0,"weapons"],
		["mountain_gunshop","Ammu-Nation","mountain",Vector2(7750,-220),"@AmmunationModel",Vector2(14,10),2.65,4.0,"weapons"],
		["westgate_garden","Westgate Garden","harbor",Vector2(250,150),"world/harbor/residences/ResidenceInterior3D.gd",Vector2(14.4,10.4),3.5,4.5,"residence"],
		["quayside_house","Quayside","harbor",Vector2(2815,1670),"world/harbor/residences/ResidenceInterior3D.gd",Vector2(14.4,10.4),3.5,4.5,"residence"],
		["canal_north","Canal North","harbor",Vector2(4915,-860),"world/harbor/residences/ResidenceInterior3D.gd",Vector2(14.4,10.4),3.5,4.5,"residence"],
		["cemetery_keeper","Casa do Zelador","harbor",Vector2(-885,1495),"world/harbor/cemetery/CemeteryHouseInterior3D.gd",Vector2(9.3,7.4),2.2,2.95,"cemetery"],
		["port_boss_garage","Garagem do Chefe","harbor",Vector2(5515,5870),"world/harbor/PortBossGarageArt.gd",Vector2(22,20),6.0,7.4,"restricted_garage"],
		["harbor_sewer","Esgoto","harbor",Vector2(1182,2114),"@SewerModel",Vector2(23,13.5),0.0,0.0,"sewer"],
		["santa_mare_hold","Santa Mare","harbor",Vector2(4250,2980),"@SantaMareCargoHold3D",Vector2(18,12),4.65,4.75,"cargo_hold"],
	])
	for i in 4:
		rows.append(["mountain_cabin_village_%d"%(i+1),"ChalÃ© %02d"%(i+1),"mountain",[Vector2(7405,-1480),Vector2(7545,-1480),Vector2(7725,-1440),Vector2(7870,-1440)][i],"world/mountain_pass/MountainCabinVariants3D.gd",Vector2(14,9.5),3.0,4.15,"shelter"])
	var result: Array[Dictionary] = []
	for row in rows:
		var id: String = row[0]
		var region: String = row[2]
		var exterior := _at(row[3],region)
		var variant := 0
		if id in ["mountain_gunshop","quayside_house"]: variant = 1
		elif id == "canal_north": variant = 2
		if id == "mountain_cabin_encosta": variant = 1
		elif id == "mountain_cabin_forest": variant = 2
		elif id.begins_with("mountain_cabin_village_"): variant = int(id.right(1))+2
		elif id == "mountain_boutique": variant = 2
		elif id == "mountain_village_outfitters": variant = 3
		elif id == "mountain_outfitters": variant = 1
		var approach: Vector3 = exterior + Vector3(0,0,4)
		var return_point: Vector3
		if id in ["westgate_garden","quayside_house","canal_north"]: approach = exterior + Vector3(0,0,(120 if id == "westgate_garden" else 116)*SCALE)
		elif id == "harbor_police": approach = exterior + Vector3(0,0,8.95)
		elif id == "harbor_hospital": approach = _at(Vector2(1800,1705),region)
		elif id == "harbor_fire_station": approach = exterior + FIRE_STATION_DOOR_OFFSET + Vector3(0,0,1.5)
		elif id == "port_boss_garage": approach = exterior + Vector3(-4,0,0)
		elif id == "harbor_sewer": approach = exterior
		elif id == "santa_mare_hold": approach = exterior
		elif id.begins_with("harbor_"): approach = exterior + Vector3(0,0,130*SCALE)
		var walkup := walkup_family(id)
		if not walkup.is_empty(): approach = exterior + Vector3(0, 0, walkup_door_z(walkup) + 1.5)
		# PortBossGarage.leave() restores the actor at EXTERIOR exactly.
		return_point = exterior if id == "port_boss_garage" else approach + Vector3(0,0,1)
		if id == "harbor_police": return_point = approach
		var reward: Dictionary = {}
		if id.begins_with("mountain_cabin") and variant > 0: reward = {"id":id+"_cash_01","kind":"cash","amount":[0,5000,850,450,1200,650,1800][variant]}
		if id == "mountain_bunker": reward = {"id":"mountain_bunker_cash_01","kind":"cash","amount":1500}
		if id == "ski_lodge": reward = {"id":"summit_lodge_cash_01","kind":"cash","amount":900}
		if id == "lumberjack_shelter": reward = {"id":"lumberjack_shelter_axe","kind":"weapon","item":"axe","amount":1}
		if id == "mountain_mystery_cave": reward = {"id":"mountain_cave_rpg","kind":"weapon","item":"rpg","amount":1}
		# Segredo da V1 (HarborManholeSewer.SECRET_POSITION 265,61): mesmo id e munição.
		if id == "harbor_sewer": reward = {"id":"harbor_police_sewer_sawed_off","kind":"weapon","item":"sawed_off","amount":1,"ammo":24,"local_position":Vector3(8.25,0,2.2)}
		if id == "santa_mare_hold": reward = {"id":"santa_mare_hidden_chest_01","kind":"cash","amount":2800,"local_position":Vector3(5.1,0,-4.5)}
		result.append({"id":id,"original_name":row[1],"region":region,"source_id":row[4],"model":("res://world/places/"+str(row[4]).trim_prefix("@")+".gd") if str(row[4]).begins_with("@") else SOURCE+row[4],"exterior_position":exterior,"entry_position":approach,"return_position":return_point,"spawn":Vector3(0,0,row[6]),"exit":Vector3(0,0,row[7]),"camera_target":Vector3(0,.7,0),"camera_size":maxf(row[5].x*.82,row[5].y*1.25),"size":row[5],"variant":variant,"service":row[8],"reward":reward,"integration_status":"native_geometry_pending_gameplay"})

	for definition in result:
		preload("res://world/editing/WorldServiceBuildings.gd").update_definition(definition)
		definition["npcs"] = preload("res://world/places/OriginalResidents.gd").for_place(definition.id)
		definition["rewards"] = [] if definition.reward.is_empty() else [definition.reward.duplicate(true)]
		if definition.id == "mountain_cabin":
			for station in [["hunting_rifle",Vector3(3.1,.08,1.8),35],["axe",Vector3(2.5,.08,2.8),0],["knife",Vector3(-2.55,.08,1.3),0]]:
				definition.rewards.append({"id":"mountain_cabin_"+station[0],"kind":"weapon","item":station[0],"amount":1,"ammo":station[2],"local_position":station[1]})
		if definition.id == "port_boss_garage":
			definition.camera_size = 20.5
			definition["vehicles"] = preload("res://world/places/PortBossStock.gd").definitions()
			definition["vehicle_rules"] = preload("res://world/places/PortBossStock.gd").rules()
			definition["vehicle_spawn"] = Vector3(0,.04,4)
			definition["vehicle_exit"] = Vector3(0,.04,8)
			definition["vehicle_return"] = definition.exterior_position + Vector3(0,.04,0)
			definition["vehicle_return_yaw"] = -PI/2
		if definition.id == "harbor_police":
			definition.camera_size = 16.0
			definition.camera_target = Vector3(0, .7, -.6)
		definition["npc_model"] = ""
		definition["npc_point"] = Vector3.ZERO
		if definition.id == "harbor_bank":
			definition.npc_model = SOURCE+"world/harbor/events/BankClerkModel.gd"
			definition.npc_point = Vector3(-3.5,0,-.5)
			definition["npc_name"] = "Helena"
		if definition.id == "harbor_sewer":
			definition.spawn = Vector3(-5,0,-.85)
			definition.exit = Vector3(-5,0,-.85)
		if definition.id == "santa_mare_hold":
			definition.camera_size = 14.5
			definition.camera_target = Vector3(0,.45,0)
			definition.npcs = [
				{"id":"santa_mare_hold_crew_01","name":"Lucas","model":"res://world/places/SantaMareCrewModel3D.gd","appearance":{},"local_position":Vector3(-1.4,0,1.1)},
				{"id":"santa_mare_hold_crew_02","name":"Mara","model":"res://world/places/SantaMareCrewModel3D.gd","appearance":{},"local_position":Vector3(1.6,0,-2.5)},
			]
	result.append(preload("res://gameplay/urban_v1/VerticeUndercroftPlace.gd").definition_data())
	result.append(preload("res://gameplay/urban_v1/MountainFortPlace.gd").definition_data())
	return result
static func get_definition(id: String) -> Dictionary:
	for definition in definitions():
		if definition.id == id: return definition
	return {}
static func create_place(id: String) -> Node3D:
	var definition := get_definition(id)
	if definition.is_empty(): return null
	if id == "vertice_undercroft":
		var hidden = preload("res://gameplay/urban_v1/VerticeUndercroftPlace.gd").new()
		hidden.definition = definition
		return hidden
	if id == "mountain_fort":
		var fort = preload("res://gameplay/urban_v1/MountainFortPlace.gd").new()
		fort.definition = definition
		return fort
	var place = load("res://world/places/NativePlace.gd").new()
	place.definition = definition
	return place
static func access_points() -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	for definition in definitions():
		if definition.get("hidden_access",false): continue
		points.append({"id":definition.id,"place_id":definition.id,"region":definition.region,"position":definition.entry_position,"return_position":definition.return_position})
	for index in 2:
		var position := shelter_access_exterior(index) + Vector3(0,0,walkup_door_z("cabin")+1.5)
		points.append({"id":"lumberjack_shelter_%d"%(index+2),"place_id":"lumberjack_shelter","region":"mountain","position":position,"return_position":position+Vector3(0,0,1)})
	return points
