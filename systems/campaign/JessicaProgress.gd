extends RefCounted
## Narrative encounters are recorded individually; there is no affection score.
## World adapters supply verified robbery, boarding and physical return events.
const CAR_ID := "jessica_jetta_gli"
const PHASES := ["", "accepted", "escaped", "riding", "returned", "complete"]
const DEFAULT := {"version":1, "met":false, "bank_phase":"", "bank_cycle":-1,
	"baseline_mask":0, "haul_mask":0, "haul_receipt":"", "bank_complete":false,
	"failure":"", "conversations":[]}

static func fresh_snapshot() -> Dictionary:
	return DEFAULT.duplicate(true)

static func data(world_state: Dictionary) -> Dictionary:
	return world_state.get("jessica", DEFAULT).duplicate(true)

static func mark_met(world_state: Dictionary) -> bool:
	var value := data(world_state)
	if value.met: return false
	value.met = true
	value.conversations.append("first_meeting")
	world_state.jessica = value
	return true

static func bank_mask(bank: Dictionary) -> int:
	return int(bank.get("bank_cash0",false)) + int(bank.get("bank_cash1",false))*2 + int(bank.get("bank_cash2",false))*4

static func begin_bank_job(world_state: Dictionary, bank: Dictionary) -> bool:
	var value := data(world_state)
	if value.bank_complete or not value.bank_phase.is_empty() or not _whole(bank.get("bank_cycle"),0,10000000): return false
	for key in ["bank_cash0", "bank_cash1", "bank_cash2", "bank_failed", "bank_alarm"]:
		if not bank.get(key) is bool: return false
	if bank.bank_failed or bank.bank_alarm or bank.get("aftermath","") != "" or bank_mask(bank) == 7: return false
	if not _whole(bank.get("bank_pending"),0,15000) or bank.bank_pending != 0: return false
	if not value.met:
		value.met = true
		value.conversations.append("first_meeting")
	value.bank_phase = "accepted"
	value.bank_cycle = int(bank.bank_cycle)
	value.baseline_mask = bank_mask(bank)
	value.haul_mask = 0
	value.haul_receipt = ""
	value.failure = ""
	world_state.jessica = value
	return true

static func report_world_event(world_state: Dictionary, event: String, proof: Dictionary) -> bool:
	var value := data(world_state)
	if not validate_snapshot(value): return false
	match event:
		"bank_escaped":
			if value.bank_phase != "accepted": return false
			if not _whole(proof.get("cycle"),0,10000000) or int(proof.cycle) != value.bank_cycle: return false
			if not _whole(proof.get("mask"),1,7): return false
			var mask := int(proof.mask)
			if (mask & int(value.baseline_mask)) != int(value.baseline_mask) or (mask & (7 ^ int(value.baseline_mask))) == 0: return false
			var receipt := "bank_haul:%d:%d" % [value.bank_cycle,mask]
			if proof.get("receipt") != receipt or proof.get("receipt_paid") != true: return false
			if proof.get("alive") != true or proof.get("outside_bank") != true or proof.get("bank_failed") != false: return false
			value.haul_mask = mask
			value.haul_receipt = receipt
			value.bank_phase = "escaped"
		"getaway_boarded":
			if value.bank_phase != "escaped" or proof.get("vehicle_id") != CAR_ID: return false
			if proof.get("alive") != true or proof.get("passenger") != true or proof.get("door_clear") != true: return false
			value.bank_phase = "riding"
		"safe_return":
			if value.bank_phase != "riding" or proof.get("vehicle_id") != CAR_ID: return false
			if proof.get("alive") != true or proof.get("route_finished") != true or proof.get("safe_exit") != true or proof.get("exterior") != true: return false
			if proof.get("inside_courtyard") != true: return false
			if not _whole(proof.get("wanted"),0,6) or proof.wanted != 0: return false
			if not _number(proof.get("travelled"),25,10000) or not _number(proof.get("safe_distance"),0,12): return false
			value.bank_phase = "returned"
		"bank_debrief":
			if value.bank_phase != "returned" or proof.get("at_jessica") != true or proof.get("alive") != true or proof.get("wanted") != 0: return false
			value.bank_phase = "complete"
			value.bank_complete = true
			value.conversations.append("bank_debrief")
		_:
			return false
	world_state.jessica = value
	return true

static func cancel_attempt(world_state: Dictionary, reason: String) -> bool:
	var value := data(world_state)
	if value.bank_phase in ["", "complete"]: return false
	if reason.is_empty() or reason.length() > 80: return false
	value.bank_phase = ""
	value.bank_cycle = -1
	value.baseline_mask = 0
	value.haul_mask = 0
	value.haul_receipt = ""
	value.failure = reason
	world_state.jessica = value
	return true

static func validate_snapshot(value: Dictionary) -> bool:
	if not _whole(value.get("version"),1,1): return false
	if not value.get("met") is bool or not value.get("bank_complete") is bool: return false
	if value.get("bank_phase") not in PHASES: return false
	if not _whole(value.get("bank_cycle"),-1,10000000): return false
	for key in ["baseline_mask", "haul_mask"]:
		if not _whole(value.get(key),0,7): return false
	if not value.get("haul_receipt") is String or not value.get("failure") is String or value.failure.length() > 80: return false
	if not value.get("conversations") is Array: return false
	var seen := {}
	for encounter in value.conversations:
		if encounter not in ["first_meeting", "bank_debrief"] or seen.has(encounter): return false
		seen[encounter] = true
	if value.met != seen.has("first_meeting") or value.bank_complete != seen.has("bank_debrief"): return false
	if value.bank_complete != (value.bank_phase == "complete"): return false
	if value.bank_phase.is_empty():
		return value.bank_cycle == -1 and value.baseline_mask == 0 and value.haul_mask == 0 and value.haul_receipt.is_empty()
	if not value.met or value.bank_cycle < 0 or value.baseline_mask == 7 or not value.failure.is_empty(): return false
	if value.bank_phase == "accepted": return value.haul_mask == 0 and value.haul_receipt.is_empty()
	if (int(value.haul_mask) & int(value.baseline_mask)) != int(value.baseline_mask): return false
	if (int(value.haul_mask) & (7 ^ int(value.baseline_mask))) == 0: return false
	return value.haul_receipt == "bank_haul:%d:%d" % [value.bank_cycle,value.haul_mask]

static func _whole(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and float(value) == floorf(float(value))

static func _number(value: Variant, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) >= low and float(value) <= high
