extends Node2D
## Temporary, physical race event: stop new arrivals and guide existing cars
## through the normal lane graph to the west exit. No teleport or despawn.
const RING := ["cobra_court_northwest", "cobra_court_northeast", "cobra_court_southeast", "cobra_court_southwest"]
const APPROACH := "cobra_approach"
const PREPARATION_LIMIT := 90.0
var controller: Node2D
var road_id := ""
var active := false
var remaining := 0
var elapsed := 0.0
var _blocked_seconds := 0.0
var _clock := 0.0
var _plans: Dictionary = {}
var _owned: Dictionary = {}
var _pinned: Dictionary = {}

func configure(owner_controller: Node2D) -> bool:
	controller = owner_controller
	# Stop arrivals before the junction reservation window. A nearer gate
	# lets a stopped arrival own the junction and prevent every outbound car.
	global_position = Vector2(6900,1700)
	for node in get_tree().current_scene.find_children("*", "", true, false):
		if not node.has_method("get_graph_data") or not node.has_method("get_lane_path"): continue
		var graph: Dictionary = node.get_graph_data()
		var lanes: Dictionary = {}
		for lane in graph.get("lanes", []):
			lanes[String(lane.lane_id)] = lane
			if String(lane.road_id).get_file() == APPROACH: road_id = String(lane.road_id)
		if road_id.is_empty(): continue
		for connection in graph.get("lane_connections", []):
			var lane: Dictionary = lanes.get(String(connection.from_lane_id), {})
			var destination: Dictionary = lanes.get(String(connection.to_lane_id), {})
			if lane.is_empty() or destination.is_empty(): continue
			var road := String(lane.road_id).get_file()
			var quarter := RING.find(road)
			if quarter < 0: continue
			var direction := int(lane.direction)
			var desired: String = APPROACH if (direction == 1 and quarter == 3) or (direction == -1 and quarter == 0) else RING[quarter + direction]
			var destination_direction := -1 if desired == APPROACH else direction
			if String(destination.road_id).get_file() == desired and int(destination.direction) == destination_direction:
				_plans[String(lane.lane_id)] = connection
		break
	active = _plans.size() == 8 and not road_id.is_empty()
	if active:
		add_to_group("traffic_control_zone")
		_update_routes()
	return active

func get_crossing_data() -> Dictionary:
	return {"id": &"cobra_trial_closure", "road_id":road_id, "position":global_position}

func should_stop_vehicle(vehicle: Node = null) -> bool:
	# The outbound lane stays open so the existing cast physically evacuates.
	if not active or not is_instance_valid(vehicle) or vehicle.get("is_driven_by_player") == true:
		return false
	var follow := vehicle.get_parent() as PathFollow2D
	var path := follow.get_parent() as Path2D if follow != null else null
	return path != null and int(path.get_meta("traffic_direction", 0)) == 1

func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(controller): return
	if not controller._race_started:
		elapsed += delta
		_blocked_seconds = _blocked_seconds + delta if remaining > 0 else 0.0
		if _blocked_seconds > PREPARATION_LIMIT:
			controller.fail_mission(controller._tr("A praça não ficou livre para a prova. Preparação cancelada sem cobrança; tente novamente no quadro do Maciota.", "The square could not be cleared for the trial. Preparation cancelled at no charge; retry at Maciota's board."))
			return
	_clock += delta
	if _clock < 0.25: return
	_clock = 0.0
	_update_routes()

