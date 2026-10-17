extends RefCounted
## Explicit sound design assignment, independent of legacy family heuristics.
## A profile is an authored acoustic class, not proof of an OEM engine swap.
## Constants only: no file access, directory scans or resource loads per frame.
## Motorcycles, the tank and the electric forklift retain their dedicated banks.

const VEHICLE_PROFILES := {
	"american_dump_truck": "truck_i6_diesel",
	"american_tanker_truck": "truck_i6_diesel",
	"arctic_jeep": "utility_v6_na",
	"atlas_crew_pickup": "tdi_i4_diesel",
	"aurora_executive": "utility_v6_na",
	"beach_buggy": "sport_i4_na",
	"beach_cabriolet": "sport_i4_na",
	"boxrunner": "truck_i6_diesel",
	"bravio_crew": "utility_v6_na",
	"cargo_flatbed_truck": "truck_v12_diesel",
	"cobra_v8": "v8_crossplane",
	"courier_van": "tdi_i4_diesel",
	"desert_jeep_4x4": "utility_v6_na",
	"dock_delivery_van": "tdi_i4_diesel",
	"dune_buggy": "sport_i4_na",
	"lumber_pickup_4x4": "v8_crossplane",
	"medic_box": "tdi_i4_diesel",
	"metro_hatch": "city_i4_na",
	"monaliza": "rb26_i6_turbo",
	"muscle_classic": "v8_crossplane",
	"nimbus_minivan": "utility_v6_na",
	"nordic_estate": "classic_i4_na",
	"orbita_micro": "city_i4_na",
	"polar_van": "tdi_i4_diesel",
	"police_cruiser": "v8_crossplane",
	"police_suv": "utility_v6_na",
	"police_transport": "tdi_i4_diesel",
	"porto_rosso": "v12_gt",
	"ranch_pickup": "v8_crossplane",
	"ranch_single": "v8_crossplane",
	"rescue_pumper": "truck_i6_diesel",
	"route_city": "bus_i6_diesel",
	"sedan_classic": "classic_i4_na",
	"sertao_trail_pickup": "utility_v6_na",
	"snow_plow_truck": "truck_i6_diesel",
	"sport_coupe": "jz2_i6_turbo",
	"sport_estate": "v8_crossplane",
	"station_wagon": "classic_i4_na",
	"summit_suv": "utility_v6_na",
	"surf_woody_wagon": "classic_i4_na",
	"taxi_yellow": "classic_i4_na",
	"towmaster": "truck_i6_diesel",
	"union_sedan": "classic_i4_na",
	"vale_crossover": "utility_v6_na",
	"vertice_midengine": "vq35_v6_na",
	"winter_suv_heavy": "v8_crossplane",
	# Authored special catalogs and mission vehicles.
	"biarticulated_510": "bus_i6_diesel",
	"armored_truck": "truck_i6_diesel",
	"mining_backhoe": "work_i4_diesel",
	"mining_tractor": "work_i4_diesel",
	"mining_haul_truck": "truck_i6_diesel",
	"desert_faisca": "sport_i4_na",
	"desert_faisca_rally": "sport_i4_na",
	"desert_coyote": "v8_crossplane",
	"desert_coyote_drag": "v8_crossplane",
	"desert_siroco": "ea888_i4_turbo",
	"desert_bison": "tdi_i4_diesel",
	"desert_mirage": "vq35_v6_na",
	"desert_mirage_gt": "vq35_v6_na",
	"rauhz_focus_mk1": "sport_i4_na",
	"supra_a80": "jz2_i6_turbo",
	"jessica_jetta_gli": "ea888_i4_turbo",
	"digo_amarok_2014": "tdi_i4_diesel",
	"digo_gol_1993": "ap_i4_turbo",
	"cobra_boss_ironback": "v8_crossplane",
	"desert_cargo_truck": "truck_i6_diesel",
	# Compatibility IDs referenced by saved personal cars / existing audio code.
	"personal_monaliza": "rb26_i6_turbo",
	"maciota_350z": "vq35_v6_na",
	"maciota_m8": "v8_twin_turbo",
}

const DEDICATED_PROFILES := {
	"bike_sport": "bike_sport",
	"bike_cruiser": "bike_cruiser",
	"bike_urban": "bike_urban",
	"bike_police": "bike_urban",
	"army_tank": "tank",
	"port_forklift": "electric",
}

