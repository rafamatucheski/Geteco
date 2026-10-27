extends RefCounted
## Muscle cars e lowriders (27/10): a garagem dos Cobras e da quebrada. Desenhos próprios, inspirados
## nas linhas clássicas americanas (fastback, notchback, coluna-vela, faróis escondidos) sem copiar
## carro nenhum. Ficha no formato da frota (16 px por metro); a aparência é assada offline por
## tools/fleet_fixups/build_muscle_fleet.gd em assets/fleet/redesigned/<id>.scn. Todos são RWD.
## Os lowriders saem de fábrica rebaixados e com hidráulica (gameplay/lowrider/LowriderHydraulics.gd).
const MUSCLE_IDS := ["potro_68", "jararaca_v10", "carcara_ss", "trovao_440", "caiman_454", "brasa_hc"]
const LOWRIDER_IDS := ["imperador_64", "imperador_64_conv", "monte_rei_84", "duque_76"]
const IDS := ["potro_68", "jararaca_v10", "carcara_ss", "trovao_440", "caiman_454", "brasa_hc",
	"imperador_64", "imperador_64_conv", "monte_rei_84", "duque_76"]
## Pintura de gangue: verde-ferro, preto, cobre e vinho, sorteados por carro para a frota dos
## Cobras não sair toda igual (antes todo Cobra era o mesmo cupê verde).
const COBRA_PAINTS := ["202d26", "2b3b2f", "16191b", "3a2a20", "8a4b2a", "4a1e22", "33402c"]
const DATA := {
	"potro_68": {"label":"Potro 68 Fastback", "size":[1.84,1.35,4.84], "colors":["2e5e3e","b8282e","e9e6dc","1d2a44","c9a24a"],
		"speed":660.0, "accel":1220.0, "braking":1500.0, "turn":2.90, "drift":.92, "mass":1.52, "durability":210, "pitch":.98,
		"engine":"muscle", "district":"city",
		"door":{"zf":-.90,"zr":.30,"sill":.27,"belt":0.87,"top":1.21,"x":0.89,"seat_z":-.10}},
	"jararaca_v10": {"label":"Jararaca V10", "size":[1.96,1.26,4.55], "colors":["b8282e","1f4f9a","e9e6dc","16191b","d9a520"],
		"speed":700.0, "accel":1300.0, "braking":1650.0, "turn":2.95, "drift":.88, "mass":1.55, "durability":200, "pitch":1.08,
		"engine":"muscle", "district":"exclusive",
		"door":{"zf":-.55,"zr":.40,"sill":.21,"belt":0.83,"top":1.18,"x":0.90,"seat_z":.08}},
	"carcara_ss": {"label":"Carcará SS", "size":[1.92,1.34,4.85], "colors":["d9a520","1f4f9a","b8282e","2e5e3e","e9e6dc"],
		"speed":665.0, "accel":1230.0, "braking":1500.0, "turn":2.85, "drift":.92, "mass":1.58, "durability":220, "pitch":.96,
		"engine":"muscle", "district":"city",
		"door":{"zf":-.88,"zr":.40,"sill":.26,"belt":0.86,"top":1.23,"x":0.91,"seat_z":-.10}},
	"trovao_440": {"label":"Trovão 440", "size":[1.96,1.39,5.42], "colors":["16191b","8a1f24","e2672c","2e5e3e","c9ced2"],
		"speed":680.0, "accel":1250.0, "braking":1450.0, "turn":2.60, "drift":.93, "mass":1.75, "durability":250, "pitch":.92,
		"engine":"muscle", "district":"city",
		"door":{"zf":-1.02,"zr":.46,"sill":.26,"belt":0.88,"top":1.30,"x":0.93,"seat_z":-.12}},
	"caiman_454": {"label":"Caimã 454", "size":[1.94,1.38,5.17], "colors":["8a1f24","e9e6dc","16191b","2f6fb8","d9a520"],
		"speed":670.0, "accel":1240.0, "braking":1460.0, "turn":2.70, "drift":.93, "mass":1.70, "durability":240, "pitch":.94,
		"engine":"muscle", "district":"city",
		"door":{"zf":-.96,"zr":.42,"sill":.27,"belt":0.88,"top":1.32,"x":0.94,"seat_z":-.14}},
	"brasa_hc": {"label":"Brasa HC", "size":[2.05,1.49,5.10], "colors":["e2672c","16191b","5b6570","8a1f24","2e5e3e"],
		"speed":700.0, "accel":1320.0, "braking":1700.0, "turn":2.75, "drift":.88, "mass":1.95, "durability":260, "pitch":.90,
		"engine":"muscle", "district":"exclusive",
		"door":{"zf":-1.00,"zr":.50,"sill":.25,"belt":0.92,"top":1.36,"x":0.96,"seat_z":-.10}},
	"imperador_64": {"label":"Imperador 64", "size":[1.99,1.28,5.53], "colors":["6b1fa0","b8282e","1f6fa8","2f8f4e","d9a520"],
		"speed":520.0, "accel":920.0, "braking":1250.0, "turn":2.40, "drift":.95, "mass":1.95, "durability":250, "pitch":.85,
		"engine":"muscle", "district":"city", "lowrider":true,
		"door":{"zf":-1.02,"zr":.46,"sill":.18,"belt":0.76,"top":1.24,"x":0.98,"seat_z":-.15}},
	"imperador_64_conv": {"label":"Imperador 64 Conversível", "size":[2.08,1.12,5.70], "colors":["b8282e","1f6fa8","e9e6dc","6b1fa0","2f8f4e"],
		"speed":520.0, "accel":920.0, "braking":1250.0, "turn":2.40, "drift":.95, "mass":1.98, "durability":240, "pitch":.85,
		"engine":"muscle", "district":"beach", "lowrider":true,
		"door":{"zf":-1.02,"zr":.46,"sill":.18,"belt":0.76,"top":1.10,"x":0.98,"seat_z":-.05}},
	"monte_rei_84": {"label":"Monte Rei 84", "size":[1.93,1.29,5.31], "colors":["8a1f24","16191b","e9e6dc","2f5f8f","c9a24a"],
		"speed":530.0, "accel":950.0, "braking":1300.0, "turn":2.50, "drift":.94, "mass":1.75, "durability":230, "pitch":.88,
		"engine":"muscle", "district":"city", "lowrider":true,
		"door":{"zf":-1.00,"zr":.38,"sill":.18,"belt":0.75,"top":1.25,"x":0.92,"seat_z":-.18}},
	"duque_76": {"label":"Duque 76", "size":[2.08,1.40,5.95], "colors":["e9e6dc","16191b","5a1e2a","2f3f5f","c9a24a"],
		"speed":500.0, "accel":880.0, "braking":1200.0, "turn":2.25, "drift":.95, "mass":2.30, "durability":290, "pitch":.80,
		"engine":"muscle", "district":"city", "lowrider":true,
		"door":{"zf":-1.10,"zr":.18,"sill":.20,"belt":0.81,"top":1.34,"x":1.00,"seat_z":-.30}},
}

