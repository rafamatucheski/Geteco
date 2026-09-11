extends Node2D

## Runtime population uses the same generated lane paths and junction authority
## as the live game. No cosmetic cars are translated independently of the graph.
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const CONTROLLER := preload("res://world/shared/roads/traffic/JunctionTrafficController.gd")
const RAIL := preload("res://world/harbor/HarborRailLine.gd")
const CAR_TYPES := ["sedan_classic", "union_sedan", "metro_hatch", "courier_van", "station_wagon", "taxi_yellow", "route_city", "summit_suv"]

@export var rail_path: NodePath = NodePath("../FreightRail")

var _configured := false
var traffic_controller: Node
var rail_line: Node2D
var vehicles: Array[Node2D] = []
var walkers: Array[Node2D] = []
var _traffic_lanes: Array[Path2D] = []
var _traffic_target := 0
var _population_clock := 0.0
var _budget_clock := 0.0
var _spawn_serial := 1000
var _sleeping_vehicles: Dictionary = {}
var _sleeping_walkers: Dictionary = {}


class HarborController extends JunctionTrafficController:
	func try_reserve_junction(junction_ref: Variant, vehicle_instance_id: int, road_index: int, lane_id: StringName = &"", vehicle: Node = null) -> bool:
		var junction_index := _resolve_junction_index(junction_ref)
		var state: Dictionary = _states.get(junction_index, {})
		# Never revoke a committed car's reservation. Gate only NEW requests so
		# node processing order cannot award the junction to the back of a queue.
		if int(state.get("reservation_owner", 0)) != vehicle_instance_id and vehicle != null:
			var follow := vehicle.get_parent() as PathFollow2D
			var path := follow.get_parent() as Path2D if follow != null else null
			if path != null and path.curve != null and is_instance_valid(graph_source) and graph_source.is_ancestor_of(path) and junction_index >= 0:
				var junction_offset := path.curve.get_closest_offset(path.to_local(_junction_world_position(junction_index)))
				for sibling in path.get_children():
					if sibling == follow or not sibling is PathFollow2D or sibling.get_child_count() == 0:
						continue
					if not sibling.get_child(0) is DemoTrafficVehicle:
						continue
					var ahead := sibling as PathFollow2D
					if ahead.progress > follow.progress + 0.5 and ahead.progress <= junction_offset + 0.5:
						_telemetry.reservation_denials = int(_telemetry.reservation_denials) + 1
						_track_wait(vehicle_instance_id, junction_index, road_index, lane_id)
						return false
		return super.try_reserve_junction(junction_ref, vehicle_instance_id, road_index, lane_id, vehicle)


	func _release_if_vehicle_cleared(vehicle: Node2D, vehicle_length: float) -> void:
		super._release_if_vehicle_cleared(vehicle, vehicle_length)
		var owned := _owned_junction_for_vehicle(vehicle.get_instance_id())
		if owned < 0 or not bool(_states[owned].reservation_entered):
			return
		var follow := vehicle.get_parent() as PathFollow2D
		if follow == null or follow.get_parent().is_in_group("unified_lane_connector"):
			return
		var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
		if collision == null or not collision.shape is RectangleShape2D:
			return
		# The broad approach radius overlaps the next zebra on short blocks.
		# Release after the whole body clears the actual perpendicular carriageway.
		# Non-orthogonal junctions retain the generic conservative radius contract.
		var axis := vehicle.global_transform.x.normalized()
		var crossing_half_width := 0.0
		for approach in _junctions[owned].get("approaches", []):
			var tangent: Vector2 = approach.get("entry_tangent", Vector2.ZERO)
			tangent = graph_source.global_transform.basis_xform(tangent).normalized()
			var alignment := absf(axis.dot(tangent))
			if alignment > 0.01 and alignment < 0.99:
				return
			if alignment <= 0.01:
				crossing_half_width = maxf(crossing_half_width, float(approach.road_width) * 0.5)
		if crossing_half_width <= 0.0:
			return
		var center := _junction_world_position(owned)
		var half_size := (collision.shape as RectangleShape2D).size * 0.5
		for corner in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), half_size, Vector2(-half_size.x, half_size.y)]:
			if (collision.to_global(corner) - center).dot(axis) <= crossing_half_width + 8.0:
				return
		_clear_reservation(owned)


	var _demand_index_frame := -1
	var _demand_crossings: Dictionary = {}

	func notify_crossing_demand(junction_ref: Variant, crossing_axis: Variant = &"", active: bool = true) -> void:
		# Several arms share one intersection phase. An empty arm must not erase
		# the request of a person waiting on another arm during signal sync.
		var demanded := active
		var junction_index := _resolve_junction_index(junction_ref)
		if not active and is_inside_tree() and _demand_index_frame != Engine.get_physics_frames():
			_demand_index_frame = Engine.get_physics_frames()
			_demand_crossings.clear()
			for crossing in get_tree().get_nodes_in_group("road_crossing_area"):
				var coordinator := crossing.get_parent().get_parent()
				var same_graph: bool = coordinator.has_method("_road_graph") and coordinator.call("_road_graph") == graph_source
				if same_graph and crossing.has_method("get_crossing_data"):
					var index: int = int(crossing.get_meta("junction_index", -2))
					if not _demand_crossings.has(index): _demand_crossings[index] = []
					_demand_crossings[index].append(crossing)
		if not active:
			for crossing in _demand_crossings.get(junction_index, []):
				if is_instance_valid(crossing):
					var data: Dictionary = crossing.get_crossing_data()
					demanded = demanded or int(data.get("pedestrians_inside", 0)) > 0
		super.notify_crossing_demand(junction_ref, crossing_axis, demanded)


