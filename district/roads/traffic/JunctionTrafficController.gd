class_name JunctionTrafficController
extends Node

## Logical traffic authority for the junctions already discovered by
## UnifiedRoadNetwork2D. This class never intersects road geometry and never
## reads provider control points: its only junction source is
## get_graph_data()["junctions"]. Directed Path2D lanes register their
## traffic_road_index metadata against those junction records.

signal junction_stage_changed(junction_id: StringName, stage: int, active_roads: Array)
signal reservation_changed(junction_id: StringName, vehicle_instance_id: int, occupied: bool)
signal traffic_contract_violation(kind: StringName, details: Dictionary)

enum SignalState { RED, YELLOW, GREEN }
enum JunctionStage { GREEN, YELLOW, ALL_RED }

const CONTROLLER_GROUP: StringName = &"junction_traffic_controller"
const LANE_GROUP: StringName = &"unified_traffic_lane"
const NO_ADVANCE := 0.0
const SIGNAL_VISUAL := preload("res://district/roads/traffic/JunctionSignalVisual2D.gd")

@export_range(1.0, 60.0, 0.1) var minimum_green_seconds := 7.5
@export_range(0.5, 10.0, 0.1) var yellow_seconds := 2.2
@export_range(0.5, 10.0, 0.1) var all_red_seconds := 1.5
@export_range(0.0, 80.0, 1.0) var stop_line_margin := 14.0
@export_range(40.0, 600.0, 1.0) var reservation_request_distance := 220.0
@export_range(1.0, 20.0, 0.1) var reservation_heartbeat_timeout := 4.0
@export_range(5.0, 180.0, 1.0) var deadlock_telemetry_limit := 45.0

var graph_source: Node2D = null
var _junctions: Array[Dictionary] = []
var _states: Dictionary = {}
var _junction_id_to_index: Dictionary = {}
var _graph_signature := ""
var _sync_elapsed := 0.0
var _crossing_sync_elapsed := 0.0
var _lane_projection_cache: Dictionary = {}
var _signal_visuals: Dictionary = {}
var _lane_paths_by_id: Dictionary = {}
var _connections_by_id: Dictionary = {}
var _connections_from_lane: Dictionary = {}
var _warned_lanes: Dictionary = {}
var _waiting_since: Dictionary = {}
var _deadlock_reported: Dictionary = {}
var _telemetry := {
	"reservation_grants": 0,
	"reservation_releases": 0,
	"reservation_denials": 0,
	"red_stop_clamps": 0,
	"invalid_lane_contracts": 0,
	"deadlock_limit_exceeded": 0,
	"maximum_wait_seconds": 0.0,
}


