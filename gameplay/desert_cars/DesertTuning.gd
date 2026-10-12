extends RefCounted
## Slot -> part ID, persisted per vehicle. Unlocks are earned by distinct race wins.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const PARTS := {
	"paint_rosso":{"label":"Vermelho", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"b62930"},
	"paint_ocean":{"label":"Azul petróleo", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"285968"},
	"paint_pearl":{"label":"Branco pérola", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"e4e1d6"},
	"paint_graphite":{"label":"Grafite", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"30383c"},
	"finish_gloss":{"label":"Brilhante", "slot":"finish", "cost":850, "wins":0, "effect":"Verniz brilhante na carroceria", "body_roughness":.23, "body_metallic":.42},
	"finish_satin":{"label":"Acetinado", "slot":"finish", "cost":850, "wins":0, "effect":"Reflexos suaves na carroceria", "body_roughness":.58, "body_metallic":.20},
	"finish_matte":{"label":"Fosco", "slot":"finish", "cost":850, "wins":0, "effect":"Acabamento fosco na carroceria", "body_roughness":.88, "body_metallic":.05},
	"wheels_silver":{"label":"Prata", "slot":"wheels", "cost":700, "wins":0, "effect":"Acabamento dos aros; mantém o modelo da roda", "wheel_color":"bfc7c8"},
	"wheels_bronze":{"label":"Bronze", "slot":"wheels", "cost":700, "wins":0, "effect":"Acabamento dos aros; mantém o modelo da roda", "wheel_color":"a58450"},
	"wheels_graphite":{"label":"Grafite", "slot":"wheels", "cost":700, "wins":0, "effect":"Acabamento dos aros; mantém o modelo da roda", "wheel_color":"384148"},
	"ecu_1":{"label":"ECU: mapa de rua", "slot":"ecu", "cost":1400, "wins":1, "effect":"Torque +4%; giro máximo +250 rpm", "torque":1.04, "redline_add":250.0, "cap":.02},
	"ecu_2":{"label":"ECU: mapa esportivo", "slot":"ecu", "cost":3300, "wins":3, "effect":"Torque +8%; giro máximo +500 rpm; baixa −3%", "torque":1.08, "redline_add":500.0, "low":.97, "cap":.04},
	"ecu_3":{"label":"ECU: mapa de competição", "slot":"ecu", "cost":6900, "wins":6, "effect":"Torque +13%; giro máximo +800 rpm; baixa −7%", "torque":1.13, "redline_add":800.0, "low":.93, "cap":.06},
	"street_cam":{"label":"Comando de rua", "slot":"engine", "cost":1800, "wins":1, "effect":"Torque +12%; resposta em baixa −4%", "torque":1.12, "low":.96, "cap":.02},
	"race_cam":{"label":"Comando de competição", "slot":"engine", "cost":5600, "wins":4, "effect":"Torque +25%; resposta em baixa −16%", "torque":1.25, "low":.84, "cap":.04},
	"turbo_small":{"label":"Turbo de resposta rápida", "slot":"turbo", "cost":3600, "wins":2, "effect":"Pressão +22%; enchimento progressivo", "boost":.22, "spool":.34, "cap":.03},
	"turbo_mid":{"label":"Turbo esportivo", "slot":"turbo", "cost":5200, "wins":3, "effect":"Pressão +33%; atraso moderado em baixa", "boost":.33, "spool":.55, "cap":.045},
	"turbo_large":{"label":"Turbo de alta vazão", "slot":"turbo", "cost":7900, "wins":5, "effect":"Pressão +45%; maior atraso em baixa", "boost":.45, "spool":.80, "cap":.06},
	"gear_short":{"label":"Relação curta", "slot":"gearbox", "cost":2100, "wins":1, "effect":"Relação +15%; final −13%", "ratio":1.15},
	"gear_long":{"label":"Relação longa", "slot":"gearbox", "cost":2300, "wins":2, "effect":"Relação −12%; arrancada mais lenta", "ratio":.88},
	"drag_tires":{"label":"Pneus de arrancada", "slot":"tires", "cost":2800, "wins":2, "effect":"Tração no asfalto +24%; na terra −30%", "grip":1.24, "dirt":.70},
	"desert_tires":{"label":"Pneus mistos", "slot":"tires", "cost":1600, "wins":1, "effect":"Tração na terra +20%; asfalto −8%", "grip":.92, "dirt":1.20},
	"lightweight":{"label":"Alívio de peso", "slot":"weight", "cost":3100, "wins":3, "effect":"Peso −12%; resistência −15%", "mass":.88, "durability":.85, "cap":.02},
	"nitro_street":{"label":"Nitro progressivo", "slot":"nitro", "cost":2900, "wins":2, "effect":"Torque +28% durante 5 s", "nitro_force":.28, "nitro_seconds":5.0},
	"nitro_race":{"label":"Nitro de descarga forte", "slot":"nitro", "cost":5100, "wins":4, "effect":"Torque +52% durante 2,8 s", "nitro_force":.52, "nitro_seconds":2.8},
	"nitro_pro":{"label":"Nitro de competição", "slot":"nitro", "cost":8800, "wins":7, "effect":"Torque +70% durante 2,2 s", "nitro_force":.70, "nitro_seconds":2.2},
	"suspension_sport":{"label":"Suspensão esportiva", "slot":"suspension", "cost":2400, "wins":2, "effect":"Curva +8%; tração +4%", "grip":1.04, "turn":1.08},
	"suspension_rally":{"label":"Suspensão de rali", "slot":"suspension", "cost":3400, "wins":4, "effect":"Terra +18%; curva +4%", "dirt":1.18, "turn":1.04},
	"drag_suspension":{"label":"Suspensão de arrancada", "slot":"suspension", "cost":2600, "wins":3, "effect":"Tração +9%; agilidade em curva −16%", "grip":1.09, "turn":.84},
	"race_exhaust":{"label":"Escape de competição", "slot":"exhaust", "cost":1500, "wins":1, "effect":"Torque +5%; escape mais presente", "torque":1.05, "exhaust":1.0, "cap":.01},
	"neon_cyan":{"label":"Neon ciano", "slot":"neon", "cost":900, "wins":1, "effect":"Iluminação sob o carro, só visual", "neon":"73edc3"},
	"neon_magenta":{"label":"Neon magenta", "slot":"neon", "cost":900, "wins":1, "effect":"Iluminação sob o carro, só visual", "neon":"ff3fa8"},
	"neon_amber":{"label":"Neon âmbar", "slot":"neon", "cost":900, "wins":1, "effect":"Iluminação sob o carro, só visual", "neon":"ff9a2e"},
	"neon_violet":{"label":"Neon violeta", "slot":"neon", "cost":900, "wins":1, "effect":"Iluminação sob o carro, só visual", "neon":"9a63ff"},
	"neon_white":{"label":"Neon branco", "slot":"neon", "cost":900, "wins":1, "effect":"Iluminação sob o carro, só visual", "neon":"e8f1ff"}
}

