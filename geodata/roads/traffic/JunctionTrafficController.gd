class_name JunctionTrafficController
extends Node

## Logical traffic authority for the junctions already discovered by
## UnifiedRoadNetwork2D. This class never intersects road geometry and never
## reads provider control points: its only junction source is
## get_graph_data()["junctions"]. Directed Path2D lanes register their
## traffic_road_index metadata against those junction records.

signal junction_stage_changed(junction_id: StringName, stage: int, active_roads: Array)
signal reservation_changed(junction_id: StringName, vehicle_instance_id: int, occupied: bool)

# A long vehicle can span two nearby conflict zones. The previous zone stays
# reserved until the rear clears while the next zone is acquired normally.
var _retained_junctions: Dictionary = {}
signal traffic_contract_violation(kind: StringName, details: Dictionary)

enum SignalState { RED, YELLOW, GREEN }
enum JunctionStage { GREEN, YELLOW, ALL_RED }

const CONTROLLER_GROUP: StringName = &"junction_traffic_controller"
const LANE_GROUP: StringName = &"unified_traffic_lane"
const NO_ADVANCE := 0.0
const SIGNAL_VISUAL := preload("res://geodata/roads/traffic/JunctionSignalVisual2D.gd")
const MAX_CONNECTOR_ENTRY_OVERSHOOT := 12.0
const FLOW := preload("res://cars/traffic/TrafficFlowModel.gd")

@export_range(1.0, 60.0, 0.1) var minimum_green_seconds := 5.0
@export_range(0.5, 10.0, 0.1) var yellow_seconds := 2.2
@export_range(0.5, 10.0, 0.1) var all_red_seconds := 1.5
@export_range(1.0, 20.0, 0.1) var pedestrian_clearance_seconds := 6.0
@export_range(0.5, 10.0, 0.1) var pedestrian_walk_seconds := 2.5
@export_range(0.0, 80.0, 1.0) var stop_line_margin := 14.0
@export_range(40.0, 600.0, 1.0) var reservation_request_distance := 220.0
@export_range(1.0, 20.0, 0.1) var reservation_heartbeat_timeout := 4.0
@export_range(5.0, 180.0, 1.0) var deadlock_telemetry_limit := 45.0

var graph_source: Node2D = null
var _junctions: Array[Dictionary] = []
var _states: Dictionary = {}
var _junction_id_to_index: Dictionary = {}
var _graph_signature := ""
var _synced_graph_source_id: int = 0
var _synced_routing_revision: int = -1
var _sync_elapsed := 0.0
var _crossing_sync_elapsed := 0.0
var _batching_stage_publication := false
var _stage_publication_pending := false
var _lane_projection_cache: Dictionary = {}
var _signal_visuals: Dictionary = {}
var _lane_paths_by_id: Dictionary = {}
var _connections_by_id: Dictionary = {}
var _connections_from_lane: Dictionary = {}
var _warned_lanes: Dictionary = {}
var _waiting_since: Dictionary = {}
var _deadlock_reported: Dictionary = {}
# Reverse index (vehicle_instance_id -> junction_index) mirroring
# state.reservation_owner, kept in sync at its only two mutation sites
# (try_reserve_junction / _clear_reservation). Every ambient vehicle in the
# scene calls evaluate_lane_motion() every frame, which previously scanned
# every junction in the district (_owned_junction_for_vehicle /
# _release_if_vehicle_cleared) just to answer "do I already own one?" — an
# O(vehicles x junctions) cost regardless of camera/visibility. This turns
# that lookup into O(1) instead of changing what it computes.
var _vehicle_owned_junction: Dictionary = {}
var _pedestrian_demand: Dictionary = {}
var _crossings_by_junction: Dictionary = {}
var _admission_blockers: Dictionary = {}
var _actor_index_frame := -1
var _traffic_actors: Array[Node] = []
var _simulation_seconds := 0.0
var _telemetry := {
	"reservation_grants": 0,
	"reservation_releases": 0,
	"reservation_denials": 0,
	"red_stop_clamps": 0,
	"connector_entries": 0,
	"connector_handoffs": 0,
	"invalid_lane_contracts": 0,
	"deadlock_limit_exceeded": 0,
	"maximum_wait_seconds": 0.0,
	"queue_yields": 0,
	"blocked_exit_yields": 0,
	"fairness_yields": 0,
}


