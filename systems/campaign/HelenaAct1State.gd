extends RefCounted
## Ato 1, cadeia paralela da Helena e do Neco (roteiro de diretor de 21/10/2026, seção "Ato 1 — Harbor"):
##   M02-B "Cobrança em dobro" (debt), M04-B "O desmanche do Neco" (press), M05-B "Posto de lavagem"
##   (wash), M06-B "O que a Helena guardou" (folder), a cena opcional "Carona" (ride) e a despedida no
##   cais que fecha M07 (farewell).
## As missões principais (HarborMissions) não mudam: nem ORDER, nem ids, nem recompensas. Cada missão
## daqui guarda a própria etapa numa chave do world_state e só abre depois da principal que a antecede
## ("after"); save antigo, sem nenhuma chave, continua válido e só encontra as missões disponíveis.
## Quem paga paga uma vez, na conclusão, com recibo de valor fixo (Economy.grant_world_reward).
## Valores gravados em recibo: NUNCA mudar (o save valida contra eles; HOW-TO-DEVELOP, regra 11).
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const CHAIN := {
	# Helena mostra a cobrança dupla; o Neco empresta o guincho; três carros voltam aos donos.
	"debt": {"key": "harbor_act1_debt", "title": "Cobrança em dobro", "after": "cobra_contact", "needs": "",
		"stages": ["", "neco", "tow1", "tow2", "tow3", "done"], "receipt": "harbor_act1_debt", "amount": 300},
	# Carro raspado de cliente do Maciota na prensa: prensar (a sucata paga pela prensa, como sempre) ou
	# devolver ao dono. A escolha fica gravada em "choice".
	"press": {"key": "harbor_act1_press", "title": "O desmanche do Neco", "after": "cobra_collection", "needs": "",
		"stages": ["", "press", "return", "done"], "next": {"": ["press", "return"], "press": ["done"], "return": ["done"]},
		"receipt": "", "amount": 0},
	# Cena do cais, o cofre do posto dos Cobras com a Helena no telefone e os envelopes na porta de quem
	# pagou em dobro (a lista de M02-B).
	"wash": {"key": "harbor_act1_wash", "title": "Posto de lavagem", "after": "jessica_bank", "needs": "debt",
		"stages": ["", "station", "escape", "envelopes", "done"], "receipt": "harbor_act1_wash", "amount": 600},
	# Infiltração noturna no North Pier para tirar a pasta da Helena antes da auditoria.
	"folder": {"key": "harbor_act1_folder", "title": "O que a Helena guardou", "after": "cobra_supply", "needs": "wash",
		"stages": ["", "night", "handoff", "done"], "receipt": "", "amount": 0},
	# Cena opcional: Helena no ponto de ônibus do cais, à noite, carona na Monaliza.
	"ride": {"key": "harbor_act1_ride", "title": "Carona", "after": "cobra_contact", "needs": "",
		"stages": ["", "done"], "receipt": "", "amount": 0},
	# Fechamento de M07: Helena no cais ao amanhecer, com a mala. Depois da ligação do Maciota.
	"farewell": {"key": "harbor_act1_farewell", "title": "A última volta · cais", "after": "cobra_finale", "needs": "folder",
		"stages": ["", "done"], "receipt": "", "amount": 0},
}
const ORDER := ["debt", "ride", "press", "wash", "folder", "farewell"]
## M02-B: carros tomados pelos Cobras ("garantia"), cada um num canto de Ashbend, e a porta do dono.
## Pontos na pista da Prova de rua (CobraRaceCourse.POINTS), que é rua de verdade; o último é o da dona Cida.
const DEBT_CARS := [
	{"model": "union_sedan", "pickup": Vector3(425.0, 0, 104.8), "yaw": PI * .5, "drop": Vector3(301.0, 0, 23.27), "owner": "seu Arlindo"},
	{"model": "metro_hatch", "pickup": Vector3(404.0, 0, 90.7), "yaw": 0.0, "drop": Vector3(348.87, 0, 52.8), "owner": "Rosa da padaria"},
	{"model": "station_wagon", "pickup": Vector3(371.4, 0, 76.1), "yaw": PI * .5, "drop": Vector3(450.0, 0, 104.89), "owner": "dona Cida"},
]
const DEBT_DROP_RADIUS := 10.0

static func spec(id: String) -> Dictionary:
	return CHAIN.get(id, {})

static func _value(world: Dictionary, id: String) -> Dictionary:
	var value: Variant = world.get(CHAIN[id].key, {})
	return value if value is Dictionary else {}

static func stage(world: Dictionary, id: String) -> String:
	return str(_value(world, id).get("stage", ""))

static func complete(world: Dictionary, id: String) -> bool:
	return stage(world, id) == "done"

static func choice(world: Dictionary) -> String:
	return str(_value(world, "press").get("choice", ""))

## Missão principal anterior concluída (ou pulada por save antigo) e, quando houver, a anterior da cadeia.
static func ready(world: Dictionary, campaign: Dictionary, id: String) -> bool:
	var definition: Dictionary = CHAIN[id]
	if not _has_progress(campaign, str(definition.after)): return false
	if id == "farewell" and not bool(campaign.get("aftermath", {}).get("call_complete", false)): return false
	return str(definition.needs).is_empty() or complete(world, str(definition.needs))

static func _has_progress(campaign: Dictionary, mission: String) -> bool:
	return campaign.get("completed", []).has(mission) or campaign.get("legacy_skipped", []).has(mission)