class HarborWalker extends AuthoredSidewalkPedestrian:
	var pause_at_destinations := true
	var destination_pauses := 0
	var _destination_pause := 0.0
	var companion: Node2D
	var appearance_variant := 0

	func _ready() -> void:
		district_theme = DistrictTheme.CITY_DOWNTOWN
		defer_presentation = true
		archetype_override = [0,1,2,4,6,7][appearance_variant%6]
		appearance_seed = appearance_variant
		appearance_gender = 1 + appearance_variant % 2
		super._ready()
		preload("res://world/shared/pedestrians/CitizenDetails.gd").dress(self,appearance_variant)

	# Existing generic shop visits target an approximate facade position. Until
	# preview buildings expose verified entrances, remain on audited promenades.
	func _try_start_poi_visit() -> void:
		pass

	func _physics_process(delta: float) -> void:
		_destination_pause = maxf(0.0, _destination_pause - delta)
		super._physics_process(delta)

	func _pick_new_sidewalk_target() -> void:
		if pause_at_destinations and _route_target_ready:
			_destination_pause = randf_range(0.4, 2.4)
			destination_pauses += 1
		super._pick_new_sidewalk_target()

	func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
		move_speed *= 0.80
		if preload("res://world/harbor/HarborPedestrianRoutes.gd").crossing_wait(self,dest): return Vector2.ZERO
		if is_instance_valid(companion) and not is_scared and not companion.is_dead:
			var gap: float = global_position.distance_to(companion.global_position)
			if gap>55 and global_position.distance_to(dest)<companion.global_position.distance_to(dest): move_speed *= 0.4
		if _destination_pause > 0.0 and not is_scared:
			return Vector2.ZERO
		var desired := super._navigate_towards(dest, move_speed, delta)
		if route_points.size() != 2 or delta <= 0.0:
			return desired
		# Constrain the requested velocity, never actor position. The inherited
		# CharacterBody2D still performs every movement and collision response.
		var start := route_points[0]
		var segment := route_points[1] - start
		var axis := segment.normalized()
		var normal := axis.orthogonal()
		var predicted := global_position + desired * delta - start
		var safe_next := start + axis * clampf(predicted.dot(axis), 0.0, segment.length())
		safe_next += normal * clampf(predicted.dot(normal), -14.0, 14.0)
		return ((safe_next - global_position) / delta).limit_length(move_speed)