## Ordem e nome dos espaços na oficina; peças de potência somam no teto de rua até este limite.
const SLOTS := ["ecu","engine","turbo","nitro","gearbox","suspension","tires","weight","exhaust","paint","finish","wheels","neon"]
const SLOT_LABELS := {"ecu":"ECU","engine":"Motor","turbo":"Turbo","nitro":"Nitro","gearbox":"Câmbio","suspension":"Suspensão","tires":"Pneus","weight":"Peso","exhaust":"Escape","paint":"Pintura","finish":"Acabamento","wheels":"Aros","neon":"Neon"}
const MAX_STREET_CAP_GAIN := .20

static func clean_parts(parts: Dictionary) -> Dictionary:
	var result := {}
	for slot in parts:
		var id := str(parts[slot])
		if PARTS.has(id) and str(PARTS[id].slot) == str(slot): result[str(slot)] = id
	return result

## Ficha de partida: carro do deserto ou carro do jogo base com perfil mecânico.
static func base_spec(car_id: String) -> Dictionary:
	return STREET.spec(car_id) if STREET.has(car_id) else CARS.spec(car_id)

static func tuned_spec(car_id: String, parts: Dictionary = {}) -> Dictionary:
	var s := base_spec(car_id)
	if s.is_empty(): s = CARS.spec("desert_faisca")
	# Teto da direção livre: o motor completo chegaria a 200-276 km/h fora das provas.
	# A arrancada usa o próprio motor e ignora este valor (45 m/s = teto do jogo base).
	# Carros do jogo base trazem o teto próprio (a velocidade final que já tinham).
	if not s.has("street_cap_mps"): s["street_cap_mps"] = 45.0
	s.merge({"low_response":1.0, "boost_gain":.12 if s.get("factory_turbo",false) else 0.0,
		"spool_seconds":.3, "dirt_grip":1.0, "nitro_force":0.0, "nitro_seconds":0.0, "exhaust":0.0},true)
	var cap_gain := 0.0
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
		s.redline = float(s.redline)+float(p.get("redline_add",0.0))
		cap_gain += float(p.get("cap",0.0))
		if p.has("neon"): s.neon_color = str(p.neon); s.neon_strength = 1.0
		if p.has("boost"): s.boost_gain = float(p.boost); s.spool_seconds = float(p.spool)
		if p.has("nitro_force"): s.nitro_force = float(p.nitro_force); s.nitro_seconds = float(p.nitro_seconds)
		if p.has("exhaust"): s.exhaust = float(p.exhaust)
	s.street_cap_mps = float(s.street_cap_mps)*(1.0+minf(cap_gain,MAX_STREET_CAP_GAIN))
	return s

static func purchase_check(parts: Dictionary, owned: Array, part_id: String, wins: int, money: int) -> Dictionary:
	if not PARTS.has(part_id): return {"ok":false,"reason":"Peça inexistente"}
	var p: Dictionary = PARTS[part_id]
	if wins < int(p.wins): return {"ok":false,"reason":String(TranslationServer.translate("Vença %d provas diferentes")) % int(p.wins)}
	var cost := 0 if part_id in owned else int(p.cost)
	if money < cost: return {"ok":false,"reason":"Saldo insuficiente"}
	var next := clean_parts(parts)
	next[str(p.slot)] = part_id
	var inventory := owned.duplicate()
	if part_id not in inventory: inventory.append(part_id)
	return {"ok":true,"cost":cost,"parts":next,"owned":inventory}
