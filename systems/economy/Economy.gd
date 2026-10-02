extends RefCounted
## Pure wallet/inventory. Scene adapters enforce physical shop access and safe zones.
const Weapons := preload("res://gameplay/WeaponCatalog.gd")
const Outfits := preload("res://data/catalogs/OutfitCatalog.gd")
const Collectibles := preload("res://data/catalogs/CollectibleCatalog.gd")
const Achievements := preload("res://data/catalogs/AchievementCatalog.gd")
const Services := preload("res://data/catalogs/ServiceCatalog.gd")
const GRID := preload("res://systems/inventory/GridInventory.gd")
const INVENTORY_MIGRATION := preload("res://systems/inventory/InventoryMigration.gd")
const LIMIT := 100000000
const MAX_AMMO := 99999
const SUPPLIES := {"lockpick":{"price":75}}
const PERSONAL_SLOTS := {
	"curta":["pistol","magnum","smg"],
	"longa":["shotgun","sawed_off","ak47","m4a1","hunting_rifle","rpg","flamethrower"],
	"corpo":["knife","axe","knuckles","bat"], "granada":["grenade"]}
var _data := {"version": 1, "balance": 0, "weapons": {"fists": {"magazine": -1, "reserve": -1}},
	"equipped_weapon": "fists", "outfits": ["dante_classic"], "outfit": "dante_classic",
	"inventory": {}, "discoveries": [], "collectibles": [], "achievements": [], "transactions": {}}
var balance: int:
	get: return int(_data.balance)
var equipped_weapon: String:
	get: return _cheat_equipped if cheat_all_weapons and not _cheat_equipped.is_empty() else _data.equipped_weapon
var outfit: String:
	get: return _data.outfit
var inventory: Dictionary:
	get:
		if not grid_enabled(): return _data.inventory.duplicate(true)
		var carried := {}
		for id in _data.inventory:
			var amount := GRID.count(_data.grid_inventory,str(id))
			if amount>0: carried[id]=amount
		return carried

func snapshot() -> Dictionary:
	return _data.duplicate(true)

## Read receipt membership without exposing or copying the wallet/inventory.
func has_reward_receipt(receipt_id: String) -> bool:
	return _data.transactions.has("reward:" + receipt_id)

func storefront(category: String) -> Array:
	var result := []
	var catalog: Dictionary = Weapons.WEAPONS if category == "weapon" else (Outfits.OUTFITS if category == "outfit" else SUPPLIES if category == "supply" else {})
	for id in catalog:
		var row: Dictionary = catalog[id].duplicate(true)
		row.id = id
		row.owned = _data.weapons.has(id) if category == "weapon" else owns_outfit(id)
		row.unlocked = is_weapon_unlocked(id) if category == "weapon" else (category == "supply" or Outfits.ORDER.has(id) or owns_outfit(id))
		result.append(row)
	return result

func owns_weapon(id: String) -> bool:
	return _data.weapons.has(id) or _cheat_weapons.has(id)

func grant_weapon(id: String) -> bool:
	if not Weapons.WEAPONS.has(id) or _data.weapons.has(id): return false
	var before := _data.duplicate(true)
	var spec: Dictionary = Weapons.WEAPONS[id]
	_data.weapons[id] = {"magazine": int(spec.magazine_size), "reserve": int(spec.starting_reserve)}
	_assign_personal_slot(id)
	if grid_enabled() and not _grid_register_weapon(id): _data=before; return false
	var discovery := str(spec.get("discovery_pickup", ""))
	if discovery != "": discover(discovery)
	return true

func spend(amount: int, receipt_id: String) -> bool:
	if amount < 0 or amount > LIMIT or not _valid_id(receipt_id) or receipt_id.length() > 110: return false
	var key := "spend:" + receipt_id
	if _data.transactions.has(key): return _data.transactions[key].amount == amount
	if balance < amount: return false
	_data.balance -= amount
	_data.transactions[key] = {"kind": "spend", "item": receipt_id, "amount": amount}
	return true