## Must match tools/audio/build_engine_design_pack.py and its manifest.
## Nominal values are measured in RPM; divide by 120 for four-stroke cycle Hz.
const PROFILE_META := {
	"jz2_i6_turbo": {"rpm_bands":[840,1320,2040,3000,4200,5640,6960],"cylinders":6,"fuel":"petrol","turbo":true,"bypass_valve":true},
	"rb26_i6_turbo": {"rpm_bands":[960,1440,2160,3240,4560,6120,7800],"cylinders":6,"fuel":"petrol","turbo":true,"bypass_valve":true},
	"v8_crossplane": {"rpm_bands":[720,1200,1800,2640,3720,5040,6480],"cylinders":8,"fuel":"petrol","turbo":false,"bypass_valve":false},
	"v12_gt": {"rpm_bands":[840,1440,2280,3360,4800,6480,8400],"cylinders":12,"fuel":"petrol","turbo":false,"bypass_valve":false},
	"ap_i4_turbo": {"rpm_bands":[960,1440,2160,3120,4320,5520,6720],"cylinders":4,"fuel":"petrol","turbo":true,"bypass_valve":true},
	"ea888_i4_turbo": {"rpm_bands":[840,1320,2040,3000,4200,5400,6600],"cylinders":4,"fuel":"petrol","turbo":true,"bypass_valve":true},
	"vq35_v6_na": {"rpm_bands":[840,1320,2040,3000,4200,5520,6720],"cylinders":6,"fuel":"petrol","turbo":false,"bypass_valve":false},
	"tdi_i4_diesel": {"rpm_bands":[840,1200,1680,2160,2760,3480,4320],"cylinders":4,"fuel":"diesel","turbo":true,"bypass_valve":false},
	"city_i4_na": {"rpm_bands":[840,1320,1920,2760,3840,5040,6240],"cylinders":4,"fuel":"petrol","turbo":false,"bypass_valve":false},
	"v8_twin_turbo": {"rpm_bands":[720,1200,1800,2760,3960,5400,7080],"cylinders":8,"fuel":"petrol","turbo":true,"bypass_valve":true},
	"truck_i6_diesel": {"rpm_bands":[600,840,1080,1320,1680,2040,2400],"cylinders":6,"fuel":"diesel","turbo":true,"bypass_valve":false},
	"bus_i6_diesel": {"rpm_bands":[600,840,1080,1320,1560,1920,2280],"cylinders":6,"fuel":"diesel","turbo":true,"bypass_valve":false},
	"work_i4_diesel": {"rpm_bands":[720,960,1200,1560,1920,2280,2640],"cylinders":4,"fuel":"diesel","turbo":true,"bypass_valve":false},
	"truck_v12_diesel": {"rpm_bands":[600,840,1080,1320,1680,2040,2400],"cylinders":12,"fuel":"diesel","turbo":true,"bypass_valve":false},
	"utility_v6_na": {"rpm_bands":[720,1200,1800,2640,3600,4800,6000],"cylinders":6,"fuel":"petrol","turbo":false,"bypass_valve":false},
	"sport_i4_na": {"rpm_bands":[960,1440,2160,3240,4560,5880,7200],"cylinders":4,"fuel":"petrol","turbo":false,"bypass_valve":false},
	"classic_i4_na": {"rpm_bands":[720,1080,1680,2400,3360,4560,5760],"cylinders":4,"fuel":"petrol","turbo":false,"bypass_valve":false},
}

static func profile(archetype: String) -> String:
	return str(VEHICLE_PROFILES.get(archetype, ""))

static func all_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for profile_id: String in PROFILE_META:
		result.append(profile_id)
	return result

static func has_profile(profile_id: String) -> bool:
	return PROFILE_META.has(profile_id)

static func rpm_bands(profile_id: String) -> Array:
	return PROFILE_META.get(profile_id, {}).get("rpm_bands", [])

static func metadata(profile_id: String) -> Dictionary:
	return PROFILE_META.get(profile_id, {})

static func dedicated_profile(archetype: String) -> String:
	return str(DEDICATED_PROFILES.get(archetype, ""))
