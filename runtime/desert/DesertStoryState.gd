extends RefCounted
## Act two checkpoint ledger. Dialogues, physical clues and race results own events.
const FLAGS := ["arrived","met_vicente","cargo_found","bank_proof","jessica_met","delivered"]
static func defaults() -> Dictionary:
	return {"version":1,"arrived":false,"met_vicente":false,"cargo_found":false,"bank_proof":false,"jessica_met":false,"delivered":false}
static func data(world_state: Dictionary) -> Dictionary:
	return world_state.get("desert_story",defaults()).duplicate(true)
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	for key in FLAGS:
		if not value.get(key) is bool: return false
	if value.met_vicente and not value.arrived: return false
	if value.cargo_found and not value.met_vicente: return false
	if value.bank_proof and not value.cargo_found: return false
	if value.delivered and (not value.bank_proof or not value.jessica_met): return false
	return true
static func mark(world_state: Dictionary, flag: String) -> bool:
	if flag not in FLAGS: return false
	var next := data(world_state)
	if next[flag]: return false
	next[flag] = true
	if not valid(next): return false
	world_state.desert_story = next
	return true