func purchase_body_armor(current_armor: Variant, maximum_armor: Variant, transaction_id: String) -> Dictionary:
	# The wallet owns the final precondition as well as the debit. UI may disable
	# the button, but stale menus cannot charge when protection is already full.
	if typeof(current_armor) not in [TYPE_INT,TYPE_FLOAT] or typeof(maximum_armor) not in [TYPE_INT,TYPE_FLOAT]:
		return _result(false,"invalid_protection")
	if not is_finite(float(current_armor)) or not is_finite(float(maximum_armor)) or float(maximum_armor) <= 0.0:
		return _result(false,"invalid_protection")
	if float(current_armor) < 0.0 or float(current_armor) > float(maximum_armor):
		return _result(false,"invalid_protection")
	if float(current_armor) >= float(maximum_armor): return _result(false,"protection_full")
	if not _valid_id(transaction_id) or transaction_id.length() > 95: return _result(false,"invalid_transaction")
	var price := int(Services.SERVICES.body_armor.price)
	if not spend(price,"body_armor:"+transaction_id): return _result(false,"insufficient_funds")
	return {"ok":true,"reason":"purchased","amount":price,"armor":int(maximum_armor)}

func buy_ammo(id: String, rounds: int, transaction_id: String) -> bool:
	if not _data.weapons.has(id) or rounds <= 0 or rounds > MAX_AMMO or not _valid_id(transaction_id) or transaction_id.length() > 110: return false
	var key := "ammo:" + transaction_id
	if _data.transactions.has(key):
		return _data.transactions[key].item == id and _data.transactions[key].get("rounds", 0) == rounds
	if int(_data.weapons[id].reserve) < 0 or int(_data.weapons[id].reserve) > MAX_AMMO - rounds: return false
	# HarborAmmunationInterior._ammo_price; rounds vary with selected package.
	var price := maxi(40, rounds * (60 if id in ["grenade", "rpg"] else 2))
	if balance < price: return false
	if grid_enabled() and not _grid_add_ammo(id,rounds): return false
	_data.balance -= price
	if not grid_enabled(): _data.weapons[id].reserve += rounds
	_data.transactions[key] = {"kind": "ammo", "item": id, "amount": price, "rounds": rounds}
	return true

func get_ammo(id: String) -> Dictionary:
	if _cheat_weapons.has(id): return _cheat_weapons[id].duplicate(true)
	var result: Dictionary = _data.weapons.get(id, {"magazine": 0, "reserve": 0}).duplicate(true)
	if grid_enabled() and int(result.reserve)>=0:
		result.reserve += GRID.count(_data.grid_inventory,"ammo:"+id,not cheat_all_weapons)
	return result

func equip_weapon(id: String) -> bool:
	if not can_carry_weapon(id): return false
	if cheat_all_weapons:
		_cheat_equipped=id
		return true
	_data.equipped_weapon = id
	return true

func consume_ammo(id: String, amount: int = 1) -> bool:
	if not can_carry_weapon(id) or amount <= 0: return false
	if _cheat_weapons.has(id):
		if int(_cheat_weapons[id].magazine)<0: return true
		if int(_cheat_weapons[id].magazine)<amount: return false
		_cheat_weapons[id].magazine-=amount
		return true
	if int(_data.weapons[id].magazine) == -1: return true
	if int(_data.weapons[id].magazine) < amount: return false
	_data.weapons[id].magazine -= amount
	return true

func add_ammo(id: String, amount: int) -> bool:
	if not _data.weapons.has(id) or amount <= 0 or amount > MAX_AMMO: return false
	if int(_data.weapons[id].reserve) == -1: return false
	if int(_data.weapons[id].reserve) > MAX_AMMO - amount: return false
	if grid_enabled(): return _grid_add_ammo(id,amount)
	_data.weapons[id].reserve += amount
	return true

func reload_weapon(id: String, capacity: int = -1) -> bool:
	if not owns_weapon(id): return false
	if capacity == -1: capacity = int(Weapons.WEAPONS[id].magazine_size)
	if capacity > _max_capacity(id): return false
	if capacity < 0: return false
	if _cheat_weapons.has(id):
		if int(_cheat_weapons[id].magazine)>=capacity: return false
		_cheat_weapons[id].magazine=capacity
		return true
	if grid_enabled():
		capacity=mini(capacity,99)
		var needed := mini(99-int(_data.weapons[id].magazine)-int(_data.weapons[id].reserve),GRID.count(_data.grid_inventory,"ammo:"+id))
		if needed>0 and GRID.remove_carried(_data.grid_inventory,"ammo:"+id,needed): _data.weapons[id].reserve += needed
	var rounds := mini(capacity - int(_data.weapons[id].magazine), int(_data.weapons[id].reserve))
	if rounds <= 0: return false
	_data.weapons[id].magazine += rounds
	_data.weapons[id].reserve -= rounds
	return true