func _ready() -> void:
	add_to_group(CONTROLLER_GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if graph_source == null:
		graph_source = _discover_graph_source()
	_sync_from_graph()


func _process(delta: float) -> void:
	if get_tree().paused: return
	_simulation_seconds += delta
	if graph_source == null or not is_instance_valid(graph_source):
		graph_source = _discover_graph_source()
	_sync_elapsed += delta
	if _sync_elapsed >= 0.5:
		_sync_elapsed = 0.0
		_sync_from_graph()
	_batching_stage_publication = true
	for index_value in _states.keys():
		var junction_index := int(index_value)
		_validate_reservation(junction_index)
		_advance_junction(junction_index, delta)
	_batching_stage_publication = false
	_update_wait_telemetry()
	_crossing_sync_elapsed += delta
	if _crossing_sync_elapsed >= 0.5:
		_crossing_sync_elapsed = 0.0
		_refresh_lane_path_index()
		_stage_publication_pending = true
	if _stage_publication_pending:
		_stage_publication_pending = false
		_refresh_signal_visuals()
		_synchronize_crossing_consumers()


func configure_graph_source(source: Node2D) -> void:
	graph_source = source
	_graph_signature = ""
	_synced_graph_source_id = 0
	_synced_routing_revision = -1
	_sync_from_graph()


func _traffic_now_ms() -> int:
	# Reservations, queue age and signal stages share simulation time. Frame
	# rate, test acceleration and a paused game must not create fake deadlocks.
	return int(_simulation_seconds * 1000.0)


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
	var source_id := graph_source.get_instance_id()
	var has_revision := graph_source.has_method("get_routing_revision")
	var routing_revision: int = int(graph_source.call("get_routing_revision")) if has_revision else -1
	# Unified increments its revision after a complete rebuild. Avoid deep-copying
	# the entire graph and serializing junctions on every half-second poll.
	if has_revision and source_id == _synced_graph_source_id and routing_revision == _synced_routing_revision:
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
			junction.get("signalized", (junction.get("approaches", []) as Array).size() >= 3),
			junction.get("roads", []),
			junction.get("approaches", []),
			_connection_signature(junction.get("lane_connections", [])),
		])
	var next_signature := str(signature_values)
	# A rebuild can replace Path2D references without changing geometry. Revision
	# changes must refresh connections too; unversioned providers keep the old
	# signature fallback (including detection of in-place geometry edits).
	if not has_revision and source_id == _synced_graph_source_id and next_signature == _graph_signature:
		return
	_synced_graph_source_id = source_id
	_synced_routing_revision = routing_revision
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
		# `signalized` belongs to the canonical graph. The approach-count fallback
		# keeps third-party/fake graph implementations backward compatible while
		# preserving the same >=3 rule.
		var signalized := bool(junction.get("signalized", (junction.get("approaches", []) as Array).size() >= 3))
		junction["signalized"] = signalized
		_junctions.append(junction)
		_junction_id_to_index[junction_id] = index
		var previous: Dictionary = _states.get(index, {})
		var roads := _road_indices(junction)
		var phases: Array = []
		if signalized:
			# One connected road per phase is conservative by design. Both directed
			# lanes of that road share the phase; roads that may conflict never do.
			for road_index in roads:
				phases.append([road_index])
		else:
			# Unsignalized continuations expose every road as freely permitted. The
			# independent reservation owner below still serializes actual occupancy.
			phases.append(roads.duplicate())
		if phases.is_empty():
			phases.append([])
		_states[index] = {
			"junction_id": junction_id,
			"signalized": signalized,
			"roads": roads,
			"phases": phases,
			"phase_index": mini(int(previous.get("phase_index", index % phases.size())), phases.size() - 1),
			"stage": int(previous.get("stage", JunctionStage.GREEN)) if signalized else JunctionStage.GREEN,
			"elapsed": float(previous.get("elapsed", 0.0)) if signalized else 0.0,
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
	if state.is_empty() or not bool(state.get("signalized", false)):
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
			var required_clearance := pedestrian_clearance_seconds if bool(_pedestrian_demand.get(junction_index, false)) else all_red_seconds
			if float(state.elapsed) >= required_clearance and int(state.reservation_owner) == 0 and not _pedestrian_roadway_busy(junction_index):
				state.phase_index = _next_requested_phase(junction_index)
				_set_stage(junction_index, JunctionStage.GREEN)


func _next_requested_phase(junction_index: int) -> int:
	var state: Dictionary = _states[junction_index]
	var phases: Array = state.phases
	var current := int(state.phase_index)
	var chosen := -1
	var oldest := 9223372036854775807
	# Serve actual demand on other approaches before repeating this one. Empty
	# approaches need no green interval, but yellow and pedestrian clearance
	# are always completed before this selection runs.
	for step in range(1, phases.size() + 1):
		var candidate := (current + step) % phases.size()
		if candidate == current and chosen >= 0: break
		for request in _waiting_since.values():
			if int(request.junction_index) != junction_index or not phases[candidate].has(int(request.road_index)): continue
			if _traffic_now_ms() - int(request.last_seen_ms) > int(reservation_heartbeat_timeout * 1000): continue
			var reference = request.get("vehicle_ref")
			var actor: Node2D = reference.get_ref() as Node2D if reference is WeakRef else null
			if not is_instance_valid(actor) or int(request.started_ms) >= oldest: continue
			if not _admission_ready(actor, junction_index): continue
			chosen = candidate
			oldest = int(request.started_ms)
	return chosen if chosen >= 0 else (current + 1) % phases.size()


func _set_stage(junction_index: int, next_stage: JunctionStage) -> void:
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or not bool(state.get("signalized", false)) or int(state.stage) == next_stage:
		return
	state.stage = next_stage
	state.elapsed = 0.0
	var active_roads: Array = []
	if next_stage != JunctionStage.ALL_RED:
		active_roads = (state.phases as Array)[int(state.phase_index)].duplicate()
	junction_stage_changed.emit(StringName(state.junction_id), next_stage, active_roads)
	# Multiple junctions commonly change phase on the same tick. Keep all logical
	# changes/signals immediate, then publish their final states once before this
	# _process returns. External/manual stage changes still publish immediately.
	if _batching_stage_publication:
		_stage_publication_pending = true
		return
	_refresh_signal_visuals()
	_synchronize_crossing_consumers()


func get_vehicle_permission(junction_ref: Variant, road_index: int, _lane_id: StringName = &"") -> bool:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty() or not (state.get("roads", []) as Array).has(road_index):
		return false
	if not bool(state.get("signalized", false)):
		return true
	if int(state.stage) != JunctionStage.GREEN:
		return false
	var active_roads: Array = (state.phases as Array)[int(state.phase_index)]
	return active_roads.has(road_index)


func can_clear_crossing(vehicle: Node, junction_ref: Variant, crossing: Node2D = null) -> bool:
	# Crossing lights stop new arrivals; they must not trap a vehicle already
	# committed to this same conflict zone while all-red waits for its exit.
	if not is_instance_valid(vehicle):
		return false
	var junction_index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or not bool(state.get("signalized", false)):
		return false
	if int(state.get("reservation_owner", 0)) == vehicle.get_instance_id() and bool(state.get("reservation_entered", false)):
		return true
	# A car may have spawned on the exit or released its reservation already.
	# Its canonical lane must put the junction behind and this zebra ahead,
	# with its body still clearing the conflict envelope, never approaching it.
	if crossing == null or not vehicle is Node2D:
		return false
	var follow := vehicle.get_parent() as PathFollow2D
	if follow == null:
		return false
	var path := follow.get_parent() as Path2D
	if path == null or path.curve == null or not path.is_in_group(LANE_GROUP):
		return false
	var road_index := int(path.get_meta("traffic_road_index", -1))
	# Use the same live property as signal synchronization; configure-time
	# metadata need not follow later road association changes.
	var crossing_road_index := int(crossing.road_index) if "road_index" in crossing else -1
	if road_index < 0 or road_index != crossing_road_index:
		return false
	var center := _junction_world_position(junction_index)
	var actor := vehicle as Node2D
	var body_radius := 0.0
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D:
		return false
	var half_size := (collision.shape as RectangleShape2D).size * 0.5
	for corner in [Vector2(-half_size.x,-half_size.y),Vector2(half_size.x,-half_size.y),half_size,Vector2(-half_size.x,half_size.y)]:
		body_radius = maxf(body_radius,actor.global_position.distance_to(collision.to_global(corner)))
	var radius := float((_junctions[junction_index] as Dictionary).get("radius",48.0))
	if actor.global_position.distance_to(center) > radius + body_radius + stop_line_margin:
		return false
	var progress := path.curve.get_closest_offset(path.to_local(actor.global_position))
	var crossing_offset := path.curve.get_closest_offset(path.to_local(crossing.global_position))
	if crossing_offset <= progress + 0.5:
		return false
	var length := path.curve.get_baked_length()
	var forward := path.to_global(path.curve.sample_baked(minf(length,progress+2.0))) - path.to_global(path.curve.sample_baked(maxf(0.0,progress-2.0)))
	if forward.is_zero_approx() or (actor.global_position-center).dot(forward.normalized()) <= 0.5:
		return false
	for projection in _lane_junction_projections(path,road_index):
		if int(projection.junction_index) == junction_index:
			return progress > float(projection.offset) + 0.5
	return false


func get_signal_state(junction_ref: Variant, road_index: int) -> SignalState:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty():
		return SignalState.RED
	if not bool(state.get("signalized", false)):
		return SignalState.GREEN if (state.get("roads", []) as Array).has(road_index) else SignalState.RED
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
		and bool(state.get("signalized", false)) \
		and int(state.stage) == JunctionStage.ALL_RED \
		and int(state.reservation_owner) == 0 \
		and float(state.elapsed) < pedestrian_walk_seconds


func _pedestrian_roadway_busy(junction_index: int) -> bool:
	for crossing in _crossings_by_junction.get(junction_index, []):
		if is_instance_valid(crossing) and crossing.has_method("has_pedestrian_on_roadway") and crossing.has_pedestrian_on_roadway():
			return true
	return false


func notify_crossing_demand(junction_ref: Variant, _crossing_axis: Variant = &"", active: bool = true) -> void:
	var index := _resolve_junction_index(junction_ref)
	if index < 0 or not is_junction_signalized(index):
		return
	_pedestrian_demand[index] = active


func is_junction_signalized(junction_ref: Variant) -> bool:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	return not state.is_empty() and bool(state.get("signalized", false))


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
		state.reservation_heartbeat_ms = _traffic_now_ms()
		return true
	_track_wait(vehicle_instance_id, index, road_index, lane_id)
	_waiting_since[vehicle_instance_id]["vehicle_ref"] = weakref(vehicle) if vehicle != null else null
	if not get_vehicle_permission(index, road_index, lane_id) or int(state.reservation_owner) != 0:
		_telemetry.reservation_denials = int(_telemetry.reservation_denials) + 1
		_track_wait(vehicle_instance_id, index, road_index, lane_id)
		return false
	if vehicle is Node2D and not _admission_ready(vehicle, index):
		_telemetry.reservation_denials += 1
		return false
	# Oldest eligible head of queue goes first. A red approach, vanished actor,
	# blocked exit or follower cannot hold up a different usable entrance.
	var request: Dictionary = _waiting_since[vehicle_instance_id]
	for other_id in _waiting_since:
		if int(other_id) == vehicle_instance_id: continue
		var other: Dictionary = _waiting_since[other_id]
		if int(other.junction_index) != index: continue
		if int(other.started_ms) > int(request.started_ms): continue
		if int(other.started_ms) == int(request.started_ms) and int(other_id) > vehicle_instance_id: continue
		if _traffic_now_ms() - int(other.get("last_seen_ms", 0)) > int(reservation_heartbeat_timeout * 1000): continue
		if not get_vehicle_permission(index, int(other.road_index), StringName(other.lane_id)): continue
		var reference = other.get("vehicle_ref")
		var actor: Node2D = reference.get_ref() as Node2D if reference is WeakRef else null
		if is_instance_valid(actor) and _admission_ready(actor, index):
			_telemetry.fairness_yields += 1
			return false
	state.reservation_owner = vehicle_instance_id
	state.reservation_road = road_index
	state.reservation_lane = lane_id
	state.reservation_ref = weakref(vehicle) if vehicle != null else null
	state.reservation_heartbeat_ms = _traffic_now_ms()
	state.reservation_entered = false
	_vehicle_owned_junction[vehicle_instance_id] = index
	_waiting_since.erase(vehicle_instance_id)
	_deadlock_reported.erase(vehicle_instance_id)
	_telemetry.reservation_grants = int(_telemetry.reservation_grants) + 1
	reservation_changed.emit(StringName(state.junction_id), vehicle_instance_id, true)
	return true


func _admission_ready(vehicle: Node2D, junction_index: int) -> bool:
	if _pedestrian_roadway_busy(junction_index): return false
	var follow := vehicle.get_parent() as PathFollow2D
	var path := follow.get_parent() as Path2D if follow != null else null
	if path == null or path.curve == null or not path.is_in_group(LANE_GROUP): return true
	var next := _next_lane_junction(path, follow, int(path.get_meta("traffic_road_index", -1)))
	if next.is_empty() or int(next.junction_index) != junction_index: return false
	var leader := FLOW.lane_leader(vehicle, path, follow, float(next.distance))
	if leader != null:
		_admission_blockers[vehicle.get_instance_id()] = weakref(leader)
		_telemetry.queue_yields += 1
		return false
	var connection := _planned_connection(vehicle, path, follow)
	var outgoing := path
	var center_offset := float(next.offset)
	var start := center_offset + float(next.radius)
	if bool(connection.get("requires_connector", false)):
		outgoing = _lane_paths_by_id.get(String(connection.get("to_lane_id", ""))) as Path2D
		if not is_instance_valid(outgoing) or outgoing.curve == null: return false
		center_offset = outgoing.curve.get_closest_offset(outgoing.to_local(_junction_world_position(junction_index)))
		start = maxf(float(connection.get("exit_curve_offset", 0.0)), center_offset + float(next.radius))
	var extent := FLOW.extent(vehicle, vehicle.global_transform.x.normalized())
	if not _tour_admits(path, outgoing): return false
	# Articulation can shorten the projected hull during a bend; reserve the
	# full road length, so a bus never budgets only its leading section.
	var body_length := extent.x + extent.y
	if vehicle.has_method("get_traffic_storage_length"):
		body_length = maxf(body_length, float(vehicle.get_traffic_storage_length()))
	if _actor_index_frame != Engine.get_process_frames():
		_actor_index_frame = Engine.get_process_frames()
		_traffic_actors = get_tree().get_nodes_in_group("vehicle")
	var blocker := FLOW.exit_blocker(vehicle, outgoing, start, start + body_length + stop_line_margin + FLOW.STANDSTILL_GAP, _traffic_actors)
	if blocker != null:
		_admission_blockers[vehicle.get_instance_id()] = weakref(blocker)
		_telemetry.blocked_exit_yields += 1
		if _try_queue_detour(vehicle, path, follow, next, connection, body_length):
			_admission_blockers.erase(vehicle.get_instance_id())
			return true
		return false
	_admission_blockers.erase(vehicle.get_instance_id())
	return true


func _try_queue_detour(vehicle: Node2D, path: Path2D, follow: PathFollow2D, next: Dictionary, original: Dictionary, body_length: float) -> bool:
	# Rethink the next legal turn after a real queue delay. Never reroute an
	# occupied connector or a mission/taxi route, and never bypass exit storage.
	if not "block_wait_timer" in vehicle or float(vehicle.block_wait_timer) < 6.0: return false
	if vehicle.has_meta("taxi_route_end") or path.is_in_group("unified_lane_connector"): return false
	var owned := _owned_junction_for_vehicle(vehicle.get_instance_id())
	if owned >= 0 and bool(_states[owned].reservation_entered): return false
	var now := _traffic_now_ms()
	if now < int(follow.get_meta("traffic_detour_after_ms", 0)): return false
	follow.set_meta("traffic_detour_after_ms", now + 3000)
	var lane_id := String(path.get_meta("traffic_lane_id", ""))
	var candidates := _collect_planning_candidates(lane_id, int(next.junction_index), follow.progress, false)
	for candidate in candidates:
		if String(candidate.get("connection_id", "")) == String(original.get("connection_id", "")): continue
		# A late decision may not reverse back to an already-passed turn entry.
		if bool(candidate.get("requires_connector", false)) and float(candidate.get("entry_curve_offset", -1.0)) < follow.progress: continue
		var outgoing := path
		var start := float(next.offset) + float(next.radius)
		if bool(candidate.get("requires_connector", false)):
			outgoing = _lane_paths_by_id.get(String(candidate.get("to_lane_id", ""))) as Path2D
			if not is_instance_valid(outgoing) or outgoing.curve == null: continue
			var center := outgoing.curve.get_closest_offset(outgoing.to_local(_junction_world_position(int(next.junction_index))))
			start = maxf(float(candidate.get("exit_curve_offset", 0.0)), center + float(next.radius))
		if FLOW.exit_blocker(vehicle, outgoing, start, start + body_length + stop_line_margin + FLOW.STANDSTILL_GAP, _traffic_actors) != null: continue
		follow.set_meta("traffic_planned_connection_id", String(candidate.connection_id))
		follow.set_meta("traffic_planned_junction_index", int(next.junction_index))
		vehicle.set_meta("traffic_queue_detours", int(vehicle.get_meta("traffic_queue_detours", 0)) + 1)
		return true
	return false


func notify_vehicle_entered(junction_ref: Variant, vehicle_instance_id: int) -> void:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if not state.is_empty() and int(state.reservation_owner) == vehicle_instance_id:
		state.reservation_entered = true
		state.reservation_heartbeat_ms = _traffic_now_ms()


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
	_admission_blockers.erase(vehicle_instance_id)


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
		_refresh_retained_junctions(vehicle, vehicle_length)
		return _evaluate_connector_motion(vehicle, path, desired_advance)
	var road_index := int(path.get_meta("traffic_road_index", -1))
	var lane_id := StringName(path.get_meta("traffic_lane_id", path.name))
	if not path.is_in_group(LANE_GROUP):
		return unrestricted
	if road_index < 0:
		_report_invalid_lane_once(path, road_index)
		return unrestricted
	_release_if_vehicle_cleared(vehicle, vehicle_length)
	var vehicle_id := vehicle.get_instance_id()
	var owned_junction := _owned_junction_for_vehicle(vehicle_id)
	if owned_junction >= 0:
		var held: Dictionary = _states[owned_junction]
		# Permission to approach is revocable until entry. A waiting car cannot
		# keep an obsolete green or an exit that has filled since its request.
		if not bool(held.reservation_entered) and (not get_vehicle_permission(owned_junction, road_index, lane_id) or not _admission_ready(vehicle, owned_junction)):
			_clear_reservation(owned_junction)
			owned_junction = -1
	# A long render frame must stop at the authored turn entry, not skip it
	# and discard the plan as an excessive connector overshoot. The normal
	# post-movement handoff still requires the junction reservation below.
	var planned_id := String(follow.get_meta("traffic_planned_connection_id", ""))
	var planned: Dictionary = _connections_by_id.get(planned_id, {})
	var compound_link := bool(path.get_meta("compound_junction_reservations", false)) or (vehicle.has_method("get_traffic_storage_length") and float(vehicle.get_traffic_storage_length()) >= 110.0)
	if bool(planned.get("requires_connector", false)) and String(planned.get("from_lane_id", "")) == String(lane_id) and (compound_link or owned_junction < 0 or int(planned.get("junction_index", -1)) == owned_junction):
		var entry_distance := float(planned.get("entry_curve_offset", -1.0)) - follow.progress
		if entry_distance >= 0.0 and entry_distance < float(unrestricted.allowed_advance):
			unrestricted.allowed_advance = entry_distance
			unrestricted.controlled = true
	var next: Dictionary = {}
	if compound_link and owned_junction >= 0:
		next = _next_lane_junction(path, follow, road_index)
	var adjoining_transition := compound_link and owned_junction >= 0 and not next.is_empty() and int(next.junction_index) != owned_junction and int(planned.get("junction_index", -1)) == int(next.junction_index) and String(planned.get("from_lane_id", "")) == String(lane_id)
	if owned_junction >= 0 and not adjoining_transition:
		var owned_state: Dictionary = _states[owned_junction]
		var owned_radius := float((_junctions[owned_junction] as Dictionary).get("radius", 48.0))
		owned_state.reservation_heartbeat_ms = _traffic_now_ms()
		if vehicle.global_position.distance_to(_junction_world_position(owned_junction)) <= owned_radius + vehicle_length * 0.5:
			notify_vehicle_entered(owned_junction, vehicle_id)
		unrestricted.controlled = true
		unrestricted.reservation_granted = true
		unrestricted.junction_index = owned_junction
		unrestricted.junction_id = owned_state.junction_id
		return unrestricted
	if next.is_empty():
		next = _next_lane_junction(path, follow, road_index)
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
	var distance_to_world_center := vehicle.global_position.distance_to(_junction_world_position(junction_index))
	if int(state.reservation_owner) == vehicle_id:
		state.reservation_heartbeat_ms = _traffic_now_ms()
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
		if adjoining_transition:
			var retained: Array = _retained_junctions.get(vehicle_id, [])
			if not retained.has(owned_junction):
				retained.append(owned_junction)
			_retained_junctions[vehicle_id] = retained
		unrestricted.controlled = true
		unrestricted.reservation_granted = true
		unrestricted.junction_index = junction_index
		unrestricted.junction_id = state.junction_id
		unrestricted.stop_distance = stop_distance
		return unrestricted

	var must_yield := signal_state != SignalState.GREEN or (close_enough_to_reserve and not reserved)
	if not must_yield:
		return unrestricted
	var safe_stop_distance := maxf(NO_ADVANCE, stop_distance)
	var safe_braking := maxf(1.0, braking_rate)
	var braking_distance := current_speed * current_speed / (2.0 * safe_braking) + vehicle_length * 0.5 + 12.0
	var target_speed := sqrt(maxf(0.0, 2.0 * safe_braking * safe_stop_distance))
	var result := {
		"controlled": true,
		"must_stop": safe_stop_distance <= maxf(braking_distance, reservation_request_distance),
		"allowed_advance": minf(float(unrestricted.allowed_advance), safe_stop_distance),
		"target_speed": target_speed,
		"signal_state": signal_state,
		"reservation_granted": false,
		"junction_index": junction_index,
		"junction_id": state.junction_id,
		"stop_distance": safe_stop_distance,
	}
	if safe_stop_distance <= desired_advance + 0.001:
		_telemetry.red_stop_clamps = int(_telemetry.red_stop_clamps) + 1
	if bool(result.must_stop):
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
	state.reservation_heartbeat_ms = _traffic_now_ms()
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
		if not loops and distance < -0.5:
			continue
		if distance < best_distance:
			best_distance = distance
			best = projection.duplicate()
			best["distance"] = distance
	return best


func _lane_junction_projections(path: Path2D, road_index: int) -> Array:
	var curve_length := path.curve.get_baked_length()
	# _sync_from_graph clears this cache whenever the graph signature changes.
	# Do not copy/hash the entire graph signature for every vehicle query.
	var cache_key := "%d:%d:%.3f" % [path.get_instance_id(), road_index, curve_length]
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


## progress lets a caller ask "is there still a reachable transition ahead of
## where this vehicle actually is", not just "does one exist somewhere on this
## lane". A vehicle can spawn (ambient traffic is scattered across each lane's
## progress range at load time) past a connector's entry_curve_offset -- the
## only way off a dead-end lane segment like westgate_drive's southern end,
## 190px from the harbor seawall. Ignoring progress here made
## _open_lane_end_motion report "a transition exists" and skip end-of-lane
## braking for that vehicle forever, even though _planned_connection() would
## always reject the same connector as already passed (entry_curve_offset <
## progress). The vehicle then cruised at full speed to the curve's hard
## clamp and sat there indefinitely, revving with nowhere left to go -- easy
## for a player to carjack with zero reaction room before the wall. Default
## -1.0 preserves the old "exists anywhere" answer for other callers.
func has_lane_transition(path: Path2D, progress: float = -1.0) -> bool:
	if path == null or path.curve == null or not path.is_in_group(LANE_GROUP):
		return false
	var lane_id := String(path.get_meta("traffic_lane_id", ""))
	var road_index := int(path.get_meta("traffic_road_index", -1))
	var length := path.curve.get_baked_length()
	for connection_value in _connections_from_lane.get(lane_id, []):
		var connection := connection_value as Dictionary
		if not bool(connection.get("requires_connector", false)):
			continue
		if progress >= 0.0 and float(connection.get("entry_curve_offset", -1.0)) < progress - 0.5:
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
	# _planned_connection() only ever hands back a connection that needed
	# the relaxed, per-connection landing_overshoot_allowance when its own
	# strict pass (the original, unwidened MAX_CONNECTOR_ENTRY_OVERSHOOT)
	# found nothing else at all -- so honouring that same allowance here
	# just executes the plan it already made; it can never let a connection
	# through that strict planning would otherwise have skipped.
	if follow.progress - entry_offset > _connector_entry_overshoot_limit(connection):
		follow.remove_meta("traffic_planned_connection_id")
		follow.remove_meta("traffic_planned_junction_index")
		return false
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or int(state.reservation_owner) != vehicle.get_instance_id():
		return false
	var connector := connection.get("path") as Path2D
	if connector == null or not is_instance_valid(connector) or connector.curve == null:
		return false
	var overshoot := maxf(0.0, follow.progress - entry_offset)
	if vehicle.has_method("can_apply_lane_pose"):
		var pose := connector.global_transform * connector.curve.sample_baked_with_rotation(minf(overshoot, connector.curve.get_baked_length()), follow.cubic_interp) * vehicle.transform
		if not vehicle.can_apply_lane_pose(pose): return false
	follow.reparent(connector, false)
	follow.loop = false
	follow.progress = minf(overshoot, connector.curve.get_baked_length())
	follow.set_meta("traffic_planned_connection_id", String(connection.connection_id))
	follow.set_meta("traffic_planned_junction_index", junction_index)
	_telemetry.connector_entries = int(_telemetry.connector_entries) + 1
	return true


## A vehicle overshoots its planned turn's entry_curve_offset two different
## ways: driving too fast to react (the original, narrow reason
## MAX_CONNECTOR_ENTRY_OVERSHOOT exists -- "you missed it, live with it"), or
## simply materializing past it because a PRIOR connector's own
## exit_curve_offset landed it there directly, with no chance to react at
## all. The second case is not a missed turn and needs a bigger allowance,
## but ONLY for the exact connections where it structurally happens --
## a junction-radius formula applied to every connection at a junction was
## tried and reverted: it also widened the tolerance for ordinary
## drove-past-it-too-fast overshoot on OTHER, unrelated connections sharing
## that junction, including ones on Bairro1's rail level crossing approach,
## and that caused a real vehicle/train collision
## (rail_level_crossing_runtime_test). UnifiedRoadNetwork2D._build_lane_connections
## now computes, once per connection at graph-build time, the *exact* extra
## allowance a specific connection needs (0.0 for the overwhelming majority)
## by checking whether its own exit_curve_offset already lands past the
## destination lane's own outgoing entry_curve_offset at the same junction --
## precisely the structural case (a short lane whose relevant end IS the
## junction) that stranded HarborTraffic_00 arriving at
## junction_039_7400_1700 via the cobra_approach connector. Every other
## connection's allowance is 0.0, so this cannot change behaviour anywhere
## else, including the rail crossing.
func _connector_entry_overshoot_limit(connection: Dictionary) -> float:
	return maxf(MAX_CONNECTOR_ENTRY_OVERSHOOT, float(connection.get("landing_overshoot_allowance", 0.0)))


func _planned_connection(vehicle: Node2D, path: Path2D, follow: PathFollow2D) -> Dictionary:
	var planned_id := String(follow.get_meta("traffic_planned_connection_id", ""))
	if not planned_id.is_empty() and _connections_by_id.has(planned_id):
		var existing: Dictionary = _connections_by_id[planned_id]
		var destination := _lane_paths_by_id.get(String(existing.get("to_lane_id", ""))) as Path2D
		if String(existing.get("from_lane_id", "")) == String(path.get_meta("traffic_lane_id", "")) and _tour_admits(path, destination):
			return existing
		follow.remove_meta("traffic_planned_connection_id")
		follow.remove_meta("traffic_planned_junction_index")
	var road_index := int(path.get_meta("traffic_road_index", -1))
	var next := _next_lane_junction(path, follow, road_index)
	if next.is_empty():
		return {}
	var junction_index := int(next.junction_index)
	var lane_id := String(path.get_meta("traffic_lane_id", ""))
	# Two passes: strict first (the original, unwidened MAX_CONNECTOR_ENTRY_
	# OVERSHOOT tolerance), and only if that finds nothing at all, a second,
	# relaxed pass using each candidate's precomputed landing_overshoot_
	# allowance (0.0 for the overwhelming majority of connections; see
	# UnifiedRoadNetwork2D._build_lane_connections). This is a *last resort*,
	# not a proactive allowance: a wider tolerance was tried unconditionally
	# instead and, even scoped per-connection, changed a vehicle's timing
	# through Bairro1Expansion's midtown_cross/east_arc junction -- which
	# structurally has the same "arrival lands past this junction's own
	# exit" pattern as the Cobra roundabout, but where the strict pass
	# already always succeeds in practice -- shifting exactly when it
	# reached the adjacent rail crossing and causing a real vehicle/train
	# collision. Only falling back when strict planning would otherwise
	# leave the vehicle with zero candidates (the genuine "permanently
	# stuck" case, as arriving via the cobra_approach connector did) keeps
	# every junction that already works unaffected.
	var candidates: Array[Dictionary] = _collect_planning_candidates(lane_id, junction_index, follow.progress, false)
	if candidates.is_empty():
		candidates = _collect_planning_candidates(lane_id, junction_index, follow.progress, true)
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


func _collect_planning_candidates(lane_id: String, junction_index: int, progress: float, allow_landing_overshoot: bool) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for connection_value in _connections_from_lane.get(lane_id, []):
		var candidate := connection_value as Dictionary
		if int(candidate.get("junction_index", -1)) != junction_index:
			continue
		if not _tour_admits(_lane_paths_by_id.get(lane_id) as Path2D, _lane_paths_by_id.get(String(candidate.get("to_lane_id", ""))) as Path2D):
			continue
		if bool(candidate.get("requires_connector", false)):
			var limit := _connector_entry_overshoot_limit(candidate) if allow_landing_overshoot else MAX_CONNECTOR_ENTRY_OVERSHOOT
			if float(candidate.get("entry_curve_offset", -1.0)) < progress - limit:
				continue
			var connector := candidate.get("path") as Path2D
			if connector == null or not is_instance_valid(connector):
				continue
		elif String(candidate.get("to_lane_id", "")) == lane_id and is_equal_approx(float(candidate.get("to_road_progress", -1.0)), float(candidate.get("from_road_progress", -2.0))):
			# A genuine "continue straight through this junction on the same
			# lane, no connector needed" entry always advances road_progress
			# (the junction sits partway along a longer, unbroken lane). One
			# whose from/to road_progress are identical on its OWN lane is a
			# graph artefact: both ends of a tight quarter-arc road (e.g. the
			# Ashbend/Cobra roundabout's cobra_court_southwest) can register
			# against the same junction, and the connection builder pairs the
			# lane with itself as if traffic could just keep going. There is
			# nowhere left to go -- this vehicle is already at progress ==
			# curve length. Picking this candidate (previously equally likely
			# to be hash-selected as the two real, connector-requiring exits
			# here) permanently stranded HarborTraffic_05 at the Cobra
			# roundabout entrance: reservation granted, signal green, engine
			# desiring to move, and nowhere the game would ever let it go.
			continue
		candidates.append(candidate)
	return candidates


func _movement_priority(movement: String) -> int:
	match movement:
		"straight":
			return 0
		"right":
			return 1
		_:
			return 2

func _tour_admits(origin: Path2D, destination: Path2D) -> bool:
	const RESERVATION = preload("res://world/harbor/campaign/TourTrafficReservation.gd")
	return not RESERVATION.reserved(destination) or RESERVATION.reserved(origin)


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
	for actor in follow.get_children():
		if actor is Node2D and actor.has_method("can_apply_lane_pose"):
			var pose: Transform2D = target_path.global_transform * target_path.curve.sample_baked_with_rotation(exit_offset, follow.cubic_interp) * actor.transform
			if not actor.can_apply_lane_pose(pose): return false
	follow.reparent(target_path, false)
	follow.loop = bool(target_path.get_meta("traffic_lane_loop", false))
	follow.progress = exit_offset
	follow.remove_meta("traffic_planned_connection_id")
	follow.remove_meta("traffic_planned_junction_index")
	_telemetry.connector_handoffs = int(_telemetry.connector_handoffs) + 1
	return true


func _release_if_vehicle_cleared(vehicle: Node2D, vehicle_length: float) -> void:
	_refresh_retained_junctions(vehicle, vehicle_length)
	var vehicle_id := vehicle.get_instance_id()
	var junction_index := _owned_junction_for_vehicle(vehicle_id)
	if junction_index < 0:
		return
	_release_one_if_cleared(vehicle, vehicle_length, junction_index)

func _refresh_retained_junctions(vehicle: Node2D, vehicle_length: float) -> void:
	var retained: Array = _retained_junctions.get(vehicle.get_instance_id(), [])
	for junction_index in retained.duplicate():
		var state: Dictionary = _states.get(int(junction_index), {})
		if int(state.get("reservation_owner", 0)) == vehicle.get_instance_id():
			state.reservation_heartbeat_ms = _traffic_now_ms()
		_release_one_if_cleared(vehicle, vehicle_length, int(junction_index))

func _release_one_if_cleared(vehicle: Node2D, vehicle_length: float, junction_index: int) -> void:
	var vehicle_id := vehicle.get_instance_id()
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or int(state.reservation_owner) != vehicle_id:
		return
	var radius := float((_junctions[junction_index] as Dictionary).get("radius", 48.0))
	var distance := vehicle.global_position.distance_to(_junction_world_position(junction_index))
	var body_radius := vehicle_length * 0.5
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision != null and collision.shape is RectangleShape2D:
		var half_size := (collision.shape as RectangleShape2D).size * 0.5
		for corner in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), half_size, Vector2(-half_size.x, half_size.y)]:
			body_radius = maxf(body_radius, vehicle.global_position.distance_to(collision.to_global(corner)))
	if distance <= radius + vehicle_length * 0.5:
		notify_vehicle_entered(junction_index, vehicle_id)
	# Clear only after the whole collision rectangle (including lateral corners)
	# is outside the conflict radius plus margin. Using a FULL vehicle length
	# retained a cleared junction until after the next short-block turn entry.
	elif bool(state.reservation_entered) and distance > radius + body_radius + stop_line_margin:
		if vehicle.has_method("occupies_junction") and vehicle.occupies_junction(_junction_world_position(junction_index),radius+stop_line_margin):
			return
		_clear_reservation(junction_index)