func _update_routes() -> void:
	var previous := remaining
	remaining = 0
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not vehicle is Node2D or vehicle.get("is_driven_by_player") == true: continue
		if blocks_route(vehicle):
			remaining += 1
		var follow := vehicle.get_parent() as PathFollow2D
		if follow == null: continue
		var path := follow.get_parent() as Path2D
		if path == null: continue
		var lane_id := String(path.get_meta("traffic_lane_id", ""))
		var plan: Dictionary = _plans.get(lane_id, {})
		var exit_corridor: bool = String(path.get_meta("traffic_road_id", "")).get_file() == APPROACH or vehicle.global_position.distance_squared_to(Vector2(6450,1700)) < 250.0 * 250.0
		if plan.is_empty() and not exit_corridor: continue
		# The player accepts in a distant interior. Mission traffic must use
		# the population owner's existing keep-alive contract to leave while
		# offscreen; changing route metadata alone cannot wake sleeping cars.
		var actor_key := vehicle.get_instance_id()
		if not _pinned.has(actor_key):
			_pinned[actor_key] = {"actor":weakref(vehicle), "already_pinned":vehicle.is_in_group("simulation_keep_alive")}
			vehicle.add_to_group("simulation_keep_alive")
		if plan.is_empty(): continue
		var key := follow.get_instance_id()
		if not _owned.has(key):
			_owned[key] = {"follow":weakref(follow), "lane":lane_id, "old_id":follow.get_meta("traffic_planned_connection_id") if follow.has_meta("traffic_planned_connection_id") else null, "old_junction":follow.get_meta("traffic_planned_junction_index") if follow.has_meta("traffic_planned_junction_index") else null}
		_owned[key]["assigned"] = String(plan.connection_id)
		follow.set_meta("traffic_planned_connection_id", String(plan.connection_id))
		follow.set_meta("traffic_planned_junction_index", int(plan.junction_index))
	if remaining != previous:
		controller.changed.emit()

func is_clear() -> bool:
	return active and remaining == 0

func blocks_route(vehicle: Node2D) -> bool:
	var follow := vehicle.get_parent() as PathFollow2D
	if follow != null and _plans.has(String(follow.get_parent().get_meta("traffic_lane_id", ""))):
		return true # Moving cars in either course lane must finish evacuating.
	if vehicle.global_position.distance_to(controller.CENTER) > controller.RACE_RADIUS + 150.0:
		return false
	# Parked/personal cars count only when their actual hull intersects the
	# driving corridor, not merely because they are somewhere in the square.
	var collider := vehicle.get_node_or_null("Collision") as CollisionShape2D
	var half_size := Vector2(20,14)
	var pose := vehicle.global_transform
	if collider != null and collider.shape is RectangleShape2D:
		half_size = (collider.shape as RectangleShape2D).size * 0.5
		pose = collider.global_transform
	var minimum := INF
	var maximum := 0.0
	for point in [Vector2(-half_size.x,-half_size.y), Vector2(half_size.x,-half_size.y), half_size, Vector2(-half_size.x,half_size.y)]:
		var distance: float = (pose * point).distance_to(controller.CENTER)
		minimum = minf(minimum, distance)
		maximum = maxf(maximum, distance)
	return minimum <= controller.RACE_LANE_RADIUS + 20.0 and maximum >= controller.RACE_LANE_RADIUS - 20.0

func cleanup() -> void:
	active = false
	remove_from_group("traffic_control_zone")
	for entry in _owned.values():
		var follow: Node = entry.follow.get_ref()
		if not is_instance_valid(follow): continue
		if String(follow.get_meta("traffic_planned_connection_id", "")) != String(entry.get("assigned", "")): continue
		var same_lane: bool = String(follow.get_parent().get_meta("traffic_lane_id", "")) == String(entry.lane)
		for pair in [["traffic_planned_connection_id", "old_id"], ["traffic_planned_junction_index", "old_junction"]]:
			if same_lane and entry[pair[1]] != null: follow.set_meta(pair[0], entry[pair[1]])
			else: follow.remove_meta(pair[0])
	_owned.clear()
	for entry in _pinned.values():
		var actor: Node = entry.actor.get_ref()
		if is_instance_valid(actor) and not entry.already_pinned:
			actor.remove_from_group("simulation_keep_alive")
	_pinned.clear()

func _exit_tree() -> void:
	cleanup()