static func _max_capacity(id: String) -> int:
	var base := int(Weapons.WEAPONS[id].magazine_size)
	if id == "shotgun": return base + 2
	if id == "hunting_rifle": return base + 3
	# Magazine capacity counts whole rounds; preserve truncation.
	@warning_ignore("integer_division")
	if id in ["pistol", "smg", "ak47", "m4a1"]: return base + int(base / 2)
	return base

func grant_reward(receipt_id: String, amount: int) -> bool:
	if not _valid_id(receipt_id) or receipt_id.length() > 110 or amount < 0 or amount > LIMIT or balance > LIMIT - amount: return false
	var key := "reward:" + receipt_id
	if _data.transactions.has(key): return false
	_data.balance += amount
	_data.transactions[key] = {"kind": "reward", "item": receipt_id, "amount": amount}
	return true

func grant_world_reward(definition: Dictionary) -> Dictionary:
	# World pickups are one transaction even when they contain a weapon plus
	# ammunition. The zero-value receipt for non-cash pickups is durable proof
	# that a missing world marker may be reconciled after a load without granting
	# the payload twice.
	var id: Variant = definition.get("id")
	var kind: Variant = definition.get("kind")
	if not _valid_id(id) or str(id).length() > 110: return _result(false,"invalid_reward")
	if not kind is String or kind not in ["cash","weapon","item"]: return _result(false,"invalid_reward")
	var amount_value: Variant = definition.get("amount",1)
	if not _integer(amount_value,1,LIMIT if kind == "cash" else 999):
		return _result(false,"invalid_reward")
	var amount := int(amount_value)
	var receipt_amount := amount if kind == "cash" else 0
	var receipt_key := "reward:"+str(id)
	if _data.transactions.has(receipt_key):
		var previous: Variant = _data.transactions[receipt_key]
		if previous is Dictionary and previous.get("kind","") == "reward" and previous.get("item","") == id and int(previous.get("amount",-1)) == receipt_amount:
			if kind == "weapon" and not owns_weapon(str(definition.get("item",""))): return _result(false,"transaction_conflict")
			return {"ok":true,"reason":"already_applied","changed":false}
		return _result(false,"transaction_conflict")
	var before := _data.duplicate(true)
	match kind:
		"cash":
			if not grant_reward(str(id),amount): return _result(false,"wallet_full")
		"weapon":
			var weapon_id: Variant = definition.get("item")
			var ammo_value: Variant = definition.get("ammo",0)
			if not weapon_id is String or not Weapons.WEAPONS.has(weapon_id) or not _integer(ammo_value,0,MAX_AMMO):
				return _result(false,"invalid_reward")
			if owns_weapon(weapon_id): return _result(false,"already_owned")
			var reserve := int(Weapons.WEAPONS[weapon_id].starting_reserve)
			var ammo := int(ammo_value)
			if reserve < 0 and ammo > 0: return _result(false,"invalid_reward")
			if reserve >= 0 and reserve > MAX_AMMO-ammo: return _result(false,"ammo_full")
			if not grant_weapon(weapon_id) or (ammo > 0 and not add_ammo(weapon_id,ammo)) or not grant_reward(str(id),0):
				_data = before
				return _result(false,"grant_failed")
		"item":
			var item_id: Variant = definition.get("item")
			if not _valid_id(item_id): return _result(false,"invalid_reward")
			if int(_data.inventory.get(item_id,0)) > 999-amount: return _result(false,"inventory_full")
			if not grant_item(item_id,amount) or not grant_reward(str(id),0):
				_data = before
				return _result(false,"grant_failed")
	return {"ok":true,"reason":"granted","changed":true}

