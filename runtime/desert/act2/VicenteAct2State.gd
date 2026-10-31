extends RefCounted
## Ato 2 (20/10/2026; roteiro em docs/story-act2-vicente-20261020.md): livro de etapas das missões
## A2-01 "Oito anos" (chave KEY) e A2-02 "Respeita a pista" (chave TRACK_KEY).
##
## A2-01:
## Livro de etapas do reencontro: o encontro da arrancada, o Motel Oásis e a Capela. Cada etapa só
## avança no fim do diálogo dela (morte ou prisão no meio da conversa não conta), e o save guarda a
## etapa: carregar, morrer ou ser preso volta para o mesmo lugar da história.
## A conclusão marca "met_vicente" em DesertStoryState, que destrava o resto da cadeia antiga do
## deserto (Digo, manifesto, Irene, Jessica, prova). Save sem a chave "vicente_act2" e com
## met_vicente já marcado veio da conversa única de antes de 20/10: conta como reencontro feito.
const KEY := "vicente_act2"
const STAGES := ["", "motel", "chapel", "done"]
## Envelope que Vicente devolve na capela: o dinheiro que Dante mandou ao advogado nos oito anos.
## Valor gravado em recibo: NUNCA mudar (o save valida contra ele; ver HOW-TO-DEVELOP, regra 11).
const ENVELOPE_RECEIPT := "desert_act2_reunion_envelope"
const ENVELOPE_AMOUNT := 1500
const STORY := preload("res://runtime/desert/DesertStoryState.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
## A2-02: Bia explica a reta, a corrida com o Digo (a prova que já existe) e a conversa com Vicente na
## Arquibancada. A corrida é da própria arrancada (DigoProgress): terminar a prova com o Digo, mesmo
## sem falar com a Bia antes, já leva para a Arquibancada. Sem recompensa em dinheiro (a oficina do
## Digo é o prêmio, como no esqueleto). Save antigo que já tinha a oficina sem passar por A2-01 nesta
## versão (sem KEY) conta como feito.
const TRACK_KEY := "vicente_act2_track"
const TRACK_STAGES := ["", "race", "grandstand", "done"]

static func defaults() -> Dictionary:
	return {"version": 1, "stage": ""}

static func data(world: Dictionary) -> Dictionary:
	var value: Variant = world.get(KEY, defaults())
	return value.duplicate(true) if value is Dictionary else defaults()

## Etapa efetiva: save antigo com o encontro feito pela conversa única conta como concluído.
static func stage(world: Dictionary) -> String:
	if not world.has(KEY) and bool(STORY.data(world).met_vicente): return "done"
	return str(data(world).get("stage", ""))

static func complete(world: Dictionary) -> bool:
	return stage(world) == "done"

## Avança uma etapa por vez (sem pular) e recusa voltar.
static func advance(world: Dictionary, to_stage: String) -> bool:
	var current := stage(world)
	var at := STAGES.find(current)
	if at < 0 or STAGES.find(to_stage) != at + 1: return false
	var next := data(world)
	next.stage = to_stage
	world[KEY] = next
	return true

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	if not value.get("stage") is String or value.stage not in STAGES: return false
	return value.size() == 2

## Contrato com a carteira e com o livro antigo do deserto: o envelope existe se e só se a missão
## terminou, com o valor gravado; missão concluída implica met_vicente, e met_vicente sem a missão
## só vale para save anterior a ela (sem a chave).
static func validate_wallet(world: Dictionary, wallet: Dictionary) -> bool:
	var receipt: Dictionary = preload("res://systems/economy/RecurringReceipts.gd").lookup(wallet, "reward", ENVELOPE_RECEIPT)
	if not receipt.is_empty() and int(receipt.get("amount", -1)) != ENVELOPE_AMOUNT: return false
	var met: bool = bool(world.get("desert_story", {}).get("met_vicente", false)) if world.get("desert_story") is Dictionary else false
	if not world.has(KEY): return receipt.is_empty() and validate_track(world) and validate_chain(world, wallet)
	if not valid(world[KEY]): return false
	var done: bool = world[KEY].stage == "done"
	if done != not receipt.is_empty(): return false
	if done and not met: return false
	if met and not done: return false
	if world[KEY].stage != "" and not bool(world.get("desert_story", {}).get("arrived", false)): return false
	return validate_track(world) and validate_chain(world, wallet)

# --- A2-02 "Respeita a pista" -----------------------------------------------------------------------

## Etapa efetiva: "" também quer dizer "A2-01 ainda não acabou" (quem chama confere complete()).
static func track_stage(world: Dictionary) -> String:
	if not complete(world): return ""
	var raced := DIGO.workshop_unlocked(world)
	if not world.has(TRACK_KEY):
		if raced: return "done" if not world.has(KEY) else "grandstand"
		return ""
	var stored := str(world[TRACK_KEY].get("stage", "")) if world[TRACK_KEY] is Dictionary else ""
	if stored in ["", "race"] and raced: return "grandstand"
	return stored

static func track_complete(world: Dictionary) -> bool:
	return track_stage(world) == "done"

static func track_advance(world: Dictionary, to_stage: String) -> bool:
	var current := track_stage(world)
	var ok := false
	match to_stage:
		"race": ok = complete(world) and current == ""
		"done": ok = current == "grandstand"
	if not ok: return false
	world[TRACK_KEY] = {"version": 1, "stage": to_stage}
	return true

static func validate_track(world: Dictionary) -> bool:
	if not world.has(TRACK_KEY): return true
	var value: Variant = world[TRACK_KEY]
	if not value is Dictionary or value.get("version") != 1 or value.size() != 2: return false
	if not value.get("stage") is String or value.stage not in TRACK_STAGES: return false
	if value.stage != "" and not complete(world): return false
	if value.stage in ["grandstand", "done"] and not DIGO.workshop_unlocked(world): return false
	return true

# --- A2-03 a A2-13: missões em cadeia -----------------------------------------------------------------
# Cada uma tem a própria chave de etapas, começa quando a anterior acaba (ORDER) e, na conclusão, paga
# (se houver recibo) e marca a flag antiga do esqueleto de DesertStoryState que ela substitui, tudo de
# uma vez (chain_finish). Save sem a chave e com a flag já marcada passou por ali pelo esqueleto: conta
# como feita, sem a recompensa nova; save com o ato antigo terminado (delivered) conta todas como feitas.
# "next" lista as etapas permitidas a partir de cada uma quando não é só a seguinte da lista.
## Valores gravados em recibo: NUNCA mudar (o save valida contra eles).
const CHAIN := {
	"cargo": {"key": "vicente_act2_cargo", "stages": ["", "crate", "weigh", "raul", "done"], "flag": "cargo_found",
		"receipt": "desert_act2_cargo_freight", "amount": 900},
	"order": {"key": "vicente_act2_order", "stages": ["", "night", "call", "done"], "flag": "bank_proof",
		"receipt": "", "amount": 0},
	# A2-05: conversa no encontro, a prova contra Vicente (resultado físico) e a conversa depois.
	"brothers": {"key": "vicente_act2_brothers", "stages": ["", "race", "won", "lost", "done"], "flag": "",
		"receipt": "", "amount": 0, "next": {"": ["race"], "race": ["won", "lost"], "won": ["done"], "lost": ["done"]}},
	# A2-06: Vicente espera na caverna do Coyote; uma conversa só.
	"cave": {"key": "vicente_act2_cave", "stages": ["", "done"], "flag": "", "receipt": "", "amount": 0},
	# A2-07: Dona Fátima na capela, torre de rádio, cooperativa de Santa Lua.
	# Roteiro de diretor (21/10): "water" é a caixa-d'água de Santa Lua com a Helena, antes da conclusão.
	"letters": {"key": "vicente_act2_letters", "stages": ["", "tower", "coop", "water", "done"], "flag": "",
		"receipt": "desert_act2_coop_radio", "amount": 1200},
	# A2-08: a prova da Jessica (a que já existe) é pré-requisito; depois Jessica, Cascavel, a aposta e a chave.
	"bet": {"key": "vicente_act2_bet", "stages": ["", "cascavel", "race", "keys", "done"], "flag": "",
		"receipt": "", "amount": 0},
	# A2-09: carro do Nonato (opcional) e o armazém no porta-malas pela Bia e pelo Digo.
	"trunk": {"key": "vicente_act2_trunk", "stages": ["", "car", "done"], "flag": "", "receipt": "", "amount": 0,
		"next": {"": ["car", "done"], "car": ["done"]}},
	# A2-10: o assalto do comboio (DesertHeist) e a conversa no Motel Oásis.
	"convoy": {"key": "vicente_act2_convoy", "stages": ["", "motel", "done"], "flag": "",
		"receipt": "desert_act2_convoy", "amount": 1500},
	# A2-11: Seu Bento nas Salinas e o caderno no acampamento da serra.
	# Roteiro de diretor: "home" é a casa da Helena revirada em Santa Lua, depois do caderno.
	"salt": {"key": "vicente_act2_salt", "stages": ["", "camp", "home", "done"], "flag": "",
		"receipt": "desert_act2_salt_ledger", "amount": 2200},
	# A2-12: Teodoro no Motel Oásis e a pasta largada na obra da passagem norte.
	# Roteiro de diretor: "fight" é a briga dos irmãos no estacionamento do motel, antes da fuga.
	"teodoro": {"key": "vicente_act2_teodoro", "stages": ["", "fight", "chase", "done"], "flag": "", "receipt": "", "amount": 0},
	# A2-13: Arquibancada, o ataque dos Cobras ao encontro e Vicente na passagem norte (abre o ato 3).
	"finale": {"key": "vicente_act2_finale", "stages": ["", "defend", "gate", "done"], "flag": "delivered",
		"receipt": "desert_act2_finale", "amount": 5000},
}
const ORDER := ["cargo", "order", "brothers", "cave", "letters", "bet", "trunk", "convoy", "salt", "teodoro", "finale"]
## A Monaliza perdida na aposta (A2-08) e o carro que ganhou o armazém (A2-09). O ato 3 limpa "lost".
const MONALIZA_KEY := "monaliza_act2"
## Carro velho do Nonato (A2-09): frota do deserto, recibo de valor zero como prova de que foi dado.
const NONATO_CAR_ID := "act2_nonato_bison"
const NONATO_CAR_ARCHETYPE := "desert_bison"
const NONATO_CAR_RECEIPT := "desert_act2_nonato_car"

## A missão anterior de cada uma da cadeia.
static func chain_ready(world: Dictionary, id: String) -> bool:
	var at := ORDER.find(id)
	if at < 0: return false
	if at == 0: return track_complete(world)
	return chain_complete(world, ORDER[at - 1])

static func chain_stage(world: Dictionary, id: String) -> String:
	var spec: Dictionary = CHAIN[id]
	if not world.has(spec.key):
		if not str(spec.flag).is_empty() and bool(STORY.data(world).get(spec.flag, false)): return "done"
		return "done" if bool(STORY.data(world).delivered) else ""
	var value: Variant = world[spec.key]
	return str(value.get("stage", "")) if value is Dictionary else ""

static func chain_complete(world: Dictionary, id: String) -> bool:
	return chain_stage(world, id) == "done"

static func _allowed(spec: Dictionary, from: String) -> Array:
	if spec.has("next"): return spec.next.get(from, [])
	var stages: Array = spec.stages
	var at := stages.find(from)
	return [stages[at + 1]] if at >= 0 and at + 1 < stages.size() else []

## Etapa seguinte permitida, só com a missão anterior concluída. "done" quem chama faz junto com a
## recompensa e a flag antiga (chain_finish).
static func chain_advance(world: Dictionary, id: String, to_stage: String) -> bool:
	var spec: Dictionary = CHAIN[id]
	if to_stage == "done" or not chain_ready(world, id): return false
	if to_stage not in _allowed(spec, chain_stage(world, id)): return false
	if id == "bet" and not bool(STORY.data(world).jessica_met): return false
	world[spec.key] = {"version": 1, "stage": to_stage}
	return true

## Conclusão: recompensa (se houver), etapa "done", flag antiga e marcas da Monaliza, tudo ou nada.
static func chain_finish(world: Dictionary, economy, id: String, extra := {}) -> Dictionary:
	var spec: Dictionary = CHAIN[id]
	if "done" not in _allowed(spec, chain_stage(world, id)) or not chain_ready(world, id): return {"ok": false, "reason": "stage"}
	if id == "trunk" and str(extra.get("trunk_car", "")).is_empty(): return {"ok": false, "reason": "stage"}
	if int(spec.amount) > 0:
		var paid: Dictionary = economy.grant_world_reward({"id": str(spec.receipt), "kind": "cash", "amount": int(spec.amount), "label": str(extra.get("label", ""))})
		if not paid.ok: return {"ok": false, "reason": str(paid.get("reason", "wallet_full"))}
	world[spec.key] = {"version": 1, "stage": "done"}
	if not str(spec.flag).is_empty(): STORY.mark(world, str(spec.flag))
	if id in ["bet", "trunk"]:
		var record := monaliza(world)
		if id == "bet": record.lost = true
		else: record.trunk_car = str(extra.trunk_car)
		world[MONALIZA_KEY] = record
	return {"ok": true}

static func monaliza(world: Dictionary) -> Dictionary:
	var value: Variant = world.get(MONALIZA_KEY, {})
	if value is Dictionary and value.get("version") == 1: return value.duplicate(true)
	return {"version": 1, "lost": false, "trunk_car": ""}

static func monaliza_lost(world: Dictionary) -> bool:
	return bool(monaliza(world).lost)

static func trunk_car(world: Dictionary) -> String:
	return str(monaliza(world).trunk_car)

static func validate_chain(world: Dictionary, wallet: Dictionary) -> bool:
	for id in ORDER:
		var spec: Dictionary = CHAIN[id]
		var receipt: Dictionary = {} if str(spec.receipt).is_empty() else RECEIPTS.lookup(wallet, "reward", str(spec.receipt))
		if not receipt.is_empty() and int(receipt.get("amount", -1)) != int(spec.amount): return false
		if not world.has(spec.key):
			if not receipt.is_empty(): return false
			continue
		var value: Variant = world[spec.key]
		if not value is Dictionary or value.get("version") != 1 or value.size() != 2: return false
		if not value.get("stage") is String or value.stage not in spec.stages: return false
		var done: bool = value.stage == "done"
		if not str(spec.flag).is_empty() and done != bool(STORY.data(world).get(spec.flag, false)): return false
		if int(spec.amount) > 0 and done == receipt.is_empty(): return false
		if value.stage != "" and not chain_ready(world, id): return false
		if id == "bet" and value.stage != "" and not bool(STORY.data(world).jessica_met): return false
	# Monaliza: perdida se e só se a aposta terminou pela missão; armazém em outro carro se e só se A2-09
	# terminou, num carro da frota do deserto. Carro do Nonato só com o recibo dele (e A2-09 começada).
	var fleet: Variant = world.get("desert_fleet", {})
	if not fleet is Dictionary: return false
	var nonato: bool = not RECEIPTS.lookup(wallet, "reward", NONATO_CAR_RECEIPT).is_empty()
	if fleet.has(NONATO_CAR_ID) and not nonato: return false
	if nonato and chain_stage(world, "trunk") == "": return false
	var bet_done: bool = world.has(CHAIN.bet.key) and chain_stage(world, "bet") == "done"
	var trunk_done: bool = world.has(CHAIN.trunk.key) and chain_stage(world, "trunk") == "done"
	if not world.has(MONALIZA_KEY): return not bet_done and not trunk_done
	var m: Variant = world[MONALIZA_KEY]
	if not m is Dictionary or m.get("version") != 1 or not m.get("lost") is bool or not m.get("trunk_car") is String or m.size() != 3: return false
	if m.lost != bet_done: return false
	if trunk_done == str(m.trunk_car).is_empty(): return false
	if trunk_done and not fleet.has(m.trunk_car): return false
	return true