func _owned_junction_for_vehicle(vehicle_instance_id: int) -> int:
	# O(1) common path via the reverse index kept by try_reserve_junction() /
	# _clear_reservation(); falls back to the full scan only if the cache and
	# the authoritative per-junction state ever disagree, so a missed update
	# site would degrade to the old behavior instead of returning a wrong answer.
	var cached := int(_vehicle_owned_junction.get(vehicle_instance_id, -1))
	if cached >= 0:
		var cached_state: Dictionary = _states.get(cached, {})
		if not cached_state.is_empty() and int(cached_state.reservation_owner) == vehicle_instance_id:
			return cached
		_vehicle_owned_junction.erase(vehicle_instance_id)
	for index_value in _states.keys():
		if int((_states[index_value] as Dictionary).get("reservation_owner", 0)) == vehicle_instance_id:
			return int(index_value)
	return -1


func _validate_reservation(junction_index: int) -> void:
	var state: Dictionary = _states.get(junction_index, {})
	if state.is_empty() or int(state.reservation_owner) == 0:
		return
	var owner_ref = state.get("reservation_ref", null)
	var owner: Object = owner_ref.get_ref() if owner_ref is WeakRef else null
	if owner_ref is WeakRef and not is_instance_valid(owner):
		_clear_reservation(junction_index)
		return
	var heartbeat_age := float(_traffic_now_ms() - int(state.reservation_heartbeat_ms)) / 1000.0
	if heartbeat_age <= reservation_heartbeat_timeout:
		return
	# A stale owner outside the conflict zone can be recovered safely. A stale
	# owner still inside keeps the junction all-red; releasing it would trade a
	# visible queue for a collision. Active lane AI heartbeats every frame.
	if owner is Node2D:
		var radius := float((_junctions[junction_index] as Dictionary).get("radius", 48.0))
		var center := _junction_world_position(junction_index)
		var outside := (owner as Node2D).global_position.distance_to(center) > radius * 1.5 + stop_line_margin
		if outside and owner.has_method("occupies_junction"):
			outside = not bool(owner.call("occupies_junction",center,radius+stop_line_margin))
		if outside:
			_clear_reservation(junction_index)
			return
	if bool(state.get("signalized", false)) and int(state.stage) != JunctionStage.ALL_RED:
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
	if _retained_junctions.has(previous_owner):
		var retained: Array = _retained_junctions[previous_owner]
		retained.erase(junction_index)
		if retained.is_empty():
			_retained_junctions.erase(previous_owner)
	state.reservation_owner = 0
	state.reservation_road = -1
	state.reservation_lane = &""
	state.reservation_ref = null
	if int(_vehicle_owned_junction.get(previous_owner, -1)) == junction_index:
		_vehicle_owned_junction.erase(previous_owner)
	state.reservation_heartbeat_ms = 0
	state.reservation_entered = false
	if previous_owner != 0:
		_telemetry.reservation_releases = int(_telemetry.reservation_releases) + 1
		_waiting_since.erase(previous_owner)
		_deadlock_reported.erase(previous_owner)
		reservation_changed.emit(StringName(state.junction_id), previous_owner, false)