func purchase(category: String, id: String, transaction_id: String) -> Dictionary:
	if not _valid_id(transaction_id) or transaction_id.length() > 110: return _result(false, "invalid_transaction")
	var receipt := "purchase:" + transaction_id
	if _data.transactions.has(receipt):
		var old: Dictionary = _data.transactions[receipt]
		return _result(old.kind == category and old.item == id, "already_applied" if old.kind == category and old.item == id else "transaction_conflict")
	var catalog: Dictionary = Weapons.WEAPONS if category == "weapon" else (Outfits.OUTFITS if category == "outfit" else SUPPLIES if category == "supply" else {})
	if not catalog.has(id): return _result(false, "unknown_item")
	if category == "supply" and int(_data.inventory.get(id,0)) >= 999: return _result(false,"inventory_full")
	if category == "supply" and grid_enabled():
		var candidate: Dictionary = _data.grid_inventory.duplicate(true)
		if GRID.add_carried(candidate,id,1)!=0: return _result(false,"inventory_full")
	if category == "outfit" and not Outfits.ORDER.has(id): return _result(false, "reward_only")
	if (category == "weapon" and _data.weapons.has(id)) or (category == "outfit" and _data.outfits.has(id)):
		return _result(false, "already_owned")
	if category == "weapon" and not is_weapon_unlocked(id): return _result(false, "discovery_required")
	var price := int(catalog[id].price)
	if price < 0 or balance < price: return _result(false, "insufficient_funds")
	var before := _data.duplicate(true)
	_data.balance -= price
	if category == "weapon":
		_data.weapons[id] = {"magazine": int(catalog[id].magazine_size), "reserve": int(catalog[id].starting_reserve)}
		_assign_personal_slot(id)
		if grid_enabled() and not _grid_register_weapon(id): _data=before; return _result(false,"inventory_full")
	elif category == "supply":
		grant_item(id)
	else:
		_data.outfits.append(id)
	_data.transactions[receipt] = {"kind": category, "item": id, "amount": price}
	return _result(true, "purchased")

func buy_weapon(id: String, transaction_id: String = "") -> bool:
	return bool(purchase("weapon", id, transaction_id if transaction_id != "" else "weapon:" + id).ok)

func equip_outfit(id: String) -> bool:
	if not _data.outfits.has(id): return false
	_data.outfit = id
	return true

func owns_outfit(id: String) -> bool:
	return _data.outfits.has(id)

func grant_outfit(id: String) -> bool:
	if not Outfits.OUTFITS.has(id) or owns_outfit(id): return false
	_data.outfits.append(id)
	return true

func is_weapon_unlocked(id: String) -> bool:
	if not Weapons.WEAPONS.has(id): return false
	var discovery := str(Weapons.WEAPONS[id].get("discovery_pickup", ""))
	return discovery.is_empty() or _data.discoveries.has(discovery)

func discover(id: String) -> bool:
	var known := false
	for weapon in Weapons.WEAPONS.values():
		if weapon.get("discovery_pickup", "") == id and id != "": known = true
	if not known or _data.discoveries.has(id): return false
	_data.discoveries.append(id)
	return true

func grant_item(id: String, count: int = 1) -> bool:
	if not _valid_id(id) or count <= 0 or count > 999: return false
	if int(_data.inventory.get(id, 0)) + count > 999: return false
	if grid_enabled():
		var candidate: Dictionary = _data.grid_inventory.duplicate(true)
		if GRID.add_carried(candidate,id,count)!=0: return false
		_data.grid_inventory = candidate
	_data.inventory[id] = int(_data.inventory.get(id, 0)) + count
	return true

func consume_item(id: String, count: int = 1) -> bool:
	if count <= 0 or int(_data.inventory.get(id, 0)) < count: return false
	if grid_enabled() and not GRID.remove_carried(_data.grid_inventory,id,count): return false
	_data.inventory[id] -= count
	if int(_data.inventory[id]) == 0: _data.inventory.erase(id)
	return true

func collect(id: String) -> bool:
	if not Collectibles.ENTRIES.has(id) or _data.collectibles.has(id): return false
	var next_count: int = _data.collectibles.size() + 1
	var reward: int = Collectibles.FIND_CASH + int(Collectibles.MILESTONE_CASH.get(next_count, 0))
	if not grant_reward("collectible:" + id, reward): return false
	_data.collectibles.append(id)
	return true

func achievement_stats() -> Dictionary:
	# Wallet-owned criteria come from the authoritative inventory, not adapters.
	var stats := {}
	stats.money = balance
	stats.weapons = _data.weapons.size() # V1 also counts fists as an owned weapon.
	stats.collectibles = _data.collectibles.size()
	var clues := 0
	for id in ["mountain_expedition_pack", "mountain_expedition_journal", "mountain_expedition_camera"]:
		if _data.collectibles.has(id): clues += 1
	stats.mountain_clues = clues
	# Ordinary tow work is not a completed chop-shop crushing delivery.
	stats.chop_shop_deliveries = 1 if _data.transactions.has("reward:port_boss_porto_rosso") else 0
	return stats

