extends RefCounted
## Delivery and its one-time receipt commit together; no campaign flag changes.
const KEY := "mining_yard_job"
const RECEIPT := "serra_bruta_clearance"
const REWARD := 1800
const COUNT := 3
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const DELIVERY_MIN := Vector2(LAYOUT.CENTER.x-16.25,LAYOUT.CENTER.z+6.25)
const DELIVERY_MAX := Vector2(LAYOUT.CENTER.x-9.75,LAYOUT.CENTER.z+10.75)

static func defaults() -> Dictionary:
	return {"version":1,"status":"idle","delivered":{}}

static func data(world: Dictionary) -> Dictionary:
	return world.get(KEY,defaults()).duplicate(true)

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1 or value.get("status","") not in ["idle","active","paused","complete"]: return false
	var deliveries: Variant=value.get("delivered")
	if not deliveries is Dictionary or deliveries.size()>COUNT: return false
	if value.status=="idle" and not deliveries.is_empty(): return false
	if value.status=="complete" and deliveries.size()!=COUNT: return false
	for id in deliveries:
		if id not in ["0","1","2"]: return false
		var row: Variant=deliveries[id]
		if not row is Dictionary: return false
		for key in ["position","rotation"]:
			var vector: Variant=row.get(key)
			if not vector is Array or vector.size()!=3: return false
			for axis in vector:
				if not (axis is int or axis is float) or not is_finite(float(axis)): return false
		var point:=Vector3(row.position[0],row.position[1],row.position[2])
		if point.x<DELIVERY_MIN.x or point.x>DELIVERY_MAX.x or point.z<DELIVERY_MIN.y or point.z>DELIVERY_MAX.y or point.y< -27.8 or point.y> -26.9: return false
		for angle in row.rotation:
			if absf(float(angle))>TAU: return false
	return true

static func validate_wallet(world: Dictionary, wallet: Dictionary) -> bool:
	if world.has(KEY) and not valid(world[KEY]): return false
	var state:=data(world)
	if not valid(state): return false
	var receipt:=RECEIPTS.lookup(wallet,"reward",RECEIPT)
	if (state.status=="complete")!=not receipt.is_empty(): return false
	return receipt.is_empty() or (receipt.get("kind")=="reward" and receipt.get("item")==RECEIPT and receipt.get("amount")==REWARD)

static func begin(world: Dictionary) -> bool:
	var state:=data(world)
	if not valid(state) or state.status not in ["idle","paused"]: return false
	state.status="active"
	world[KEY]=state
	return true

static func pause(world: Dictionary) -> void:
	var state:=data(world)
	if state.status!="active": return
	state.status="paused"
	world[KEY]=state

static func deliver(world: Dictionary, id: int, point: Vector3, rotation: Vector3) -> bool:
	var state:=data(world)
	if state.status!="active" or id<0 or id>=COUNT or state.delivered.has(str(id)): return false
	state.delivered[str(id)]={"position":[point.x,point.y,point.z],"rotation":[rotation.x,rotation.y,rotation.z]}
	if not valid(state): return false
	world[KEY]=state
	return true

static func claim(world: Dictionary, wallet: RefCounted) -> Dictionary:
	var state:=data(world)
	if not valid(state) or state.status!="active" or state.delivered.size()!=COUNT: return {"ok":false}
	var result: Dictionary=wallet.grant_world_reward({"id":RECEIPT,"kind":"cash","amount":REWARD})
	if not result.get("ok",false): return result
	state.status="complete"
	world[KEY]=state
	return {"ok":true,"amount":REWARD}
