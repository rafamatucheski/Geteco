extends RefCounted
## Independent side-quest ledger. Cargo rewards and expedition collectibles
## retain their own owners; these receipts only record completed discoveries.
const EVENTS := ["cargo_identified", "cargo_manifest", "cave_shelter", "vicente_note"]
const QUESTS := ["cobra_cargo", "vicente_trail"]
const CAVE := "mountain_mystery_cave"
const INTERACTION_RANGE := 1.65
const DEFAULT := {"version":1, "events":[], "receipts":[], "completed":[]}

static func fresh_snapshot() -> Dictionary:
	return DEFAULT.duplicate(true)

static func data(world_state: Dictionary) -> Dictionary:
	if not world_state.has("mountain_story"): return fresh_snapshot()
	var saved: Variant = world_state.mountain_story
	return saved.duplicate(true) if validate_snapshot(saved) else {}

static func next_event(saved: Dictionary) -> String:
	if not validate_snapshot(saved) or saved.events.size() == EVENTS.size(): return ""
	return EVENTS[saved.events.size()]

static func record(world_state: Dictionary, event: String, proof: Dictionary) -> bool:
	var saved := data(world_state)
	if saved.is_empty() or next_event(saved) != event or event not in EVENTS: return false
	if proof.get("region") != "mountain" or proof.get("place") != place_for(event): return false
	if proof.get("anchor") != ("cargo_plane" if place_for(event).is_empty() else CAVE): return false
	for key in ["alive", "on_foot", "reachable", "dialogue_complete"]:
		if not proof.get(key) is bool or proof[key] != true: return false
	var distance: Variant = proof.get("distance")
	if typeof(distance) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(distance)): return false
	if distance < 0 or distance > INTERACTION_RANGE: return false
	saved.events.append(event)
	saved.receipts.append("mountain_story:"+event)
	if event == "cargo_manifest": saved.completed.append(QUESTS[0])
	if event == "vicente_note": saved.completed.append(QUESTS[1])
	world_state.mountain_story = saved
	return true

static func place_for(event: String) -> String:
	return CAVE if event in ["cave_shelter", "vicente_note"] else ""

static func validate_snapshot(saved: Variant) -> bool:
	if not saved is Dictionary: return false
	var version: Variant = saved.get("version")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(version)) or version != 1: return false
	for key in ["events", "receipts", "completed"]:
		if not saved.get(key) is Array: return false
	if saved.events.size() > EVENTS.size() or saved.receipts.size() != saved.events.size(): return false
	for index in saved.events.size():
		if saved.events[index] != EVENTS[index] or saved.receipts[index] != "mountain_story:"+EVENTS[index]: return false
	var expected: Array = []
	if saved.events.size() >= 2: expected.append(QUESTS[0])
	if saved.events.size() == EVENTS.size(): expected.append(QUESTS[1])
	return saved.completed == expected
