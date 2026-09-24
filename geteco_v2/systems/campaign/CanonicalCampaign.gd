extends RefCounted
## Canonical nine-beat data ledger, separate from the six-mission Harbor runtime.
## This does not instantiate cutscenes, pursuits or contracts by itself.
const PATH := "res://data/campaign/campaign_v1.json"
var catalog: Dictionary = {}
var _data := {"version": 1, "current_stage": "prologue_call", "completed_beats": [],
	"completed_contracts": [], "flags": {}, "regions": ["central"], "territories": ["mercado_velho"]}

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary: catalog = parsed

func snapshot() -> Dictionary:
	return _data.duplicate(true)

func current_beat() -> Dictionary:
	return _find("beats", _data.current_stage)

func objective() -> String:
	return str(current_beat().get("objective", ""))

func complete_beat(event_id: String) -> bool:
	var beat := current_beat()
	if beat.is_empty() or event_id != str(beat.id) + "_completed" or _data.completed_beats.has(beat.id): return false
	for requirement in beat.get("requires_beats", []):
		if not _data.completed_beats.has(requirement): return false
	if beat.id == "contracts_arc":
		for contract in catalog.district_one_contracts:
			if contract.get("story_required", false) and not _data.completed_contracts.has(contract.id): return false
	_data.completed_beats.append(beat.id)
	_apply(beat)
	if str(beat.get("next_beat", "")) != "": _data.current_stage = beat.next_beat
	return true

func complete_contract(id: String, economy: RefCounted) -> bool:
	if _data.current_stage != "contracts_arc" or _data.completed_contracts.has(id): return false
	var contract := _find("district_one_contracts", id)
	if contract.is_empty(): return false
	# Scene contract adapter must verify the original theft/delivery conditions.
	if not economy.grant_reward("canonical_contract:" + id, int(contract.reward)): return false
	_data.completed_contracts.append(id)
	_apply(contract)
	return true

func _apply(definition: Dictionary) -> void:
	for id in definition.get("sets_flags", []): _data.flags[id] = true
	for id in definition.get("clears_flags", []): _data.flags[id] = false
	for id in definition.get("unlocks_regions", []):
		if not _data.regions.has(id): _data.regions.append(id)
	for id in definition.get("unlocks_territories", []):
		if not _data.territories.has(id): _data.territories.append(id)

func _find(group: String, id: String) -> Dictionary:
	for entry in catalog.get(group, []):
		if entry.id == id: return entry.duplicate(true)
	return {}

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	_data = data.duplicate(true)
	_data.version = 1
	return true

func validate_snapshot(data: Dictionary) -> bool:
	for key in ["version", "current_stage", "completed_beats", "completed_contracts", "flags", "regions", "territories"]:
		if not data.has(key): return false
	if typeof(data.version) not in [TYPE_INT, TYPE_FLOAT] or float(data.version) != 1.0: return false
	if not data.current_stage is String or _find("beats", data.current_stage).is_empty() or not data.flags is Dictionary: return false
	for key in ["completed_beats", "completed_contracts", "regions", "territories"]:
		if not data[key] is Array: return false
		var seen := {}
		for id in data[key]:
			if not id is String or seen.has(id): return false
			seen[id] = true
	if data.completed_beats.size() > catalog.beats.size(): return false
	for i in data.completed_beats.size():
		if data.completed_beats[i] != catalog.beats[i].id: return false
	var stage_index := mini(data.completed_beats.size(), catalog.beats.size() - 1)
	if data.current_stage != catalog.beats[stage_index].id: return false
	for id in data.completed_contracts:
		if _find("district_one_contracts", id).is_empty(): return false
	if not data.completed_contracts.is_empty() and not data.completed_beats.has("garage_and_contracts"): return false
	if data.completed_beats.has("contracts_arc"):
		for contract in catalog.district_one_contracts:
			if contract.get("story_required", false) and not data.completed_contracts.has(contract.id): return false
	# Rebuild derived flags/unlocks to prevent mutually inconsistent snapshots.
	var expected := {"flags": {}, "regions": ["central"], "territories": ["mercado_velho"]}
	for group in ["completed_beats", "completed_contracts"]:
		for id in data[group]:
			var definition := _find("beats" if group == "completed_beats" else "district_one_contracts", id)
			for flag in definition.get("sets_flags", []): expected.flags[flag] = true
			for flag in definition.get("clears_flags", []): expected.flags[flag] = false
			for region in definition.get("unlocks_regions", []):
				if not expected.regions.has(region): expected.regions.append(region)
			for territory in definition.get("unlocks_territories", []):
				if not expected.territories.has(territory): expected.territories.append(territory)
	return data.flags == expected.flags and data.regions == expected.regions and data.territories == expected.territories
