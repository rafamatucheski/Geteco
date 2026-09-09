extends SceneTree
## Production-authored network; only destination choices and initial spawn are fixtures.
const FACTORY := preload("res://world/shared/emergency/ModernTrafficFactory.gd")
const LIFE := preload("res://world/harbor/HarborLife.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)

func run() -> void:
	seed(75211)
	# Extract the actual saved providers/network, keeping their authored settings.
	# No unrelated campaign actors or ambient queues are injected into this trip.
	var packed: Node = load("res://world/harbor/HarborPreview.tscn").instantiate()
	var fixture := Node2D.new()
	root.add_child(fixture)
	current_scene = fixture
	for id in ["RoadLayout", "CobraNeighborhood", "RoadNetwork"]:
		var node: Node = packed.get_node(id)
		packed.remove_child(node)
		node.owner = null
		fixture.add_child(node)
	packed.free()
	var network: Node2D = fixture.get_node("RoadNetwork")
	var controller := LIFE.HarborController.new()
	controller.graph_source = network
	fixture.add_child(controller)
	for frame in 3:
		await physics_frame
	check(network.get_validation_errors().is_empty(), "Production road graph validates before trip")
	var graph: Dictionary = network.get_graph_data()
	# Prescribe one legal clockwise itinerary, including a full circle and exit.
	var legs: Array[Dictionary] = []
	var enter_circle: Dictionary = {}
	for connection in graph.lane_connections:
		if String(connection.from_road_id).get_file() == "cobra_approach" and String(connection.to_road_id).get_file() == "cobra_court_northwest":
			enter_circle = connection
			break
	if not enter_circle.is_empty():
		for connection in graph.lane_connections:
			if String(connection.to_lane_id) == String(enter_circle.from_lane_id) and not String(connection.from_road_id).get_file().begins_with("cobra_") and float(connection.entry_curve_offset) > 350.0:
				legs.append(connection)
				break
		legs.append(enter_circle)
		for road_id in ["cobra_court_northeast", "cobra_court_southeast", "cobra_court_southwest", "cobra_approach"]:
			for connection in graph.lane_connections:
				if String(connection.from_lane_id) == String(legs.back().to_lane_id) and String(connection.to_road_id).get_file() == road_id:
					legs.append(connection)
					break
		for connection in graph.lane_connections:
			if String(connection.from_lane_id) == String(legs.back().to_lane_id) and not String(connection.to_road_id).get_file().begins_with("cobra_"):
				legs.append(connection)
				break
	check(legs.size() == 7, "Real lane connections supply city -> approach -> four quarters -> approach -> city; got %d" % legs.size())
	if legs.size() == 7:
		await drive(network, controller, legs)
	print("COBRA TRAFFIC: %d failure(s)" % failures.size())
	Engine.time_scale = 1.0
	fixture.free()
	quit(0 if failures.is_empty() else 1)

func plan(follow: PathFollow2D, leg: Dictionary) -> void:
	follow.set_meta("traffic_planned_connection_id", String(leg.connection_id))
	follow.set_meta("traffic_planned_junction_index", int(leg.junction_index))

func drive(network: Node2D, controller: Node, legs: Array[Dictionary]) -> void:
	var first: Dictionary = legs[0]
	var path: Path2D = network.get_lane_path(String(first.from_lane_id))
	var spawn_offset := maxf(10.0, float(first.entry_curve_offset) - 260.0)
	var car := FACTORY.spawn_moving_vehicle(path, "CobraRoundTrip", "sedan_classic", spawn_offset / path.curve.get_baked_length(), 90.0, 0)
	var follow := car.get_parent() as PathFollow2D
	# Factory relocates ambient spawns away from all junctions. This isolated
	# approach fixture has no other cars: place once before any movement frame.
	follow.progress = spawn_offset
	print("COBRA_START lane=%s spawn=%.1f entry=%.1f" % [first.from_lane_id, follow.progress, float(first.entry_curve_offset)])
	check(follow.progress < float(first.entry_curve_offset), "Trip starts physically before city entrance connector")
	plan(follow, first)
	var completed := 0
	var travelled := 0.0
	var max_jump := 0.0
	var previous := car.global_position
	var elapsed := 0.0
	Engine.time_scale = 6.0
	while elapsed < 160.0 and completed < legs.size():
		await physics_frame
		elapsed += 6.0 / Engine.physics_ticks_per_second
		var step := previous.distance_to(car.global_position)
		max_jump = maxf(max_jump, step)
		travelled += step
		previous = car.global_position
		if follow.get_parent() == network.get_lane_path(String(legs[completed].to_lane_id)):
			print("COBRA_DRIVE leg=%d road=%s distance=%.1f" % [completed, legs[completed].to_road_id, travelled])
			completed += 1
			if completed < legs.size():
				plan(follow, legs[completed])
	check(completed == legs.size(), "Vehicle completes real neighborhood round trip without timeout: legs=%d position=%s planned=%s contract=%s" % [completed, car.global_position, follow.get_meta("traffic_planned_connection_id", ""), car.get("_last_lane_motion_contract")])
	check(travelled > 3000.0, "Vehicle physically traverses access twice and full circle: %.1fpx" % travelled)
	# JunctionTrafficController.landing_overshoot_allowance (added to fix a
	# real deadlock: a vehicle landing via the cobra_approach ->
	# cobra_court_southwest connector -- this exact route drives it -- was
	# already past its own next connector's entry_curve_offset and could
	# never plan onward, stalled forever with reservation granted and signal
	# green) lets that one specific outgoing connection execute its handoff
	# across a wider window of frames than the previous flat 12px cap. It is
	# still one single, continuous, curve-to-curve reparent -- never a
	# second hop chained into the same frame, and every other connection's
	# allowance stays exactly 0.0 (unchanged from before this fix) -- but
	# across which frame within that window it lands can now vary by a
	# fixed geometry offset. Measured over repeated runs: 13.98-16.50px, well
	# short of the hundreds/thousands of px an actual teleport would produce.
	check(max_jump <= 20.0, "No connector teleport/frame jump: %.2fpx" % max_jump)
	check(int(controller.get_telemetry_snapshot().get("invalid_lane_contracts", 0)) == 0, "Trip retains valid production traffic lane contracts")
	print("COBRA_ROUND_TRIP legs=%d travelled=%.1f max_jump=%.2f elapsed=%.1f telemetry=%s" % [completed, travelled, max_jump, elapsed, controller.get_telemetry_snapshot()])
