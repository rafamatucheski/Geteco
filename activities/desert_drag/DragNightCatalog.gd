extends RefCounted
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const CATEGORIES := {
	"livre":{"name":"Livre","budget":-1},
	"street":{"name":"Acerto R$ 6 mil","budget":6000},
	"prepared":{"name":"Acerto R$ 12 mil","budget":12000},
}
const COSMETIC := ["paint","finish","wheels","neon"]
const GIFT_VALUES := {"rival_digo_ecu":1800,"rival_livia_tires":2400,"rival_raul_gear":2200,"rival_jessica_turbo":4300,"rival_nadir_weight":2600,"rival_rauhz_nitro":3900}
## The specialty explains an actionable setup choice, never decorative signage.
const RIVALS := {
	"digo":{"specialty":"Resposta em baixa","parts":"ECU · COMANDO DE RUA","advice":"201 m: resposta rápida e tração antes de potência.","voice":"O acerto bom aparece no primeiro metro. Depois a gente conversa de cavalo."},
	"livia":{"specialty":"Tração na saída","parts":"PNEUS · SUSPENSÃO","advice":"201 m: patinar menos vale mais que subir o giro.","voice":"Escuta o pneu. Se ele grita o tempo todo, a força está ficando no chão."},
	"raul":{"specialty":"Relação de marcha","parts":"RELAÇÃO CURTA · LONGA","advice":"800 m: relação curta demais cobra no fim.","voice":"Curta pra sair. Longa pra chegar. Quero ver qual tu escolhe."},
	"jessica":{"specialty":"Giro e turbo","parts":"ECU ESPORTIVA · TURBO","advice":"402 m: repita o acerto para comparar as duas passadas.","voice":"Uma puxada boa pode ser sorte. Duas mostram que você conhece o carro."},
	"nadir":{"specialty":"Fôlego em alta","parts":"PESO · NITRO","advice":"800 m: guarde força para o trecho que decide.","voice":"Eu olho a chegada. O resto é só barulho até você provar o contrário."},
	"rauhz":{"specialty":"Preparação completa","parts":"PEÇAS DE COMPETIÇÃO","advice":"Vença duas das três provas para levar a noite.","voice":"Quero ver esse mesmo carro sair, repetir e chegar. A noite inteira."},
}

static func get_rival(identity: String) -> Dictionary:
	return RIVALS.get(identity,RIVALS.digo).duplicate(true)

static func preparation_value(parts: Dictionary) -> int:
	var total := 0
	for slot in TUNING.clean_parts(parts):
		if slot in COSMETIC: continue
		var id := str(parts[slot])
		total+=int(GIFT_VALUES.get(id,TUNING.PARTS[id].cost))
	return total

static func fits_category(parts: Dictionary, category: String) -> bool:
	if not CATEGORIES.has(category): return false
	return int(CATEGORIES[category].budget)<0 or preparation_value(parts)<=int(CATEGORIES[category].budget)

static func rival_preparation(parts: Dictionary, category: String) -> Dictionary:
	if category=="livre": return parts.duplicate(true)
	var result := {}
	# Prefer usable traction and gearing before a high-power build. Every candidate
	# is still one of this rival's authored parts and obeys the same installed cap.
	for slot in ["tires","gearbox","ecu","suspension","engine","turbo","weight","nitro","exhaust"]:
		if not parts.has(slot): continue
		var candidate := result.duplicate()
		candidate[slot]=parts[slot]
		if fits_category(candidate,category): result=candidate
	return result