static func is_lowrider(id: String) -> bool:
	return bool(DATA.get(id, {}).get("lowrider", false))

static func door_spec(id: String) -> Dictionary:
	return DATA.get(id, {}).get("door", {}).duplicate(true)

static func spec(id: String) -> Dictionary:
	if not DATA.has(id): return {}
	var d: Dictionary = DATA[id]
	return {"id":id, "label":d.label, "scene":"res://assets/fleet/redesigned/"+id+".scn",
		"bounds_size":d.size, "bounds_center":[0, float(d.size[1])*.5, 0], "colors":d.colors,
		"target_width":float(d.size[0])*16.0, "target_length":float(d.size[2])*16.0,
		"acceleration":d.accel, "braking":d.braking, "max_speed":d.speed, "turn_speed":d.turn, "drift_factor":d.drift,
		"mass":d.mass, "durability":d.durability, "drivetrain":"rwd", "engine_family":d.engine, "engine_pitch":d.pitch,
		"district":d.district, "roof_prop":"none", "crop_index":0, "mesh_count":10, "sport_fleet":true,
		"muscle_fleet":true, "lowrider":bool(d.get("lowrider", false))}

## Carro para um Cobra: muscle car na rua, às vezes um lowrider. A pintura vem de COBRA_PAINTS.
static func cobra_pick(rng_value: float) -> String:
	if rng_value < .28: return LOWRIDER_IDS[int(rng_value / .28 * LOWRIDER_IDS.size()) % LOWRIDER_IDS.size()]
	var t := (rng_value - .28) / .72
	return MUSCLE_IDS[int(t * MUSCLE_IDS.size()) % MUSCLE_IDS.size()]
