extends RefCounted
## Slot -> part ID, persisted per vehicle. Unlocks are earned by distinct race wins.
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const PARTS := {
	"paint_black":{"label":"Preto", "slot":"paint", "cost":1200, "wins":0, "effect":"Cor da carroceria", "body_color":"101319"},
	"paint_silver":{"label":"Prata", "slot":"paint", "cost":1200, "wins":0, "effect":"Cor da carroceria", "body_color":"aab3ba"},
	"paint_yellow":{"label":"Amarelo", "slot":"paint", "cost":1200, "wins":0, "effect":"Cor da carroceria", "body_color":"e7bb2f"},
	"paint_orange":{"label":"Laranja", "slot":"paint", "cost":1200, "wins":0, "effect":"Cor da carroceria", "body_color":"cf612b"},
	"paint_green":{"label":"Verde", "slot":"paint", "cost":1200, "wins":0, "effect":"Cor da carroceria", "body_color":"376d46"},
	"paint_purple":{"label":"Roxo", "slot":"paint", "cost":1200, "wins":0, "effect":"Cor da carroceria", "body_color":"694586"},
	"spoiler_lip":{"label":"Lâmina", "slot":"spoiler", "cost":1700, "wins":0, "effect":"Aerofólio da carroceria", "spoiler_style":"lip"},
	"spoiler_sport":{"label":"Esportivo", "slot":"spoiler", "cost":3200, "wins":0, "effect":"Aerofólio da carroceria", "spoiler_style":"sport"},
	"sunroof_glass":{"label":"Vidro fumê", "slot":"sunroof", "cost":3800, "wins":0, "effect":"Vidro do teto solar", "sunroof_style":"glass"},
	"sunroof_clear":{"label":"Vidro claro", "slot":"sunroof", "cost":3800, "wins":0, "effect":"Vidro do teto solar", "sunroof_style":"clear"},
	"taillights_smoke":{"label":"Fumê", "slot":"taillights", "cost":950, "wins":0, "effect":"Acabamento das lanternas", "tail_color":"352c37"},
	"taillights_amber":{"label":"Âmbar", "slot":"taillights", "cost":950, "wins":0, "effect":"Acabamento das lanternas", "tail_color":"d57a25"},
	"taillights_ruby":{"label":"Rubi", "slot":"taillights", "cost":950, "wins":0, "effect":"Acabamento das lanternas", "tail_color":"8c1737"},
	"wheel_five_spoke":{"label":"Cinco raios", "slot":"wheel_model", "cost":2200, "wins":0, "effect":"Modelo dos aros", "wheel_design":"five_spoke"},
	"wheel_mesh":{"label":"Malha", "slot":"wheel_model", "cost":2800, "wins":0, "effect":"Modelo dos aros", "wheel_design":"mesh"},
	"wheel_turbine":{"label":"Turbina", "slot":"wheel_model", "cost":3100, "wins":0, "effect":"Modelo dos aros", "wheel_design":"turbine"},
	"wheel_size_compact":{"label":"Aro compacto", "slot":"wheel_size", "cost":850, "wins":0, "effect":"Tamanho dos aros", "rim_ratio":.60},
	"wheel_size_sport":{"label":"Aro esportivo", "slot":"wheel_size", "cost":1100, "wins":0, "effect":"Tamanho dos aros", "rim_ratio":.72},
	"wheel_size_large":{"label":"Aro grande", "slot":"wheel_size", "cost":1450, "wins":0, "effect":"Tamanho dos aros", "rim_ratio":.80},
	"rival_digo_ecu":{"label":"Mapa Digo · saída", "slot":"ecu", "cost":0, "wins":0, "rival_reward":"digo", "effect":"Torque +5,5%; resposta em baixa +10%; giro máximo −100 rpm", "torque":1.055, "low":1.10, "redline_add":-100.0, "cap":.02},
	"rival_livia_tires":{"label":"Pneus Lívia · rua", "slot":"tires", "cost":0, "wins":0, "rival_reward":"livia", "effect":"Tração: asfalto +18%; terra −3,2% no total; agilidade −4%", "grip":1.18, "dirt":.82, "turn":.96},
	"rival_raul_gear":{"label":"Relação Raul · equilíbrio", "slot":"gearbox", "cost":0, "wins":0, "rival_reward":"raul", "effect":"Relação −6%; mais final, saída um pouco mais longa", "ratio":.94},
	"rival_jessica_turbo":{"label":"Turbo Jessica · resposta", "slot":"turbo", "cost":0, "wins":0, "rival_reward":"jessica", "effect":"Pressão +27%; responde antes do esportivo, com menos pico", "boost":.27, "spool":.26, "cap":.035},
	"rival_nadir_weight":{"label":"Alívio Nadir · reforçado", "slot":"weight", "cost":0, "wins":0, "rival_reward":"nadir", "effect":"Peso −7%; resistência −3%; preserva mais resistência que o alívio comum", "mass":.93, "durability":.97, "cap":.01},
	"rival_rauhz_nitro":{"label":"Nitro Rauhz · dosado", "slot":"nitro", "cost":0, "wins":0, "rival_reward":"rauhz", "effect":"Torque +38% durante 3,6 s; entre o progressivo e o de descarga forte", "nitro_force":.38, "nitro_seconds":3.6},
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
	"neon_white":{"label":"Neon branco", "slot":"neon", "cost":900, "wins":1, "effect":"Iluminação sob o carro, só visual", "neon":"e8f1ff"},
	"spoiler_ducktail":{"label":"Rabo de pato", "slot":"spoiler", "cost":2300, "wins":0, "effect":"Aerofólio da carroceria", "spoiler_style":"ducktail"},
	"spoiler_gt":{"label":"Asa GT", "slot":"spoiler", "cost":4800, "wins":0, "effect":"Aerofólio alto de pista", "spoiler_style":"gt"},
	"skirt_slim":{"label":"Reta", "slot":"skirts", "cost":1400, "wins":0, "effect":"Saia lateral discreta na cor do carro", "skirt_style":"slim"},
	"skirt_sport":{"label":"Esportiva", "slot":"skirts", "cost":2100, "wins":0, "effect":"Saia lateral com lábio, na cor do carro", "skirt_style":"sport"},
	"skirt_vented":{"label":"Com entradas", "slot":"skirts", "cost":2600, "wins":0, "effect":"Saia esportiva com entradas de ar", "skirt_style":"vented"},
	"skirt_carbon":{"label":"Carbono", "slot":"skirts", "cost":3400, "wins":0, "effect":"Saia esportiva em fibra de carbono", "skirt_style":"carbon"},
	"skirt_step":{"label":"Estribo", "slot":"skirts", "cost":1900, "wins":0, "effect":"Estribo lateral de utilitário", "skirt_style":"step"},
	"lip_sport":{"label":"Lábio esportivo", "slot":"front_lip", "cost":1300, "wins":0, "effect":"Lábio sob o para-choque, na cor do carro", "lip_style":"sport"},
	"lip_splitter":{"label":"Splitter de carbono", "slot":"front_lip", "cost":2400, "wins":0, "effect":"Lâmina dianteira larga com defletores", "lip_style":"splitter"},
	"diffuser_street":{"label":"Difusor de rua", "slot":"diffuser", "cost":1500, "wins":0, "effect":"Difusor traseiro com quatro aletas", "diffuser_style":"street"},
	"diffuser_race":{"label":"Difusor de pista", "slot":"diffuser", "cost":2900, "wins":0, "effect":"Difusor de carbono com seis aletas e luz de chuva", "diffuser_style":"race"},
	"paint_royal":{"label":"Azul royal", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"1f3f9a"},
	"paint_wine":{"label":"Vinho", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"5e1a26"},
	"paint_lime":{"label":"Verde limão", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"9bc53d"},
	"paint_pink":{"label":"Rosa", "slot":"paint", "cost":1200, "wins":0, "effect":"Pintura da carroceria", "body_color":"d9628f"},
	"wheels_black":{"label":"Preto", "slot":"wheels", "cost":700, "wins":0, "effect":"Acabamento dos aros; mantém o modelo da roda", "wheel_color":"1c1f22"},
	"wheels_gold":{"label":"Dourado", "slot":"wheels", "cost":700, "wins":0, "effect":"Acabamento dos aros; mantém o modelo da roda", "wheel_color":"c9a24a"},
	"wheels_white":{"label":"Branco", "slot":"wheels", "cost":700, "wins":0, "effect":"Acabamento dos aros; mantém o modelo da roda", "wheel_color":"e6e6e1"},
	"wheel_six_spoke":{"label":"Seis raios", "slot":"wheel_model", "cost":2400, "wins":0, "effect":"Modelo dos aros", "wheel_design":"six_spoke"},
	"wheel_multi_spoke":{"label":"Raios finos", "slot":"wheel_model", "cost":3300, "wins":0, "effect":"Modelo dos aros", "wheel_design":"multi_spoke"}
}

