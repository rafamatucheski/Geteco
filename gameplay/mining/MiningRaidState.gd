extends RefCounted
const KEY := "mining_raid"
const RECEIPT := "remote_mine_smuggling_haul"
const CASH := 12000
static func defaults() -> Dictionary: return {"version":1,"escaped":false}
static func valid(value: Variant) -> bool:
	return value is Dictionary and value.size()==2 and value.get("version")==1 and value.get("escaped") is bool

static func valid_wallet(value: Variant, wallet: Dictionary) -> bool:
	if not valid(value): return false
	var receipt: Dictionary=preload("res://systems/economy/RecurringReceipts.gd").lookup(wallet,"reward",RECEIPT)
	if receipt.is_empty(): return not value.escaped
	return value.escaped and receipt.get("kind")=="reward" and receipt.get("item")==RECEIPT and receipt.get("amount")==CASH
