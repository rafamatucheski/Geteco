extends RefCounted
const RULES := preload("res://activities/fishing/FishingRules.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const KEY := "fishing"
const ENTRY_FEE := 10
const MAX_VISITS := 4000

static func fresh() -> Dictionary:
	return {"version":1, "serial":0, "catches":0, "best":0, "species":{}, "rewards":{}, "last":{}}

static func data(world: Dictionary) -> Dictionary:
	var value: Variant = world.get(KEY, fresh())
	return value.duplicate(true) if value is Dictionary else {}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	if not _integer(value.get("serial"), 0, MAX_VISITS) or not _integer(value.get("catches"), 0, 1000000): return false
	if not _integer(value.get("best"), 0, 14000) or not value.get("species") is Dictionary or not value.get("rewards") is Dictionary or not value.get("last") is Dictionary: return false
	var best := 0
	for id in value.species:
		if not id is String or not RULES.valid_catch({"id":id, "grams":value.species[id]}): return false
		best = maxi(best, int(value.species[id]))
	if best != int(value.best) or value.species.size() > int(value.catches): return false
	if (value.catches == 0) != value.species.is_empty(): return false
	for receipt in value.rewards:
		if not receipt is String or not receipt.is_valid_int() or str(receipt.to_int()) != receipt: return false
		if not _integer(receipt.to_int(), 1, int(value.serial)) or not _integer(value.rewards[receipt], 0, 2): return false
	if value.serial == 0: return value.last.is_empty() and value.catches == 0 and value.rewards.is_empty()
	if value.rewards.size() > int(value.catches): return false
	if value.last.is_empty(): return false
	var last: Dictionary = value.last
	if not _integer(last.get("serial"), int(value.serial), int(value.serial)) or not _integer(last.get("tier"), -1, 2): return false
	if last.get("status") not in ["active", "cancelled", "complete"] or not last.get("won") is bool: return false
	if not _integer(last.get("best"), 0, int(value.best)): return false
	if last.won and (last.tier < 0 or last.status != "complete" or last.best <= 0): return false
	return value.rewards.has(str(int(last.serial))) == bool(last.won)

static func validate_world(world: Dictionary, wallet: Dictionary) -> bool:
	var saved := data(world)
	if not valid(saved): return false
	var transactions: Variant = wallet.get("transactions", {})
	if not transactions is Dictionary: return false
	for key in transactions:
		if str(key).begins_with("spend:fishing:") or str(key).begins_with("reward:fishing:"):
			if not transactions[key] is Dictionary: return false
	for serial in range(1, int(saved.serial) + 1):
		var entry: Dictionary = RECEIPTS.lookup(wallet, "spend", "fishing:entry:%d" % serial)
		if entry.get("amount", -1) != ENTRY_FEE: return false
	for serial in saved.rewards:
		var prize: Dictionary = RECEIPTS.lookup(wallet, "reward", "fishing:prize:" + str(serial))
		if not prize.is_empty() and prize.get("amount", -1) != int(RULES.TIERS[int(saved.rewards[serial])].prize): return false
	for key in transactions:
		if str(key).begins_with("spend:fishing:entry:"):
			var serial := str(key).trim_prefix("spend:fishing:entry:")
			if not serial.is_valid_int() or serial.to_int() < 1 or serial.to_int() > saved.serial: return false
		elif str(key).begins_with("reward:fishing:prize:"):
			var serial := str(key).trim_prefix("reward:fishing:prize:")
			if not saved.rewards.has(serial): return false
	return true

static func begin(world: Dictionary, economy, tier: int) -> int:
	var saved := data(world)
	if tier < -1 or tier > 2 or not validate_world(world, economy.snapshot()) or saved.serial >= MAX_VISITS: return 0
	if not saved.last.is_empty() and saved.last.status == "active": return 0
	var serial := int(saved.serial) + 1
	if not economy.spend(ENTRY_FEE, "fishing:entry:%d" % serial): return 0
	saved.serial = serial
	saved.last = {"serial":serial, "tier":tier, "status":"active", "won":false, "best":0}
	world[KEY] = saved
	return serial

static func record_catch(world: Dictionary, serial: int, fish: Dictionary) -> bool:
	var saved := data(world)
	if not valid(saved) or not RULES.valid_catch(fish) or saved.serial != serial or saved.last.is_empty() or saved.last.status != "active" or saved.catches >= 1000000: return false
	saved.catches += 1
	saved.species[fish.id] = maxi(int(saved.species.get(fish.id, 0)), int(fish.grams))
	saved.best = maxi(int(saved.best), int(fish.grams))
	saved.last.best = maxi(int(saved.last.best), int(fish.grams))
	world[KEY] = saved
	return true

static func finish(world: Dictionary, serial: int, completed: bool, rivals: Array = []) -> bool:
	var saved := data(world)
	if not valid(saved) or saved.serial != serial or saved.last.is_empty() or saved.last.status != "active": return false
	saved.last.status = "complete" if completed else "cancelled"
	saved.last.won = completed and saved.last.tier >= 0 and RULES.winner(int(saved.last.best), rivals)
	if saved.last.won: saved.rewards[str(serial)] = int(saved.last.tier)
	world[KEY] = saved
	return true

static func claim(world: Dictionary, economy) -> int:
	if not validate_world(world, economy.snapshot()): return 0
	var paid := 0
	var saved := data(world)
	for serial in saved.rewards:
		var prize := int(RULES.TIERS[int(saved.rewards[serial])].prize)
		if economy.grant_reward("fishing:prize:" + str(serial), prize): paid += prize
	return paid
