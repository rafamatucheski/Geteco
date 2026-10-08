extends RefCounted
## Instrument cosmetics share the game's wallet and save envelope. They never
## change the race drivetrain, prizes, or championship ledger.
const KEY := "drag_instruments"
const RECEIPT_PREFIX := "drag_instrument:"
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
const RECEIPTS := preload("res://systems/economy/RecurringReceipts.gd")
const IDS := ["classic","bar","street","pro","champion"]
## Version-1 prices also define saved receipt amounts. Future price changes need
## an explicit migration; do not reinterpret already purchased ownership.
const CATALOG := {
	"classic":{"name":"Clássico","price":0,"wins":0},
	"bar":{"name":"Barras","price":0,"wins":0},
	"street":{"name":"Street","price":1500,"wins":1},
	"pro":{"name":"Pro","price":3500,"wins":3},
	"champion":{"name":"Campeão","price":6500,"wins":5},
}

static func definitions() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for identity in IDS:
		var row: Dictionary=CATALOG[identity].duplicate(true)
		row.id=identity
		rows.append(row)
	return rows

static func defaults() -> Dictionary:
	return {"version":1,"owned":["classic","bar"],"selected":"classic"}

static func data(world: Dictionary) -> Dictionary:
	var value: Variant=world.get(KEY,defaults())
	return value.duplicate(true) if value is Dictionary else {}

static func validate_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=3: return false
	if typeof(value.get("version")) not in [TYPE_INT,TYPE_FLOAT] or value.version!=1: return false
	if not value.get("owned") is Array or not value.get("selected") is String: return false
	if value.owned.size()<2 or value.owned.size()>IDS.size(): return false
	var seen: Array=[]
	for identity in value.owned:
		if not identity is String or identity not in IDS or identity in seen: return false
		seen.append(identity)
	return "classic" in seen and "bar" in seen and value.selected in seen

static func owned(world: Dictionary, identity: String) -> bool:
	var value := data(world)
	return validate_snapshot(value) and identity in value.owned

static func selection(world: Dictionary) -> String:
	var value := data(world)
	return str(value.selected) if validate_snapshot(value) else "classic"

static func unlocked(world: Dictionary, identity: String) -> bool:
	if not CATALOG.has(identity): return false
	var progress := PROGRESS.data(world)
	return PROGRESS.validate_snapshot(progress) and progress.wins.size()>=int(CATALOG[identity].wins)

static func validate_wallet(world: Dictionary, wallet: Dictionary) -> bool:
	var value := data(world)
	if not validate_snapshot(value): return false
	var progress := PROGRESS.data(world)
	if not PROGRESS.validate_snapshot(progress): return false
	var transactions: Variant=wallet.get("transactions",{})
	if not transactions is Dictionary: return false
	# These three one-time receipts remain ordinary exact receipts; recurring
	# range compaction is neither needed nor applicable to cosmetic ownership.
	for key in transactions:
		if not str(key).begins_with("spend:"+RECEIPT_PREFIX): continue
		var identity := str(key).trim_prefix("spend:"+RECEIPT_PREFIX)
		if not CATALOG.has(identity) or int(CATALOG[identity].price)<=0: return false
		if not transactions[key] is Dictionary: return false
	for identity in IDS:
		var price := int(CATALOG[identity].price)
		if price==0: continue
		var receipt: Dictionary=RECEIPTS.lookup(wallet,"spend",RECEIPT_PREFIX+identity)
		var purchased: bool=identity in value.owned
		if purchased != (not receipt.is_empty()): return false
		if not purchased: continue
		if progress.wins.size()<int(CATALOG[identity].wins): return false
		if receipt.get("kind")!="spend" or receipt.get("item")!=RECEIPT_PREFIX+identity: return false
		var amount: Variant=receipt.get("amount")
		if typeof(amount) not in [TYPE_INT,TYPE_FLOAT] or float(amount)!=float(price): return false
	return true

static func select(world: Dictionary, economy, identity: String) -> Dictionary:
	return _apply(world,economy,identity,true)

static func purchase_and_equip(world: Dictionary, economy, identity: String) -> Dictionary:
	return select(world,economy,identity)

static func equip(world: Dictionary, economy, identity: String) -> Dictionary:
	return _apply(world,economy,identity,false)

static func _apply(world: Dictionary, economy, identity: String, allow_purchase: bool) -> Dictionary:
	if not CATALOG.has(identity): return _failure("unknown_style")
	if not validate_wallet(world,economy.snapshot()): return _failure("invalid_state")
	var value := data(world)
	var purchased: bool=identity not in value.owned
	if purchased and not allow_purchase: return _failure("not_owned")
	if not unlocked(world,identity): return _failure("locked")
	var price := int(CATALOG[identity].price) if purchased else 0
	if economy.balance<price: return _failure("insufficient_funds")
	# Every precondition is settled before debit; no await, callback or fallible
	# operation separates the wallet receipt from ownership in this world state.
	if purchased and not economy.spend(price,RECEIPT_PREFIX+identity): return _failure("transaction_refused")
	var changed: bool=purchased or value.selected!=identity
	if purchased: value.owned.append(identity)
	value.selected=identity
	if changed: world[KEY]=value
	return {"ok":true,"reason":"purchased" if purchased else "equipped","changed":changed,"purchased":purchased,"cost":price,"selected":identity}

static func _failure(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"changed":false,"purchased":false,"cost":0}