func _ready() -> void:
	add_to_group(CONTROLLER_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if graph_source == null:
		graph_source = _discover_graph_source()
	_sync_from_graph()


func _process(delta: float) -> void:
	if graph_source == null or not is_instance_valid(graph_source):
		graph_source = _discover_graph_source()
	_sync_elapsed += delta
	if _sync_elapsed >= 0.5:
		_sync_elapsed = 0.0
		_sync_from_graph()
	for index_value in _states.keys():
		var junction_index := int(index_value)
		_validate_reservation(junction_index)
		_advance_junction(junction_index, delta)
	_update_wait_telemetry()
	_crossing_sync_elapsed += delta
	if _crossing_sync_elapsed >= 0.5:
		_crossing_sync_elapsed = 0.0
		_refresh_lane_path_index()
		_refresh_signal_visuals()
		_synchronize_crossing_consumers()


func configure_graph_source(source: Node2D) -> void:
	graph_source = source
	_graph_signature = ""
	_sync_from_graph()


func _discover_graph_source() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var candidates: Array[Node] = [scene]
	candidates.append_array(scene.find_children("*", "Node2D", true, false))
	for candidate in candidates:
		if candidate is Node2D and candidate.has_method("get_graph_data"):
			var data = candidate.call("get_graph_data")
			if data is Dictionary and (data as Dictionary).has("junctions"):
				return candidate as Node2D
	return null


func _sync_from_graph() -> void:
	if graph_source == null or not is_instance_valid(graph_source) or not graph_source.has_method("get_graph_data"):
		return
	var graph_data = graph_source.call("get_graph_data")
	if not graph_data is Dictionary:
		return
	# Deliberately do not retain/read graph_data.roads here. The controller's
	# complete geometric input is the canonical junction array.
	var source_junctions: Array = (graph_data as Dictionary).get("junctions", [])
	var signature_values: Array = []
	for junction_value in source_junctions:
		var junction := junction_value as Dictionary
		signature_values.append([
			junction.get("id", ""),
			junction.get("position", Vector2.ZERO),
			junction.get("radius", 0.0),
			junction.get("roads", []),
			junction.get("approaches", []),
			_connection_signature(junction.get("lane_connections", [])),
		])
	var next_signature := str(signature_values)
	if next_signature == _graph_signature:
		return
	_graph_signature = next_signature
	_junctions.clear()
	_junction_id_to_index.clear()
	_lane_projection_cache.clear()
	_connections_by_id.clear()
	_connections_from_lane.clear()
	for index in source_junctions.size():
		var junction: Dictionary = (source_junctions[index] as Dictionary).duplicate(true)
		var junction_id := _canonical_junction_id(index, junction)
		junction["id"] = junction_id
		_junctions.append(junction)
		_junction_id_to_index[junction_id] = index
		var previous: Dictionary = _states.get(index, {})
		var roads := _road_indices(junction)
		var phases: Array = []
		# One connected road per phase is conservative by design. Both directed
		# lanes of that road share the phase; roads that may conflict never do.
		for road_index in roads:
			phases.append([road_index])
		if phases.is_empty():
			phases.append([])
		_states[index] = {
			"junction_id": junction_id,
			"roads": roads,
			"phases": phases,
			"phase_index": mini(int(previous.get("phase_index", index % phases.size())), phases.size() - 1),
			"stage": int(previous.get("stage", JunctionStage.GREEN)),
			"elapsed": float(previous.get("elapsed", 0.0)),
			"reservation_owner": int(previous.get("reservation_owner", 0)),
			"reservation_road": int(previous.get("reservation_road", -1)),
			"reservation_lane": StringName(previous.get("reservation_lane", &"")),
			"reservation_ref": previous.get("reservation_ref", null),
			"reservation_heartbeat_ms": int(previous.get("reservation_heartbeat_ms", 0)),
			"reservation_entered": bool(previous.get("reservation_entered", false)),
		}
		for connection_value in junction.get("lane_connections", []):
			var connection := connection_value as Dictionary
			var connection_id := String(connection.get("connection_id", ""))
			var from_lane_id := String(connection.get("from_lane_id", ""))
			if connection_id.is_empty() or from_lane_id.is_empty():
				continue
			_connections_by_id[connection_id] = connection
			var lane_connections: Array = _connections_from_lane.get(from_lane_id, [])
			lane_connections.append(connection)
			_connections_from_lane[from_lane_id] = lane_connections
	for stale_index in _states.keys():
		if int(stale_index) >= _junctions.size():
			_states.erase(stale_index)
	_rebuild_signal_visuals()
	_refresh_lane_path_index()
	_synchronize_crossing_consumers()


func _connection_signature(connections: Array) -> Array:
	var result: Array = []
	for connection_value in connections:
		var connection := connection_value as Dictionary
		result.append([
			connection.get("connection_id", ""),
			connection.get("from_lane_id", ""),
			connection.get("to_lane_id", ""),
			connection.get("movement", ""),
			connection.get("entry_curve_offset", -1.0),
			connection.get("exit_curve_offset", -1.0),
		])
	return result


func _canonical_junction_id(index: int, junction: Dictionary) -> StringName:
	var authored := StringName(junction.get("id", &""))
	if not authored.is_empty():
		return authored
	var position: Vector2 = junction.get("position", Vector2.ZERO)
	return StringName("junction_%03d_%d_%d" % [index, roundi(position.x), roundi(position.y)])


func _road_indices(junction: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for road_value in junction.get("roads", []):
		var road_index := int(road_value)
		if not result.has(road_index):
			result.append(road_index)
	result.sort()
	return result


func _advance_junction(junction_index: int, delta: float) -> void:
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty():
		return
	state.elapsed = float(state.elapsed) + delta
	match int(state.stage):
		JunctionStage.GREEN:
			if float(state.elapsed) >= minimum_green_seconds:
				_set_stage(junction_index, JunctionStage.YELLOW)
		JunctionStage.YELLOW:
			if float(state.elapsed) >= yellow_seconds:
				_set_stage(junction_index, JunctionStage.ALL_RED)
		JunctionStage.ALL_RED:
			# The clearance interval cannot finish while a vehicle that entered
			# under the previous phase still owns the conflict zone.
			if float(state.elapsed) >= all_red_seconds and int(state.reservation_owner) == 0:
				var phases: Array = state.phases
				state.phase_index = (int(state.phase_index) + 1) % phases.size()
				_set_stage(junction_index, JunctionStage.GREEN)


func _set_stage(junction_index: int, next_stage: JunctionStage) -> void:
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or int(state.stage) == next_stage:
		return
	state.stage = next_stage
	state.elapsed = 0.0
	var active_roads: Array = []
	if next_stage != JunctionStage.ALL_RED:
		active_roads = (state.phases as Array)[int(state.phase_index)].duplicate()
	junction_stage_changed.emit(StringName(state.junction_id), next_stage, active_roads)
	_refresh_signal_visuals()
	_synchronize_crossing_consumers()


func get_vehicle_permission(junction_ref: Variant, road_index: int, _lane_id: StringName = &"") -> bool:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty() or int(state.stage) != JunctionStage.GREEN:
		return false
	var active_roads: Array = (state.phases as Array)[int(state.phase_index)]
	return active_roads.has(road_index)


func get_signal_state(junction_ref: Variant, road_index: int) -> SignalState:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty():
		return SignalState.RED
	if get_vehicle_permission(index, road_index):
		return SignalState.GREEN
	if int(state.stage) == JunctionStage.YELLOW:
		var active_roads: Array = (state.phases as Array)[int(state.phase_index)]
		if active_roads.has(road_index):
			return SignalState.YELLOW
	return SignalState.RED


func is_pedestrian_phase(junction_ref: Variant, _road_index: int = -1, _crossing_id: StringName = &"") -> bool:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	return not state.is_empty() \
		and int(state.stage) == JunctionStage.ALL_RED \
		and int(state.reservation_owner) == 0


func try_reserve_junction(
	junction_ref: Variant,
	vehicle_instance_id: int,
	road_index: int,
	lane_id: StringName = &"",
	vehicle: Node = null
) -> bool:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty() or vehicle_instance_id == 0:
		return false
	if int(state.reservation_owner) == vehicle_instance_id:
		state.reservation_heartbeat_ms = Time.get_ticks_msec()
		return true
	if not get_vehicle_permission(index, road_index, lane_id) or int(state.reservation_owner) != 0:
		_telemetry.reservation_denials = int(_telemetry.reservation_denials) + 1
		_track_wait(vehicle_instance_id, index, road_index, lane_id)
		return false
	state.reservation_owner = vehicle_instance_id
	state.reservation_road = road_index
	state.reservation_lane = lane_id
	state.reservation_ref = weakref(vehicle) if vehicle != null else null
	state.reservation_heartbeat_ms = Time.get_ticks_msec()
	state.reservation_entered = false
	_waiting_since.erase(vehicle_instance_id)
	_deadlock_reported.erase(vehicle_instance_id)
	_telemetry.reservation_grants = int(_telemetry.reservation_grants) + 1
	reservation_changed.emit(StringName(state.junction_id), vehicle_instance_id, true)
	return true


func notify_vehicle_entered(junction_ref: Variant, vehicle_instance_id: int) -> void:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if not state.is_empty() and int(state.reservation_owner) == vehicle_instance_id:
		state.reservation_entered = true
		state.reservation_heartbeat_ms = Time.get_ticks_msec()


func release_junction(junction_ref: Variant, vehicle_instance_id: int) -> void:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty() or int(state.reservation_owner) != vehicle_instance_id:
		return
	_clear_reservation(index)


func release_vehicle(vehicle_instance_id: int) -> void:
	for index_value in _states.keys():
		var state: Dictionary = _states[index_value]
		if int(state.reservation_owner) == vehicle_instance_id:
			_clear_reservation(int(index_value))
	_waiting_since.erase(vehicle_instance_id)
	_deadlock_reported.erase(vehicle_instance_id)


## Returns a hard movement contract. `allowed_advance` is the maximum number
## of PathFollow2D pixels the caller may add this frame. At a red stop line it
## reaches exactly zero, independently of frame rate or current velocity.
func evaluate_lane_motion(
	vehicle: Node2D,
	path: Path2D,
	follow: PathFollow2D,
	desired_advance: float,
	vehicle_length: float,
	current_speed: float,
	braking_rate: float
) -> Dictionary:
	var unrestricted := {
		"controlled": false,
		"must_stop": false,
		"allowed_advance": maxf(NO_ADVANCE, desired_advance),
		"target_speed": INF,
		"signal_state": SignalState.GREEN,
		"reservation_granted": false,
		"junction_index": -1,
		"junction_id": &"",
		"stop_distance": INF,
	}
	if vehicle == null or path == null or follow == null or path.curve == null:
		return unrestricted
	if path.is_in_group("unified_lane_connector"):
		return _evaluate_connector_motion(vehicle, path, desired_advance)
	var road_index := int(path.get_meta("traffic_road_index", -1))
	var lane_id := StringName(path.get_meta("traffic_lane_id", path.name))
	if road_index < 0 or not path.is_in_group(LANE_GROUP):
		_report_invalid_lane_once(path, road_index)
		return unrestricted
	_release_if_vehicle_cleared(vehicle, vehicle_length)
	var next := _next_lane_junction(path, follow, road_index)
	if next.is_empty():
		return unrestricted
	var junction_index := int(next.junction_index)
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty():
		return unrestricted
	var half_length := vehicle_length * 0.5
	var radius := float((_junctions[junction_index] as Dictionary).get("radius", 48.0))
	var center_distance := float(next.distance)
	var stop_distance := center_distance - radius - stop_line_margin - half_length
	var vehicle_id := vehicle.get_instance_id()
	var distance_to_world_center := vehicle.global_position.distance_to(_junction_world_position(junction_index))
	if int(state.reservation_owner) == vehicle_id:
		state.reservation_heartbeat_ms = Time.get_ticks_msec()
		if distance_to_world_center <= radius + half_length:
			notify_vehicle_entered(junction_index, vehicle_id)
		unrestricted.controlled = true
		unrestricted.reservation_granted = true
		unrestricted.junction_index = junction_index
		unrestricted.junction_id = state.junction_id
		unrestricted.stop_distance = stop_distance
		return unrestricted

	var signal_state := get_signal_state(junction_index, road_index)
	var close_enough_to_reserve := stop_distance <= maxf(reservation_request_distance, radius + vehicle_length)
	var reserved := false
	if signal_state == SignalState.GREEN and close_enough_to_reserve:
		reserved = try_reserve_junction(junction_index, vehicle_id, road_index, lane_id, vehicle)
	if reserved:
		unrestricted.controlled = true
		unrestricted.reservation_granted = true
		unrestricted.junction_index = junction_index
		unrestricted.junction_id = state.junction_id
		unrestricted.stop_distance = stop_distance
		return unrestricted

	var occupied := int(state.reservation_owner) != 0
	var must_yield := signal_state != SignalState.GREEN or (close_enough_to_reserve and occupied)
	if not must_yield:
		return unrestricted
	var safe_stop_distance := maxf(NO_ADVANCE, stop_distance)
	var safe_braking := maxf(1.0, braking_rate)
	var braking_distance := current_speed * current_speed / (2.0 * safe_braking) + vehicle_length * 0.5 + 12.0
	var target_speed := sqrt(maxf(0.0, 2.0 * safe_braking * safe_stop_distance))
	var result := {
		"controlled": true,
		"must_stop": safe_stop_distance <= maxf(braking_distance, reservation_request_distance),
		"allowed_advance": minf(maxf(NO_ADVANCE, desired_advance), safe_stop_distance),
		"target_speed": target_speed,
		"signal_state": signal_state,
		"reservation_granted": false,
		"junction_index": junction_index,
		"junction_id": state.junction_id,
		"stop_distance": safe_stop_distance,
	}
	if safe_stop_distance <= desired_advance + 0.001:
		_telemetry.red_stop_clamps = int(_telemetry.red_stop_clamps) + 1
	_track_wait(vehicle_id, junction_index, road_index, lane_id)
	return result


func _evaluate_connector_motion(vehicle: Node2D, connector: Path2D, desired_advance: float) -> Dictionary:
	var junction_index := int(connector.get_meta("traffic_junction_index", -1))
	var state: Dictionary = _states.get(junction_index, {})
	var vehicle_id := vehicle.get_instance_id()
	if state.is_empty() or int(state.reservation_owner) != vehicle_id:
		traffic_contract_violation.emit(&"connector_without_reservation", {
			"vehicle_instance_id": vehicle_id,
			"connector": connector.get_path(),
			"junction_index": junction_index,
		})
		return {
			"controlled": true,
			"must_stop": true,
			"allowed_advance": 0.0,
			"target_speed": 0.0,
			"signal_state": SignalState.RED,
			"reservation_granted": false,
			"junction_index": junction_index,
			"junction_id": state.get("junction_id", &""),
			"stop_distance": 0.0,
		}
	state.reservation_heartbeat_ms = Time.get_ticks_msec()
	state.reservation_entered = true
	return {
		"controlled": true,
		"must_stop": false,
		"allowed_advance": maxf(0.0, desired_advance),
		"target_speed": INF,
		"signal_state": get_signal_state(junction_index, int(state.reservation_road)),
		"reservation_granted": true,
		"junction_index": junction_index,
		"junction_id": state.junction_id,
		"stop_distance": INF,
	}


func _next_lane_junction(path: Path2D, follow: PathFollow2D, road_index: int) -> Dictionary:
	var projections := _lane_junction_projections(path, road_index)
	if projections.is_empty():
		return {}
	var length := maxf(1.0, path.curve.get_baked_length())
	var loops := bool(path.get_meta("traffic_lane_loop", follow.loop)) and follow.loop
	var best := {}
	var best_distance := INF
	for projection_value in projections:
		var projection := projection_value as Dictionary
		var distance := float(projection.offset) - follow.progress
		if loops and distance < -0.5:
			distance += length
		if not loops and distance < -float(projection.radius) * 1.5:
			continue
		if distance < best_distance:
			best_distance = distance
			best = projection.duplicate()
			best["distance"] = distance
	return best


func _lane_junction_projections(path: Path2D, road_index: int) -> Array:
	var curve_length := path.curve.get_baked_length()
	var cache_key := "%d:%d:%.3f:%s" % [path.get_instance_id(), road_index, curve_length, _graph_signature]
	if _lane_projection_cache.has(cache_key):
		return _lane_projection_cache[cache_key]
	var result: Array = []
	for junction_index in _junctions.size():
		var junction: Dictionary = _junctions[junction_index]
		if not _road_indices(junction).has(road_index):
			continue
		var world_position := _junction_world_position(junction_index)
		var local_position := path.to_local(world_position)
		var offset := path.curve.get_closest_offset(local_position)
		var lane_point := path.to_global(path.curve.sample_baked(offset, true))
		var radius := float(junction.get("radius", 48.0))
		# This is association with a canonical junction, not intersection
		# discovery. The road index is authoritative; the radius rejects a lane
		# whose metadata was attached to the wrong district/path.
		if lane_point.distance_to(world_position) <= radius + 48.0:
			result.append({
				"junction_index": junction_index,
				"junction_id": junction.id,
				"offset": offset,
				"radius": radius,
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.offset) < float(b.offset))
	_lane_projection_cache[cache_key] = result
	return result


func _refresh_lane_path_index() -> void:
	_lane_paths_by_id.clear()
	if not is_inside_tree():
		return
	for candidate in get_tree().get_nodes_in_group(LANE_GROUP):
		if not candidate is Path2D:
			continue
		var path := candidate as Path2D
		if graph_source != null and not graph_source.is_ancestor_of(path):
			continue
		var lane_id := String(path.get_meta("traffic_lane_id", ""))
		if not lane_id.is_empty():
			_lane_paths_by_id[lane_id] = path


func has_lane_transition(path: Path2D) -> bool:
	if path == null or path.curve == null or not path.is_in_group(LANE_GROUP):
		return false
	var lane_id := String(path.get_meta("traffic_lane_id", ""))
	var road_index := int(path.get_meta("traffic_road_index", -1))
	var length := path.curve.get_baked_length()
	for connection_value in _connections_from_lane.get(lane_id, []):
		var connection := connection_value as Dictionary
		if not bool(connection.get("requires_connector", false)):
			continue
		var junction_index := int(connection.get("junction_index", -1))
		for projection_value in _lane_junction_projections(path, road_index):
			var projection := projection_value as Dictionary
			if int(projection.junction_index) == junction_index and float(projection.offset) >= length - 2.0:
				return true
	return false


## Moves a PathFollow2D only through connector Path2D objects published in
## junction.lane_connections. No turn point or curve is generated by the AI.
func complete_lane_transition(vehicle: Node2D, path: Path2D, follow: PathFollow2D) -> bool:
	if vehicle == null or path == null or follow == null or path.curve == null:
		return false
	if path.is_in_group("unified_lane_connector"):
		return _finish_connector_transition(path, follow)
	if not path.is_in_group(LANE_GROUP):
		return false
	var connection := _planned_connection(vehicle, path, follow)
	if connection.is_empty():
		return false
	if not bool(connection.get("requires_connector", false)):
		_clear_passed_straight_plan(path, follow, connection)
		return false
	var entry_offset := float(connection.get("entry_curve_offset", -1.0))
	if entry_offset < 0.0 or follow.progress + 0.01 < entry_offset:
		return false
	var junction_index := int(connection.get("junction_index", -1))
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or int(state.reservation_owner) != vehicle.get_instance_id():
		return false
	var connector := connection.get("path") as Path2D
	if connector == null or not is_instance_valid(connector) or connector.curve == null:
		return false
	var overshoot := maxf(0.0, follow.progress - entry_offset)
	follow.reparent(connector, false)
	follow.loop = false
	follow.progress = minf(overshoot, connector.curve.get_baked_length())
	follow.set_meta("traffic_planned_connection_id", String(connection.connection_id))
	follow.set_meta("traffic_planned_junction_index", junction_index)
	return true


func _planned_connection(vehicle: Node2D, path: Path2D, follow: PathFollow2D) -> Dictionary:
	var planned_id := String(follow.get_meta("traffic_planned_connection_id", ""))
	if not planned_id.is_empty() and _connections_by_id.has(planned_id):
		var existing: Dictionary = _connections_by_id[planned_id]
		if String(existing.get("from_lane_id", "")) == String(path.get_meta("traffic_lane_id", "")):
			return existing
		follow.remove_meta("traffic_planned_connection_id")
		follow.remove_meta("traffic_planned_junction_index")
	var road_index := int(path.get_meta("traffic_road_index", -1))
	var next := _next_lane_junction(path, follow, road_index)
	if next.is_empty():
		return {}
	var junction_index := int(next.junction_index)
	var lane_id := String(path.get_meta("traffic_lane_id", ""))
	var candidates: Array[Dictionary] = []
	for connection_value in _connections_from_lane.get(lane_id, []):
		var candidate := connection_value as Dictionary
		if int(candidate.get("junction_index", -1)) != junction_index:
			continue
		if bool(candidate.get("requires_connector", false)):
			var connector := candidate.get("path") as Path2D
			if connector == null or not is_instance_valid(connector):
				continue
		candidates.append(candidate)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first_priority := _movement_priority(String(a.get("movement", "straight")))
		var second_priority := _movement_priority(String(b.get("movement", "straight")))
		if first_priority == second_priority:
			return String(a.get("connection_id", "")) < String(b.get("connection_id", ""))
		return first_priority < second_priority
	)
	var visit_count := int(follow.get_meta("traffic_route_decision_count", 0))
	var selector := posmod(hash("%s:%s:%d:%d" % [vehicle.name, lane_id, junction_index, visit_count]), candidates.size())
	var selected: Dictionary = candidates[selector]
	follow.set_meta("traffic_route_decision_count", visit_count + 1)
	follow.set_meta("traffic_planned_connection_id", String(selected.connection_id))
	follow.set_meta("traffic_planned_junction_index", junction_index)
	return selected


func _movement_priority(movement: String) -> int:
	match movement:
		"straight":
			return 0
		"right":
			return 1
		_:
			return 2


func _clear_passed_straight_plan(path: Path2D, follow: PathFollow2D, connection: Dictionary) -> void:
	var junction_index := int(connection.get("junction_index", -1))
	var road_index := int(path.get_meta("traffic_road_index", -1))
	for projection_value in _lane_junction_projections(path, road_index):
		var projection := projection_value as Dictionary
		if int(projection.junction_index) != junction_index:
			continue
		if follow.progress > float(projection.offset) + float(projection.radius) * 1.2:
			follow.remove_meta("traffic_planned_connection_id")
			follow.remove_meta("traffic_planned_junction_index")
		return


func _finish_connector_transition(connector: Path2D, follow: PathFollow2D) -> bool:
	var connector_length := connector.curve.get_baked_length()
	if follow.progress < connector_length - 0.01:
		return false
	var connection_id := String(connector.get_meta("traffic_connection_id", ""))
	var connection: Dictionary = _connections_by_id.get(connection_id, {})
	if connection.is_empty():
		return false
	_refresh_lane_path_index()
	var target_lane_id := String(connection.get("to_lane_id", ""))
	var target_path := _lane_paths_by_id.get(target_lane_id) as Path2D
	if target_path == null or not is_instance_valid(target_path) or target_path.curve == null:
		return false
	var exit_offset := clampf(
		float(connection.get("exit_curve_offset", 0.0)),
		0.0,
		target_path.curve.get_baked_length()
	)
	follow.reparent(target_path, false)
	follow.loop = bool(target_path.get_meta("traffic_lane_loop", false))
	follow.progress = exit_offset
	follow.remove_meta("traffic_planned_connection_id")
	follow.remove_meta("traffic_planned_junction_index")
	return true


func _release_if_vehicle_cleared(vehicle: Node2D, vehicle_length: float) -> void:
	var vehicle_id := vehicle.get_instance_id()
	for index_value in _states.keys():
		var junction_index := int(index_value)
		var state: Dictionary = _states[junction_index]
		if int(state.reservation_owner) != vehicle_id:
			continue
		var radius := float((_junctions[junction_index] as Dictionary).get("radius", 48.0))
		var distance := vehicle.global_position.distance_to(_junction_world_position(junction_index))
		if distance <= radius + vehicle_length * 0.5:
			notify_vehicle_entered(junction_index, vehicle_id)
		elif bool(state.reservation_entered) and distance > radius + vehicle_length + stop_line_margin:
			_clear_reservation(junction_index)


func _validate_reservation(junction_index: int) -> void:
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or int(state.reservation_owner) == 0:
		return
	var owner_ref = state.get("reservation_ref", null)
	var owner: Object = owner_ref.get_ref() if owner_ref is WeakRef else null
	if owner_ref is WeakRef and not is_instance_valid(owner):
		_clear_reservation(junction_index)
		return
	var heartbeat_age := float(Time.get_ticks_msec() - int(state.reservation_heartbeat_ms)) / 1000.0
	if heartbeat_age <= reservation_heartbeat_timeout:
		return
	# A stale owner outside the conflict zone can be recovered safely. A stale
	# owner still inside keeps the junction all-red; releasing it would trade a
	# visible queue for a collision. Active lane AI heartbeats every frame.
	if owner is Node2D:
		var radius := float((_junctions[junction_index] as Dictionary).get("radius", 48.0))
		if (owner as Node2D).global_position.distance_to(_junction_world_position(junction_index)) > radius * 1.5 + stop_line_margin:
			_clear_reservation(junction_index)
			return
	if int(state.stage) != JunctionStage.ALL_RED:
		_set_stage(junction_index, JunctionStage.ALL_RED)
	traffic_contract_violation.emit(&"stale_reservation_inside_junction", {
		"junction_id": state.junction_id,
		"vehicle_instance_id": state.reservation_owner,
		"heartbeat_age": heartbeat_age,
	})


func _clear_reservation(junction_index: int) -> void:
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty():
		return
	var previous_owner := int(state.reservation_owner)
	state.reservation_owner = 0
	state.reservation_road = -1
	state.reservation_lane = &""
	state.reservation_ref = null
	state.reservation_heartbeat_ms = 0
	state.reservation_entered = false
	if previous_owner != 0:
		_telemetry.reservation_releases = int(_telemetry.reservation_releases) + 1
		_waiting_since.erase(previous_owner)
		_deadlock_reported.erase(previous_owner)
		reservation_changed.emit(StringName(state.junction_id), previous_owner, false)


func _track_wait(vehicle_id: int, junction_index: int, road_index: int, lane_id: StringName) -> void:
	if not _waiting_since.has(vehicle_id):
		_waiting_since[vehicle_id] = {
			"started_ms": Time.get_ticks_msec(),
			"junction_index": junction_index,
			"road_index": road_index,
			"lane_id": lane_id,
		}


func _update_wait_telemetry() -> void:
	var now := Time.get_ticks_msec()
	for vehicle_value in _waiting_since.keys():
		var vehicle_id := int(vehicle_value)
		var wait: Dictionary = _waiting_since[vehicle_id]
		var seconds := float(now - int(wait.started_ms)) / 1000.0
		_telemetry.maximum_wait_seconds = maxf(float(_telemetry.maximum_wait_seconds), seconds)
		if seconds > deadlock_telemetry_limit and not _deadlock_reported.has(vehicle_id):
			_deadlock_reported[vehicle_id] = true
			_telemetry.deadlock_limit_exceeded = int(_telemetry.deadlock_limit_exceeded) + 1
			traffic_contract_violation.emit(&"deadlock_limit_exceeded", {
				"vehicle_instance_id": vehicle_id,
				"wait_seconds": seconds,
				"junction_index": wait.junction_index,
				"road_index": wait.road_index,
				"lane_id": wait.lane_id,
			})


func _report_invalid_lane_once(path: Path2D, road_index: int) -> void:
	var instance_id := path.get_instance_id()
	if _warned_lanes.has(instance_id):
		return
	_warned_lanes[instance_id] = true
	_telemetry.invalid_lane_contracts = int(_telemetry.invalid_lane_contracts) + 1
	traffic_contract_violation.emit(&"invalid_directed_lane_contract", {
		"path": path.get_path(),
		"traffic_road_index": road_index,
		"required_group": LANE_GROUP,
	})


func _resolve_junction_index(junction_ref: Variant) -> int:
	if junction_ref is int or junction_ref is float:
		var index := int(junction_ref)
		return index if _states.has(index) else -1
	var key := StringName(junction_ref)
	return int(_junction_id_to_index.get(key, -1))


func _junction_world_position(junction_index: int) -> Vector2:
	if junction_index < 0 or junction_index >= _junctions.size():
		return Vector2.ZERO
	var local_position: Vector2 = (_junctions[junction_index] as Dictionary).get("position", Vector2.ZERO)
	return graph_source.to_global(local_position) if graph_source != null else local_position


func _rebuild_signal_visuals() -> void:
	for visual_value in _signal_visuals.values():
		var previous := visual_value as Node
		if is_instance_valid(previous):
			previous.queue_free()
	_signal_visuals.clear()
	for junction_index in _junctions.size():
		var junction: Dictionary = _junctions[junction_index]
		var approaches: Array = junction.get("approaches", [])
		if approaches.is_empty():
			continue
		var visual := SIGNAL_VISUAL.new()
		visual.name = "Signals_%s" % String(junction.id)
		visual.z_index = 32
		add_child(visual)
		visual.global_position = _junction_world_position(junction_index)
		visual.configure(StringName(junction.id), float(junction.get("radius", 48.0)), approaches)
		_signal_visuals[junction_index] = visual
	_refresh_signal_visuals()


func _refresh_signal_visuals() -> void:
	for index_value in _signal_visuals.keys():
		var junction_index := int(index_value)
		var visual = _signal_visuals[junction_index]
		if not is_instance_valid(visual):
			continue
		visual.global_position = _junction_world_position(junction_index)
		visual.set_road_states(_signal_states_for_junction(junction_index))


func _synchronize_crossing_consumers() -> void:
	if not is_inside_tree():
		return
	var seen: Dictionary = {}
	for group_name in [&"road_crossing_area", &"road_crossing", &"traffic_crossing"]:
		for crossing in get_tree().get_nodes_in_group(group_name):
			if seen.has(crossing.get_instance_id()):
				continue
			seen[crossing.get_instance_id()] = true
			if not crossing.has_method("get_crossing_data") or not crossing.has_method("set_signal_state"):
				continue
			var data = crossing.call("get_crossing_data")
			if not data is Dictionary:
				continue
			var junction_ref: Variant = (data as Dictionary).get("junction_id", -1)
			var road_index := int((data as Dictionary).get("road_index", -1))
			var crossing_id := StringName((data as Dictionary).get("crossing_id", &""))
			crossing.call(
				"set_signal_state",
				get_vehicle_permission(junction_ref, road_index),
				is_pedestrian_phase(junction_ref, road_index, crossing_id)
			)
	# Synchronization is deliberately per RoadCrossingArea2D above. The older
	# safety-system API lacks road_index, so calling it once per road would let
	# the last call overwrite every crossing at that junction.


func get_junction_id(junction_index: int) -> StringName:
	var state: Dictionary = _states.get(junction_index, {})
	return StringName(state.get("junction_id", &""))


func get_junction_snapshot(junction_ref: Variant) -> Dictionary:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty():
		return {}
	return {
		"junction_index": index,
		"junction_id": state.junction_id,
		"position": _junction_world_position(index),
		"stage": state.stage,
		"signal_states": _signal_states_for_junction(index),
		"active_roads": (state.phases as Array)[int(state.phase_index)].duplicate() if int(state.stage) != JunctionStage.ALL_RED else [],
		"reservation_owner": state.reservation_owner,
		"reservation_road": state.reservation_road,
		"reservation_lane": state.reservation_lane,
	}


func _signal_states_for_junction(junction_index: int) -> Dictionary:
	var result := {}
	var state: Dictionary = _states.get(junction_index, {})
	for road_index in state.get("roads", []):
		result[int(road_index)] = get_signal_state(junction_index, int(road_index))
	return result


func get_telemetry_snapshot() -> Dictionary:
	var snapshot: Dictionary = _telemetry.duplicate(true)
	snapshot["junction_count"] = _junctions.size()
	snapshot["active_reservations"] = 0
	for state_value in _states.values():
		if int((state_value as Dictionary).get("reservation_owner", 0)) != 0:
			snapshot.active_reservations = int(snapshot.active_reservations) + 1
	return snapshot


func is_lane_spawn_position_safe(path: Path2D, progress: float, vehicle_length: float) -> bool:
	if path == null or path.curve == null:
		return false
	var road_index := int(path.get_meta("traffic_road_index", -1))
	if road_index < 0:
		return false
	var route_length := maxf(1.0, path.curve.get_baked_length())
	var loops := bool(path.get_meta("traffic_lane_loop", false))
	for projection_value in _lane_junction_projections(path, road_index):
		var projection := projection_value as Dictionary
		var separation := absf(float(projection.offset) - progress)
		if loops:
			separation = minf(separation, route_length - separation)
		var exclusion := float(projection.radius) + vehicle_length * 0.5 + stop_line_margin
		if separation < exclusion:
			return false
	return true
