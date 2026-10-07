extends RefCounted
const KEY := "desert_wash"
const RECEIPT := "desert_wash:first"
const REWARD := 1800
const COURSE := preload("res://activities/desert_wash/DesertWashCourse.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")

static func data(world: Dictionary) -> Dictionary:
	var value: Variant=world.get(KEY,{"version":1,"finishes":0,"best":0.0,"won":false})
	return value.duplicate(true) if value is Dictionary else {}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1 or not value.get("won") is bool: return false
	for key in ["finishes","best"]:
		if typeof(value.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[key])): return false
	if value.finishes<0 or value.finishes>1000000 or float(value.finishes)!=floorf(float(value.finishes)): return false
	if value.finishes==0: return value.best==0 and not value.won
	return value.best>0 and value.best<=COURSE.TIME_LIMIT and value.won==(value.best<=COURSE.PRIZE_TIME)

static func validate_world(world: Dictionary, wallet: Dictionary) -> bool:
	var saved:=data(world)
	if not valid(saved): return false
	var receipt: Dictionary=RECEIPTS.lookup(wallet,"reward",RECEIPT)
	return receipt.is_empty() or (saved.won and receipt.get("amount") == REWARD)

static func record(world: Dictionary, seconds: float) -> bool:
	var saved:=data(world)
	if not valid(saved) or not is_finite(seconds) or seconds<=0 or seconds>COURSE.TIME_LIMIT or saved.finishes>=1000000: return false
	saved.best=seconds if saved.finishes==0 else minf(saved.best,seconds)
	saved.finishes+=1
	saved.won=saved.best<=COURSE.PRIZE_TIME
	world[KEY]=saved
	return true

static func claim(world: Dictionary, economy) -> bool:
	var saved:=data(world)
	if not validate_world(world,economy.snapshot()) or not saved.won: return false
	if not RECEIPTS.lookup(economy.snapshot(),"reward",RECEIPT).is_empty(): return false
	return economy.grant_reward(RECEIPT,REWARD)
