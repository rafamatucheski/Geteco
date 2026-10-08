extends RefCounted
## Ephemeral, entry-driven state. The hallucination is never a save location.
const PLACE := "harbor_haunted_house"
const EXTREME := 90.0
const MIN_DURATION := 10.0
const MAX_DURATION := 15.0
var pending_entry := 0
var consumed_entry := 0
var active := false
var duration := 0.0
var elapsed := 0.0

static func eligible(place_id: String, alcohol: float, restored := false) -> bool:
	return not restored and place_id==PLACE and is_finite(alcohol) and alcohol>=EXTREME and alcohol<=100.0

func arm_entry(entry: int, place_id: String, alcohol: float, restored := false) -> bool:
	if active or pending_entry!=0 or entry<=0 or entry==consumed_entry or not eligible(place_id,alcohol,restored): return false
	pending_entry=entry
	return true

func start(entry: int, seconds: float) -> bool:
	if active or entry!=pending_entry or entry<=0 or not is_finite(seconds) or seconds<MIN_DURATION or seconds>MAX_DURATION: return false
	consumed_entry=entry
	pending_entry=0
	active=true
	duration=seconds
	elapsed=0.0
	return true

func tick(delta: float, paused := false) -> bool:
	if not active or paused or not is_finite(delta) or delta<=0.0: return false
	elapsed=minf(duration,elapsed+delta)
	return elapsed>=duration

func cancel() -> void:
	# Clearing the pending entry does not permit the same already-consumed entry.
	pending_entry=0
	active=false
	elapsed=0.0
	duration=0.0

func snapshot() -> Dictionary:
	return {"pending_entry":pending_entry,"consumed_entry":consumed_entry,"active":active,"duration":duration,"elapsed":elapsed}
