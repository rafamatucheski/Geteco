extends RefCounted
## Only completed, physically timed races enter this ledger. Attempts are transient.
const KEY := "desert_drag"
const RIVALS := ["digo", "livia", "raul", "jessica", "nadir", "rauhz"]
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")

static func defaults() -> Dictionary:
	return {"version":1,"finishes":0,"wins":[],"completed_rivals":[],"best":{},"last_rival":"","last_won":false}

static func data(world: Dictionary) -> Dictionary:
	var value: Variant = world.get(KEY, defaults())
	return value.duplicate(true) if value is Dictionary else {}

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["version", "finishes"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT]: return false
		if not is_finite(float(value[key])) or float(value[key]) != floorf(float(value[key])): return false
	if value.version != 1 or value.finishes < 0 or value.finishes > 1000000: return false
	if not value.get("wins") is Array or not value.get("best") is Dictionary or not value.get("completed_rivals") is Array: return false
	if not value.get("last_rival") is String or not value.get("last_won") is bool: return false
	if value.wins.size() > RIVALS.size() or value.best.size() > RIVALS.size(): return false
	if value.completed_rivals.size() != value.best.size(): return false
	var completed: Array = []
	for rival in value.completed_rivals:
		if rival not in RIVALS or rival in completed or not value.best.has(rival): return false
		completed.append(rival)
	var seen: Array = []
	for rival in value.wins:
		if not rival is String or rival not in RIVALS or rival in seen or not value.best.has(rival): return false
		seen.append(rival)
	for rival in value.best:
		if rival not in RIVALS or typeof(value.best[rival]) not in [TYPE_INT, TYPE_FLOAT]: return false
		if not is_finite(float(value.best[rival])) or value.best[rival] <= 0 or value.best[rival] > 65: return false
		var index := RIVALS.find(rival)
		for previous in range(index):
			if RIVALS[previous] not in seen: return false
	if value.finishes < value.best.size() or value.finishes < value.wins.size(): return false
	if value.finishes == 0:
		return value.best.is_empty() and value.wins.is_empty() and value.last_rival.is_empty() and not value.last_won
	return value.last_rival in RIVALS and value.best.has(value.last_rival) and (not value.last_won or value.last_rival in value.wins)

static func current_rival(world: Dictionary) -> String:
	var saved := data(world)
	if not validate_snapshot(saved): return ""
	for rival in RIVALS:
		if rival not in saved.wins: return rival
	return RIVALS.back()

static func can_race(world: Dictionary, rival: String) -> bool:
	var saved := data(world)
	if not validate_snapshot(saved) or rival not in RIVALS: return false
	return rival == current_rival(world) or rival in saved.wins

static func reward_amount(rival: String) -> int:
	var index := RIVALS.find(rival)
	return 3000+(index+1)*1000 if index>=0 else 0

static func validate_wallet(value: Variant, wallet: Dictionary) -> bool:
	if not validate_snapshot(value): return false
	for key in wallet.get("transactions",{}):
		if str(key).begins_with("reward:desert_drag:") and str(key).trim_prefix("reward:desert_drag:") not in RIVALS: return false
	for rival in RIVALS:
		var receipt: Dictionary = RECEIPTS.lookup(wallet,"reward","desert_drag:"+rival)
		# A win with no receipt is a durable pending prize. A receipt without its
		# physical win, or with an altered amount, is corrupt provenance.
		if receipt.is_empty(): continue
		var amount: Variant = receipt.get("amount",-1)
		if typeof(amount) not in [TYPE_INT,TYPE_FLOAT]: return false
		if rival not in value.wins or float(amount)!=float(reward_amount(rival)): return false
	return true

static func pending_rewards(world: Dictionary, wallet: Dictionary) -> Array[String]:
	var pending: Array[String] = []
	var saved := data(world)
	if not validate_wallet(saved,wallet): return pending
	for rival in saved.wins:
		if RECEIPTS.lookup(wallet,"reward","desert_drag:"+str(rival)).is_empty(): pending.append(str(rival))
	return pending

static func claim_rewards(world: Dictionary, economy) -> int:
	var pending := pending_rewards(world,economy.snapshot())
	var total := 0
	for rival in pending:
		var amount := reward_amount(rival)
		if economy.grant_reward("desert_drag:"+rival,amount): total += amount
	return total

static func record_finish(world: Dictionary, rival: String, won: bool, seconds: float) -> Dictionary:
	var saved := data(world)
	if not can_race(world,rival): return {}
	if not is_finite(seconds) or seconds <= 0 or seconds > 65 or saved.finishes >= 1000000: return {}
	var first_win: bool = won and rival not in saved.wins
	saved.finishes += 1
	saved.last_rival = rival
	saved.last_won = won
	saved.best[rival] = minf(seconds, float(saved.best.get(rival, INF)))
	if rival not in saved.completed_rivals: saved.completed_rivals.append(rival)
	if first_win: saved.wins.append(rival)
	world[KEY] = saved
	return {"rival_id":rival,"tier":RIVALS.find(rival)+1,"won":won,"first_win":first_win,"seconds":seconds,"finished":true}

static func crossing_time(before: float, after: float, finish: float, elapsed_before: float, delta: float) -> float:
	if after <= before or before >= finish or after < finish: return INF
	return elapsed_before + delta * clampf((finish-before)/(after-before), 0.0, 1.0)
