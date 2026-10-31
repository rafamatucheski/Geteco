extends RefCounted
## História escrita do Harbor. O antigo livro canônico fica só como arquivo de save.
const VERSION := 1
const PRISON_YEARS := 8
const DESTINATION := "desert"
const KEYS := ["version","opening_seen","maciota_met","brother_route_found","act_two_available"]

static func fresh_snapshot() -> Dictionary:
	return {"version":VERSION,"opening_seen":false,"maciota_met":false,"brother_route_found":false,"act_two_available":false}

static func data(world_state: Dictionary) -> Dictionary:
	return world_state.get("harbor_story",fresh_snapshot()).duplicate(true)

static func mark_opening(world_state: Dictionary) -> bool:
	var value := data(world_state)
	if value.opening_seen: return false
	value.opening_seen = true
	world_state.harbor_story = value
	return true

static func mark_maciota(world_state: Dictionary) -> bool:
	var value := data(world_state)
	if value.maciota_met: return false
	value.maciota_met = true
	world_state.harbor_story = value
	return true

static func record_brother_route(world_state: Dictionary, mission_completed: bool) -> bool:
	if not mission_completed: return false
	var value := data(world_state)
	if not value.maciota_met or value.brother_route_found: return false
	value.brother_route_found = true
	value.act_two_available = true
	world_state.harbor_story = value
	return true

static func validate_snapshot(value: Dictionary) -> bool:
	if value.size() != KEYS.size() or value.get("version") != VERSION: return false
	for key in KEYS:
		if not value.has(key): return false
	for key in KEYS.slice(1):
		if not value[key] is bool: return false
	return value.act_two_available == value.brother_route_found and (not value.brother_route_found or value.maciota_met)