func _ready() -> void:
	if not Engine.is_editor_hint():
		call_deferred("_setup_sibling")


func _setup_sibling() -> void:
	var network := get_parent().get_node_or_null("RoadNetwork") as Node2D
	if network != null:
		setup(network)


func setup(network: Node2D) -> void:
	if _configured or Engine.is_editor_hint():
		return
	if not network.has_method("get_graph_data"):
		push_error("HarborLife requires a canonical road network")
		return
	_configured = true
	traffic_controller = HarborController.new()
	traffic_controller.name = "JunctionTrafficController"
	traffic_controller.graph_source = network
	add_child(traffic_controller)
	_spawn_traffic(network)
	_spawn_walkers()
	rail_line = get_node_or_null(rail_path) as Node2D if not rail_path.is_empty() else null
	if rail_line == null:
		rail_line = RAIL.new()
		rail_line.name = "FreightRail"
		add_child(rail_line)


func _spawn_traffic(network: Node2D) -> void:
	var lanes: Array[Path2D] = []
	for candidate in network.find_children("*", "Path2D", true, false):
		if candidate.is_in_group("unified_traffic_lane") and not bool(candidate.get_meta("is_lane_connector", false)):
			lanes.append(candidate as Path2D)
	lanes.sort_custom(func(a: Path2D, b: Path2D) -> bool: return String(a.name) < String(b.name))
	for lane in lanes:
		var road_id := String(lane.get_meta("traffic_road_id", ""))
		if "mountain_bridge" in road_id: lane.set_meta("mountain_traffic", true)
		if road_id.ends_with("mountain_bridge_outbound"): lane.set_meta("continuous_border_end", true)
		if road_id.ends_with("mountain_bridge_inbound"): lane.set_meta("continuous_border_start", true)
	var target_population := 60 if lanes.size() >= 38 else (36 if lanes.size() >= 24 else 18)
	var population := mini(target_population, lanes.size())
	_traffic_lanes = lanes
	_traffic_target = population
	for index in population:
		# Cover the entire authored district, including northern/highway lanes,
		# rather than excluding roads at the end of the alphabetic lane list.
		var lane_index := floori(float(index * lanes.size()) / float(population))
		var vehicle := FACTORY.spawn_moving_vehicle(
			lanes[lane_index], "HarborTraffic_%02d" % index,
			CAR_TYPES[index % CAR_TYPES.size()], 0.17 + float(index % 4) * 0.17,
			80.0 + float(index % 3) * 9.6, index)
		vehicles.append(vehicle)


func _spawn_walkers() -> void:
	# Sidewalk centres are 82px from the 120px road centreline: 22px
	# outside asphalt, safely inside the existing 42px sidewalk band.
	var routes = preload("res://world/harbor/HarborPedestrianRoutes.gd")
	var promenades: Array[PackedVector2Array] = []
	for box in routes.BLOCKS: promenades.append(routes.circuit(box))
	promenades.append_array(routes.connected_routes(get_tree()).slice(0,3))
	for route_index in promenades.size():
		var local_route: PackedVector2Array = promenades[route_index]
		var global_route := PackedVector2Array()
		for point in local_route:
			global_route.append(to_global(point))
		var residents := 4 if route_index < 5 else 3
		for index in residents:
			var walker := HarborWalker.new()
			walker.name = "HarborResident_%d_%d" % [route_index, index]
			var directed_route := global_route.duplicate()
			if index >= 2:
				directed_route.reverse()
			walker.configure_authored_route(directed_route, "harbor_walk_%d" % route_index, (float(index) + 0.35) * global_route[0].distance_to(global_route[1]) / float(residents))
			walker.appearance_variant = route_index*4+index
			walker.sidewalk_half_width = 14.0
			add_child(walker)
			walkers.append(walker)
			if index == 1:
				var partner = walkers[walkers.size()-2]
				walker.companion=partner
				partner.companion=walker
				walker._place_at_route_distance(0.35*global_route[0].distance_to(global_route[1])/float(residents)+25)
	for i in [0,3]:
		var officer := preload("res://world/harbor/HarborFootPatrol.gd").new()
		officer.patrol_route=promenades[i]
		officer.position=promenades[i][0]
		add_child(officer)
	_spawn_place_strollers()
	for district_name in ["EastDistrict", "NorthDistrict"]:
		_spawn_district_neighbors(district_name)


