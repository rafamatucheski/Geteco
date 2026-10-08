extends SceneTree
## Route contracts, independent of rendered quality or real station admission.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("RAILWAY_NETWORK ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func run() -> void:
	var stations := NETWORK.stations()
	var ids: Array[String] = []
	var regions: Array[String] = []
	for station in stations:
		check(not str(station.id).is_empty() and station.id not in ids, "unique usable station id: " + str(station.id))
		ids.append(str(station.id))
		if station.region not in regions: regions.append(str(station.region))
		check(not str(station.name).is_empty(), "station has a selectable proper name: " + str(station.id))
		check(station.position.is_finite() and station.arrival.is_finite() and station.entry.is_finite(), "station positions finite: " + str(station.id))
		check(station.arrival.distance_to(station.position) > 3.0, "passenger disembarks off the running rails: " + str(station.id))
		check(NETWORK.nearest_station(station.arrival, 1.0).get("id") == station.id, "platform identifies its own station: " + str(station.id))
		check(NETWORK.nearest_station(station.arrival - Vector3.UP * 10.0, 4.0).is_empty(), "road underneath cannot board elevated platform: " + str(station.id))
		check(bool(station.requires_act1) == (station.region == "desert"), "desert gate remains separate from accessible mountain: " + str(station.id))
	check(regions.has("harbor") and regions.has("mountain") and regions.has("desert"), "network reaches city, mountain and desert")
	check(stations.filter(func(station): return station.region == "harbor").size() >= 2, "city has an actual inter-station journey")
	check(NETWORK.get_station("unknown").is_empty() and NETWORK.get_route("unknown", ids[0]).is_empty(), "invalid departure is rejected")
	check(NETWORK.get_route(ids[0], "unknown").is_empty(), "invalid destination is rejected")
	check(NETWORK.nearest_station(Vector3(90000, 90000, 90000)).is_empty(), "distant world position cannot select a station")
	for origin in stations:
		check(NETWORK.get_route(origin.id, origin.id).is_empty(), "same-station trip rejected: " + str(origin.id))
		for destination in stations:
			if origin.id == destination.id: continue
			var route := NETWORK.get_route(origin.id, destination.id)
			var reverse := NETWORK.get_route(destination.id, origin.id)
			var label := str(origin.id) + " -> " + str(destination.id)
			check(route.size() >= 2 and route[0].is_equal_approx(origin.position) and route[-1].is_equal_approx(destination.position), "continuous endpoints " + label)
			if route.size() < 2: continue
			var length := NETWORK.route_length(route)
			check(length > origin.position.distance_to(destination.position) * 0.99 and is_equal_approx(length, NETWORK.route_length(reverse)), "outward and return journeys cover the same distance " + label)
			check(NETWORK.sample(route, -1.0).position.is_equal_approx(origin.position) and NETWORK.sample(route, length + 1.0).position.is_equal_approx(destination.position), "distance sampling stays inside endpoints " + label)
			var continuous := true
			for index in range(1, route.size()):
				var delta := route[index] - route[index - 1]
				if not route[index].is_finite() or delta.length() < 0.00001 or delta.length() > 5.1:
					continuous = false
					break
			check(continuous, "finite railway without duplicate or disconnected rail samples " + label)
			var facing := NETWORK.sample(route, length * 0.43)
			check(facing.position.is_finite() and facing.direction.is_normalized() and is_finite(float(facing.yaw)), "train receives a valid moving pose " + label)
	var tunnels := NETWORK.tunnels()
	check(tunnels.size() >= 2, "authored journeys include more than one tunnel")
	for tunnel in tunnels:
		var destination_id := "mountain_pines" if tunnel.region == "mountain" else "desert_copper"
		var route := NETWORK.get_route("harbor_central", destination_id)
		var aligned := true
		for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var point: Vector3 = tunnel.a.lerp(tunnel.b, fraction)
			var nearest := INF
			for index in range(1, route.size()):
				nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point, route[index - 1], route[index])))
			if nearest > NETWORK.TRACK_WIDTH * 0.5: aligned = false
		check(aligned, "tunnel is traversed by the passenger route: " + str(tunnel.id))
	var changed := NETWORK.stations()
	changed[0].id = "tampered"
	check(NETWORK.get_station(ids[0]).id == ids[0], "UI callers cannot mutate the authoritative station cache")
	print("RAILWAY_NETWORK_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
