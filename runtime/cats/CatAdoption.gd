extends RefCounted
## Persistent identities and supplies; the scene adapter owns physical access.
const CAT_IDS: Array[String] = ["cat_01", "cat_02", "cat_03", "cat_04", "cat_05", "cat_06", "cat_07", "cat_08", "cat_09", "cat_10"]
const FURNITURE := {
	"bed": {"label":"Caminha", "price":120, "limit":10},
	"ball": {"label":"Bolinha", "price":35, "limit":3},
	"scratcher": {"label":"Arranhador", "price":180, "limit":2},
}

static func default_state() -> Dictionary:
	return {"adopted":[], "furniture":{"bed":0, "ball":0, "scratcher":0}}

static func validate(value: Variant, has_home: bool) -> bool:
	if not value is Dictionary: return false
	if not value.get("adopted") is Array or not value.get("furniture") is Dictionary: return false
	if value.adopted.size() > CAT_IDS.size(): return false
	var seen := {}
	for id in value.adopted:
		if not id is String or id not in CAT_IDS or seen.has(id): return false
		seen[id] = true
	if not has_home and not seen.is_empty(): return false
	if value.furniture.size() != FURNITURE.size(): return false
	for id in FURNITURE:
		var amount: Variant = value.furniture.get(id)
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT]: return false
		if not is_finite(float(amount)) or float(amount) != floorf(float(amount)): return false
		if float(amount) < 0 or float(amount) > int(FURNITURE[id].limit): return false
		if not has_home and float(amount) != 0: return false
	return true

static func normalize_validated(value: Dictionary) -> Dictionary:
	var result := default_state()
	result.adopted = value.adopted.duplicate()
	for id in FURNITURE: result.furniture[id] = int(value.furniture[id])
	return result

static func adopt(state: Dictionary, id: String, has_home: bool) -> bool:
	if not has_home or id not in CAT_IDS or id in state.adopted: return false
	state.adopted.append(id)
	return true

static func purchase(state: Dictionary, id: String, has_home: bool, economy) -> bool:
	if not has_home or not FURNITURE.has(id) or economy == null: return false
	var count := int(state.furniture[id])
	if count >= int(FURNITURE[id].limit): return false
	# Counts never reset when moving house, keeping receipts unique forever.
	if not economy.spend(int(FURNITURE[id].price), "cat_furniture:%s:%d" % [id, count + 1]): return false
	state.furniture[id] = count + 1
	return true
