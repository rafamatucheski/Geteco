extends SceneTree

const CONTROLLER := preload("res://district/roads/traffic/JunctionTrafficController.gd")

class VersionedGraph:
	extends Node2D
	var revision := 1
	var graph_reads := 0
	var junctions: Array = [{"id": "test", "position": Vector2(100, 0), "radius": 20.0, "roads": [0], "signalized": false}]
	func get_routing_revision() -> int:
		return revision
	func get_graph_data() -> Dictionary:
		graph_reads += 1
		return {"junctions": junctions.duplicate(true)}

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var graph := VersionedGraph.new()
	root.add_child(graph)
	var controller := CONTROLLER.new()
	controller.graph_source = graph
	root.add_child(controller)
	controller.set_process(false)
	check(graph.graph_reads == 1, "Initial graph must load once")
	controller._lane_projection_cache["sentinel"] = []
	for index in 20:
		controller._sync_from_graph()
	check(graph.graph_reads == 1, "Unchanged revision must not copy/serialize graph")
	check(controller._lane_projection_cache.has("sentinel"), "Unchanged revision must preserve projections")
	graph.revision += 1
	controller._sync_from_graph()
	check(graph.graph_reads == 2, "New revision must read graph")
	check(controller._lane_projection_cache.is_empty(), "Identical geometry rebuild must invalidate replaced path references")
	graph.junctions[0].position = Vector2(240, 0)
	graph.revision += 1
	controller._sync_from_graph()
	check(controller._junctions[0].position == Vector2(240, 0), "Revision must publish updated geometry")
	var replacement := VersionedGraph.new()
	replacement.revision = graph.revision
	replacement.junctions[0].position = Vector2(300, 0)
	root.add_child(replacement)
	controller.graph_source = replacement
	controller._sync_from_graph()
	check(replacement.graph_reads == 1, "Different source with same revision must load")
	check(controller._junctions[0].position == Vector2(300, 0), "Source identity must distinguish same revision")
	controller._lane_projection_cache["sentinel"] = []
	controller.configure_graph_source(replacement)
	check(replacement.graph_reads == 2, "Explicit configure must force resynchronization")
	check(controller._lane_projection_cache.is_empty(), "Explicit configure must invalidate projections")
	controller.queue_free()
	graph.queue_free()
	replacement.queue_free()
	await process_frame
	print("JUNCTION_REVISION_CACHE_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
