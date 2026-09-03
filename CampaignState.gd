extends Node

## Persistent, data-driven campaign state.  This autoload intentionally owns
## no scene nodes and never calls Player, police, shops, or MissionManager.
## Scene-specific adapters can consume its data when those systems are ready.

signal campaign_started()
signal campaign_stage_changed(previous_stage: StringName, current_stage: StringName)
signal region_unlocked(region_id: StringName)
signal territory_unlocked(territory_id: StringName)
signal campaign_flag_changed(flag_id: StringName, enabled: bool)

const DATA_PATH := "res://data/campaign/campaign_v1.json"
const INITIAL_STAGE: StringName = &"prologue_call"

var campaign_data: Dictionary = {}
var current_stage: StringName = INITIAL_STAGE
var unlocked_regions: Array[StringName] = []
var unlocked_territories: Array[StringName] = []
var campaign_flags: Dictionary = {}
var completed_beats: Array[StringName] = []


func _ready() -> void:
	load_campaign_data()
	reset_campaign()


func load_campaign_data() -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Campaign data missing: %s" % DATA_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Campaign data must be a JSON object: %s" % DATA_PATH)
		return false
	campaign_data = parsed as Dictionary
	return _validate_campaign_data()


func reset_campaign() -> void:
	current_stage = INITIAL_STAGE
	completed_beats.clear()
	campaign_flags.clear()
	unlocked_regions.clear()
	unlocked_territories.clear()
	var central := StringName("central")
	unlock_region(central)
	for territory_data in get_territories_for_region(central):
		if bool(territory_data.get("available_at_start", false)):
			unlock_territory(StringName(territory_data.get("id", "")))
	campaign_started.emit()


func get_current_beat() -> Dictionary:
	return get_beat(current_stage)


func get_beat(beat_id: StringName) -> Dictionary:
	for beat_data in campaign_data.get("beats", []):
		if StringName(beat_data.get("id", "")) == beat_id:
			return (beat_data as Dictionary).duplicate(true)
	return {}


func can_advance_to(beat_id: StringName) -> bool:
	var target := get_beat(beat_id)
	if target.is_empty():
		return false
	for requirement in target.get("requires_beats", []):
		if not completed_beats.has(StringName(requirement)):
			return false
	return true


func advance_to(beat_id: StringName) -> bool:
	if not can_advance_to(beat_id):
		return false
	var previous := current_stage
	current_stage = beat_id
	campaign_stage_changed.emit(previous, current_stage)
	return true


func complete_current_beat() -> bool:
	var current := get_current_beat()
	if current.is_empty():
		return false
	_apply_beat_unlocks(current)
	if not completed_beats.has(current_stage):
		completed_beats.append(current_stage)
	var next_id := StringName(current.get("next_beat", ""))
	if next_id.is_empty():
		return true
	return advance_to(next_id)


func set_campaign_flag(flag_id: StringName, enabled: bool = true) -> void:
	if flag_id.is_empty():
		return
	campaign_flags[flag_id] = enabled
	campaign_flag_changed.emit(flag_id, enabled)


func has_campaign_flag(flag_id: StringName) -> bool:
	return bool(campaign_flags.get(flag_id, false))


func unlock_region(region_id: StringName) -> bool:
	if region_id.is_empty() or unlocked_regions.has(region_id):
		return false
	if get_region(region_id).is_empty():
		return false
	unlocked_regions.append(region_id)
	region_unlocked.emit(region_id)
	return true


func unlock_territory(territory_id: StringName) -> bool:
	if territory_id.is_empty() or unlocked_territories.has(territory_id):
		return false
	var territory := get_territory(territory_id)
	if territory.is_empty():
		return false
	unlock_region(StringName(territory.get("region", "")))
	unlocked_territories.append(territory_id)
	territory_unlocked.emit(territory_id)
	return true


func get_region(region_id: StringName) -> Dictionary:
	for region_data in campaign_data.get("regions", []):
		if StringName(region_data.get("id", "")) == region_id:
			return (region_data as Dictionary).duplicate(true)
	return {}


