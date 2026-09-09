class_name VehicleCatalog
extends RefCounted

# Catálogo Completo de Veículos por Zonas e Biomas
# Contém especificações físicas reais (massa, aceleração, velocidade, durabilidade, drift) e paletas de cores.

const DISTRICT_VEHICLES := {
	"city": ["sedan_classic", "taxi_yellow", "sport_coupe", "station_wagon", "cobra_v8", "union_sedan", "metro_hatch", "courier_van", "route_city"],
	"desert": ["desert_jeep_4x4", "dune_buggy", "ranch_pickup", "muscle_classic", "ranch_single"],
	"winter": ["winter_suv_heavy", "snow_plow_truck", "polar_van"],
	"beach": ["beach_cabriolet", "surf_woody_wagon", "beach_buggy"],
	"industrial": ["cargo_flatbed_truck", "lumber_pickup_4x4", "dock_delivery_van", "boxrunner", "towmaster", "ranch_single"],
	"forest": ["lumber_pickup_4x4", "desert_jeep_4x4", "station_wagon", "ranch_single"],
	"emergency": ["rescue_pumper", "medic_box", "towmaster"],
	"gang_specials": ["cobra_v8"]
}

const VEHICLES := {
	"monaliza": {
		"id":"monaliza", "label":"Monaliza GT Turbo", "district":"personal",
		"target_length":74.0, "target_width":33.0, "mass":0.95,
		"max_speed":560.0, "acceleration":460.0, "braking":1250.0,
		"turn_speed":3.1, "drift_factor":0.88, "durability":180,
		"engine_pitch":1.1, "roof_prop":"none", "crop_index":4,
		"colors":[Color("183b91")]
	},
	# ==========================================
	# 1. CENTRO URBANO (CITY DOWNTOWN)
	# ==========================================
	"sedan_classic": {
		"id": "sedan_classic", "label": "Sedan Premier 2.0", "district": "city",
		"target_length": 76.0, "target_width": 32.0, "mass": 1.0,
		"max_speed": 490.0, "acceleration": 880.0, "braking": 1150.0, "turn_speed": 3.1, "drift_factor": 0.88,
		"durability": 100, "engine_pitch": 1.0, "roof_prop": "none",
		"crop_index": 0,
		"colors": [Color.WHITE, Color("f1f2f6"), Color("d2dae2")]
	},
	"taxi_yellow": {
		"id": "taxi_yellow", "label": "Táxi Metropolitano", "district": "city",
		"target_length": 78.0, "target_width": 33.0, "mass": 1.05,
		"max_speed": 480.0, "acceleration": 890.0, "braking": 1180.0, "turn_speed": 3.2, "drift_factor": 0.85,
		"durability": 110, "engine_pitch": 1.02, "roof_prop": "taxi_sign",
		"crop_index": 1,
		"colors": [Color.WHITE]
	},
	"sport_coupe": {
		"id": "sport_coupe", "label": "Infernus GT Turbo", "district": "city",
		"target_length": 72.0, "target_width": 34.0, "mass": 0.85, # Super leve e ágil
		"max_speed": 620.0, "acceleration": 1180.0, "braking": 1450.0, "turn_speed": 3.65, "drift_factor": 1.15,
		"durability": 80, "engine_pitch": 1.25, "roof_prop": "spoiler",
		"crop_index": 4,
		"colors": [Color.WHITE]
	},
	"station_wagon": {
		"id": "station_wagon", "label": "Perua Touring Classic", "district": "city",
		"target_length": 84.0, "target_width": 32.0, "mass": 1.15,
		"max_speed": 450.0, "acceleration": 780.0, "braking": 1020.0, "turn_speed": 2.85, "drift_factor": 0.80,
		"durability": 120, "engine_pitch": 0.95, "roof_prop": "roof_rack",
		"crop_index": 3,
		"colors": [Color.WHITE]
	},
	"police_cruiser": {
		"id": "police_cruiser", "label": "Viatura PM Interceptor", "district": "city",
		"target_length": 82.0, "target_width": 36.0, "mass": 1.25,
		"max_speed": 600.0, "acceleration": 1100.0, "braking": 1400.0, "turn_speed": 3.40, "drift_factor": 0.95,
		"durability": 170, "engine_pitch": 1.12, "roof_prop": "police_lightbar",
		"texture": "res://assets/art/police_car.png",
		"colors": [Color.WHITE]
	},

	# ==========================================
	# 2. DESERTO / BADLANDS (DESERT)
	# ==========================================
	"desert_jeep_4x4": {
		"id": "desert_jeep_4x4", "label": "Wrangler 4x4 Desértico", "district": "desert",
		"target_length": 86.0, "target_width": 36.0, "mass": 1.50, # Forte e resistente
		"max_speed": 430.0, "acceleration": 860.0, "braking": 1100.0, "turn_speed": 2.75, "drift_factor": 0.70,
		"durability": 160, "engine_pitch": 0.92, "roof_prop": "spare_wheel",
		"crop_index": 3,
		"colors": [Color.WHITE, Color("d1ccc0")]
	},
	"dune_buggy": {
		"id": "dune_buggy", "label": "Sandstorm Dune Buggy", "district": "desert",
		"target_length": 58.0, "target_width": 33.0, "mass": 0.70, # Ultra leve!
		"max_speed": 510.0, "acceleration": 1050.0, "braking": 1250.0, "turn_speed": 3.80, "drift_factor": 1.28,
		"durability": 70, "engine_pitch": 1.35, "roof_prop": "roll_cage",
		"crop_index": 4,
		"colors": [Color.WHITE]
	},
	"ranch_pickup": {
		"id": "ranch_pickup", "label": "Pickup V8 Rancho", "district": "desert",
		"target_length": 88.0, "target_width": 35.0, "mass": 1.65,
		"max_speed": 420.0, "acceleration": 820.0, "braking": 960.0, "turn_speed": 2.60, "drift_factor": 0.85,
		"durability": 175, "engine_pitch": 0.86, "roof_prop": "bed_bars",
		"crop_index": 5,
		"colors": [Color.WHITE]
	},
	"muscle_classic": {
		"id": "muscle_classic", "label": "Stallion V8 Hardtop", "district": "desert",
		"target_length": 82.0, "target_width": 35.0, "mass": 1.30,
		"max_speed": 560.0, "acceleration": 1020.0, "braking": 1080.0, "turn_speed": 3.05, "drift_factor": 1.25, # Alto torque e drift
		"durability": 120, "engine_pitch": 0.88, "roof_prop": "hood_scoop",
		"crop_index": 2,
		"colors": [Color.WHITE]
	},

	# ==========================================
	# 3. BAIRRO DE NEVE / FRIO (WINTER)
	# ==========================================
	"winter_suv_heavy": {
		"id": "winter_suv_heavy", "label": "Mammoth SUV 4x4 Neve", "district": "winter",
		"target_length": 90.0, "target_width": 37.0, "mass": 1.85,
		"max_speed": 440.0, "acceleration": 800.0, "braking": 1080.0, "turn_speed": 2.60, "drift_factor": 0.72,
		"durability": 190, "engine_pitch": 0.90, "roof_prop": "ski_rack",
		"colors": [Color("f5f6fa"), Color("74b9ff"), Color("2f3542"), Color("57606f")]
	},
	"snow_plow_truck": {
		"id": "snow_plow_truck", "label": "Limpa-Neves Industrial", "district": "winter",
		"target_length": 112.0, "target_width": 42.0, "mass": 3.00, # Massa colossal! Empurra tudo!
		"max_speed": 340.0, "acceleration": 600.0, "braking": 850.0, "turn_speed": 2.05, "drift_factor": 0.50,
		"durability": 280, "engine_pitch": 0.76, "roof_prop": "plow_blade",
		"colors": [Color("e67e22"), Color("f1c40f")]
	},
	"polar_van": {
		"id": "polar_van", "label": "Furgão Ártico Térmico", "district": "winter",
		"target_length": 86.0, "target_width": 36.0, "mass": 1.70,
		"max_speed": 410.0, "acceleration": 750.0, "braking": 980.0, "turn_speed": 2.50, "drift_factor": 0.68,
		"durability": 160, "engine_pitch": 0.92, "roof_prop": "vent_roof",
		"colors": [Color("ffffff"), Color("81ecec"), Color("a4b0be")]
	},

	# ==========================================
	# 4. BAIRRO DE PRAIA / COSTA (BEACH)
	# ==========================================
	"beach_cabriolet": {
		"id": "beach_cabriolet", "label": "Cabriolet Tropical Conversível", "district": "beach",
		"target_length": 74.0, "target_width": 33.0, "mass": 0.95,
		"max_speed": 570.0, "acceleration": 1040.0, "braking": 1280.0, "turn_speed": 3.45, "drift_factor": 1.05,
		"durability": 85, "engine_pitch": 1.15, "roof_prop": "open_top",
		"colors": [Color("00cec9"), Color("fd79a8"), Color("ffeaa7"), Color("ffffff"), Color("fab1a0")]
	},
	"surf_woody_wagon": {
		"id": "surf_woody_wagon", "label": "Woody Wagon com Prancha de Surf", "district": "beach",
		"target_length": 85.0, "target_width": 33.0, "mass": 1.20,
		"max_speed": 440.0, "acceleration": 780.0, "braking": 980.0, "turn_speed": 2.80, "drift_factor": 0.82,
		"durability": 115, "engine_pitch": 0.95, "roof_prop": "surfboard",
		"colors": [Color("16a085"), Color("e58e26"), Color("34495e"), Color("786d56")]
	},
	"beach_buggy": {
		"id": "beach_buggy", "label": "Tropic Buggy Praiano", "district": "beach",
		"target_length": 60.0, "target_width": 34.0, "mass": 0.75,
		"max_speed": 490.0, "acceleration": 980.0, "braking": 1160.0, "turn_speed": 3.60, "drift_factor": 1.18,
		"durability": 75, "engine_pitch": 1.30, "roof_prop": "roll_cage",
		"colors": [Color("e17055"), Color("badc58"), Color("f9ca24")]
	},

	# ==========================================
	# 5. INDÚSTRIA / FLORESTA / DOCAS (INDUSTRIAL & DOCKS)
	# ==========================================
	"cargo_flatbed_truck": {
		"id": "cargo_flatbed_truck", "label": "Caminhão Freight Cargo V12", "district": "industrial",
		"target_length": 118.0, "target_width": 42.0, "mass": 3.20, # O peso-pesado supremo
		"max_speed": 320.0, "acceleration": 560.0, "braking": 820.0, "turn_speed": 1.85, "drift_factor": 0.45,
		"durability": 320, "engine_pitch": 0.72, "roof_prop": "exhaust_stacks",
		"colors": [Color("800000"), Color("1e3799"), Color("1e824c"), Color("2c3e50")]
	},
	"lumber_pickup_4x4": {
		"id": "lumber_pickup_4x4", "label": "Pickup Florestal Heavy Duty", "district": "forest",
		"target_length": 90.0, "target_width": 37.0, "mass": 1.60,
		"max_speed": 430.0, "acceleration": 830.0, "braking": 1000.0, "turn_speed": 2.70, "drift_factor": 0.75,
		"durability": 180, "engine_pitch": 0.88, "roof_prop": "snorkel_bars",
		"colors": [Color("2d3436"), Color("4b4b4b"), Color("27ae60"), Color("5352ed")]
	},
	# ==========================================
	# 6. VEÍCULOS ESPECIAIS DE GANGUE (GANG SPECIALS)
	# ==========================================
	"cobra_v8": {
		"id": "cobra_v8", "label": "Cobra V8 Custom (Cobras de Ferro)", "district": "city",
		"target_length": 80.0, "target_width": 35.0, "mass": 1.20,
		"max_speed": 610.0, "acceleration": 1150.0, "braking": 1300.0, "turn_speed": 3.45, "drift_factor": 1.20,
		"durability": 140, "engine_pitch": 0.85, "roof_prop": "hood_scoop",
		"colors": [Color("1a0505"), Color("0f0f12"), Color("380b0b"), Color("2c0808")]
	},

	# ==========================================
	# 7. FASE 2: FROTA CIVIL 3D EXPANDIDA
	# ==========================================
	"union_sedan": {
		"id": "union_sedan", "label": "Union Sedan Premier", "district": "city",
		"target_length": 82.0, "target_width": 34.0, "mass": 1.10,
		"max_speed": 490.0, "acceleration": 870.0, "braking": 1120.0, "turn_speed": 3.10, "drift_factor": 0.85,
		"durability": 110, "engine_pitch": 1.0, "roof_prop": "none",
		"model_class": "res://prototypes/living_cast/models/UnionSedanModel.gd",
		"colors": [Color("#2c3e50"), Color("#7f8c8d"), Color("#1e272e"), Color("#34495e"), Color("#c0392b")]
	},
	"metro_hatch": {
		"id": "metro_hatch", "label": "Metro Hatchback Sport", "district": "city",
		"target_length": 68.0, "target_width": 32.0, "mass": 0.85,
		"max_speed": 520.0, "acceleration": 1020.0, "braking": 1280.0, "turn_speed": 3.65, "drift_factor": 1.10,
		"durability": 85, "engine_pitch": 1.22, "roof_prop": "spoiler",
		"model_class": "res://prototypes/living_cast/models/MetroHatchModel.gd",
		"colors": [Color("#e74c3c"), Color("#f1c40f"), Color("#3498db"), Color("#2ecc71"), Color("#ecf0f1")]
	},
	"courier_van": {
		"id": "courier_van", "label": "Courier Van Express", "district": "city",
		"target_length": 84.0, "target_width": 36.0, "mass": 1.50,
		"max_speed": 430.0, "acceleration": 760.0, "braking": 990.0, "turn_speed": 2.65, "drift_factor": 0.72,
		"durability": 140, "engine_pitch": 0.92, "roof_prop": "roof_rack",
		"model_class": "res://prototypes/living_cast/models/CourierVanModel.gd",
		"colors": [Color("#ffffff"), Color("#f39c12"), Color("#2980b9"), Color("#bdc3c7")]
	},
	"summit_suv": {
		"id": "summit_suv", "label": "Summit SUV 4x4", "district": "forest",
		"target_length": 84.0, "target_width": 38.0, "mass": 1.8,
		"max_speed": 480.0, "acceleration": 440.0, "braking": 950.0, "turn_speed": 2.8, "drift_factor": 0.88,
		"durability": 200, "engine_pitch": 0.85, "roof_prop": "",
		"model_class": "res://prototypes/living_cast/models/SummitSUVModel.gd",
		"colors": [Color("315b6b"),Color("dce3df"),Color("6b7055"),Color("934c39")]
	},
	"arctic_jeep": {
		"id": "arctic_jeep", "label": "Arctic Trail 4x4", "district": "forest",
		"target_length": 84.0, "target_width": 38.0, "mass": 1.8,
		"max_speed": 480.0, "acceleration": 440.0, "braking": 950.0, "turn_speed": 2.8, "drift_factor": 0.88,
		"durability": 200, "engine_pitch": 0.85, "roof_prop": "",
		"model_class": "res://prototypes/living_cast/models/ArcticJeepModel.gd",
		"colors": [Color("315b6b"),Color("dce3df"),Color("6b7055"),Color("934c39")]
	},
	"ranch_single": {
		"id": "ranch_single", "label": "Ranch Single V8 4x4", "district": "desert",
		"target_length": 88.0, "target_width": 36.0, "mass": 1.65,
		"max_speed": 450.0, "acceleration": 850.0, "braking": 980.0, "turn_speed": 2.60, "drift_factor": 0.88,
		"durability": 180, "engine_pitch": 0.85, "roof_prop": "bed_bars",
		"model_class": "res://prototypes/living_cast/models/RanchSingleModel.gd",
		"colors": [Color("#8e44ad"), Color("#2c3e50"), Color("#b53471"), Color("#30336b"), Color("#dff9fb")]
	},
	"route_city": {
		"id": "route_city", "label": "Route City Ônibus Urbano", "district": "city",
		"target_length": 132.0, "target_width": 42.0, "mass": 4.20,
		"max_speed": 340.0, "acceleration": 520.0, "braking": 780.0, "turn_speed": 1.95, "drift_factor": 0.40,
		"durability": 300, "engine_pitch": 0.70, "roof_prop": "ac_unit",
		"model_class": "res://prototypes/living_cast/models/RouteCityModel.gd",
		"colors": [Color("#2980b9"), Color("#27ae60"), Color("#d35400"), Color("#8e44ad")]
	},

	# ==========================================
	# 8. FASE 2: FROTA DE SERVIÇO & EMERGÊNCIA 3D
	# ==========================================
	"rescue_pumper": {
		"id": "rescue_pumper", "label": "Rescue Pumper (Corpo de Bombeiros)", "district": "emergency",
		"target_length": 128.0, "target_width": 42.0, "mass": 4.80,
		"max_speed": 380.0, "acceleration": 680.0, "braking": 920.0, "turn_speed": 2.10, "drift_factor": 0.45,
		"durability": 320, "engine_pitch": 0.74, "roof_prop": "fire_lightbar",
		"model_class": "res://prototypes/living_cast/models/RescuePumperModel.gd",
		"colors": [Color("#c0392b"), Color("#d63031")]
	},
	"medic_box": {
		"id": "medic_box", "label": "Medic Box Ambulância SAMU", "district": "emergency",
		"target_length": 92.0, "target_width": 38.0, "mass": 1.95,
		"max_speed": 510.0, "acceleration": 920.0, "braking": 1150.0, "turn_speed": 2.80, "drift_factor": 0.65,
		"durability": 160, "engine_pitch": 1.05, "roof_prop": "ambulance_lightbar",
		"model_class": "res://prototypes/living_cast/models/MedicBoxModel.gd",
		"colors": [Color("#f5f6fa"), Color("#ffffff")]
	},
	"towmaster": {
		"id": "towmaster", "label": "Towmaster Guincho Plataforma", "district": "industrial",
		"target_length": 116.0, "target_width": 40.0, "mass": 2.80,
		"max_speed": 400.0, "acceleration": 650.0, "braking": 890.0, "turn_speed": 2.25, "drift_factor": 0.55,
		"durability": 220, "engine_pitch": 0.80, "roof_prop": "amber_beacon",
		"model_class": "res://prototypes/living_cast/models/TowmasterModel.gd",
		"colors": [Color("#f39c12"), Color("#f1c40f"), Color("#e67e22")]
	},
	"boxrunner": {
		"id": "boxrunner", "label": "Boxrunner Caminhão Baú Urbano", "district": "industrial",
		"target_length": 110.0, "target_width": 39.0, "mass": 2.40,
		"max_speed": 410.0, "acceleration": 690.0, "braking": 920.0, "turn_speed": 2.35, "drift_factor": 0.60,
		"durability": 200, "engine_pitch": 0.82, "roof_prop": "cab_deflector",
		"model_class": "res://prototypes/living_cast/models/BoxrunnerModel.gd",
		"colors": [Color("#ffffff"), Color("#34495e"), Color("#2c3e50"), Color("#7f8c8d")]
	}
}