func evaluate_achievements(stats: Dictionary) -> Array:
	var unlocked := []
	for id in Achievements.ACHIEVEMENTS:
		if _data.achievements.has(id): continue
		var criterion := str(Achievements.ACHIEVEMENTS[id].check).split(">=")
		if criterion.size() != 2: continue
		var value: Variant = stats.get(criterion[0], 0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)): continue
		if float(value) < float(criterion[1]): continue
		if not grant_reward("achievement:" + id, int(Achievements.CASH_REWARDS.get(id, 0))): continue
		_data.achievements.append(id)
		unlocked.append(id)
	return unlocked

static func _valid_id(id: Variant) -> bool:
	return id is String and id.length() > 0 and id.length() <= 128

func personal_loadout() -> Dictionary:
	return _data.get("personal_loadout", {}).duplicate()

func enable_personal_loadout() -> void:
	if _data.get("personal_loadout_enabled",false): return
	_data.personal_loadout_enabled = true
	_data.personal_loadout = {"curta":"","longa":"","corpo":"","granada":""}
	for slot in PERSONAL_SLOTS:
		if equipped_weapon in PERSONAL_SLOTS[slot]: _data.personal_loadout[slot] = equipped_weapon
	for id in _data.weapons: _assign_personal_slot(id)
	if not can_carry_weapon(equipped_weapon): _data.equipped_weapon = "fists"

## Arsenal temporário: armas e tiros de debug nunca entram no inventário/save.
const CHEAT_RESERVE := 9999
var cheat_all_weapons := false
var _cheat_weapons: Dictionary={}
var _cheat_equipped:=""

func activate_arsenal_cheat() -> void:
	cheat_all_weapons = true
	for id in Weapons.ORDER:
		if id == "fists": continue
		var spec: Dictionary = Weapons.WEAPONS[id]
		var capacity := int(spec.magazine_size)
		_cheat_weapons[id]={"magazine":capacity,"reserve":CHEAT_RESERVE if capacity>=0 else -1}

func can_carry_weapon(id: String) -> bool:
	return owns_weapon(id) and (id == "fists" or cheat_all_weapons or not _data.get("personal_loadout_enabled",false) or id in _data.personal_loadout.values())

func _assign_personal_slot(id: String) -> void:
	if not _data.get("personal_loadout_enabled",false): return
	for slot in PERSONAL_SLOTS:
		if id in PERSONAL_SLOTS[slot] and _data.personal_loadout.get(slot,"") == "":
			_data.personal_loadout[slot] = id

func set_personal_slot(slot: String, id: String) -> bool:
	if not _data.get("personal_loadout_enabled",false) or not PERSONAL_SLOTS.has(slot): return false
	if id != "" and (id not in PERSONAL_SLOTS[slot] or not owns_weapon(id)): return false
	if grid_enabled():
		if _data.personal_loadout[slot]==id: return true
		if id=="": return grid_store_weapon(str(_data.personal_loadout[slot]),"trunk")
		for container in ["pockets","storage","trunk"]:
			for i in _data.grid_inventory[container].size():
				if _data.grid_inventory[container][i].id=="weapon:"+id: return grid_equip_weapon(container,i)
		return false
	_data.personal_loadout[slot] = id
	if not can_carry_weapon(equipped_weapon): _data.equipped_weapon = "fists"
	return true