func get_territory(territory_id: StringName) -> Dictionary:
	for territory_data in campaign_data.get("territories", []):
		if StringName(territory_data.get("id", "")) == territory_id:
			return (territory_data as Dictionary).duplicate(true)
	return {}


func get_territories_for_region(region_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for territory_data in campaign_data.get("territories", []):
		if StringName(territory_data.get("region", "")) == region_id:
			result.append((territory_data as Dictionary).duplicate(true))
	return result


## Save adapters may serialize this dictionary to their own slot format later.
func to_save_data() -> Dictionary:
	return {
		"schema_version": int(campaign_data.get("schema_version", 1)),
		"current_stage": String(current_stage),
		"completed_beats": completed_beats.map(func(value): return String(value)),
		"unlocked_regions": unlocked_regions.map(func(value): return String(value)),
		"unlocked_territories": unlocked_territories.map(func(value): return String(value)),
		"campaign_flags": campaign_flags.duplicate(true),
	}


func restore_from_save(save_data: Dictionary) -> bool:
	if campaign_data.is_empty() and not load_campaign_data():
		return false
	var restored_stage := StringName(save_data.get("current_stage", INITIAL_STAGE))
	if get_beat(restored_stage).is_empty():
		return false
	current_stage = restored_stage
	completed_beats.clear()
	for beat_id in save_data.get("completed_beats", []):
		if not get_beat(StringName(beat_id)).is_empty():
			completed_beats.append(StringName(beat_id))
	unlocked_regions.clear()
	for region_id in save_data.get("unlocked_regions", []):
		unlock_region(StringName(region_id))
	unlocked_territories.clear()
	for territory_id in save_data.get("unlocked_territories", []):
		unlock_territory(StringName(territory_id))
	campaign_flags.clear()
	var restored_flags: Dictionary = save_data.get("campaign_flags", {})
	for flag_id in restored_flags:
		set_campaign_flag(StringName(flag_id), bool(restored_flags[flag_id]))
	return true


func _apply_beat_unlocks(beat_data: Dictionary) -> void:
	for region_id in beat_data.get("unlocks_regions", []):
		unlock_region(StringName(region_id))
	for territory_id in beat_data.get("unlocks_territories", []):
		unlock_territory(StringName(territory_id))
	for flag_id in beat_data.get("sets_flags", []):
		set_campaign_flag(StringName(flag_id), true)
	for flag_id in beat_data.get("clears_flags", []):
		set_campaign_flag(StringName(flag_id), false)


func _validate_campaign_data() -> bool:
	if int(campaign_data.get("schema_version", 0)) != 1:
		push_error("Unsupported campaign schema")
		return false
	var beats: Array = campaign_data.get("beats", [])
	var regions: Array = campaign_data.get("regions", [])
	var territories: Array = campaign_data.get("territories", [])
	if beats.size() != 9 or regions.size() != 5 or territories.size() != 9:
		push_error("Campaign requires 9 beats, 5 regions and 9 territories")
		return false
	if get_beat(INITIAL_STAGE).is_empty() or get_region(&"central").is_empty():
		push_error("Campaign is missing its prologue or central region")
		return false
	var beat_ids: Dictionary = {}
	for beat_data in beats:
		var beat_id := StringName(beat_data.get("id", ""))
		if beat_id.is_empty() or beat_ids.has(beat_id):
			push_error("Campaign contains an empty or duplicated beat id")
			return false
		beat_ids[beat_id] = true
	for beat_data in beats:
		var next_id := StringName(beat_data.get("next_beat", ""))
		if not next_id.is_empty() and not beat_ids.has(next_id):
			push_error("Campaign beat points to an unknown next beat: %s" % next_id)
			return false
		for requirement in beat_data.get("requires_beats", []):
			if not beat_ids.has(StringName(requirement)):
				push_error("Campaign beat has an unknown prerequisite: %s" % requirement)
				return false
	return true