func _spawn_district_neighbors(district_name: String) -> void:
	var district := get_parent().get_node_or_null(district_name) as Node2D
	if district == null or not district.has_method("get_sidewalk_routes"):
		return
	var routes: Array = district.get_sidewalk_routes()
	for index in routes.size():
		var points := PackedVector2Array()
		for point in routes[index]:
			points.append(district.to_global(point))
		if points.size() != 2:
			continue
		for neighbor_index in 3:
			var walker := HarborWalker.new()
			walker.name = "%sNeighbor_%d_%d" % [district_name, index, neighbor_index]
			var directed_route := points.duplicate()
			if neighbor_index % 2 == 1:
				directed_route.reverse()
			walker.configure_authored_route(directed_route, "%s_walk_%d" % [district_name.to_snake_case(), index], (float(neighbor_index) + 0.4) * points[0].distance_to(points[1]) / 3.0)
			walker.appearance_variant = index*3+neighbor_index
			walker.sidewalk_half_width = 14.0
			add_child(walker)
			walkers.append(walker)


func _spawn_place_strollers() -> void:
	# Verified outdoor destinations: storefront forecourt -> market plaza, and
	# the south residential courtyard. No claim of entering an unbuilt interior.
	# Market routes flank the fountain at (1750,955), clear of its 60px radius;
	# courtyard routes stay south of the trees aligned at y850.
	var routes := [
		PackedVector2Array([Vector2(1550, 805), Vector2(1550, 1100)]),
		PackedVector2Array([Vector2(1880, 805), Vector2(1880, 1100)]),
		PackedVector2Array([Vector2(650, 905), Vector2(1090, 905)]),
		PackedVector2Array([Vector2(650, 905), Vector2(1090, 905)]),
	]
	for index in routes.size():
		var global_route := PackedVector2Array()
		for point in routes[index]:
			global_route.append(to_global(point))
		var walker := HarborWalker.new()
		walker.name = "MarketStroller_%d" % index if index < 2 else "CourtyardNeighbor_%d" % index
		walker.pause_at_destinations = true
		walker.set_meta("ambient_activity", "market_frontage_and_plaza" if index < 2 else "courtyard_stroll")
		walker.configure_authored_route(global_route, "harbor_place_%d" % index, 90.0 * float(index % 2))
		walker.sidewalk_half_width = 14.0
		add_child(walker)
		walkers.append(walker)


func get_population_snapshot() -> Dictionary:
	var pauses := 0
	for walker in walkers:
		if is_instance_valid(walker):
			pauses += int(walker.destination_pauses)
	return {
		"vehicles": vehicles.size(), "pedestrians": walkers.size(),
		"outdoor_destination_pauses": pauses,
		"train": rail_line.call("get_train_state") if is_instance_valid(rail_line) else {},
		"traffic": traffic_controller.call("get_telemetry_snapshot") if is_instance_valid(traffic_controller) else {},
	}


