extends RefCounted
## Contrato salvo da M06-C "Turno da noite" (chave própria do world_state).
## Etapas: "" (Neco ainda não ligou) → "offered" (ligação feita, a invasão espera a noite)
## → "escaping" (a página do livro está no bolso; falta sair e ligar para o Maciota) → "done".
## A invasão em si não é etapa salva: salvar fica bloqueado enquanto a segurança está montada.
const KEY := "vertice_night"
const STAGES := ["", "offered", "escaping", "done"]
const ROUTES := ["", "stealth", "loud"]
## Recibo único do cofre do escritório (só no caminho escondido). Valor gravado em recibo
## nunca muda: o save valida contra ele.
const SAFE_RECEIPT := "vertice_night_office_safe"
const SAFE_CASH := 6500
## Dias de fita da polícia depois do caminho no tiro.
const CLOSED_DAYS := 3

static func defaults() -> Dictionary:
	return {"version":1, "stage":"", "route":"", "safe":false, "closed_until":0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5 or value.get("version") != 1: return false
	if not value.get("stage") is String or value.stage not in STAGES: return false
	if not value.get("route") is String or value.route not in ROUTES: return false
	if not value.get("safe") is bool: return false
	var closed: Variant = value.get("closed_until")
	if typeof(closed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(closed)) or float(closed) != floorf(float(closed)): return false
	if int(closed) < 0 or int(closed) > 1000000: return false
	# Rota só existe depois do livro; o cofre só sai depois do livro; fita só no tiro.
	var after_book: bool = value.stage in ["escaping", "done"]
	if after_book != (value.route != ""): return false
	if value.safe and not after_book: return false
	if int(closed) > 0 and value.route != "loud": return false
	return true

## Save inteiro: estado válido, missão só depois de Cortar o abastecimento e cofre casado
## com o recibo da carteira (nem recibo sem cofre, nem cofre sem recibo).
static func valid_world(world: Dictionary, wallet: Dictionary, campaign_completed: Array) -> bool:
	if not world.has(KEY):
		return preload("res://systems/economy/RecurringReceipts.gd").lookup(wallet, "reward", SAFE_RECEIPT).is_empty()
	var value: Variant = world[KEY]
	if not valid(value): return false
	if value.stage != "" and not campaign_completed.has("cobra_supply"): return false
	var receipt: Dictionary = preload("res://systems/economy/RecurringReceipts.gd").lookup(wallet, "reward", SAFE_RECEIPT)
	if receipt.is_empty(): return not value.safe
	return value.safe and receipt.get("kind") == "reward" and receipt.get("item") == SAFE_RECEIPT and int(receipt.get("amount", -1)) == SAFE_CASH

static func closed_by_police(world: Dictionary, moon_day: int) -> bool:
	var value: Variant = world.get(KEY)
	return value is Dictionary and int(value.get("closed_until", 0)) > moon_day
