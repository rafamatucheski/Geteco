extends RefCounted
## Authored civilian demand, evaluated once at admission, never per frame.
## Repeated entries are weights. Mission/reward cars remain out of these pools.
const POOLS := {
	"city": ["metro_hatch", "metro_hatch", "besouro_1300", "besouro_1300", "orbita_micro", "union_sedan", "sedan_classic", "station_wagon", "mare_microvan", "nimbus_minivan", "taxi_yellow", "taxi_yellow", "courier_van", "ranch_single", "ranch_pickup", "atlas_crew_pickup", "sertao_trail_pickup", "sport_coupe", "sakura_s15", "kite_type_s", "brisa_s"],
	"work": ["courier_van", "courier_van", "toco_minitruck", "toco_minitruck", "mare_microvan", "mare_microvan", "ranch_single", "ranch_pickup", "lumber_pickup_4x4", "atlas_crew_pickup", "sertao_trail_pickup", "besouro_1300", "metro_hatch", "union_sedan", "station_wagon", "taxi_yellow", "lince_rs"],
	"executive": ["union_sedan", "union_sedan", "aurora_executive", "aurora_executive", "nordic_estate", "sport_estate", "vale_crossover", "metro_hatch", "station_wagon", "nimbus_minivan", "taxi_yellow", "taxi_yellow", "sport_coupe", "raijin_gt", "tauro_v10", "bastiao_63"],
	"mountain": ["arctic_jeep", "arctic_jeep", "summit_suv", "winter_suv_heavy", "polar_van", "ranch_pickup", "ranch_single", "lumber_pickup_4x4", "atlas_crew_pickup", "sertao_trail_pickup", "station_wagon", "nimbus_minivan", "mare_microvan", "toco_minitruck", "besouro_1300", "rapina_r", "bastiao_63"],
	"desert": ["desert_faisca", "desert_faisca", "desert_coyote", "desert_siroco", "desert_bison", "desert_mirage", "courier_van", "besouro_1300", "mare_microvan", "toco_minitruck", "ranch_single", "ranch_pickup", "atlas_crew_pickup", "sertao_trail_pickup", "rapina_r"],
}
const WORK_STREETS := ["dock_street", "island_dock_street", "warehouse_way", "foundry_avenue", "salvage_access", "westgate_service_lane"]
const EXECUTIVE_STREETS := ["island_esplanade", "island_market_street", "exchange_lane", "courtyard_lane", "northbank_neighborhood_street", "northbank_civic_avenue", "northbank_gateway_avenue"]

static func profile(region_id: String, road_id: String) -> String:
	if region_id in ["mountain", "desert"]: return region_id
	var street := road_id.trim_prefix("road/")
	if street in WORK_STREETS or street.begins_with("south_port_"): return "work"
	if street in EXECUTIVE_STREETS: return "executive"
	return "city"

static func select(region_id: String, road_id: String) -> String:
	return POOLS[profile(region_id, road_id)].pick_random()

static func all_car_types() -> Array[String]:
	var result: Array[String] = []
	for pool: Array in POOLS.values():
		for id: String in pool:
			if id not in result: result.append(id)
	return result