func _track_wait(vehicle_id: int, junction_index: int, road_index: int, lane_id: StringName) -> void:
	if not _waiting_since.has(vehicle_id) or int(_waiting_since[vehicle_id].junction_index) != junction_index:
		_waiting_since[vehicle_id] = {
			"started_ms": _traffic_now_ms(),
			"junction_index": junction_index,
			"road_index": road_index,
			"lane_id": lane_id,
			"vehicle_ref": weakref(instance_from_id(vehicle_id)) if is_instance_id_valid(vehicle_id) else null,
		}
	_waiting_since[vehicle_id]["last_seen_ms"] = _traffic_now_ms()


func _update_wait_telemetry() -> void:
	var now := _traffic_now_ms()
	for vehicle_value in _waiting_since.keys():
		var vehicle_id := int(vehicle_value)
		var wait: Dictionary = _waiting_since[vehicle_id]
		if now - int(wait.get("last_seen_ms", now)) > int(reservation_heartbeat_timeout * 1000):
			_waiting_since.erase(vehicle_id)
			_admission_blockers.erase(vehicle_id)
			_deadlock_reported.erase(vehicle_id)
			continue
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
	var curb_surfaces: Array = []
	var sidewalk_surfaces: Array = []
	if is_instance_valid(graph_source) and graph_source.has_method("get_signal_ground_surfaces"):
		curb_surfaces = graph_source.get_signal_ground_surfaces(10.0)
		sidewalk_surfaces = graph_source.get_signal_ground_surfaces(84.0)
	for junction_index in _junctions.size():
		var junction: Dictionary = _junctions[junction_index]
		var approaches: Array = junction.get("approaches", [])
		if approaches.is_empty() or not bool(junction.get("signalized", false)):
			continue
		var visual := SIGNAL_VISUAL.new()
		visual.name = "Signals_%s" % String(junction.id)
		visual.z_index = 32
		visual.ground_source = graph_source
		visual.curb_surfaces = curb_surfaces
		visual.sidewalk_surfaces = sidewalk_surfaces
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
	_crossings_by_junction.clear()
	var seen: Dictionary = {}
	for group_name in [&"road_crossing_area", &"road_crossing", &"traffic_crossing"]:
		for crossing in get_tree().get_nodes_in_group(group_name):
			if seen.has(crossing.get_instance_id()):
				continue
			seen[crossing.get_instance_id()] = true
			if not crossing.has_method("set_signal_state"):
				continue
			var coordinator := crossing.get_parent().get_parent() if crossing.get_parent() != null else null
			if is_instance_valid(coordinator) and coordinator.has_method("_road_graph") and coordinator.call("_road_graph") != graph_source:
				continue
			var junction_id: StringName
			var road_index: int
			var crossing_id: StringName
			if "junction_id" in crossing and "road_index" in crossing and "crossing_id" in crossing:
				junction_id = StringName(crossing.junction_id)
				road_index = int(crossing.road_index)
				crossing_id = StringName(crossing.crossing_id)
			else:
				if not crossing.has_method("get_crossing_data"):
					continue
				var data = crossing.call("get_crossing_data")
				if not data is Dictionary:
					continue
				junction_id = StringName((data as Dictionary).get("junction_id", &""))
				road_index = int((data as Dictionary).get("road_index", -1))
				crossing_id = StringName((data as Dictionary).get("crossing_id", &""))
			var junction_index := int(crossing.get_meta("junction_index", -1))
			# A crossing outside a signalized junction keeps its own pedestrian
			# priority logic; assigning false/false would turn it permanently red.
			if junction_id.is_empty() and junction_index < 0:
				continue
			# Stable ids disambiguate local indices when several districts coexist.
			if not junction_id.is_empty() and not _junction_id_to_index.has(junction_id): continue
			var junction_ref: Variant = junction_id if not junction_id.is_empty() else junction_index
			var resolved_index := _resolve_junction_index(junction_ref)
			if resolved_index >= 0:
				if not _crossings_by_junction.has(resolved_index): _crossings_by_junction[resolved_index] = []
				_crossings_by_junction[resolved_index].append(crossing)
			if resolved_index < 0 or not is_junction_signalized(resolved_index):
				# A crossing attached to a two-approach continuation is deliberately
				# unsignalized. Restore its pedestrian-priority behavior instead of
				# feeding it an invisible permanent red/green phase.
				if crossing.has_method("clear_signal_state"):
					crossing.call("clear_signal_state")
				if crossing.has_method("set_signal_controller"):
					crossing.call("set_signal_controller", null)
				continue
			if road_index < 0:
				continue
			if crossing.has_method("set_signal_controller"):
				crossing.call("set_signal_controller", self)
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


