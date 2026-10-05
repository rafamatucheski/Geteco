extends SceneTree
## Route identity/invalidation without admitting gameplay entities.
## Functional contract only; rendered captures validate loading/frame time.
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
const OPS := preload("res://runtime/terminal/TerminalOperations.gd")
const ROUTES := preload("res://runtime/terminal/TerminalRoutes.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")

class FakeWorld extends Node3D:
	var player := Node3D.new()
	func _init() -> void: add_child(player)

class FakeController extends RefCounted:
	var world: Node3D
	var traffic_routes: RefCounted
	var state := {"region_id":"harbor","place_id":""}
	var session := {"ready_for_play":false}
	var urban_transit := {"instances":{"harbor_coach_terminal":true}}

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TERMINAL_ROUTE_PREP: "+label)

func roads(extra := false) -> Array:
	var points := PackedVector3Array([
		ROUTES.point(293,220),ROUTES.point(478,220),ROUTES.point(478,-583),
		ROUTES.point(-378,-583),ROUTES.point(-378,220),ROUTES.point(-323,220),
		ROUTES.point(293,220)])
	var result := [{"id":"terminal_rectangle","points":points,"width":7.5,"lanes_per_direction":1}]
	if extra:
		result.append({"id":"separate_road","points":PackedVector3Array([Vector3(400,0,400),Vector3(450,0,400)]),"width":7.5})
	return result

func make_graph() -> RefCounted:
	var result := GRAPH.new()
	result.configure(roads())
	return result

func same_curve(a: Curve3D, b: Curve3D) -> bool:
	if a == null or b == null or a.point_count != b.point_count: return false
	if a.bake_interval != b.bake_interval or a.get_meta("traffic_open",false) != b.get_meta("traffic_open",false): return false
	for i in a.point_count:
		if not a.get_point_position(i).is_equal_approx(b.get_point_position(i)): return false
	return true

func check_not_eligible(controller, label: String) -> void:
	var untouched := OPS.new()
	untouched.configure(controller)
	untouched.prepare_startup_route()
	check(untouched.road == null and not untouched._road_prepared and untouched.get_child_count()==0,label)
	untouched.free()

func run() -> void:
	if not ClassDB.class_exists(&"CSharpScript"):
		check(false,"Requires the project's Godot 4.7.2 .NET and compiled Harbor.csproj")
		quit(1)
		return
	var controller := FakeController.new()
	controller.world = FakeWorld.new()
	controller.traffic_routes = make_graph()
	root.add_child(controller.world)
	controller.world.player.global_position = ROUTES.point(0,0)
	var operations := OPS.new()
	operations.configure(controller)
	root.add_child(operations)
	WORK.enabled = true
	WORK.take()
	operations.prepare_startup_route()
	var first: Curve3D = operations.road
	check(first != null,"The eligible real road is resolved during preparation")
	var native_plans := 0
	for event in WORK.take():
		if event.get("label","") == "terminal.street.router_plan" and event.details.get("native_active",false): native_plans += 1
	check(native_plans == 3,"All three real plans used the active C# path; no silent fallback")
	check(not operations.resident and not operations.running and operations.fleet.is_empty() and operations.gates.is_empty() and operations.get_child_count()==0,
		"Preparation admits no coaches, passengers, gates or active collisions")
	check(operations._clock == 0.0 and not controller.session.ready_for_play,"Preparation does not advance timers or ready flags")
	operations.prepare_startup_route()
	check(operations.road == first and WORK.take().is_empty(),"Repeated preparation reuses the same curve without repeating resolution")
	var reference := ROUTES.street(controller.traffic_routes)
	check(same_curve(first,reference),"Prepared points, bake and road metadata match the original resolver")
	controller.traffic_routes.configure(roads(true))
	operations.prepare_startup_route()
	check(operations.road != first and same_curve(operations.road,ROUTES.street(controller.traffic_routes)),
		"Graph reconfigure invalidates the prepared road and still matches the original resolver")
	check(operations._clock == 0.0 and operations.get_child_count()==0 and not controller.session.ready_for_play,
		"Invalidation preserves timers, ready flags and empty entity lifecycle")
	controller.state.region_id = "mountain"
	check_not_eligible(controller,"Mountain startup leaves lazy terminal resolution available")
	controller.state.region_id = "harbor"
	controller.state.place_id = "garage"
	check_not_eligible(controller,"Interior startup leaves lazy terminal resolution available")
	controller.state.place_id = ""
	controller.world.player.global_position = Vector3(1000,0,1000)
	check_not_eligible(controller,"Distant startup leaves lazy terminal resolution available")
	controller.world.player.global_position = ROUTES.point(0,0)
	controller.urban_transit.instances.clear()
	check_not_eligible(controller,"An absent station leaves lazy terminal resolution available")
	operations.free()
	controller.world.free()
	WORK.enabled = false
	WORK.take()
	print("TERMINAL_ROUTE_PREP ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
