extends SceneTree

## Full production-preview geometry, lane connectivity and physical access audit.
var failures: Array[String] = []
var exclusions: Array[RID] = []
var samples := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	seed(90210)
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	for frame in 8:
		await physics_frame
	var neighborhood := scene.get_node_or_null("CobraNeighborhood") as Node2D
	check(neighborhood != null, "Production preview integrates CobraNeighborhood")
	if neighborhood == null:
		finish(scene)
		return
	var territory := scene.get_node_or_null("CobraTerritory")
	check(territory != null, "Production scene integrates territorial behavior")
	if territory != null:
		check(territory.guards.size() == 3 and territory.residents.size() == 2, "Production neighborhood instantiates guards and civilians")
	var network := scene.get_node("RoadNetwork")
	var graph: Dictionary = network.get_graph_data()
	check(network.get_validation_errors().is_empty(), "Unified road validation: %s" % [network.get_validation_errors()])
	var definitions: Array = neighborhood.get_road_graph_definitions()
	check(definitions.size() >= 5, "Approach and four non-duplicate residential arc segments are authored")
	var new_ids: Array[String] = []
	for road in definitions:
		new_ids.append(String(road.id))
		check(not road.get("open_start", false) and not road.get("open_end", false), "%s must connect without hiding dangling ends" % road.id)
	audit_connectivity(graph, new_ids)
	var safety: Dictionary = scene.get_node("RoadSafety").get_safety_data()
	check(safety.validation_errors.is_empty(), "Production road/rail safety validates")
	var neighborhood_crossings := 0
	for crossing in safety.pedestrian_crossings:
		if String(crossing.road_id).get_file() in new_ids and Vector2(crossing.position).x > 6800.0:
			neighborhood_crossings += 1
	check(neighborhood_crossings == 2, "Residential loop has two intentional crossings, not repeated junction zebras: %d" % neighborhood_crossings)
	# Unsignalized is not unprotected: an actual player body must make vehicles
	# yield on the authored crossing, without fabricating a signal phase.
	var crossing_player: CharacterBody2D = scene.get_node("Player")
	var original_player_position := crossing_player.global_position
	var tested_yield := 0
	for crossing in scene.get_node("RoadSafety").find_children("*", "Area2D", true, false):
		if crossing is RoadCrossingArea2D and String(crossing.road_id).get_file() in new_ids and crossing.global_position.x > 6800.0:
			crossing_player.global_position = crossing.global_position
			for frame in 4:
				await physics_frame
			check(not bool(crossing.get_crossing_data().has_signal_state), "Local pedestrian crossing must stay unsignalized")
			check(crossing.should_stop_vehicle(), "Real player overlap must stop traffic at the unsignalized crossing")
			tested_yield += 1
	crossing_player.global_position = original_player_position
	check(tested_yield == 2, "Both local crossing priority contracts are exercised")
	for cardinal in [Vector2(7400, 1700), Vector2(7700, 1400), Vector2(8000, 1700), Vector2(7700, 2000)]:
		var found := false
		for junction in graph.junctions:
			if Vector2(junction.position).distance_to(cardinal) < 3.0:
				found = true
				check(not junction.signalized, "Residential cardinal is not a fabricated traffic-light junction: %s" % cardinal)
		check(found, "Expected connected cardinal exists at %s" % cardinal)
	collect_exclusions(scene)
	var space := scene.get_world_2d().direct_space_state
	var footprints: Array = neighborhood.get_building_footprints()
	check(footprints.size() >= 6, "Residential block has authored buildings")
	var bounds: Rect2 = neighborhood.get_neighborhood_bounds()
	for index in footprints.size():
		var footprint: Rect2 = footprints[index]
		check(bounds.encloses(footprint), "Building %d remains on neighborhood land" % index)
		check(not hits(space, footprint.get_center(), 2.0).is_empty(), "Building %d has a physical solid" % index)
		for other in range(index + 1, footprints.size()):
			check(not footprint.intersects(footprints[other]), "Buildings %d and %d overlap" % [index, other])
	for road in graph.roads:
		if not String(road.id).get_file() in new_ids:
			continue
		var points: PackedVector2Array = road.points
		for index in range(points.size() - 1):
			var a := points[index]
			var b := points[index + 1]
			var steps := maxi(1, ceili(a.distance_to(b) / 14.0))
			var normal := (b - a).normalized().orthogonal()
			for step in range(steps + 1):
				var center := a.lerp(b, float(step) / steps)
				for fraction in [-0.38, 0.0, 0.38]:
					var point: Vector2 = center + normal * float(road.width) * fraction
					var obstacles := hits(space, point, 3.0)
					samples += 1
					check(obstacles.is_empty(), "%s physical asphalt blocked at %s: %s" % [road.id, point, describe(obstacles)])
				for footprint in footprints:
					var closest := Vector2(clampf(center.x, footprint.position.x, footprint.end.x), clampf(center.y, footprint.position.y, footprint.end.y))
					check(center.distance_to(closest) >= float(road.width) * 0.5 + 18.0, "%s building invades road/curb setback near %s" % [road.id, center])
	var routes: Array = neighborhood.get_pedestrian_routes()
	check(routes.size() >= 2, "Neighborhood provides more than one pedestrian route")
	for route in routes:
		for index in range(route.size() - 1):
			var steps := maxi(1, ceili(route[index].distance_to(route[index + 1]) / 12.0))
			for step in range(steps + 1):
				var point: Vector2 = route[index].lerp(route[index + 1], float(step) / steps)
				check(hits(space, point, 5.0).is_empty(), "Pedestrian route blocked at %s" % point)
	var lamps: Array = []
	for child in neighborhood.get_children():
		if child is StreetLamp:
			lamps.append(child)
	check(lamps.size() >= 6, "Neighborhood includes street lighting")
	var weather := scene.get_node("DayNightWeather")
	weather.time_of_day = 0.9
	weather.set_biome(weather.current_biome)
	for frame in 3:
		await physics_frame
	for lamp in lamps:
		check(lamp.is_lit and lamp.lamp_light.visible, "Authored lamp responds to nighttime: %s" % lamp.position)
	weather.time_of_day = 0.45
	weather.set_biome(weather.current_biome)
	await drive_approach(scene)
	print("COBRA_NEIGHBORHOOD buildings=%d roads=%d asphalt_samples=%d failures=%d" % [footprints.size(), definitions.size(), samples, failures.size()])
	finish(scene)