func get_reserved_vehicles() -> Array[Node2D]:
	# Simulation budgets must let committed vehicles finish their crossing.
	var result: Array[Node2D] = []
	for state_value in _states.values():
		var owner_id := int(state_value.get("reservation_owner", 0))
		if owner_id == 0:
			continue
		var owner = instance_from_id(owner_id)
		if is_instance_valid(owner) and owner is Node2D and not result.has(owner):
			result.append(owner)
	return result


func get_waiting_traffic_actors() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for vehicle_id in _admission_blockers:
		if not _waiting_since.has(vehicle_id): continue
		var wait: Dictionary = _waiting_since[vehicle_id]
		if _traffic_now_ms() - int(wait.get("last_seen_ms", 0)) > int(reservation_heartbeat_timeout * 1000): continue
		for reference in [wait.get("vehicle_ref"), _admission_blockers[vehicle_id]]:
			var actor: Node2D = reference.get_ref() as Node2D if reference is WeakRef else null
			if is_instance_valid(actor) and not result.has(actor): result.append(actor)
	return result


func is_reservation_owner(junction_ref: Variant, vehicle: Node) -> bool:
	if not is_instance_valid(vehicle): return false
	var state: Dictionary = _states.get(_resolve_junction_index(junction_ref), {})
	return int(state.get("reservation_owner",0)) == vehicle.get_instance_id()

func get_junction_snapshot(junction_ref: Variant) -> Dictionary:
	var index := _resolve_junction_index(junction_ref)
	var state: Dictionary = _states.get(index, {})
	if state.is_empty():
		return {}
	return {
		"junction_index": index,
		"junction_id": state.junction_id,
		"signalized": bool(state.get("signalized", false)),
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
	snapshot["signalized_junction_count"] = 0
	snapshot["unsignalized_junction_count"] = 0
	snapshot["signal_visual_count"] = get_signal_visual_count()
	snapshot["active_reservations"] = 0
	for state_value in _states.values():
		var state := state_value as Dictionary
		if bool(state.get("signalized", false)):
			snapshot.signalized_junction_count = int(snapshot.signalized_junction_count) + 1
		else:
			snapshot.unsignalized_junction_count = int(snapshot.unsignalized_junction_count) + 1
		if int(state.get("reservation_owner", 0)) != 0:
			snapshot.active_reservations = int(snapshot.active_reservations) + 1
	return snapshot


func get_signal_visual_count() -> int:
	var count := 0
	for visual in _signal_visuals.values():
		if is_instance_valid(visual) and not (visual as Node).is_queued_for_deletion():
			count += 1
	return count


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
