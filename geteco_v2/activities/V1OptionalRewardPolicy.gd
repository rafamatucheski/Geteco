extends RefCounted
## Stateless settlement policy for the optional ski races connected in V1.
##
## V1 (`world/mountain_pass/SkiRaceController.gd:_finish`) pays the course
## reward after every finish and adds the record bonus whenever the new time is
## better.  Receipt serials are derived from Economy transactions so this can
## be integrated without adding another field to the persisted activity state.

const MAX_RECEIPT_SERIAL := 10000000

static func ski_settlement(course_id: String, spec: Dictionary, elapsed: float, previous_best: Variant, transactions: Dictionary) -> Dictionary:
	if course_id.is_empty() or not is_finite(elapsed) or elapsed <= 0.0 or elapsed > 600.0:
		return {"ok":false,"reason":"invalid_result"}
	if not spec.has("reward") or not spec.has("bonus"):
		return {"ok":false,"reason":"invalid_course"}
	var base_reward := int(spec.reward)
	var record_bonus := int(spec.bonus)
	if base_reward < 0 or record_bonus < 0:
		return {"ok":false,"reason":"invalid_course"}
	var record := previous_best == null
	if previous_best != null:
		if typeof(previous_best) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(previous_best)) or float(previous_best) <= 0.0:
			return {"ok":false,"reason":"invalid_previous_best"}
		record = elapsed < float(previous_best)
	var serial := _next_run_serial(transactions,course_id)
	if serial < 1:
		return {"ok":false,"reason":"receipt_limit"}
	return {
		"ok":true,
		"course_id":course_id,
		"elapsed":elapsed,
		"record":record,
		"amount":base_reward+(record_bonus if record else 0),
		"finish_receipt":"ski_finish:%s:%d"%[course_id,serial],
		"finish_amount":base_reward,
		"record_receipt":"ski_record:%s:%d"%[course_id,serial],
		"record_amount":record_bonus if record else 0,
	}

static func apply_ski_settlement(economy: RefCounted, settlement: Dictionary) -> bool:
	if economy == null or settlement.get("ok") != true:
		return false
	var before: Dictionary = economy.snapshot()
	if not economy.grant_reward(str(settlement.finish_receipt),int(settlement.finish_amount)):
		return false
	if int(settlement.record_amount) > 0 and not economy.grant_reward(str(settlement.record_receipt),int(settlement.record_amount)):
		economy.restore_snapshot(before)
		return false
	return true

static func _next_run_serial(transactions: Dictionary, course_id: String) -> int:
	var highest := 0
	for receipt in ["ski_finish:"+course_id+":","ski_record:"+course_id+":"]:
		var stored_prefix: String = "reward:"+str(receipt)
		for key_value in transactions.keys():
			var key := str(key_value)
			if not key.begins_with(stored_prefix):
				continue
			var suffix := key.trim_prefix(stored_prefix)
			if suffix.is_valid_int():
				highest = maxi(highest,suffix.to_int())
	if highest >= MAX_RECEIPT_SERIAL:
		return -1
	return highest+1
