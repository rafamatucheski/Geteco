extends RefCounted
## Persistent results and the single supplied jeep; active attempts never enter saves.
const COURSE := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const FLEET := preload("res://runtime/FleetState.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const PRIZE := 700
const RECEIPT := "mountain_jeep_first_finish_v1"
const DEFAULT := {"version":1,"best":0.0,"finishes":0,"rewarded":false,"vehicle":{}}
var data := DEFAULT.duplicate(true)

func snapshot() -> Dictionary:
	return data.duplicate(true)

func vehicle_for_restore(selected: Dictionary) -> Dictionary:
	# tree_exiting can be newer than the last saved player-car selection.
	# A live production-restored body is adopted before this method is needed.
	if not data.vehicle.is_empty(): return data.vehicle.duplicate(true)
	if selected.get("vehicle_id","")==COURSE.LOAN_ID and selected.get("archetype","")==COURSE.VEHICLE and FLEET.validate(selected):
		return selected.duplicate(true)
	return {}

func restore_snapshot(value: Variant) -> bool:
	if not validate_snapshot(value): return false
	data=value.duplicate(true)
	return true

func settle(run: RefCounted, economy: RefCounted) -> Dictionary:
	if not run.finished or run.active or run.settled or not _number(run.elapsed,.01,COURSE.TIME_LIMIT): return {}
	if run.gate!=COURSE.checkpoints().size() or run.gates.size()!=run.gate: return {}
	if not validate_snapshot(data) or not validate_wallet(data,economy.snapshot()): return {}
	var paid := 0
	if not data.rewarded:
		if not economy.grant_reward(RECEIPT,PRIZE): return {}
		data.rewarded=true
		paid=PRIZE
	var record: bool = float(data.best)==0.0 or run.elapsed<float(data.best)
	if record: data.best=run.elapsed
	data.finishes=mini(10000000,int(data.finishes)+1)
	run.settled=true
	return {"time":run.elapsed,"record":record,"paid":paid}

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _whole(value.get("version"),1,1) or not _whole(value.get("finishes"),0,10000000): return false
	if not _number(value.get("best"),0.0,COURSE.TIME_LIMIT) or not value.get("rewarded") is bool: return false
	if (int(value.finishes)>0) != bool(value.rewarded): return false
	if (float(value.best)>0.0) != (int(value.finishes)>0): return false
	if not value.get("vehicle") is Dictionary: return false
	var vehicle: Dictionary=value.vehicle
	if vehicle.is_empty(): return true
	return vehicle.get("vehicle_id") == COURSE.LOAN_ID and vehicle.get("archetype") == COURSE.VEHICLE and FLEET.validate(vehicle)

static func validate_wallet(value: Variant, wallet: Variant) -> bool:
	if not validate_snapshot(value) or not wallet is Dictionary: return false
	if not wallet.get("transactions",{}) is Dictionary: return false
	var raw_receipt: Variant=wallet.get("transactions",{}).get("reward:"+RECEIPT,{})
	if not raw_receipt is Dictionary: return false
	var receipt := RECEIPTS.lookup(wallet,"reward",RECEIPT)
	if not value.rewarded: return receipt.is_empty()
	return receipt.get("kind")=="reward" and receipt.get("item")==RECEIPT and _whole(receipt.get("amount"),PRIZE,PRIZE)

static func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and float(value)==floorf(float(value))
