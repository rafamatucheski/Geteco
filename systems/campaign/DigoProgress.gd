extends RefCounted
## Digo's relationship follows the player between maps; lessons are optional.
## Desert completion must be called by the future race's verified finish event.
const DEFAULT := {"version":1,"met":false,"lesson_completed":false,"desert_raced":false,"friend":false}
const DESERT_RACE_ID := "digo_desert_race"
const WORKSHOP_ID := "digo_workshop"

static func data(world_state: Dictionary) -> Dictionary:
	return world_state.get("digo",DEFAULT).duplicate(true)

static func mark_met(world_state: Dictionary) -> bool:
	var value := data(world_state)
	if value.met: return false
	value.met = true
	world_state.digo = value
	return true

static func complete_lesson(world_state: Dictionary) -> bool:
	var value := data(world_state)
	if value.lesson_completed: return false
	value.met = true
	value.lesson_completed = true
	world_state.digo = value
	return true

static func complete_desert_race(world_state: Dictionary, race_id: String, finished: bool) -> bool:
	if race_id != DESERT_RACE_ID or not finished: return false
	var value := data(world_state)
	if value.desert_raced: return false
	value.met = true
	value.desert_raced = true
	value.friend = true
	world_state.digo = value
	return true

static func workshop_unlocked(world_state: Dictionary) -> bool:
	var value := data(world_state)
	return value.desert_raced and value.friend

static func validate_snapshot(value: Dictionary) -> bool:
	if typeof(value.get("version")) not in [TYPE_INT,TYPE_FLOAT] or value.version != 1: return false
	for key in ["met","lesson_completed","desert_raced","friend"]:
		if not value.get(key) is bool: return false
	if (value.lesson_completed or value.desert_raced) and not value.met: return false
	return value.friend == value.desert_raced
