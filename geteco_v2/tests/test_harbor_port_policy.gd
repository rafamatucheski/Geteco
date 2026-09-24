extends SceneTree

const POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition: return
	failures.append(label)
	push_error(label)

func run() -> void:
	check(POLICY.contains_private_area(Vector3(200,0,200)),"Port yard belongs to the protected area")
	check(POLICY.contains_private_area(Vector3(222,0,150)),"Port walkway belongs to the protected area")
	check(POLICY.contains_private_area(Vector3(275,0,180)),"Cargo ship belongs to the protected area")
	check(POLICY.contains_private_area(Vector3(390,0,234)),"Pier belongs to the protected area")
	check(not POLICY.contains_private_area(Vector3(100,0,100)),"Public city street stays outside the protected area")

	var roads: Array = [
		{"id":"south_port_west","width":7.5,"points":PackedVector3Array([Vector3(230,0,230),Vector3(230,0,350)])},
		{"id":"generic_road_crossing_port","width":7.5,"points":PackedVector3Array([Vector3(180,0,350),Vector3(250,0,350)])},
		{"id":"public_street","width":7.5,"points":PackedVector3Array([Vector3(80,0,80),Vector3(120,0,80)])},
	]
	var ambient := POLICY.ambient_roads(roads)
	check(ambient.size()==1 and ambient[0].id=="public_street","Ambient traffic and pedestrians get only public roads")
	check(POLICY.segment_enters_private_area(Vector3(180,0,350),Vector3(250,0,350)),"Sidewalk clearance catches roads bordering the private apron")

	var safe_route := Curve3D.new()
	safe_route.add_point(Vector3(80,0,80))
	safe_route.add_point(Vector3(120,0,80))
	var port_route := Curve3D.new()
	port_route.add_point(Vector3(180,0,350))
	port_route.add_point(Vector3(250,0,350))
	check(POLICY.route_is_ambient_safe(safe_route),"Public ambient route passes the route guard")
	check(not POLICY.route_is_ambient_safe(port_route),"A route curve cannot carry ambient traffic through the port")

	print("HARBOR_PORT_POLICY ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
