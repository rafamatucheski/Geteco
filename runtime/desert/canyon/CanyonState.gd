extends RefCounted
## Finite authored defenders and two independent, atomic armory rewards.
const KEY := "desert_smuggler_canyon"
const GUARD_COUNT := 8
const FULL_MASK := (1 << GUARD_COUNT) - 1
const RECEIPTS := ["desert_canyon_ak47", "desert_canyon_grenades"]
const WEAPONS := ["ak47", "grenade"]
const AMMO := [90, 3]
const ECONOMY := preload("res://systems/economy/Economy.gd")

static func defaults() -> Dictionary:
	return {"version":1,"defeated_mask":0,"cache_mask":0}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=3: return false
	for key in ["version","defeated_mask","cache_mask"]:
		if not value.has(key) or not ECONOMY._integer(value[key],0,FULL_MASK): return false
	return int(value.version)==1 and int(value.cache_mask)<=3 and (int(value.cache_mask)==0 or int(value.defeated_mask)==FULL_MASK)

static func validate_wallet(world: Dictionary, economy: Dictionary) -> bool:
	var saved: Variant=world.get(KEY,defaults())
	if not valid(saved): return false
	var transactions: Dictionary=economy.get("transactions",{})
	for index in RECEIPTS.size():
		var receipt: Variant=transactions.get("reward:"+RECEIPTS[index],{})
		if not receipt is Dictionary: return false
		var marked := (int(saved.cache_mask)&(1<<index))!=0
		if marked != (not receipt.is_empty()): return false
		if marked and (not receipt is Dictionary or receipt.size()!=3 or receipt.get("kind")!="reward" or receipt.get("item")!=RECEIPTS[index] or not ECONOMY._integer(receipt.get("amount"),0,0)): return false
	return true

static func defeat(world: Dictionary, slot: int) -> bool:
	if slot<0 or slot>=GUARD_COUNT: return false
	var saved: Variant=world.get(KEY,defaults())
	if not valid(saved): return false
	var next: Dictionary=saved.duplicate(true)
	next.defeated_mask=int(next.defeated_mask)|(1<<slot)
	world[KEY]=next
	return true

static func claim(world: Dictionary, economy: RefCounted, index: int, alive: bool) -> Dictionary:
	if not alive or index<0 or index>=RECEIPTS.size() or not is_instance_valid(economy): return {"ok":false,"changed":false}
	var saved: Variant=world.get(KEY,defaults())
	if not valid(saved) or int(saved.defeated_mask)!=FULL_MASK or not validate_wallet(world,economy.snapshot()): return {"ok":false,"changed":false}
	if (int(saved.cache_mask)&(1<<index))!=0: return {"ok":true,"changed":false}
	# Prepara a transação de inventário inteira, incluindo a capacidade da grade. Publicar
	# os dados validados preserva as configurações de cheat só da sessão da carteira viva.
	var staged := ECONOMY.new()
	staged._data=economy.snapshot()
	var id: String=WEAPONS[index]
	var owned: bool=staged.owns_weapon(id)
	if (owned and not staged.add_ammo(id,AMMO[index])) or (not owned and not staged.grant_weapon(id)): return {"ok":false,"changed":false,"reason":"inventory_full"}
	if not staged.grant_reward(RECEIPTS[index],0): return {"ok":false,"changed":false}
	var next: Dictionary=saved.duplicate(true)
	next.cache_mask=int(next.cache_mask)|(1<<index)
	economy._data=staged.snapshot()
	world[KEY]=next
	return {"ok":true,"changed":true,"weapon":id,"ammo_only":owned}
