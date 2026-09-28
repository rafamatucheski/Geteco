extends RefCounted
## Estado persistente e isolado da rede secreta opcional.
##
## O consumidor e responsavel por verificar marcos da campanha, apresentar a UI,
## validar o numero digitado no keypad e publicar snapshot() no world_state.
## Este modulo registra apenas fatos conquistados e suas dependencias causais.

const VERSION := 1

const FRAGMENT_IDS := [
	"map_village_fold",
	"map_drainage_grid",
	"map_service_tunnel",
	"map_pump_station",
	"map_power_branch",
	"map_sealed_annex",
]

const KEYPAD_CLUE_IDS := [
	"keypad_invoice",
	"keypad_house_plaque",
	"keypad_radio_frequency",
	"keypad_service_stamp",
]

const POWER_NODE_IDS := [
	"power_main",
	"power_drainage",
	"power_sealed_sector",
]

const ROUTE_IDS := [
	"route_village_house",
	"route_harbor_sewer",
	"route_south_port_drain",
	"route_mountain_outfall",
]

const AUDIO_IDS := [
	"audio_vicente_field",
	"audio_maintenance_shift",
	"audio_blackout",
	"audio_sealed_sector",
]

const LAB_CLUE_IDS := [
	"lab_access_badge",
	"lab_power_report",
	"lab_incident_photo",
]

const SNAPSHOT_KEYS := [
	"version",
	"dossier_received",
	"fragments",
	"keypad_clues",
	"house_discovered",
	"keypad_unlocked",
	"headquarters_discovered",
	"power_nodes",
	"routes",
	"audio_logs",
	"lab_clues",
	"sealed_sector_discovered",
	"final_door_unlocked",
]

const POWER_REQUIREMENTS := {
	"power_main":"",
	"power_drainage":"power_main",
	"power_sealed_sector":"power_main",
}

const ROUTE_REQUIREMENTS := {
	"route_village_house":"power_main",
	"route_harbor_sewer":"power_drainage",
	"route_south_port_drain":"power_drainage",
	"route_mountain_outfall":"power_drainage",
}

var data: Dictionary = fresh_snapshot()


static func fresh_snapshot() -> Dictionary:
	return {
		"version":VERSION,
		"dossier_received":false,
		"fragments":[],
		"keypad_clues":[],
		"house_discovered":false,
		"keypad_unlocked":false,
		"headquarters_discovered":false,
		"power_nodes":[],
		"routes":[],
		"audio_logs":[],
		"lab_clues":[],
		"sealed_sector_discovered":false,
		"final_door_unlocked":false,
	}


func receive_dossier() -> bool:
	if data.dossier_received:
		return false
	data.dossier_received = true
	return true


func collect_fragment(id: Variant) -> bool:
	return _append_known("fragments", id, FRAGMENT_IDS)


func discover_keypad_clue(id: Variant) -> bool:
	return _append_known("keypad_clues", id, KEYPAD_CLUE_IDS)


func discover_house() -> bool:
	if data.house_discovered:
		return false
	data.house_discovered = true
	return true


func can_unlock_keypad() -> bool:
	return data.house_discovered and _has_every(data.keypad_clues, KEYPAD_CLUE_IDS)


func unlock_keypad() -> bool:
	if data.keypad_unlocked or not can_unlock_keypad():
		return false
	data.keypad_unlocked = true
	return true


func discover_headquarters() -> bool:
	if data.headquarters_discovered or not data.keypad_unlocked:
		return false
	data.headquarters_discovered = true
	return true


func activate_power_node(id: Variant) -> bool:
	if not data.headquarters_discovered or not id is String or not POWER_NODE_IDS.has(id):
		return false
	if data.power_nodes.has(id):
		return false
	var requirement: String = POWER_REQUIREMENTS[id]
	if not requirement.is_empty() and not data.power_nodes.has(requirement):
		return false
	data.power_nodes.append(id)
	return true


func activate_route(id: Variant) -> bool:
	if not data.headquarters_discovered or not id is String or not ROUTE_IDS.has(id):
		return false
	if data.routes.has(id):
		return false
	var power_id: String = ROUTE_REQUIREMENTS[id]
	if not data.power_nodes.has(power_id):
		return false
	data.routes.append(id)
	return true


func discover_audio_log(id: Variant) -> bool:
	return _append_known("audio_logs", id, AUDIO_IDS)


func discover_lab_clue(id: Variant) -> bool:
	return _append_known("lab_clues", id, LAB_CLUE_IDS)


func discover_sealed_sector() -> bool:
	if data.sealed_sector_discovered or not data.headquarters_discovered:
		return false
	data.sealed_sector_discovered = true
	return true


func can_unlock_final_door() -> bool:
	# Quatro dígitos do cofre: três indícios do laboratório e a fita do setor lacrado.
	return data.sealed_sector_discovered \
		and data.power_nodes.has("power_sealed_sector") \
		and data.audio_logs.has("audio_sealed_sector") \
		and _has_every(data.lab_clues, LAB_CLUE_IDS)


