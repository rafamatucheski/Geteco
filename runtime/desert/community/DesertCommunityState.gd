extends RefCounted
## Optional sequel to O último ramal. Completion and its receipt commit together.
const KEY := "desert_community"
const TITLE := "Água para Santa Lua"
const LAST := 5
const REWARD := 1800
const REWARD_ID := "desert_community_water"
const CONTRACTS := preload("res://runtime/desert/DesertContractState.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")

static func defaults() -> Dictionary:
	return {"version":1,"step":0,"active":false}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1: return false
	var step: Variant=value.get("step")
	if not (step is int or step is float): return false
	if not is_finite(float(step)) or step!=int(step) or step<0 or step>LAST: return false
	if not value.get("active") is bool: return false
	return not value.active or (step>0 and step<LAST)

static func data(world: Dictionary) -> Dictionary:
	return world.get(KEY,defaults()).duplicate(true)

static func unlocked(world: Dictionary) -> bool:
	var contracts:=CONTRACTS.data(world)
	return CONTRACTS.valid(contracts) and int(contracts.rail)==4

static func validate_wallet(world: Dictionary, wallet: Dictionary) -> bool:
	if world.has(KEY) and not valid(world[KEY]): return false
	var state:=data(world)
	if state.step>0 and not unlocked(world): return false
	var receipt:=RECEIPTS.lookup(wallet,"reward",REWARD_ID)
	if (int(state.step)==LAST)!=not receipt.is_empty(): return false
	return receipt.is_empty() or (receipt.get("kind")=="reward" and receipt.get("item")==REWARD_ID and receipt.get("amount")==REWARD)

static func advance(world: Dictionary, wallet: RefCounted, expected: int) -> Dictionary:
	var state:=data(world)
	if not valid(state) or not unlocked(world) or state.step!=expected or expected>=LAST: return {"ok":false}
	var next:=expected+1
	if next==LAST:
		var paid: Dictionary=wallet.grant_world_reward({"id":REWARD_ID,"kind":"cash","amount":REWARD})
		if not paid.get("ok",false): return paid
	state.step=next
	state.active=next<LAST
	world[KEY]=state
	return {"ok":true,"finished":next==LAST,"amount":REWARD if next==LAST else 0}

static func track(world: Dictionary, active: bool) -> void:
	var state:=data(world)
	if not valid(state): return
	state.active=active and state.step>0 and state.step<LAST
	world[KEY]=state
