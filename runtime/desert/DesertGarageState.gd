extends RefCounted
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
static func defaults() -> Dictionary:
	return {"version":1,"vehicles":{},"purchased":{}}
static func data(world: Dictionary) -> Dictionary:
	return world.get("desert_garage",defaults()).duplicate(true)
static func vehicle(world: Dictionary, id: String, archetype: String) -> Dictionary:
	return data(world).vehicles.get(id,{"archetype":archetype,"parts":{},"owned":[],"presets":{}}).duplicate(true)
static func valid(value: Variant, economy: Dictionary = {}) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	if not value.get("vehicles") is Dictionary or value.vehicles.size()>128: return false
	if not value.get("purchased") is Dictionary or value.purchased.size()>CARS.IDS.size(): return false
	for id in value.vehicles:
		if not id is String or id.is_empty() or id.length()>128: return false
		var record: Variant = value.vehicles[id]
		if not record is Dictionary or not record.get("archetype") is String: return false
		if record.has("honor_gift") and (record.honor_gift != true or id != "takeshi_supra" or record.archetype != "supra_a80"): return false
		if record.has("vicente_gift") and (record.vicente_gift != true or id != LETTERS.CAR_ID or record.archetype != LETTERS.CAR_ARCHETYPE): return false
		if not record.get("parts") is Dictionary or TUNING.clean_parts(record.parts) != record.parts: return false
		if not record.get("owned") is Array or record.owned.size()>TUNING.PARTS.size(): return false
		var seen: Array = []
		for part in record.owned:
			if not part is String or not TUNING.PARTS.has(part) or part in seen: return false
			if not TUNING.compatible(part,record.archetype): return false
			seen.append(part)
			if not economy.is_empty():
				# The shared desert save contract verifies these gifts against the
				# two durable rival proofs. They are never purchases or resale items.
				if TUNING.PARTS[part].has("rival_reward"): continue
				if record.get("honor_gift",false) and part in preload("res://data/TakeshiRewardSpec.gd").PARTS.values(): continue
				# Peças que vieram montadas no Coyote do Vicente, com o recibo do achado da caverna.
				if record.get("vicente_gift",false) and part in LETTERS.CAR_PARTS.values() and not RECEIPTS.lookup(economy,"reward",LETTERS.CAR_RECEIPT).is_empty(): continue
				var receipt: Dictionary = economy.get("transactions",{}).get("spend:desert_part:"+id+":"+part,{})
				if receipt.get("amount",-1) != TUNING.PARTS[part].cost: return false
		for part in record.parts.values():
			if part not in seen: return false
		if not record.get("presets") is Dictionary or record.presets.size()>3: return false
		for preset in record.presets:
			if preset not in ["rua","drag","terra"] or not record.presets[preset] is Dictionary: return false
			if TUNING.clean_parts(record.presets[preset]) != record.presets[preset]: return false
			for part in record.presets[preset].values():
				if part not in seen: return false
	for id in value.purchased:
		if id not in CARS.IDS or value.purchased[id] != "desert_owned_"+id: return false
		if not economy.is_empty():
			var receipt: Dictionary = economy.get("transactions",{}).get("spend:desert_car:"+id,{})
			if receipt.get("amount",-1) != CARS.spec(id).price: return false
	return true
static func buy(world: Dictionary, economy, vehicle_id: String, archetype: String, part: String, wins: int) -> Dictionary:
	if not TUNING.compatible(part,archetype): return {"ok":false,"reason":"Peça incompatível com este carro"}
	var saved := data(world)
	var record := vehicle(world,vehicle_id,archetype)
	if record.archetype != archetype: return {"ok":false,"reason":"Identidade do carro inválida"}
	var checked := TUNING.purchase_check(record.parts,record.owned,part,wins,economy.balance)
	if not checked.ok: return checked
	if checked.cost>0 and not economy.spend(checked.cost,"desert_part:"+vehicle_id+":"+part): return {"ok":false,"reason":"Compra não concluída"}
	record.parts = checked.parts
	record.owned = checked.owned
	saved.vehicles[vehicle_id] = record
	world.desert_garage = saved
	return checked

## Validate the complete draft before charging; removals and owned parts are free.
static func apply_loadout(world: Dictionary, economy, vehicle_id: String, archetype: String, requested: Dictionary, wins: int) -> Dictionary:
	if vehicle_id.is_empty() or vehicle_id.length()>128: return {"ok":false,"reason":"Identidade do carro inválida"}
	var saved := data(world)
	var record := vehicle(world,vehicle_id,archetype)
	if record.archetype != archetype: return {"ok":false,"reason":"Identidade do carro inválida"}
	if TUNING.clean_parts(requested) != requested: return {"ok":false,"reason":"Peça inválida"}
	var inventory: Array = record.owned.duplicate()
	var receipts: Array = []
	var cost := 0
	for slot in requested:
		var part: String = requested[slot]
		if not TUNING.compatible(part,archetype): return {"ok":false,"reason":"Peça incompatível com este carro"}
		# Already installed or owned rewards remain usable even when their unlock
		# came from another workshop. New parts still require the current wins.
		if part in inventory: continue
		var checked := TUNING.purchase_check({},inventory,part,wins,economy.balance-cost)
		if not checked.ok: return checked
		cost += int(checked.cost)
		inventory = checked.owned
		if int(checked.cost)>0: receipts.append({"amount":int(checked.cost),"receipt_id":"desert_part:"+vehicle_id+":"+part})
	if not economy.spend_batch(receipts): return {"ok":false,"reason":"Compra não concluída"}
	record.parts = requested.duplicate(true)
	record.owned = inventory
	saved.vehicles[vehicle_id] = record
	world.desert_garage = saved
	return {"ok":true,"cost":cost,"parts":record.parts,"owned":inventory}
