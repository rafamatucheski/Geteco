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
	if not world.has(KEY): return receipt.is_empty() and validate_track(world)
	if not valid(world[KEY]): return false
	var done: bool = world[KEY].stage == "done"
	if done != not receipt.is_empty(): return false
	if done and not met: return false
	if met and not done: return false
	if world[KEY].stage != "" and not bool(world.get("desert_story", {}).get("arrived", false)): return false
	return validate_track(world)

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
