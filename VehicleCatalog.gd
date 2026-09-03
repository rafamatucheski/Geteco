class_name VehicleCatalog
extends RefCounted

# Catálogo Completo de Veículos por Zonas e Biomas
# Contém especificações físicas reais (massa, aceleração, velocidade, durabilidade, drift) e paletas de cores.

const DISTRICT_VEHICLES := {
	"city": ["sedan_classic", "taxi_yellow", "sport_coupe", "station_wagon", "cobra_v8"],
	"desert": ["desert_jeep_4x4", "dune_buggy", "ranch_pickup", "muscle_classic"],
	"winter": ["winter_suv_heavy", "snow_plow_truck", "polar_van"],
	"beach": ["beach_cabriolet", "surf_woody_wagon", "beach_buggy"],
	"industrial": ["cargo_flatbed_truck", "lumber_pickup_4x4", "dock_delivery_van"],
	"forest": ["lumber_pickup_4x4", "desert_jeep_4x4", "station_wagon"],
	"gang_specials": ["cobra_v8"]
}

const VEHICLES := {
	# ==========================================
	# 1. CENTRO URBANO (CITY DOWNTOWN)
	# ==========================================
	"sedan_classic": {
		"id": "sedan_classic", "label": "Sedan Premier 2.0", "district": "city",
		"target_length": 76.0, "target_width": 32.0, "mass": 1.0,
		"max_speed": 490.0, "acceleration": 880.0, "braking": 1150.0, "turn_speed": 3.1, "drift_factor": 0.88,
		"durability": 100, "engine_pitch": 1.0, "roof_prop": "none",
		"colors": [Color("1e272e"), Color("d2dae2"), Color("1e3799"), Color("485460"), Color("800000"), Color("0c2461")]
	},
	"taxi_yellow": {
		"id": "taxi_yellow", "label": "Táxi Metropolitano", "district": "city",
		"target_length": 78.0, "target_width": 33.0, "mass": 1.05,
		"max_speed": 480.0, "acceleration": 890.0, "braking": 1180.0, "turn_speed": 3.2, "drift_factor": 0.85,
		"durability": 110, "engine_pitch": 1.02, "roof_prop": "taxi_sign",
		"colors": [Color("f1c40f")]
	},
	"sport_coupe": {
		"id": "sport_coupe", "label": "Infernus GT Turbo", "district": "city",
		"target_length": 72.0, "target_width": 34.0, "mass": 0.85, # Super leve e ágil
		"max_speed": 620.0, "acceleration": 1180.0, "braking": 1450.0, "turn_speed": 3.65, "drift_factor": 1.15,
		"durability": 80, "engine_pitch": 1.25, "roof_prop": "spoiler",
		"colors": [Color("e74c3c"), Color("f39c12"), Color("e67e22"), Color("f5f6fa"), Color("0984e3"), Color("6c5ce7")]
	},
	"station_wagon": {
		"id": "station_wagon", "label": "Perua Touring Classic", "district": "city",
		"target_length": 84.0, "target_width": 32.0, "mass": 1.15,
		"max_speed": 450.0, "acceleration": 780.0, "braking": 1020.0, "turn_speed": 2.85, "drift_factor": 0.80,
		"durability": 120, "engine_pitch": 0.95, "roof_prop": "roof_rack",
		"colors": [Color("4b6584"), Color("2c3e50"), Color("786d56"), Color("3d3d3d")]
	},

	# ==========================================
	# 2. DESERTO / BADLANDS (DESERT)
	# ==========================================
	"desert_jeep_4x4": {
		"id": "desert_jeep_4x4", "label": "Wrangler 4x4 Desértico", "district": "desert",
		"target_length": 86.0, "target_width": 36.0, "mass": 1.50, # Forte e resistente
		"max_speed": 430.0, "acceleration": 860.0, "braking": 1100.0, "turn_speed": 2.75, "drift_factor": 0.70,
		"durability": 160, "engine_pitch": 0.92, "roof_prop": "spare_wheel",
		"colors": [Color("d1ccc0"), Color("4b6584"), Color("d35400"), Color("84817a"), Color("57606f")]
	},
	"dune_buggy": {
		"id": "dune_buggy", "label": "Sandstorm Dune Buggy", "district": "desert",
		"target_length": 58.0, "target_width": 33.0, "mass": 0.70, # Ultra leve!
		"max_speed": 510.0, "acceleration": 1050.0, "braking": 1250.0, "turn_speed": 3.80, "drift_factor": 1.28,
		"durability": 70, "engine_pitch": 1.35, "roof_prop": "roll_cage",
		"colors": [Color("f1c40f"), Color("e67e22"), Color("00cec9"), Color("e84118")]
	},
	"ranch_pickup": {
		"id": "ranch_pickup", "label": "Pickup V8 Rancho", "district": "desert",
		"target_length": 88.0, "target_width": 35.0, "mass": 1.65,
		"max_speed": 420.0, "acceleration": 820.0, "braking": 960.0, "turn_speed": 2.60, "drift_factor": 0.85,
		"durability": 175, "engine_pitch": 0.86, "roof_prop": "bed_bars",
		"colors": [Color("795548"), Color("b71540"), Color("40739e"), Color("535c68")]
	},
	"muscle_classic": {
		"id": "muscle_classic", "label": "Stallion V8 Hardtop", "district": "desert",
		"target_length": 82.0, "target_width": 35.0, "mass": 1.30,
		"max_speed": 560.0, "acceleration": 1020.0, "braking": 1080.0, "turn_speed": 3.05, "drift_factor": 1.25, # Alto torque e drift
		"durability": 120, "engine_pitch": 0.88, "roof_prop": "hood_scoop",
		"colors": [Color("111113"), Color("4b1248"), Color("192a56"), Color("b33939")]
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
	}
}

static func get_vehicle_spec(archetype_id: String) -> Dictionary:
	return VEHICLES.get(archetype_id, VEHICLES.get("sedan_classic", {}))

static func get_random_spec_for_district(district_id: String = "city") -> Dictionary:
	var list: Array = DISTRICT_VEHICLES.get(district_id, DISTRICT_VEHICLES["city"])
	var chosen_id: String = list[randi() % list.size()]
	return get_vehicle_spec(chosen_id)

static func get_all_specs() -> Array:
	return VEHICLES.values()

static func get_random_color(archetype_id: String) -> Color:
	var spec := get_vehicle_spec(archetype_id)
	var col_list: Array = spec.get("colors", [Color.WHITE])
	return col_list[randi() % col_list.size()]
