extends RefCounted
static var totals := {}
static var self_totals := {}
static var peaks := {}
static var calls := {}
static var children: Array[int] = []
static func begin() -> int:
	children.append(0)
	return Time.get_ticks_usec()
static func end(label: String, started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	var nested: int = children.pop_back()
	if not children.is_empty(): children[-1] += elapsed
	totals[label] = int(totals.get(label, 0)) + elapsed
	self_totals[label] = int(self_totals.get(label, 0)) + elapsed - nested
	peaks[label] = maxi(int(peaks.get(label, 0)), elapsed)
	calls[label] = int(calls.get(label, 0)) + 1
static func take() -> Dictionary:
	var result := {"us":totals, "self_us":self_totals, "peak_us":peaks, "calls":calls}
	totals = {}; self_totals = {}; peaks = {}; calls = {}
	return result
