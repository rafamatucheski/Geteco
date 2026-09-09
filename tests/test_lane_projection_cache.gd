extends SceneTree

const CONTROLLER := preload("res://district/roads/traffic/JunctionTrafficController.gd")

class FakeGraph:
	extends Node2D
	var junctions: Array = []
	func get_graph_data() -> Dictionary:
		return {"junctions": junctions.duplicate(true)}

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var graph := FakeGraph.new()
	graph.junctions = [{"id": "junction_" + "x".repeat(2048), "position": Vector2(100, 0), "radius": 20.0, "roads": [0], "signalized": false}]
	root.add_child(graph)
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2.ZERO)
	path.curve.add_point(Vector2(500, 0))
	root.add_child(path)
	var controller := CONTROLLER.new()
	controller.graph_source = graph
	root.add_child(controller)
	controller.set_process(false)
	var first: Array = controller._lane_junction_projections(path, 0)
	check(first.size() == 1, "Expected one lane/junction projection")
	if not first.is_empty():
		check(absf(float(first[0].offset) - 100.0) < 1.0, "Initial projection offset")
	var again: Array = controller._lane_junction_projections(path, 0)
	check(is_same(first, again), "Repeated query must reuse the cached Array")
	check(controller._lane_projection_cache.size() == 1, "Repeated query must not grow cache")
	check(controller._graph_signature.length() > 2048, "Fixture must include a large graph signature")
	for key in controller._lane_projection_cache:
		check(String(key).length() < 64, "Cache key must not contain serialized graph")
	controller._sync_from_graph()
	check(is_same(first, controller._lane_junction_projections(path, 0)), "Unchanged graph sync must retain cache")
	graph.junctions[0].position = Vector2(240, 0)
	controller._sync_from_graph()
	check(controller._lane_projection_cache.is_empty(), "Changed junction must clear projections")
	var moved: Array = controller._lane_junction_projections(path, 0)
	check(not is_same(first, moved), "Changed junction must rebuild result")
	if not moved.is_empty():
		check(absf(float(moved[0].offset) - 240.0) < 1.0, "Changed junction must update offset")
	else:
		check(false, "Moved junction projection missing")
	var replacement := FakeGraph.new()
	replacement.junctions = graph.junctions.duplicate(true)
	replacement.position = Vector2(50, 0)
	root.add_child(replacement)
	controller.configure_graph_source(replacement)
	check(controller._lane_projection_cache.is_empty(), "configure_graph_source must invalidate even with identical junction signature")
	var replaced: Array = controller._lane_junction_projections(path, 0)
	if not replaced.is_empty():
		check(absf(float(replaced[0].offset) - 290.0) < 1.0, "Replacement source transform must affect projection")
	else:
		check(false, "Replacement source projection missing")
	check(controller._lane_junction_projections(path, 1).is_empty(), "Road index must distinguish cache entries")
	controller.queue_free()
	path.queue_free()
	graph.queue_free()
	replacement.queue_free()
	await process_frame
	print("LANE_PROJECTION_CACHE_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
