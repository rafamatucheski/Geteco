class_name PopulationZoneManager
extends RefCounted

## Catalogo virtual de populacao. Um registro representa uma pessoa ou veiculo
## que pode existir no mundo sem possuir um Node enquanto estiver distante.
## A materializacao fica a cargo da regiao dona, que conhece suas rotas e
## fabricas. Este objeto nao cria geometria nem executa comportamento.

const CELL_SIZE := 1024.0
const ACTIVE_RADIUS := 1500.0
const RETAIN_RADIUS := 2400.0
const MAX_MATERIALIZE_PER_TICK := 2

var records: Dictionary = {}
var actor_keys: Dictionary = {}
var _serial := 1
var _virtual_cells: Dictionary = {}
var _pinned_virtual: Dictionary = {}
var _indexed_virtual_count := 0
var _last_query_stats: Dictionary = {
	"examined_records": 0,
	"visited_cells": 0,
	"nonempty_cells": 0,
	"pinned_examined": 0,
	"returned_records": 0,
	"indexed_virtual": 0,
	"total_records": 0,
}

func zone_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))

func zone_key(zone: Vector2i) -> String:
	return "%d:%d" % [zone.x, zone.y]

func register_virtual(record: Dictionary) -> String:
	var data := record.duplicate(true)
	var key := String(data.get("key", ""))
	if key.is_empty():
		key = "population_%d" % _serial
		_serial += 1
	if records.has(key):
		_remove_virtual_index(key, records[key])
	data["key"] = key
	if not data.has("position"): data["position"] = Vector2.ZERO
	data["position"] = data["position"] as Vector2
	data["zone"] = zone_key(zone_for_position(data["position"]))
	data["materialized"] = false
	records[key] = data
	_index_virtual(key, data)
	return key

func register_actor(actor: Node2D, key: String = "") -> String:
	if not is_instance_valid(actor): return ""
	var actor_key := key
	if actor_key.is_empty(): actor_key = String(actor.get_meta("population_key", ""))
	if actor_key.is_empty():
		actor_key = "population_%d" % _serial
		_serial += 1
	var data: Dictionary = records.get(actor_key, {})
	_remove_virtual_index(actor_key, data)
	data["key"] = actor_key
	data["position"] = actor.global_position
	data["zone"] = zone_key(zone_for_position(actor.global_position))
	if not data.has("kind"): data["kind"] = "pedestrian"
	data["materialized"] = true
	records[actor_key] = data
	actor_keys[actor.get_instance_id()] = actor_key
	actor.set_meta("population_key", actor_key)
	return actor_key

func update_actor(actor: Node2D) -> void:
	if not is_instance_valid(actor): return
	var key := String(actor_keys.get(actor.get_instance_id(), actor.get_meta("population_key", "")))
	if key.is_empty() or not records.has(key):
		register_actor(actor, key)
		return
	var data: Dictionary = records[key]
	_remove_virtual_index(key, data)
	data["position"] = actor.global_position
	data["zone"] = zone_key(zone_for_position(actor.global_position))
	data["materialized"] = true
	records[key] = data

