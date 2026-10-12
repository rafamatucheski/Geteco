extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure([
		{"id":"main","width":8.0,"points":PackedVector3Array([Vector3(0,0,10),Vector3(0,0,-40)])},
		{"id":"alternative","width":8.0,"points":PackedVector3Array([Vector3(0,0,10),Vector3(40,0,10),Vector3(40,0,-40),Vector3(0,0,-40)])}
	])
	var authored := Curve3D.new()
	authored.add_point(Vector3(2,0,0))
	authored.add_point(Vector3(2,0,-50))
	authored.set_meta("traffic_open",true)
	authored.set_meta("court_access_start",Vector3(2,0,-35))
	var car := preload("res://runtime/ArrivalCar.gd").new()
	scene.add_child(car)
	car.position = Vector3(2,.01,0)
	car.route = authored
	car.configure_journey(authored,graph)
	car._change_street_route()
	check(car.route!=authored,"blocked edge selects another street route")
	check(car.route.get_baked_length()>150,"alternative route travels around the connected block")
	check(car.route.get_point_position(car.route.point_count-1)==authored.get_point_position(authored.point_count-1),"reroute retains the original workshop destination")
	check(car.tour_route==authored and car.tour_progress()<1,"reroute does not manufacture authored tour progress")
	check(car.road_router._native!=null,"reroute uses the compiled C# road search")
	print("ARRIVAL_ROUTE_CHANGE length=",car.route.get_baked_length()," failures=",failures)
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