# Legacy save/mission IDs keep their identity and physics while using the 3D fleet.
const LEGACY_MODELS := {
	"sedan_classic": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	"taxi_yellow": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	"sport_coupe": "res://prototypes/living_cast/CoupeDamageModel.gd",
	"station_wagon": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	"police_cruiser": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	"desert_jeep_4x4": "res://prototypes/living_cast/models/ArcticJeepModel.gd",
	"dune_buggy": "res://prototypes/living_cast/models/ArcticJeepModel.gd",
	"ranch_pickup": "res://prototypes/living_cast/models/RanchSingleModel.gd",
	"muscle_classic": "res://prototypes/living_cast/BossMuscleModel.gd",
	"winter_suv_heavy": "res://prototypes/living_cast/models/SummitSUVModel.gd",
	"snow_plow_truck": "res://prototypes/living_cast/models/TowmasterModel.gd",
	"polar_van": "res://prototypes/living_cast/models/CourierVanModel.gd",
	"beach_cabriolet": "res://prototypes/living_cast/CoupeDamageModel.gd",
	"surf_woody_wagon": "res://prototypes/living_cast/models/UnionSedanModel.gd",
	"beach_buggy": "res://prototypes/living_cast/models/ArcticJeepModel.gd",
	"cargo_flatbed_truck": "res://prototypes/living_cast/models/BoxrunnerModel.gd",
	"lumber_pickup_4x4": "res://prototypes/living_cast/models/RanchSingleModel.gd",
	"dock_delivery_van": "res://prototypes/living_cast/models/CourierVanModel.gd",
	"cobra_v8": "res://prototypes/living_cast/BossMuscleModel.gd",
}
static var _resolved_specs := {}
static func get_vehicle_spec(archetype_id: String) -> Dictionary:
	if _resolved_specs.has(archetype_id): return _resolved_specs[archetype_id]
	var spec: Dictionary = VEHICLES.get(archetype_id, VEHICLES["sedan_classic"]).duplicate(true)
	if not spec.has("model_class"):
		spec["model_class"] = LEGACY_MODELS.get(archetype_id,"res://prototypes/living_cast/models/UnionSedanModel.gd")
	if archetype_id == "monaliza": spec["model_class"] = "res://world/harbor/monaliza/MonalizaModel.gd"
	_resolved_specs[archetype_id] = spec
	return spec

static func get_random_spec_for_district(district_id: String = "city") -> Dictionary:
	var list: Array = DISTRICT_VEHICLES.get(district_id, DISTRICT_VEHICLES["city"])
	var chosen_id: String = list[randi() % list.size()]
	return get_vehicle_spec(chosen_id)

static func get_all_specs() -> Array:
	var result: Array = []
	for id in VEHICLES: result.append(get_vehicle_spec(id))
	return result

static func get_random_color(archetype_id: String) -> Color:
	var spec := get_vehicle_spec(archetype_id)
	var col_list: Array = spec.get("colors", [Color.WHITE])
	return col_list[randi() % col_list.size()]
