extends Node2D

## Runtime population uses the same generated lane paths and junction authority
## as the live game. No cosmetic cars are translated independently of the graph.
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
const CONTROLLER := preload("res://geodata/roads/traffic/JunctionTrafficController.gd")
const RAIL := preload("res://world/harbor/HarborRailLine.gd")
const CAR_TYPES := ["orbita_micro", "sport_estate", "sedan_classic", "metro_hatch", "aurora_executive", "union_sedan", "vale_crossover", "metro_hatch", "nordic_estate", "sport_coupe", "nimbus_minivan", "courier_van", "station_wagon", "cobra_v8", "taxi_yellow", "vertice_midengine", "metro_hatch", "summit_suv", "bravio_crew", "courier_van", "sedan_classic", "union_sedan", "station_wagon"]
const MOTORCYCLE_TYPES := ["bike_urban", "bike_sport", "bike_cruiser"]
const MAX_AMBIENT_TRUCKS := 2

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
var _population_activity := preload("res://systems/PopulationActivity.gd").new()
var walk_space := preload("res://characters/pedestrians/PedestrianWalkSpace.gd").new()


class HarborController extends JunctionTrafficController:
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
		if vehicle.has_method("occupies_junction") and vehicle.occupies_junction(center,crossing_half_width+8.0):
			return
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
	var _social_cooldown := 12.0
	var _companion_wait := 0.0

	func _ready() -> void:
		if get_parent().get("walk_space") != null: walk_space = get_parent().get("walk_space")
		district_theme = DistrictTheme.CITY_DOWNTOWN
		defer_presentation = true
		archetype_override = [0,1,2,4,6,7][appearance_variant%6]
		appearance_seed = appearance_variant
		appearance_gender = 1 + appearance_variant % 2
		super._ready()
		preload("res://characters/pedestrians/CitizenDetails.gd").dress(self,appearance_variant)

	# Existing generic shop visits target an approximate facade position. Until
	# preview buildings expose verified entrances, remain on audited promenades.
	func _try_start_poi_visit() -> void:
		pass

	func _physics_process(delta: float) -> void:
		_destination_pause = maxf(0.0, _destination_pause - delta)
		_social_cooldown -= delta
		if is_scared or is_dead or is_incapacitated:
			_destination_pause = 0.0
			_companion_wait = 0.0
			_social_cooldown = 15.0
		elif _social_cooldown <= 0.0 and not _rejoining_route:
			_social_cooldown = randf_range(20.0, 40.0)
			# Chat only alongside a companion, on a roomy uninterrupted sidewalk.
			if is_instance_valid(companion) and not companion.is_scared and global_position.distance_to(companion.global_position) < 46.0 and global_position.distance_to(walk_target) > 90.0 and _safe_to_pause():
				_destination_pause = randf_range(1.2, 2.8)
				companion._destination_pause = _destination_pause
				companion._social_cooldown = _social_cooldown
				walk_dir = global_position.direction_to(companion.global_position)
				companion.walk_dir = -walk_dir
		super._physics_process(delta)

	func _safe_to_pause() -> bool:
		for crossing in preload("res://world/harbor/CrossingNeighborhood.gd").near(self):
			if is_instance_valid(crossing) and global_position.distance_to(crossing.global_position) < crossing.road_width * 0.5 + 65.0: return false
		for other in _cached_neighbors:
			if _social_neighbor(other) and other != companion and global_position.distance_to(other.global_position) < 50.0: return false
		return true

	func _pick_new_sidewalk_target() -> void:
		# Waiting for a crossing or another person is not completion of a leg.
		# The base pedestrian's stuck timeout used to skip these authored corners
		# and send residents diagonally into the space needed by turning vehicles.
		if _route_target_ready and not is_scared and global_position.distance_to(walk_target) > 8.0:
			return
		if pause_at_destinations and _route_target_ready and not is_scared and not _rejoining_route and _safe_to_pause():
			_destination_pause = randf_range(0.4, 2.4)
			destination_pauses += 1
		super._pick_new_sidewalk_target()
		# Corner markers stay on the route centre; clearance comes from the
		# committed detour, not a randomly offset inaccessible destination.
		if not _rejoining_route: walk_target = route_points[_next_route_index()]

	func _ambient_walk_paused() -> bool:
		return super._ambient_walk_paused() or (_destination_pause > 0.0 and not is_scared)

	func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
		move_speed *= 0.80
		if preload("res://world/harbor/HarborPedestrianRoutes.gd").crossing_wait(self,dest):
			locomotion_state = &"waiting_crossing"
			movement_navigation.reset_progress()
			stuck_timer = 0.0
			return Vector2.ZERO
		if is_instance_valid(companion) and not is_scared and not companion.is_dead and not companion.is_incapacitated and not companion.is_scared:
			var gap: float = global_position.distance_to(companion.global_position)
			if gap > 55.0 and gap < 180.0 and global_position.distance_to(dest) < companion.global_position.distance_to(dest) and _safe_to_pause():
				_companion_wait += delta
				if _companion_wait < 4.0: move_speed *= 0.5
			else: _companion_wait = 0.0
		if _destination_pause > 0.0 and not is_scared:
			return Vector2.ZERO
		return super._navigate_towards(dest, move_speed, delta)


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
	# Harbor's turning rays can touch residents on the far sidewalk. Enable
	# the actual swept corridor when this population starts, even when the
	# optional interregional coach service has not been initialized.
	var graph: Dictionary = network.get_graph_data()
	walk_space.configure(network, graph)
	for connection in graph.lane_connections:
		var connector: Path2D = connection.get("path")
		if is_instance_valid(connector) and connector.is_in_group("unified_lane_connector"):
			connector.set_meta("curved_pedestrian_corridor", true)
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
			# Local relief roads remain routable, but adding them must not seed
			# extra traffic directly across the emergency depot mouths.
			if String(candidate.get_meta("traffic_road_id", "")).get_file() in ["westgate_service_lane", "medical_garden_lane"]:
				continue
			# The freight terminal owns its working fleet; keep the city population
			# distributed over public streets instead of spawning buses in the yard.
			if String(candidate.get_meta("traffic_road_id", "")).get_file().begins_with("south_port_"):
				continue
			# This 240px link lies entirely between two turn-entry envelopes.
			# Traffic can drive through it, but seeding a car midway can place
			# it past its outgoing connector before it ever receives a route.
			if String(candidate.get_meta("traffic_road_id", "")).get_file() == "map2_temporary_return":
				continue
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
			_traffic_archetype(lanes[lane_index], index), 0.17 + float(index % 4) * 0.17,
			80.0 + float(index % 3) * 9.6, index)
		vehicles.append(vehicle)