func claim_monaliza_starter() -> bool:
	if _data.transactions.has("reward:monaliza_starter_case"): return false
	if owns_weapon("pistol") and int(_data.weapons.pistol.reserve) > MAX_AMMO - 72: return false
	if not grant_reward("monaliza_starter_case",0): return false
	# V1 adds 72 rounds total, then loads the clip. Do not add catalog starter ammo.
	if not owns_weapon("pistol"): _data.weapons.pistol = {"magazine":0,"reserve":0}
	_data.weapons.pistol.reserve += 72
	reload_weapon("pistol",12)
	# A residence may already have initialized the same slots. Keep its choices.
	enable_personal_loadout()
	_assign_personal_slot("pistol")
	if grid_enabled(): _grid_register_weapon("pistol",true)
	if not can_carry_weapon(equipped_weapon): _data.equipped_weapon = "fists"
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	var upgraded:=INVENTORY_MIGRATION.upgrade(data)
	if not validate_snapshot(upgraded): return false
	_data = upgraded
	cheat_all_weapons=false; _cheat_weapons.clear(); _cheat_equipped=""
	_data.version = 1
	_data.balance = int(_data.balance)
	if grid_enabled():
		_data.grid_inventory.version=int(_data.grid_inventory.version)
		_data.grid_inventory.serial=int(_data.grid_inventory.serial)
		for container in ["pockets","storage","trunk"]: _normalize_grid_entries(_data.grid_inventory[container])
		for drop in _data.grid_inventory.ground:
			drop.uid=int(drop.uid)
			_normalize_grid_entries(drop.entries)
	for id in _data.weapons:
		_data.weapons[id].magazine = int(_data.weapons[id].magazine)
		_data.weapons[id].reserve = int(_data.weapons[id].reserve)
	for id in _data.inventory: _data.inventory[id] = int(_data.inventory[id])
	for id in _data.transactions:
		_data.transactions[id].amount = int(_data.transactions[id].amount)
		if _data.transactions[id].has("rounds"): _data.transactions[id].rounds = int(_data.transactions[id].rounds)
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	if data.has("grid_inventory") and not GRID.validate(data.grid_inventory): return false
	for key in ["version", "balance", "weapons", "equipped_weapon", "outfits", "outfit", "inventory", "discoveries", "collectibles", "achievements", "transactions"]:
		if not data.has(key): return false
	if not _integer(data.version, 1, 1) or not _integer(data.balance, 0, LIMIT): return false
	for key in ["weapons", "inventory", "transactions"]:
		if not data[key] is Dictionary or data[key].size() > 10000: return false
	for key in ["outfits", "discoveries", "collectibles", "achievements"]:
		if not data[key] is Array or data[key].size() > 1000: return false
		var seen := {}
		for id in data[key]:
			if not _valid_id(id) or seen.has(id): return false
			seen[id] = true
	if not data.equipped_weapon is String or not data.weapons.has(data.equipped_weapon) or not data.weapons.has("fists"): return false
	if not data.outfit is String or not data.outfits.has(data.outfit) or not data.outfits.has("dante_classic"): return false
	for id in data.outfits:
		if not Outfits.OUTFITS.has(id): return false
	for id in data.collectibles:
		if not Collectibles.ENTRIES.has(id): return false
	for id in data.achievements:
		if not Achievements.ACHIEVEMENTS.has(id): return false
	for id in data.discoveries:
		var known := false
		for weapon in Weapons.WEAPONS.values():
			if weapon.get("discovery_pickup", "") == id: known = true
		if not known: return false
	for id in data.weapons:
		if not Weapons.WEAPONS.has(id) or not data.weapons[id] is Dictionary: return false
		var ammo: Dictionary = data.weapons[id]
		if not ammo.has("magazine") or not ammo.has("reserve"): return false
		var capacity := int(Weapons.WEAPONS[id].magazine_size)
		if capacity < 0:
			if not _integer(ammo.magazine, -1, -1) or not _integer(ammo.reserve, -1, -1): return false
		elif not _integer(ammo.magazine, 0, _max_capacity(id)) or not _integer(ammo.reserve, 0, MAX_AMMO): return false
	if data.has("personal_loadout_enabled") or data.has("personal_loadout"):
		if not data.get("personal_loadout_enabled") is bool or not data.get("personal_loadout") is Dictionary: return false
		if data.personal_loadout.size() != PERSONAL_SLOTS.size(): return false
		for slot in PERSONAL_SLOTS:
			var selected: Variant = data.personal_loadout.get(slot)
			if not selected is String or (selected != "" and (selected not in PERSONAL_SLOTS[slot] or not data.weapons.has(selected))): return false
		if data.personal_loadout_enabled and data.equipped_weapon != "fists" and data.equipped_weapon not in data.personal_loadout.values(): return false
	for id in data.inventory:
		if not _valid_id(id) or not _integer(data.inventory[id], 1, 999): return false
	for id in data.transactions:
		if not _valid_id(id) or not data.transactions[id] is Dictionary: return false
		var entry: Dictionary = data.transactions[id]
		if not entry.get("kind") in ["reward", "weapon", "outfit", "spend", "ammo", "supply"] or not _valid_id(entry.get("item")) or not _integer(entry.get("amount"), 0, LIMIT): return false
		match entry.kind:
			"supply":
				if not id.begins_with("purchase:") or not SUPPLIES.has(entry.item) or int(entry.amount) != int(SUPPLIES[entry.item].price): return false
			"reward", "spend":
				if id != str(entry.kind) + ":" + str(entry.item): return false
			"weapon":
				if not id.begins_with("purchase:") or not Weapons.WEAPONS.has(entry.item) or not data.weapons.has(entry.item): return false
			"outfit":
				if not id.begins_with("purchase:") or not Outfits.OUTFITS.has(entry.item) or not data.outfits.has(entry.item): return false
			"ammo":
				if not id.begins_with("ammo:") or not Weapons.WEAPONS.has(entry.item) or not data.weapons.has(entry.item) or not _integer(entry.get("rounds"), 1, MAX_AMMO): return false
	if data.has("grid_inventory") and not _validate_grid_ownership(data): return false
	return true

