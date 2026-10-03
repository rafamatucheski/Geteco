extends RefCounted
const PRICE:=30
static func fresh() -> Dictionary:
	return {"version":1,"active":false,"inside":false,"serial":0,"receipt":""}
static func valid(value: Variant, wallet: Dictionary) -> bool:
	if not value is Dictionary or value.get("version")!=1: return false
	for key in ["active","inside"]:
		if not value.get(key) is bool: return false
	if typeof(value.get("serial")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.serial)) or float(value.serial)!=floorf(float(value.serial)) or value.serial<0 or value.serial>1000000: return false
	if not value.get("receipt") is String or value.receipt.length()>110: return false
	if value.serial==0: return not value.active and not value.inside and value.receipt.is_empty()
	if value.receipt!="mountain_zoo_%d"%int(value.serial): return false
	if value.active:
		var receipt: Dictionary=wallet.get("transactions",{}).get("spend:"+value.receipt,{})
		if receipt.get("amount")!=PRICE or receipt.get("kind")!="spend": return false
	return not value.inside or value.active