func audit_connectivity(graph: Dictionary, ids: Array[String]) -> void:
	var forward: Dictionary = {}
	var reverse: Dictionary = {}
	var old_lanes: Array[String] = []
	var new_lanes: Dictionary = {}
	for road in graph.roads:
		for lane in road.lanes:
			var id := String(lane.lane_id)
			if String(road.id).get_file() in ids:
				new_lanes[id] = String(road.id)
			else:
				old_lanes.append(id)
	for connection in graph.lane_connections:
		var a := String(connection.from_lane_id)
		var b := String(connection.to_lane_id)
		if not forward.has(a):
			forward[a] = []
		if not reverse.has(b):
			reverse[b] = []
		forward[a].append(b)
		reverse[b].append(a)
	var inbound := reachable(forward, old_lanes)
	var outbound := reachable(reverse, old_lanes)
	check(not new_lanes.is_empty(), "New streets actually collected by production network")
	for lane in new_lanes:
		check(inbound.has(lane), "City cannot navigate into %s (%s)" % [lane, new_lanes[lane]])
		check(outbound.has(lane), "Cannot navigate back to city from %s" % lane)

func reachable(adjacency: Dictionary, starts: Array[String]) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[String] = starts.duplicate()
	for id in queue:
		visited[id] = true
	var index := 0
	while index < queue.size():
		for next in adjacency.get(queue[index], []):
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
		index += 1
	return visited

func drive_approach(scene: Node2D) -> void:
	# Place the real car at the fixture start once, then only actual input/physics.
	for node in scene.find_children("*", "CollisionObject2D", true, false):
		if node is PhysicsBody2D and not node is StaticBody2D and node.name not in ["PlayerCar", "Player"]:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.collision_layer = 0
	var territory := scene.get_node_or_null("CobraTerritory")
	if territory != null:
		territory.process_mode = Node.PROCESS_MODE_DISABLED
	var car := scene.get_node("PlayerCar") as CharacterBody2D
	var player := scene.get_node("Player") as CharacterBody2D
	car.global_position = Vector2(6460, 1700)
	car.rotation = 0.0
	car.set("max_speed", 200.0)
	car.call("enter_vehicle", player)
	await physics_frame
	check(bool(car.get("is_driven_by_player")), "Actual car entry succeeds")
	var collided := false
	Input.action_press("ui_up")
	for frame in 720:
		await physics_frame
		if car.get_slide_collision_count() > 0:
			collided = true
		if car.global_position.x >= 7380.0:
			break
	Input.action_release("ui_up")
	check(not collided, "Real car collided on east approach")
	check(car.global_position.x >= 7380.0, "Real car reaches neighborhood, actual endpoint=%s" % car.global_position)
	print("COBRA_ACCESS_DRIVE endpoint=%s collided=%s" % [car.global_position, collided])

func collect_exclusions(node: Node) -> void:
	if node is PhysicsBody2D and not node is StaticBody2D:
		exclusions.append(node.get_rid())
	for child in node.get_children():
		collect_exclusions(child)

func hits(space: PhysicsDirectSpaceState2D, point: Vector2, radius: float) -> Array[Dictionary]:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	query.exclude = exclusions
	return space.intersect_shape(query, 8)

func describe(obstacles: Array[Dictionary]) -> String:
	var result: Array[String] = []
	for hit in obstacles:
		result.append(String(hit.collider.get_path()))
	return ", ".join(result)

func check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)

func finish(scene: Node) -> void:
	Input.action_release("ui_up")
	for failure in failures:
		push_error("COBRA_NEIGHBORHOOD: " + failure)
	scene.queue_free()
	quit(0 if failures.is_empty() else 1)
