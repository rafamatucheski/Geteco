extends SceneTree

const ROUTER := preload("res://world/shared/roads/EmergencyLaneRouter.gd")
const NETWORK := preload("res://world/shared/roads/UnifiedRoadNetwork2D.gd")

class Roads:
	extends Node2D
	func get_road_graph_definitions() -> Array[Dictionary]:
		return [
			{"id": "horizontal", "points": PackedVector2Array([Vector2(-400, 0), Vector2(400, 0)]), "width": 96.0, "open_start": true, "open_end": true},
			{"id": "vertical", "points": PackedVector2Array([Vector2(0, -400), Vector2(0, 400)]), "width": 96.0, "open_start": true, "open_end": true},
		]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var fixture := Node2D.new()
	root.add_child(fixture)
	var roads := Roads.new()
	roads.name = "Roads"
	fixture.add_child(roads)
	var graph := NETWORK.new()
	graph.provider_paths = [NodePath("../Roads")]
	graph.build_guard_rails = false
	fixture.add_child(graph)
	var car := CharacterBody2D.new()
	car.position = Vector2(-250, 24)
	fixture.add_child(car)
	await physics_frame
	var router := ROUTER.new()
	var destination := Vector2(-24, 250)
	router.guidance(car, destination)
	_check(router.legs.size() == 3, "cross-road route must include lane, connector and destination lane")
	if router.legs.size() == 3:
		_check((router.legs[1].path as Path2D).is_in_group("unified_lane_connector"), "middle leg must use generated connector")
		for leg in router.legs:
			_check(float(leg.end) >= float(leg.start), "route must not run backwards along a lane")
	var first_cache: Dictionary = graph.get_meta(ROUTER.CACHE_KEY)
	var another := ROUTER.new()
	another.guidance(car, destination)
	_check(is_same(first_cache, graph.get_meta(ROUTER.CACHE_KEY)), "vehicles should reuse the same adjacency cache")
	for frame in 10:
		router.guidance(car, destination)
	_check(router.plans == 1, "stationary destination must not replan every frame")
	router.next_plan_ms = 0
	router.guidance(car, Vector2(250, 24))
	_check(router.plans == 2 and router.legs.size() == 1, "moved destination must produce a new direct route")
	var previous_revision := router.revision
	graph.curve_subdivisions = 14
	router.guidance(car, Vector2(250, 24))
	_check(router.revision > previous_revision, "rebuild must invalidate cached paths")
	_check(not is_same(first_cache, graph.get_meta(ROUTER.CACHE_KEY)), "rebuild must replace adjacency cache")
	# Reaching a roadside suspect must not extend the route over bridge edges.
	var final_path := router.legs.back().path as Path2D
	var final_offset: float = router.legs.back().end
	var roadside := final_path.to_global(final_path.curve.sample_baked(final_offset, true))
	car.global_position = roadside
	router.destination = roadside + Vector2(0, 200)
	router.next_plan_ms = Time.get_ticks_msec() + 10000
	router.leg_index = router.legs.size() - 1
	var safe_stop := router.guidance(car, router.destination)
	_check(safe_stop.distance_to(roadside) < 1.0, "off-road pursuit ends on its lane instead of crossing a bridge edge")

	router.reset()
	_check(router.legs.is_empty() and router.network == null, "pool reset must discard old route")
	for failure in failures:
		push_error(failure)
	print("EMERGENCY_ROUTER_CONTRACT|failures=", failures.size())
	fixture.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