func _traffic_archetype(lane: Path2D, serial: int) -> String:
	# Spread all three styles across successive streets, within the existing fleet budget.
	if posmod(serial, 4) == 3:
		return MOTORCYCLE_TYPES[posmod(floori(float(serial) / 4.0), MOTORCYCLE_TYPES.size())]
	# Freight operations have their own fleet. Residential through traffic is
	# mostly compact cars; a tanker/bus on every fourth block consumed all of
	# the short receiving lanes before any ordinary car could clear a junction.
	if serial % 11 == 0 and lane.curve.get_baked_length() >= 1500.0 and float(lane.get_meta("traffic_road_width", 0.0)) >= 140.0:
		var heavy := 0
		for vehicle in vehicles:
			if is_instance_valid(vehicle) and vehicle.vehicle_id == "cargo_flatbed_truck": heavy += 1
		if heavy < MAX_AMBIENT_TRUCKS: return "cargo_flatbed_truck"
	var car_serial := serial - floori(float(serial) / 4.0)
	return CAR_TYPES[posmod(car_serial, CAR_TYPES.size())]


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
	# Market visitors stay on the public frontage outside the terminal bus bays.
	var routes := [
		PackedVector2Array([Vector2(1550, 805), Vector2(1550, 1100)]),
		PackedVector2Array([Vector2(1880, 805), Vector2(1880, 1100)]),
		PackedVector2Array([Vector2(650, 905), Vector2(1090, 905)]),
		PackedVector2Array([Vector2(650, 905), Vector2(1090, 905)]),
	]
	if get_parent().has_node("ArrivalStop"):
		routes[0] = PackedVector2Array([Vector2(1420, 800), Vector2(1420, 1100)])
		routes[1] = PackedVector2Array([Vector2(1440, 850), Vector2(1440, 1100)])
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
	# The continuous world owns all populations. Preview scenes use this fallback.
	if get_tree().get_first_node_in_group("continuous_world") != null: return
	_population_activity.update(self, focus, vehicles, walkers)

func _exit_tree() -> void:
	_population_activity.restore_all()

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
	_replace_buried_walker()
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
			var vehicle := FACTORY.spawn_moving_vehicle(lane, "HarborTraffic_%d" % _spawn_serial, _traffic_archetype(lane, _spawn_serial), clear_ratio, 90.0, _spawn_serial)
			vehicles.append(vehicle)
			_spawn_serial += 1
			break


func _replace_buried_walker() -> void:
	var care := get_node("/root/CoronerCare")
	var renewal := get_node("/root/WorldRenewal")
	for index in walkers.size():
		var previous: Node2D = walkers[index]
		if not is_instance_valid(previous) or not previous is HarborWalker or not previous.is_dead: continue
		var key: String = care.identity(previous)
		var record: Dictionary = care.records().get(key,{})
		if record.get("phase","") not in ["buried","unrecovered"]: continue
		var distance := 0.0
		for segment in range(1,previous.route_points.size()):
			var a: Vector2 = previous.route_points[segment-1]
			var b: Vector2 = previous.route_points[segment]
			var length := a.distance_to(b)
			var point := a.lerp(b,.5)
			if not renewal.outside_view(previous,point) or not renewal.free_position(previous,point,18):
				distance += length
				continue
			var successor := HarborWalker.new()
			# A stable successor name survives scene reloads; a subsequent death
			# gets its own record rather than clearing the predecessor's obituary.
			successor.name = String(record.get("successor_name","HarborSuccessor_%s" % str(key.hash())))
			successor.appearance_variant = int(record.get("successor_variant",previous.appearance_variant+7919))
			successor.sidewalk_half_width = previous.sidewalk_half_width
			successor.configure_authored_route(previous.route_points.duplicate(),previous.route_id,distance+length*.5)
			add_child(successor)
			if not successor.is_dead and (not renewal.free_position(successor,successor.global_position,18) or not renewal.outside_view(successor,successor.global_position)):
				successor.queue_free()
				distance += length
				continue
			record.successor_name = String(successor.name)
			record.successor_variant = successor.appearance_variant
			walkers[index] = successor
			previous.queue_free()
			return # At most one replacement per existing three-second budget.