## Ordem e nome dos espaços na oficina; peças de potência somam no teto de rua até este limite.
const SLOTS := ["ecu","engine","turbo","nitro","gearbox","suspension","tires","weight","exhaust","paint","finish","wheels","neon","spoiler","sunroof","taillights","wheel_model","wheel_size","skirts","front_lip","diffuser"]
const SLOT_LABELS := {"ecu":"ECU","engine":"Motor","turbo":"Turbo","nitro":"Nitro","gearbox":"Câmbio","suspension":"Suspensão","tires":"Pneus","weight":"Peso","exhaust":"Escape","paint":"Pintura","finish":"Acabamento","wheels":"Cor dos aros","neon":"Neon","spoiler":"Aerofólio","sunroof":"Teto solar","taillights":"Lanternas","wheel_model":"Modelo de roda","wheel_size":"Tamanho do aro","skirts":"Saias laterais","front_lip":"Lábio dianteiro","diffuser":"Difusor"}
const SUNROOF_MODELS := ["desert_faisca","desert_coyote","desert_siroco","desert_bison","desert_mirage","desert_faisca_rally","desert_coyote_drag","desert_mirage_gt","rauhz_focus_mk1","supra_a80","digo_gol_1993","digo_amarok_2014","jessica_jetta_gli"]
const MAX_STREET_CAP_GAIN := .20
## Peças que o carro já traz de fábrica fundidas na malha da carroceria: a versão de
## oficina ficaria duplicada por cima (auditoria visual de 27/10). Asas e aerofólios de teto,
## splitter das edições GT/Drag/Rally, aletas do Mirage GT e escapamento lateral do Drag.
const FACTORY_KIT := {
	"spoiler":["sport_coupe","monaliza","supra_a80","desert_siroco","desert_mirage","desert_mirage_gt","desert_faisca","desert_faisca_rally","desert_coyote_drag","metro_hatch","rauhz_focus_mk1","orbita_micro","lince_rs","raijin_gt","kite_type_s"],
	"front_lip":["desert_faisca_rally","desert_coyote_drag","desert_mirage_gt"],
	"diffuser":["desert_mirage_gt"],
	"skirts":["desert_coyote_drag"]}