static func _validate_grid_ownership(data: Dictionary) -> bool:
	var grid: Dictionary=data.grid_inventory
	if not data.get("personal_loadout_enabled",false): return false
	var totals: Dictionary={}
	var entries: Array=[]
	for container in ["pockets","storage","trunk"]: entries.append_array(grid[container])
	for drop in grid.ground: entries.append_array(drop.entries)
	for entry in entries:
		var id:=str(entry.id)
		totals[id]=int(totals.get(id,0))+int(entry.amount)
		if id.begins_with("ammo:") and not data.weapons.has(id.trim_prefix("ammo:")): return false
		if id.begins_with("weapon:") and not data.weapons.has(id.trim_prefix("weapon:")): return false
	for id in data.weapons:
		if id=="fists": continue
		var owned: int=int(totals.get("weapon:"+str(id),0))+(1 if id in data.personal_loadout.values() else 0)
		if owned!=1: return false
		if int(data.weapons[id].magazine)>=0 and int(data.weapons[id].magazine)+int(data.weapons[id].reserve)>99: return false
	for id in data.inventory:
		if int(totals.get(id,0))!=int(data.inventory[id]): return false
	for id in totals:
		if not str(id).begins_with("weapon:") and not str(id).begins_with("ammo:") and not data.inventory.has(id): return false
	return true

static func _normalize_grid_entries(entries: Array) -> void:
	for entry in entries:
		for key in ["x","y","amount"]: entry[key]=int(entry[key])

static func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}

func grid_enabled() -> bool:
	return _data.has("grid_inventory")

func grid_snapshot() -> Dictionary:
	return _data.get("grid_inventory",GRID.empty()).duplicate(true)

func enable_grid_inventory() -> void:
	if grid_enabled():
		_data=INVENTORY_MIGRATION.upgrade(_data)
		return
	_data=INVENTORY_MIGRATION.upgrade(_data)
	enable_personal_loadout()
	_data.grid_inventory=GRID.empty()
	for id in _data.inventory:
		var left := GRID.add_carried(_data.grid_inventory,str(id),int(_data.inventory[id]))
		if left>0: INVENTORY_MIGRATION.store_remainder(_data.grid_inventory,str(id),left)
	for id in _data.weapons:
		if id!="fists": _grid_register_weapon(str(id),true)

func _grid_register_weapon(id: String, migration := false) -> bool:
	var grid: Dictionary = _data.grid_inventory
	if id in _data.personal_loadout.values():
		var groups: Array=[grid.pockets,grid.storage,grid.trunk]
		for drop in grid.ground: groups.append(drop.entries)
		for entries in groups:
			for i in range(entries.size()-1,-1,-1):
				if entries[i].id=="weapon:"+id: entries.remove_at(i)
	if id not in _data.personal_loadout.values() and GRID.count(grid,"weapon:"+id,false)==0:
		if migration: INVENTORY_MIGRATION.store_remainder(grid,"weapon:"+id,1)
		elif GRID.add_carried(grid,"weapon:"+id,1)!=0: return false
	var ammo: Dictionary = _data.weapons[id]
	if int(ammo.magazine)<0: return true
	var excess := maxi(0,int(ammo.magazine)+int(ammo.reserve)-99)
	if excess==0: return true
	var reserve_excess := mini(excess,int(ammo.reserve))
	ammo.reserve-=reserve_excess
	ammo.magazine-=excess-reserve_excess
	# Legacy/starter ammo is never destroyed if the initial two pockets are full.
	var left := GRID.add_carried(grid,"ammo:"+id,excess) if can_carry_weapon(id) else excess
	if left>0:
		if not migration: return false
		INVENTORY_MIGRATION.store_remainder(grid,"ammo:"+id,left)
	return true