func unlock_final_door() -> bool:
	if data.final_door_unlocked or not can_unlock_final_door():
		return false
	data.final_door_unlocked = true
	return true


func has_fragment(id: String) -> bool:
	return data.fragments.has(id)


func has_keypad_clue(id: String) -> bool:
	return data.keypad_clues.has(id)


func has_power_node(id: String) -> bool:
	return data.power_nodes.has(id)


func has_route(id: String) -> bool:
	return data.routes.has(id)


func has_audio_log(id: String) -> bool:
	return data.audio_logs.has(id)


func has_lab_clue(id: String) -> bool:
	return data.lab_clues.has(id)


func can_travel(origin_route: String, destination_route: String) -> bool:
	return origin_route != destination_route \
		and ROUTE_IDS.has(origin_route) \
		and ROUTE_IDS.has(destination_route) \
		and data.routes.has(origin_route) \
		and data.routes.has(destination_route)


func all_fragments_found() -> bool:
	return _has_every(data.fragments, FRAGMENT_IDS)


func progress_summary() -> Dictionary:
	return {
		"dossier_received":data.dossier_received,
		"fragments_found":data.fragments.size(),
		"fragments_total":FRAGMENT_IDS.size(),
		"keypad_clues_found":data.keypad_clues.size(),
		"keypad_clues_total":KEYPAD_CLUE_IDS.size(),
		"house_discovered":data.house_discovered,
		"keypad_unlocked":data.keypad_unlocked,
		"headquarters_discovered":data.headquarters_discovered,
		"routes_active":data.routes.size(),
		"routes_total":ROUTE_IDS.size(),
		"audio_logs_found":data.audio_logs.size(),
		"audio_logs_total":AUDIO_IDS.size(),
		"lab_clues_found":data.lab_clues.size(),
		"lab_clues_total":LAB_CLUE_IDS.size(),
		"sealed_sector_discovered":data.sealed_sector_discovered,
		"final_door_unlocked":data.final_door_unlocked,
	}


func snapshot() -> Dictionary:
	return data.duplicate(true)


func restore_snapshot(saved: Dictionary) -> bool:
	if not validate_snapshot(saved):
		return false
	data = saved.duplicate(true)
	return true


static func validate_snapshot(saved: Dictionary) -> bool:
	# JSON round trips may decode whole numbers as float; equality still enforces
	# the only supported schema version without rejecting a valid disk snapshot.
	if not _has_exact_keys(saved, SNAPSHOT_KEYS) or typeof(saved.version) not in [TYPE_INT,TYPE_FLOAT] or saved.version != VERSION:
		return false
	for key in [
		"dossier_received",
		"house_discovered",
		"keypad_unlocked",
		"headquarters_discovered",
		"sealed_sector_discovered",
		"final_door_unlocked",
	]:
		if not saved[key] is bool:
			return false
	if not _validate_id_list(saved.fragments, FRAGMENT_IDS):
		return false
	if not _validate_id_list(saved.keypad_clues, KEYPAD_CLUE_IDS):
		return false
	if not _validate_id_list(saved.power_nodes, POWER_NODE_IDS):
		return false
	if not _validate_id_list(saved.routes, ROUTE_IDS):
		return false
	if not _validate_id_list(saved.audio_logs, AUDIO_IDS):
		return false
	if not _validate_id_list(saved.lab_clues, LAB_CLUE_IDS):
		return false
	if saved.keypad_unlocked and (not saved.house_discovered or not _has_every(saved.keypad_clues, KEYPAD_CLUE_IDS)):
		return false
	if saved.headquarters_discovered and not saved.keypad_unlocked:
		return false
	if not saved.headquarters_discovered and (not saved.power_nodes.is_empty() or not saved.routes.is_empty() or saved.sealed_sector_discovered):
		return false
	for power_id in saved.power_nodes:
		var power_requirement: String = POWER_REQUIREMENTS[power_id]
		if not power_requirement.is_empty() and not saved.power_nodes.has(power_requirement):
			return false
	for route_id in saved.routes:
		if not saved.power_nodes.has(ROUTE_REQUIREMENTS[route_id]):
			return false
	if saved.final_door_unlocked and not (
		saved.sealed_sector_discovered
		and saved.power_nodes.has("power_sealed_sector")
		and saved.audio_logs.has("audio_sealed_sector")
		and _has_every(saved.lab_clues, LAB_CLUE_IDS)
	):
		return false
	return true


func _append_known(bucket: String, id: Variant, allowed: Array) -> bool:
	if not id is String or not allowed.has(id) or data[bucket].has(id):
		return false
	data[bucket].append(id)
	return true


static func _has_every(found: Array, expected: Array) -> bool:
	if found.size() != expected.size():
		return false
	for id in expected:
		if not found.has(id):
			return false
	return true


static func _validate_id_list(value: Variant, allowed: Array) -> bool:
	if not value is Array or value.size() > allowed.size():
		return false
	var seen: Dictionary = {}
	for id in value:
		if not id is String or not allowed.has(id) or seen.has(id):
			return false
		seen[id] = true
	return true


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true
