extends RefCounted
## Optional jobs never change campaign flags. Payment and completion commit together.
const KEY := "desert_contracts"
const LAST := {"parts":3,"rail":4}
const REWARDS := {"parts":1200,"rail":2200}
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")

static func defaults() -> Dictionary:
	return {"version":1,"active":"","parts":0,"rail":0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1: return false
	for id in LAST:
		var step: Variant=value.get(id)
		if not (step is int or step is float): return false
		if not is_finite(float(step)) or step!=int(step) or step<0 or step>LAST[id]: return false
	var active: Variant=value.get("active")
	if not active is String: return false
	return active.is_empty() or (LAST.has(active) and value[active]>0 and value[active]<LAST[active])

static func data(world: Dictionary) -> Dictionary:
	var value: Variant=world.get(KEY,defaults())
	# A present malformed prerequisite is invalid, not a new/absent contract.
	return value.duplicate(true) if value is Dictionary else {}

static func validate_wallet(world: Dictionary, wallet: Dictionary) -> bool:
	if world.has(KEY) and not valid(world[KEY]): return false
	var state:=data(world)
	for id in LAST:
		var receipt:=RECEIPTS.lookup(wallet,"reward","desert_contract_"+id)
		if (int(state[id])==int(LAST[id]))!=not receipt.is_empty(): return false
		if not receipt.is_empty() and (receipt.get("kind")!="reward" or receipt.get("item")!="desert_contract_"+id or receipt.get("amount")!=REWARDS[id]): return false
	return true

static func advance(world: Dictionary, wallet: RefCounted, id: String, expected: int) -> Dictionary:
	if not LAST.has(id) or not valid(data(world)): return {"ok":false}
	var state:=data(world)
	if int(state[id])!=expected or expected>=int(LAST[id]): return {"ok":false}
	var next:=expected+1
	if next==int(LAST[id]):
		var result: Dictionary=wallet.grant_world_reward({"id":"desert_contract_"+id,"kind":"cash","amount":REWARDS[id]})
		if not result.get("ok",false): return result
	state[id]=next
	state.active=id if next<int(LAST[id]) else ("" if state.active==id else state.active)
	world[KEY]=state
	return {"ok":true,"finished":next==int(LAST[id]),"amount":REWARDS[id] if next==int(LAST[id]) else 0}

static func track(world: Dictionary, id: String) -> void:
	var state:=data(world)
	if not valid(state): return
	if id.is_empty() or (LAST.has(id) and state[id]>0 and state[id]<LAST[id]):
		state.active=id
		world[KEY]=state
