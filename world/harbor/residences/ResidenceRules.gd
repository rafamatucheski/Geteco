class_name ResidenceRules
extends RefCounted

const SCHEMA_VERSION := 1
const TRADE_IN_RATE := 0.70


static func default_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"active_home": "",
		"stored_vehicle": {},
		"purchases": 0,
	}


static func normalize_state(value: Variant, properties: Dictionary) -> Dictionary:
	var result := default_state()
	if not (value is Dictionary):
		return result
	var source := value as Dictionary
	var active := String(source.get("active_home", ""))
	if properties.has(active):
		result["active_home"] = active
	var stored: Variant = source.get("stored_vehicle", {})
	if stored is Dictionary:
		result["stored_vehicle"] = (stored as Dictionary).duplicate(true)
	result["purchases"] = maxi(0, int(source.get("purchases", 0)))
	return result


static func purchase_quote(properties: Dictionary, current_id: String, target_id: String, money: int) -> Dictionary:
	if not properties.has(target_id):
		return {"valid": false, "reason": "unknown_property"}
	if current_id == target_id:
		return {"valid": false, "reason": "already_active"}
	var price := maxi(0, int(properties[target_id].get("price", 0)))
	var refund := 0
	if properties.has(current_id):
		refund = roundi(maxi(0, int(properties[current_id].get("price", 0))) * TRADE_IN_RATE)
	var due := maxi(0, price - refund)
	return {
		"valid": true,
		"target_id": target_id,
		"target_name": String(properties[target_id].get("name", target_id)),
		"current_id": current_id,
		"price": price,
		"refund": refund,
		"due": due,
		"money_before": maxi(0, money),
		"money_after": maxi(0, money) - due,
		"affordable": money >= due,
	}


static func apply_purchase(state: Dictionary, quote: Dictionary) -> Dictionary:
	if not bool(quote.get("valid", false)) or not bool(quote.get("affordable", false)):
		return state.duplicate(true)
	var result := state.duplicate(true)
	result["schema_version"] = SCHEMA_VERSION
	result["active_home"] = String(quote.get("target_id", ""))
	result["purchases"] = maxi(0, int(result.get("purchases", 0))) + 1
	if not (result.get("stored_vehicle", {}) is Dictionary):
		result["stored_vehicle"] = {}
	return result
