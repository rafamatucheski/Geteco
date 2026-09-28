extends RefCounted
## Durable cargo identity is its authored ground position, never a streamed node ID.
const RESTOCK_SECONDS := 1200.0
const MAX_CYCLE := 1000000

static func cargo_id(point: Vector3) -> String:
	return "port_%d_%d" % [roundi(point.x * 16), roundi(point.z * 16)]

static func known_ids() -> Array[String]:
	var ids: Array[String] = []
	for rect in preload("res://world/regions/OriginalSouthPortLayout.gd").containers():
		var center: Vector2 = rect.get_center() / 16.0
		ids.append(cargo_id(Vector3(center.x, 0, center.y)))
	return ids

static func loot(id: String, cycle := 0) -> Dictionary:
	var index := known_ids().find(id)
	if index < 0: return {}
	match (index + cycle) % 6:
		0: return {"kind":"cash", "amount":180 + (index % 3) * 65}
		1: return {"kind":"ammo", "amount":24, "weapon":"pistol"}
		2: return {"kind":"weapon", "amount":12, "weapon":"pistol" if (index + cycle) % 12 < 6 else "shotgun"}
		3: return {"kind":"empty", "amount":0}
		4: return {"kind":"armor", "amount":100}
		_: return {"kind":"cash", "amount":350 + (cycle % 3) * 50}

static func normalized(row: Dictionary) -> Dictionary:
	return {"opened":row.get("opened",false),"looted":row.get("looted",false),"cycle":int(row.get("cycle",0)),"elapsed":float(row.get("elapsed",0.0))}

static func receipt(id: String, cycle: int) -> String:
	# Cycle zero keeps receipts from saves made before restocking existed.
	return "container_loot:"+id+(":%d" % cycle if cycle > 0 else "")

static func validate_snapshot(data: Variant) -> bool:
	if not data is Dictionary or data.size() > 18: return false
	var ids := known_ids()
	for id in data:
		if id not in ids or not data[id] is Dictionary: return false
		var row: Dictionary = data[id]
		if row.size() not in [2,4] or not row.get("opened") is bool or not row.get("looted") is bool: return false
		if row.size() == 4:
			for key in ["cycle","elapsed"]:
				if typeof(row.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(row[key])): return false
			if row.cycle < 0 or row.cycle > MAX_CYCLE or row.cycle != floorf(row.cycle): return false
			if row.elapsed < 0 or row.elapsed > RESTOCK_SECONDS: return false
		if row.looted and not row.opened: return false
	return true
