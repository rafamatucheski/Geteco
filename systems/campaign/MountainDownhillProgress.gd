extends RefCounted
## Livro persistente de resultados; tentativas são só da sessão e bloqueiam o save.
const VERSION := 1
const FIRST_WIN_REWARD := 2400
const RECEIPT := "mountain_downhill_first_win"
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")

static func defaults() -> Dictionary:
	return {"version":VERSION,"finishes":0,"wins":0,"best_seconds":0.0,"last_place":0,"reward_paid":false}

static func data(world: Dictionary) -> Dictionary:
	return world.get("mountain_downhill",defaults()).duplicate(true)

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["version","finishes","wins","last_place"]:
		if typeof(value.get(key)) not in [TYPE_INT,TYPE_FLOAT]: return false
		if not is_finite(float(value[key])) or float(value[key]) != floorf(float(value[key])): return false
	if value.version != VERSION or value.finishes < 0 or value.finishes > 1000000 or value.wins < 0 or value.wins > value.finishes: return false
	if value.last_place < 0 or value.last_place > 7 or (value.finishes == 0) != (value.last_place == 0): return false
	if typeof(value.get("best_seconds")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.best_seconds)): return false
	if value.best_seconds < 0.0 or value.best_seconds > 240.0 or (value.finishes == 0) != (value.best_seconds == 0): return false
	if not value.get("reward_paid") is bool or (value.reward_paid and value.wins == 0): return false
	return true

static func validate_wallet(value: Variant, wallet: Dictionary) -> bool:
	if not validate_snapshot(value): return false
	var receipt: Dictionary = RECEIPTS.lookup(wallet,"reward",RECEIPT)
	if bool(value.reward_paid) != (not receipt.is_empty()): return false
	return receipt.is_empty() or int(receipt.get("amount",-1)) == FIRST_WIN_REWARD

static func record_finish(world: Dictionary, place: int, seconds: float) -> bool:
	var current := data(world)
	if not validate_snapshot(current) or place < 1 or place > 7 or not is_finite(seconds) or seconds <= 0 or seconds > 240: return false
	if current.finishes >= 1000000: return false
	current.finishes += 1
	current.last_place = place
	if place == 1: current.wins += 1
	if current.best_seconds == 0 or seconds < float(current.best_seconds): current.best_seconds = seconds
	world.mountain_downhill = current
	return true

static func claim_reward(world: Dictionary, economy) -> bool:
	var current := data(world)
	if not validate_snapshot(current) or current.wins == 0 or current.reward_paid: return false
	if economy.has_reward_receipt(RECEIPT): return false
	if not economy.grant_reward(RECEIPT,FIRST_WIN_REWARD): return false
	current.reward_paid = true
	world.mountain_downhill = current
	return true
