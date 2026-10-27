extends RefCounted
## Esportivos 2.0 (27/10): oito carros para cobrir as trações que faltavam (AWD, FWD, RWD e
## 4x4 esportivos). Ficha no formato da frota (16 px por metro); a aparência é assada
## offline por tools/fleet_fixups/build_sport_fleet_v2.gd em assets/fleet/redesigned/<id>.scn.
## A porta e a cabine daqui são as mesmas medidas que o gerador usa para recortar a folha.
const IDS := ["tauro_v10", "raijin_gt", "kite_type_s", "lince_rs", "brisa_s", "sakura_s15", "rapina_r", "bastiao_63"]
const DATA := {
	"tauro_v10": {"label":"Tauro V10", "size":[2.01,1.2,4.64], "colors":["8fc23aff","e2672cff","1b1e22ff","e9e9e4ff","2f6fb8ff"],
		"speed":840.0, "accel":1550.0, "braking":1780.0, "turn":3.10, "drift":.82, "mass":1.42, "durability":190, "pitch":1.24,
		"drivetrain":"awd", "engine":"rosso_v12", "district":"exclusive",
		"door":{"zf":-.78,"zr":.36,"sill":.26,"belt":0.79,"top":1.13,"x":0.81,"seat_z":-.12}},
	"raijin_gt": {"label":"Raijin GT", "size":[1.91,1.41,4.79], "colors":["c9ced2ff","1d2328ff","8a1f24ff","e9e9e4ff","2e4e74ff"],
		"speed":780.0, "accel":1500.0, "braking":1720.0, "turn":2.95, "drift":.86, "mass":1.75, "durability":240, "pitch":1.10,
		"drivetrain":"awd", "engine":"vq35", "district":"city",
		"door":{"zf":-.84,"zr":.42,"sill":.28,"belt":0.91,"top":1.28,"x":0.85,"seat_z":-.06}},
	"kite_type_s": {"label":"Kite Type S", "size":[1.74,1.36,4.48], "colors":["e6e3d8ff","b5262cff","1c1f24ff","e0b43aff","3a5f8fff"],
		"speed":640.0, "accel":1150.0, "braking":1520.0, "turn":3.25, "drift":.84, "mass":1.10, "durability":170, "pitch":1.20,
		"drivetrain":"fwd", "engine":"sport", "district":"city",
		"door":{"zf":-.92,"zr":.44,"sill":.30,"belt":0.81,"top":1.23,"x":0.79,"seat_z":-.04}},
	"lince_rs": {"label":"Lince RS", "size":[1.88,1.49,4.25], "colors":["e2832dff","d9dde0ff","1b1e22ff","2b6a4bff","b5262cff"],
		"speed":650.0, "accel":1200.0, "braking":1560.0, "turn":3.15, "drift":.84, "mass":1.35, "durability":190, "pitch":1.12,
		"drivetrain":"fwd", "engine":"sport", "district":"city",
		"door":{"zf":-.98,"zr":.32,"sill":.30,"belt":0.87,"top":1.29,"x":0.8,"seat_z":-.12}},
	"brisa_s": {"label":"Brisa S Roadster", "size":[1.79,1.16,4.05], "colors":["b8282eff","e9e9e4ff","1d2a44ff","8fb3c3ff","2f4a3cff"],
		"speed":600.0, "accel":1100.0, "braking":1500.0, "turn":3.40, "drift":.90, "mass":1.06, "durability":160, "pitch":1.15,
		"drivetrain":"rwd", "engine":"sport", "district":"beach",
		"door":{"zf":-.64,"zr":.24,"sill":.27,"belt":0.78,"top":1.1,"x":0.79,"seat_z":.06}},
	"sakura_s15": {"label":"Sakura S15", "size":[1.79,1.33,4.53], "colors":["2b4f8cff","e9e9e4ff","d79bb2ff","1b1e22ff","9aa3aaff"],
		"speed":660.0, "accel":1180.0, "braking":1520.0, "turn":3.30, "drift":.93, "mass":1.24, "durability":180, "pitch":1.10,
		"drivetrain":"rwd", "engine":"sport", "district":"city",
		"door":{"zf":-.90,"zr":.40,"sill":.29,"belt":0.81,"top":1.19,"x":0.78,"seat_z":-.04}},
	"rapina_r": {"label":"Rapina R", "size":[2.23,2.02,5.67], "colors":["5b6570ff","e2672cff","1b1e22ff","e9e9e4ff","7a2a2aff"],
		"speed":560.0, "accel":1080.0, "braking":1260.0, "turn":2.30, "drift":.80, "mass":2.65, "durability":360, "pitch":.85,
		"drivetrain":"4x4", "engine":"m8_v8", "district":"desert",
		"door":{"class":"tall","zf":-1.08,"zr":-.05,"sill":.58,"belt":1.25,"top":1.85,"x":0.91,"seat_z":-.48}},
	"bastiao_63": {"label":"Bastião 63", "size":[2.18,2.04,5.17], "colors":["8a8f93ff","1c1f22ff","5f6b4fff","e9e9e4ff","6b1f26ff"],
		"speed":580.0, "accel":1120.0, "braking":1300.0, "turn":2.40, "drift":.82, "mass":2.50, "durability":380, "pitch":.90,
		"drivetrain":"4x4", "engine":"m8_v8", "district":"exclusive",
		"door":{"class":"tall","zf":-.92,"zr":.05,"sill":.50,"belt":1.09,"top":1.94,"x":0.94,"seat_z":-.40}},
}

static func door_spec(id: String) -> Dictionary:
	return DATA.get(id, {}).get("door", {}).duplicate(true)

static func spec(id: String) -> Dictionary:
	if not DATA.has(id): return {}
	var d: Dictionary = DATA[id]
	return {"id":id, "label":d.label, "scene":"res://assets/fleet/redesigned/"+id+".scn",
		"bounds_size":d.size, "bounds_center":[0, float(d.size[1])*.5, 0], "colors":d.colors,
		"target_width":float(d.size[0])*16.0, "target_length":float(d.size[2])*16.0,
		"acceleration":d.accel, "braking":d.braking, "max_speed":d.speed, "turn_speed":d.turn, "drift_factor":d.drift,
		"mass":d.mass, "durability":d.durability, "drivetrain":d.drivetrain, "engine_family":d.engine, "engine_pitch":d.pitch,
		"district":d.district, "roof_prop":"none", "crop_index":0, "mesh_count":10, "sport_fleet":true}