func _grid_add_ammo(id: String, amount: int) -> bool:
	if not can_carry_weapon(id) and GRID.count(_data.grid_inventory,"weapon:"+id)==0: return false
	var direct := mini(amount,maxi(0,99-int(_data.weapons[id].magazine)-int(_data.weapons[id].reserve)))
	var candidate: Dictionary = _data.grid_inventory.duplicate(true)
	if GRID.add_carried(candidate,"ammo:"+id,amount-direct)!=0: return false
	_data.weapons[id].reserve+=direct
	_data.grid_inventory=candidate
	return true

func grid_move(source: String, index: int, target: String, cell := Vector2i(-1,-1), rotate := false) -> bool:
	if not grid_enabled(): return false
	var candidate: Dictionary = _data.grid_inventory.duplicate(true)
	if not GRID.move(candidate,source,index,target,cell,rotate): return false
	_data.grid_inventory=candidate
	return true

func grid_equip_weapon(source: String, index: int) -> bool:
	if not grid_enabled() or source not in ["pockets","storage","trunk"]: return false
	var candidate: Dictionary = _data.grid_inventory.duplicate(true)
	if index<0 or index>=candidate[source].size(): return false
	var id: String = str(candidate[source][index].id).trim_prefix("weapon:")
	if not owns_weapon(id): return false
	var slot := ""
	for key in PERSONAL_SLOTS:
		if id in PERSONAL_SLOTS[key]: slot=key
	if slot.is_empty(): return false
	candidate[source].remove_at(index)
	var old := str(_data.personal_loadout.get(slot,""))
	if not old.is_empty() and GRID.add(candidate,source,"weapon:"+old,1)!=0: return false
	_data.grid_inventory=candidate
	_data.personal_loadout[slot]=id
	if _data.equipped_weapon==old: _data.equipped_weapon="fists"
	return true

func grid_store_weapon(id: String, target: String) -> bool:
	if not grid_enabled() or id=="fists" or not can_carry_weapon(id) or target not in ["pockets","storage","trunk"]: return false
	if id not in _data.personal_loadout.values(): return false
	var candidate: Dictionary = _data.grid_inventory.duplicate(true)
	if GRID.add(candidate,target,"weapon:"+id,1)!=0: return false
	for slot in _data.personal_loadout:
		if _data.personal_loadout[slot]==id: _data.personal_loadout[slot]=""
	_data.grid_inventory=candidate
	if _data.equipped_weapon==id: _data.equipped_weapon="fists"
	return true

func grid_equip_bag(kind: String) -> bool:
	if not grid_enabled() or kind not in ["backpack","handbag"] or _data.grid_inventory.bag!="": return false
	_data.grid_inventory.bag=kind
	if kind=="handbag" and equipped_weapon in GRID.LONG: _data.equipped_weapon="fists"
	return true

func grid_drop_bag(region: String, place: String, position: Vector3) -> int:
	if not grid_enabled() or _data.grid_inventory.bag=="" or _data.grid_inventory.ground.size()>=512 or not position.is_finite(): return -1
	var grid: Dictionary = _data.grid_inventory
	grid.serial+=1
	grid.ground.append({"uid":grid.serial,"bag":grid.bag,"region":region,"place":place,"position":[position.x,position.y,position.z],"entries":grid.storage.duplicate(true)})
	grid.bag=""; grid.storage=[]
	return int(grid.serial)

func grid_recover_bag(uid: int) -> bool:
	if not grid_enabled() or _data.grid_inventory.bag!="": return false
	var grid: Dictionary = _data.grid_inventory
	for i in grid.ground.size():
		if int(grid.ground[i].uid)!=uid: continue
		grid.bag=grid.ground[i].bag
		grid.storage=grid.ground[i].entries.duplicate(true)
		if grid.bag=="handbag" and equipped_weapon in GRID.LONG: _data.equipped_weapon="fists"
		grid.ground.remove_at(i)
		return true
	return false

func grid_handbag() -> bool:
	return grid_enabled() and _data.grid_inventory.bag=="handbag"

func grid_claim(id: String) -> bool:
	if not grid_enabled() or id in _data.grid_inventory.claimed: return false
	_data.grid_inventory.claimed.append(id)
	return true