static func compatible(part_id: String, car_id: String) -> bool:
	if not PARTS.has(part_id): return false
	var slot := str(PARTS[part_id].slot)
	if slot == "sunroof": return car_id in SUNROOF_MODELS
	if slot in ["spoiler","wheel_model","wheel_size","taillights","skirts","front_lip","diffuser"]:
		if not STREET.has(car_id) and car_id not in SUNROOF_MODELS: return false
		if car_id.begins_with("bike_") or car_id in ["beach_buggy","dune_buggy","beach_cabriolet"]: return false
		var utility := is_utility(car_id)
		if slot in ["spoiler","front_lip","diffuser"] and utility: return false
		if car_id in FACTORY_KIT.get(slot,[]): return false
		# Utilitário leva só o estribo; carro baixo leva só as saias de verdade.
		if slot == "skirts" and utility != (str(PARTS[part_id].get("skirt_style","")) == "step"): return false
	return true

## Picapes e SUVs altos: levam estribo, não aerofólio, lábio nem difusor.
const UTILITY := ["desert_bison","digo_amarok_2014","rapina_r","bastiao_63"]

static func is_utility(car_id: String) -> bool:
	return str(STREET.PROFILES.get(car_id,{}).get("kind","")) == "utility" or car_id.contains("pickup") or car_id in UTILITY

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
	if p.has("rival_reward") and part_id not in owned: return {"ok":false,"reason":"Conclua os dois desafios deste rival e retire a peça no quadro."}
	if wins < int(p.wins): return {"ok":false,"reason":String(TranslationServer.translate("Vença %d provas diferentes")) % int(p.wins)}
	var cost := 0 if part_id in owned else int(p.cost)
	if money < cost: return {"ok":false,"reason":"Saldo insuficiente"}
	var next := clean_parts(parts)
	next[str(p.slot)] = part_id
	var inventory := owned.duplicate()
	if part_id not in inventory: inventory.append(part_id)
	return {"ok":true,"cost":cost,"parts":next,"owned":inventory}
