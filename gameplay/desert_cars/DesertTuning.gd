extends RefCounted
## Slot -> part ID, persisted per vehicle. Unlocks are earned by distinct race wins.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const PARTS := {
	"street_cam":{"label":"Comando de rua", "slot":"engine", "cost":1800, "wins":1, "effect":"Torque +12%; resposta em baixa −4%", "torque":1.12, "low":.96},
	"race_cam":{"label":"Comando de competição", "slot":"engine", "cost":5600, "wins":4, "effect":"Torque +25%; resposta em baixa −16%", "torque":1.25, "low":.84},
	"turbo_small":{"label":"Turbo de resposta rápida", "slot":"turbo", "cost":3600, "wins":2, "effect":"Pressão +22%; enchimento progressivo", "boost":.22, "spool":.34},
	"turbo_large":{"label":"Turbo de alta vazão", "slot":"turbo", "cost":7900, "wins":5, "effect":"Pressão +45%; maior atraso em baixa", "boost":.45, "spool":.80},
	"gear_short":{"label":"Relação curta", "slot":"gearbox", "cost":2100, "wins":1, "effect":"Relação +15%; final −13%", "ratio":1.15},
	"gear_long":{"label":"Relação longa", "slot":"gearbox", "cost":2300, "wins":2, "effect":"Relação −12%; arrancada mais lenta", "ratio":.88},
	"drag_tires":{"label":"Pneus de arrancada", "slot":"tires", "cost":2800, "wins":2, "effect":"Tração no asfalto +24%; na terra −30%", "grip":1.24, "dirt":.70},
	"desert_tires":{"label":"Pneus mistos", "slot":"tires", "cost":1600, "wins":1, "effect":"Tração na terra +20%; asfalto −8%", "grip":.92, "dirt":1.20},
	"lightweight":{"label":"Alívio de peso", "slot":"weight", "cost":3100, "wins":3, "effect":"Peso −12%; resistência −15%", "mass":.88, "durability":.85},
	"nitro_street":{"label":"Nitro progressivo", "slot":"nitro", "cost":2900, "wins":2, "effect":"Torque +28% durante 5 s", "nitro_force":.28, "nitro_seconds":5.0},
	"nitro_race":{"label":"Nitro de descarga forte", "slot":"nitro", "cost":5100, "wins":4, "effect":"Torque +52% durante 2,8 s", "nitro_force":.52, "nitro_seconds":2.8},
	"drag_suspension":{"label":"Suspensão de arrancada", "slot":"suspension", "cost":2600, "wins":3, "effect":"Tração +9%; agilidade em curva −16%", "grip":1.09, "turn":.84},
	"race_exhaust":{"label":"Escape de competição", "slot":"exhaust", "cost":1500, "wins":1, "effect":"Torque +5%; escape mais presente", "torque":1.05, "exhaust":1.0}
}

static func clean_parts(parts: Dictionary) -> Dictionary:
	var result := {}
	for slot in parts:
		var id := str(parts[slot])
		if PARTS.has(id) and str(PARTS[id].slot) == str(slot): result[str(slot)] = id
	return result

static func tuned_spec(car_id: String, parts: Dictionary = {}) -> Dictionary:
	var s := CARS.spec(car_id)
	if s.is_empty(): s = CARS.spec("desert_faisca")
	s.merge({"low_response":1.0, "boost_gain":.12 if s.get("factory_turbo",false) else 0.0,
		"spool_seconds":.3, "dirt_grip":1.0, "nitro_force":0.0, "nitro_seconds":0.0, "exhaust":0.0},true)
	for id in clean_parts(parts).values():
		var p: Dictionary = PARTS[id]
		s.torque_nm *= float(p.get("torque",1.0))
		s.acceleration *= float(p.get("torque",1.0))
		s.mass *= float(p.get("mass",1.0))
		s.durability = float(s.durability)*float(p.get("durability",1.0))
		s.final_drive *= float(p.get("ratio",1.0))
		s.max_speed /= float(p.get("ratio",1.0))
		s.traction *= float(p.get("grip",1.0))
		s.dirt_grip *= float(p.get("dirt",1.0))
		s.turn_speed *= float(p.get("turn",1.0))
		s.low_response *= float(p.get("low",1.0))
		if p.has("boost"): s.boost_gain = float(p.boost); s.spool_seconds = float(p.spool)
		if p.has("nitro_force"): s.nitro_force = float(p.nitro_force); s.nitro_seconds = float(p.nitro_seconds)
		if p.has("exhaust"): s.exhaust = float(p.exhaust)
	return s

static func purchase_check(parts: Dictionary, owned: Array, part_id: String, wins: int, money: int) -> Dictionary:
	if not PARTS.has(part_id): return {"ok":false,"reason":"Peça inexistente"}
	var p: Dictionary = PARTS[part_id]
	if wins < int(p.wins): return {"ok":false,"reason":"Vença %d provas diferentes" % int(p.wins)}
	var cost := 0 if part_id in owned else int(p.cost)
	if money < cost: return {"ok":false,"reason":"Saldo insuficiente"}
	var next := clean_parts(parts)
	next[str(p.slot)] = part_id
	var inventory := owned.duplicate()
	if part_id not in inventory: inventory.append(part_id)
	return {"ok":true,"cost":cost,"parts":next,"owned":inventory}