static func _allowed(id: String, from: String) -> Array:
	var definition: Dictionary = CHAIN[id]
	if definition.has("next"): return definition.next.get(from, [])
	var stages: Array = definition.stages
	var at := stages.find(from)
	return [stages[at + 1]] if at >= 0 and at + 1 < stages.size() else []

## Próxima etapa (nunca "done": a conclusão é finish, que paga junto).
static func advance(world: Dictionary, campaign: Dictionary, id: String, to_stage: String) -> bool:
	if to_stage == "done" or not ready(world, campaign, id): return false
	if to_stage not in _allowed(id, stage(world, id)): return false
	var next := {"version": 1, "stage": to_stage}
	if id == "press": next.choice = to_stage
	world[CHAIN[id].key] = next
	return true

## Conclusão: recibo (se a missão paga) e etapa "done", tudo ou nada.
static func finish(world: Dictionary, campaign: Dictionary, economy, id: String) -> Dictionary:
	var definition: Dictionary = CHAIN[id]
	if not ready(world, campaign, id) or "done" not in _allowed(id, stage(world, id)): return {"ok": false, "reason": "stage"}
	if int(definition.amount) > 0:
		var paid: Dictionary = economy.grant_world_reward({"id": str(definition.receipt), "kind": "cash", "amount": int(definition.amount), "label": String(TranslationServer.translate(str(definition.title)))})
		if not paid.ok: return {"ok": false, "reason": str(paid.get("reason", "wallet_full"))}
	var next := {"version": 1, "stage": "done"}
	if id == "press": next.choice = choice(world)
	world[definition.key] = next
	return {"ok": true, "amount": int(definition.amount)}

## Índice do carro de M02-B que o guincho pode estar levando agora (-1 fora das etapas do guincho).
static func debt_tow_index(world: Dictionary) -> int:
	return ["tow1", "tow2", "tow3"].find(stage(world, "debt"))

## Contrato do save: forma de cada chave, etapa coerente com a campanha e recibo se e só se terminou.
## `campaign` é o snapshot de CampaignRuntime (o mesmo que o save grava).
static func validate(world: Dictionary, economy: Dictionary, campaign: Dictionary) -> bool:
	for id in ORDER:
		var definition: Dictionary = CHAIN[id]
		var receipt: Dictionary = {} if str(definition.receipt).is_empty() else RECEIPTS.lookup(economy, "reward", str(definition.receipt))
		if not receipt.is_empty() and int(receipt.get("amount", -1)) != int(definition.amount): return false
		if not world.has(definition.key):
			if not receipt.is_empty(): return false
			continue
		var value: Variant = world[definition.key]
		if not value is Dictionary or value.get("version") != 1: return false
		if not value.get("stage") is String or value.stage not in definition.stages: return false
		if id == "press":
			if value.size() != 3 or not value.get("choice") is String: return false
			if value.stage == "": return false
			if value.choice not in ["press", "return"]: return false
			if value.stage != "done" and value.choice != value.stage: return false
		elif value.size() != 2: return false
		if value.stage == "" and id != "press": return false
		if not ready(world, campaign, id): return false
		if int(definition.amount) > 0 and (value.stage == "done") == receipt.is_empty(): return false
	return true

## Linha do diário (J): a missão aberta mais adiantada da cadeia, ou vazio.
static func journal_line(world: Dictionary, campaign: Dictionary) -> String:
	for id in ORDER:
		if not ready(world, campaign, id) or complete(world, id): continue
		var text := objective_for(world, id)
		if not text.is_empty(): return str(CHAIN[id].title) + " · " + text
	return ""

## Texto do objetivo de cada etapa. Objetivo diz o que fazer; o motivo fica nas falas.
static func objective_for(world: Dictionary, id: String) -> String:
	var current := stage(world, id)
	match id:
		"debt":
			match current:
				"": return "Helena quer falar com você no North Pier, no fim do expediente."
				"neco": return "Peça o guincho ao Neco, na baia dele."
				"tow1", "tow2", "tow3":
					var car: Dictionary = DEBT_CARS[debt_tow_index(world)]
					return "Guinche o carro de %s em Ashbend e deixe na porta do dono (%d/3)." % [car.owner, debt_tow_index(world) + 1]
		"press":
			match current:
				"": return "O Neco tem uma entrega para a prensa. Passe no pátio dele."
				"press": return "Pare o carro raspado na baia e acione a prensa."
				"return": return "Leve o carro raspado de volta ao cliente do Maciota, em Westgate."
		"wash":
			match current:
				"": return "Helena espera no cais, perto do porto."
				"station": return "Entre no posto dos Cobras (Fuel, North Frontage) depois da meia-noite e abra o cofre."
				"escape": return "Fuja com o dinheiro e despiste a polícia."
				"envelopes": return "Deixe os envelopes na porta de quem pagou em dobro."
		"folder":
			match current:
				"": return "Helena espera no cais, perto do porto."
				"night": return "À noite (22h–5h), entre pelos fundos do North Pier, sem ser visto, e pegue a pasta na gaveta da Helena."
				"handoff": return "Leve a pasta à Helena, na rua ao lado do banco."
		"ride":
			if current == "": return "À noite, Helena espera o ônibus no ponto Cais / Serviços. Pare a Monaliza ao lado."
		"farewell":
			if current == "": return "Ao amanhecer (5h–9h), Helena está no cais, perto do porto."
	return ""