func capture_actor(actor: Node2D, state: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(actor): return {}
	var key := String(actor_keys.get(actor.get_instance_id(), actor.get_meta("population_key", "")))
	if key.is_empty(): key = register_actor(actor)
	var data: Dictionary = records.get(key, {"key": key})
	_remove_virtual_index(key, data)
	data["position"] = actor.global_position
	data["zone"] = zone_key(zone_for_position(actor.global_position))
	data["materialized"] = false
	for field in state.keys(): data[field] = state[field]
	records[key] = data
	_index_virtual(key, data)
	actor_keys.erase(actor.get_instance_id())
	return data.duplicate(true)

func materialize(key: String) -> Dictionary:
	if not records.has(key): return {}
	var data: Dictionary = records[key]
	_remove_virtual_index(key, data)
	data["materialized"] = true
	records[key] = data
	return data.duplicate(true)

func forget(key: String) -> void:
	if records.has(key):
		_remove_virtual_index(key, records[key])
		records.erase(key)
	for instance_id in actor_keys.keys():
		if actor_keys[instance_id] == key: actor_keys.erase(instance_id)

func should_retain(position: Vector2, focus: Vector2, pinned := false) -> bool:
	return pinned or position.distance_to(focus) <= RETAIN_RADIUS

func should_materialize(position: Vector2, focus: Vector2, pinned := false) -> bool:
	return pinned or position.distance_to(focus) <= ACTIVE_RADIUS

func pending_materialization(focus: Vector2, limit := MAX_MATERIALIZE_PER_TICK, owner := "", min_distance := 0.0, kind := "") -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var distances: Array[float] = []
	var examined_records := 0
	var visited_cells := 0
	var nonempty_cells := 0
	var pinned_examined := 0
	if limit <= 0:
		_store_query_stats(0, 0, 0, 0, 0)
		return candidates
	var extent := Vector2(ACTIVE_RADIUS, ACTIVE_RADIUS)
	var min_zone := zone_for_position(focus - extent)
	var max_zone := zone_for_position(focus + extent)
	for zone_x in range(min_zone.x, max_zone.x + 1):
		for zone_y in range(min_zone.y, max_zone.y + 1):
			visited_cells += 1
			var bucket_key := zone_key(Vector2i(zone_x, zone_y))
			if not _virtual_cells.has(bucket_key): continue
			nonempty_cells += 1
			var bucket: Dictionary = _virtual_cells[bucket_key]
			for record_key_value in bucket:
				var record_key := String(record_key_value)
				if not records.has(record_key): continue
				examined_records += 1
				_consider_candidate(records[record_key], focus, limit, owner, min_distance, kind, candidates, distances)
	for record_key_value in _pinned_virtual:
		var record_key := String(record_key_value)
		if not records.has(record_key): continue
		examined_records += 1
		pinned_examined += 1
		_consider_candidate(records[record_key], focus, limit, owner, min_distance, kind, candidates, distances)
	_store_query_stats(examined_records, visited_cells, nonempty_cells, pinned_examined, candidates.size())
	return candidates

func last_query_stats() -> Dictionary:
	return _last_query_stats.duplicate(true)

func count_materialized(kind := "") -> int:
	var count := 0
	for data_value in records.values():
		var data: Dictionary = data_value
		if not bool(data.get("materialized", false)): continue
		if not kind.is_empty() and String(data.get("kind", "")) != kind: continue
		count += 1
	return count

func count_virtual(kind := "") -> int:
	var count := 0
	for data_value in records.values():
		var data: Dictionary = data_value
		if bool(data.get("materialized", false)): continue
		if not kind.is_empty() and String(data.get("kind", "")) != kind: continue
		count += 1
	return count

func prune_missing_materialized(present_keys: Dictionary) -> void:
	# Registros virtuais permanecem mesmo sem Node. Somente uma identidade que
	# ainda era materializada e deixou de existir deve ser descartada.
	for key in records.keys():
		var data: Dictionary = records[key]
		if bool(data.get("materialized", false)) and not present_keys.has(key):
			_remove_virtual_index(String(key), data)
			records.erase(key)

func snapshot() -> Dictionary:
	var zones: Dictionary = {}
	var materialized_count := 0
	var virtual_count := 0
	for data_value in records.values():
		var data: Dictionary = data_value
		var zone := String(data.get("zone", "0:0"))
		if not zones.has(zone): zones[zone] = {"materialized": 0, "virtual": 0}
		var bucket: Dictionary = zones[zone]
		if bool(data.get("materialized", false)):
			bucket["materialized"] += 1
			materialized_count += 1
		else:
			bucket["virtual"] += 1
			virtual_count += 1
	return {
		"total": records.size(),
		"materialized": materialized_count,
		"virtual": virtual_count,
		"indexed_virtual": _indexed_virtual_count,
		"indexed_cells": _virtual_cells.size(),
		"pinned_virtual": _pinned_virtual.size(),
		"zones": zones,
		"last_query": last_query_stats(),
	}

func _index_virtual(key: String, data: Dictionary) -> void:
	if bool(data.get("materialized", false)): return
	if bool(data.get("pinned", false)):
		_pinned_virtual[key] = true
		_indexed_virtual_count += 1
		return
	var bucket_key := String(data.get("zone", zone_key(zone_for_position(data.get("position", Vector2.ZERO)))))
	var bucket: Dictionary = _virtual_cells.get(bucket_key, {})
	bucket[key] = true
	_virtual_cells[bucket_key] = bucket
	_indexed_virtual_count += 1

func _remove_virtual_index(key: String, data: Dictionary) -> void:
	if data.is_empty() or bool(data.get("materialized", false)): return
	if bool(data.get("pinned", false)):
		if _pinned_virtual.erase(key): _indexed_virtual_count -= 1
		return
	var bucket_key := String(data.get("zone", zone_key(zone_for_position(data.get("position", Vector2.ZERO)))))
	if not _virtual_cells.has(bucket_key): return
	var bucket: Dictionary = _virtual_cells[bucket_key]
	if bucket.erase(key): _indexed_virtual_count -= 1
	if bucket.is_empty(): _virtual_cells.erase(bucket_key)

func _consider_candidate(data: Dictionary, focus: Vector2, limit: int, owner: String, min_distance: float, kind: String, candidates: Array[Dictionary], distances: Array[float]) -> void:
	if bool(data.get("materialized", false)): return
	if not owner.is_empty() and String(data.get("owner", "")) != owner: return
	if not kind.is_empty() and String(data.get("kind", "")) != kind: return
	var position: Vector2 = data.get("position", Vector2.ZERO)
	var pinned := bool(data.get("pinned", false))
	var distance := position.distance_squared_to(focus)
	if not pinned:
		if min_distance > 0.0 and distance < min_distance * min_distance: return
		if distance > ACTIVE_RADIUS * ACTIVE_RADIUS: return
	var insert_at := 0
	while insert_at < distances.size() and distances[insert_at] <= distance:
		insert_at += 1
	if insert_at >= limit and candidates.size() >= limit: return
	distances.insert(insert_at, distance)
	candidates.insert(insert_at, data.duplicate(true))
	if candidates.size() > limit:
		distances.pop_back()
		candidates.pop_back()

func _store_query_stats(examined_records: int, visited_cells: int, nonempty_cells: int, pinned_examined: int, returned_records: int) -> void:
	_last_query_stats["examined_records"] = examined_records
	_last_query_stats["visited_cells"] = visited_cells
	_last_query_stats["nonempty_cells"] = nonempty_cells
	_last_query_stats["pinned_examined"] = pinned_examined
	_last_query_stats["returned_records"] = returned_records
	_last_query_stats["indexed_virtual"] = _indexed_virtual_count
	_last_query_stats["indexed_cells"] = _virtual_cells.size()
	_last_query_stats["total_records"] = records.size()