func _budget_population(focus: Vector2) -> void:
	var area := preload("res://world/shared/traffic/CameraSimulationArea.gd").visible_area(self,focus)
	var walk_area := preload("res://world/shared/traffic/CameraSimulationArea.gd").visible_area(self,focus,preload("res://world/shared/traffic/CameraSimulationArea.gd").PEDESTRIAN_MARGIN)
	for car in vehicles:
		if not is_instance_valid(car): continue
		var distant: bool = not area.has_point(car.global_position) and car.get("is_driven_by_player") != true and not car.get("is_exploding")
		if distant and not _sleeping_vehicles.has(car) and (car.is_processing() or car.is_physics_processing()):
			_sleeping_vehicles[car] = {"physics": car.is_physics_processing(), "idle": car.is_processing()}
			car.set_physics_process(false)
			car.set_process(false)
		elif not distant and _sleeping_vehicles.has(car):
			car.set_physics_process(_sleeping_vehicles[car].physics)
			car.set_process(_sleeping_vehicles[car].idle)
			_sleeping_vehicles.erase(car)
	for car in _sleeping_vehicles.keys():
		if not is_instance_valid(car): _sleeping_vehicles.erase(car)

	for walker in walkers:
		if not is_instance_valid(walker): continue
		var distant_walker: bool = not walk_area.has_point(walker.global_position) and not walker.get("is_scared") and not walker.get("is_flying")
		if distant_walker and not _sleeping_walkers.has(walker) and walker.is_physics_processing():
			_sleeping_walkers[walker] = true
			walker.set_physics_process(false)
		elif not distant_walker and _sleeping_walkers.has(walker):
			walker.set_physics_process(true)
			_sleeping_walkers.erase(walker)
	for walker in _sleeping_walkers.keys():
		if not is_instance_valid(walker): _sleeping_walkers.erase(walker)

func _process(delta: float) -> void:
	if not _configured or _traffic_lanes.is_empty():
		return
	_budget_clock += delta
	if _budget_clock >= 0.2:
		_budget_clock = 0.0
		var subject := get_tree().get_first_node_in_group("player") as Node2D
		var focus := subject.global_position if subject != null else Vector2(1620, 900)
		for car in get_tree().get_nodes_in_group("modern_traffic"):
			if car.get("is_driven_by_player") == true:
				focus = car.global_position
		_budget_population(focus)
	_population_clock += delta
	if _population_clock < 3.0:
		return
	_population_clock = 0.0
	vehicles = vehicles.filter(func(car): return is_instance_valid(car) and not car.is_broken and not car._detached_from_lane)
	var subject := get_tree().get_first_node_in_group("player") as Node2D
	if subject == null:
		return
	var focus := subject.global_position
	for car in get_tree().get_nodes_in_group("modern_traffic"):
		if car.get("is_driven_by_player") == true:
			focus = car.global_position
	# Replace only missing ambient traffic, outside the camera, with a bounded budget.
	for attempt in 2:
		if vehicles.size() >= _traffic_target:
			break
		for offset in _traffic_lanes.size():
			var lane := _traffic_lanes[(_spawn_serial + offset) % _traffic_lanes.size()]
			var ratio := 0.23 + float(_spawn_serial % 3) * 0.23
			var candidate := lane.to_global(lane.curve.sample_baked(lane.curve.get_baked_length() * ratio))
			if candidate.distance_to(focus) < 1400.0:
				continue
			var clear_ratio := FACTORY._find_clear_ratio(lane, ratio)
			candidate = lane.to_global(lane.curve.sample_baked(lane.curve.get_baked_length() * clear_ratio))
			if candidate.distance_to(focus) < 1400.0 or not FACTORY._position_is_clear(get_tree(), candidate):
				continue
			var vehicle := FACTORY.spawn_moving_vehicle(lane, "HarborTraffic_%d" % _spawn_serial, CAR_TYPES[_spawn_serial % CAR_TYPES.size()], clear_ratio, 90.0, _spawn_serial)
			vehicles.append(vehicle)
			_spawn_serial += 1
			break
