extends SceneTree

## Windowed visual evidence only. It loads the real Main.tscn and never moves,
## spawns or mutates a gameplay actor. The only added node is a QA camera used
## to frame the district and its infrastructure for inspection.

const FULL_OUTPUT := "res://../artifacts/road-system-full.png"
const JUNCTION_OUTPUT := "res://../artifacts/road-system-junction.png"
const HANDOFF_OUTPUT := "res://../artifacts/road-system-handoff.png"
const INFRASTRUCTURE_OUTPUT := "res://../artifacts/road-system-infrastructure.png"
const ACTIVE_RAIL_OUTPUT := "res://../artifacts/road-system-rail-active.png"
const MAX_RAIL_WAIT_FRAMES := 2700


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var packed_main := load("res://legacy/Main.tscn") as PackedScene
	if packed_main == null:
		push_error("VISUAL_ROAD_QA: could not load res://legacy/Main.tscn")
		quit(2)
		return
	var world := packed_main.instantiate()
	root.add_child(world)
	current_scene = world
	for _frame in 30:
		await process_frame

	var camera := Camera2D.new()
	camera.name = "RoadSystemQACamera"
	world.add_child(camera)
	camera.enabled = true
	camera.position = Vector2(1600, 2350)
	camera.zoom = Vector2(0.34, 0.34)
	camera.make_current()
	for _frame in 8:
		await process_frame
	if not _save_viewport(FULL_OUTPUT):
		quit(3)
		return

	# Resolve the close-up from a live {road_id, t, junction_id} crossing. This
	# keeps the evidence camera attached to canonical geodata when roads move.
	var signalized_crossing := _find_signalized_crossing()
	if signalized_crossing == null:
		push_error("VISUAL_ROAD_QA: no signalized pedestrian crossing was generated")
		quit(4)
		return
	camera.global_position = signalized_crossing.global_position
	camera.zoom = Vector2(1.05, 1.05)
	for _frame in 8:
		await process_frame
	if not _save_viewport(JUNCTION_OUTPUT):
		quit(5)
		return

	# A degree-two handoff is the regression case for the floating red/green
	# dots reported in the editor. Resolve it from graph topology, then capture
	# the real scene to prove that it remains connected but has no signal head.
	var handoff := _find_unsignalized_handoff(world)
	if handoff.is_empty():
		push_error("VISUAL_ROAD_QA: no unsignalized two-approach handoff was generated")
		quit(6)
		return
	camera.global_position = handoff.position
	camera.zoom = Vector2(1.1, 1.1)
	for _frame in 8:
		await process_frame
	if not _save_viewport(HANDOFF_OUTPUT):
		quit(7)
		return

	camera.position = Vector2(1320, 1720)
	camera.zoom = Vector2(0.72, 0.72)
	for _frame in 8:
		await process_frame
	if not _save_viewport(INFRASTRUCTURE_OUTPUT):
		quit(8)
		return

	var active_crossing: Node2D = null
	for _frame in MAX_RAIL_WAIT_FRAMES:
		await process_frame
		for candidate in get_nodes_in_group("rail_level_crossing"):
			if candidate is Node2D and candidate.has_method("get_crossing_data"):
				var data := candidate.call("get_crossing_data") as Dictionary
				if (
					bool(data.get("stop_required", false))
					and float(data.get("gate_ratio", 0.0)) >= 0.92
					and _train_is_at_crossing(world, data)
					and not _road_vehicle_is_on_track(candidate as Node2D, data)
				):
					active_crossing = candidate as Node2D
					break
		if active_crossing != null:
			break
	if active_crossing == null:
		push_error("VISUAL_ROAD_QA: natural train run did not reach a closed, conflict-free crossing in time")
		quit(9)
		return
	camera.global_position = active_crossing.global_position
	camera.zoom = Vector2(1.25, 1.25)
	for _frame in 8:
		await process_frame
	if not _save_viewport(ACTIVE_RAIL_OUTPUT):
		quit(10)
		return
	print("VISUAL_ROAD_QA: Main.tscn full=1 junction=1 handoff=1 infrastructure=1 natural_train_at_closed_gate=1")
	quit(0)


func _find_signalized_crossing() -> Node2D:
	var controller := _junction_controller()
	var fallback: Node2D = null
	for candidate in get_nodes_in_group("road_pedestrian_crossing"):
		if not candidate is Node2D or not candidate.has_method("get_crossing_data"):
			continue
		var data := candidate.call("get_crossing_data") as Dictionary
		var junction_id := StringName(data.get("junction_id", &""))
		if junction_id.is_empty():
			continue
		if controller == null or not controller.has_method("is_junction_signalized"):
			continue
		if not bool(controller.call("is_junction_signalized", junction_id)):
			continue
		if fallback == null:
			fallback = candidate as Node2D
		var crossing_id := String(data.get("id", data.get("crossing_id", "")))
		if crossing_id.contains("gateway_midtown"):
			return candidate as Node2D
	return fallback


func _find_unsignalized_handoff(world: Node) -> Dictionary:
	var graph := world.get_node_or_null("DistrictOneComplete/UnifiedRoadNetwork") as Node2D
	if graph == null or not graph.has_method("get_graph_data"):
		return {}
	var graph_data := graph.call("get_graph_data") as Dictionary
	var best := {}
	var best_score := -INF
	for junction_value in graph_data.get("junctions", []):
		var junction := junction_value as Dictionary
		var approaches := junction.get("approaches", []) as Array
		if bool(junction.get("signalized", true)) or approaches.size() != 2:
			continue
		var first := approaches[0] as Dictionary
		var second := approaches[1] as Dictionary
		var first_tangent: Vector2 = first.get("entry_tangent", Vector2.ZERO)
		var second_tangent: Vector2 = second.get("entry_tangent", Vector2.ZERO)
		if first_tangent.is_zero_approx() or second_tangent.is_zero_approx():
			continue
		# Prefer the most visible bend/width transition instead of relying on a
		# hand-authored world coordinate. Straight continuations remain eligible.
		var bend_score := first_tangent.normalized().dot(second_tangent.normalized()) + 1.0
		var width_score := maxf(
			float(first.get("road_width", 0.0)),
			float(second.get("road_width", 0.0))
		) / 1000.0
		var score := bend_score + width_score
		if score <= best_score:
			continue
		best_score = score
		best = {
			"junction_id": StringName(junction.get("id", &"")),
			"position": graph.to_global(junction.get("position", Vector2.ZERO)),
		}
	return best


func _junction_controller() -> Node:
	for candidate in get_nodes_in_group("junction_traffic_controller"):
		if candidate.has_method("is_junction_signalized"):
			return candidate
	return null


func _train_is_at_crossing(world: Node, crossing_data: Dictionary) -> bool:
	var rail_line := world.get_node_or_null("DistrictOneComplete/DistrictRailLine")
	if rail_line == null or not rail_line.has_method("get_train_state"):
		return false
	var state := rail_line.call("get_train_state") as Dictionary
	if not bool(state.get("active", false)):
		return false
	var route_length := float(state.get("route_length", 0.0))
	if route_length <= 1.0:
		return false
	var crossing_offset := clampf(float(crossing_data.get("rail_t", 0.0)), 0.0, 1.0) * route_length
	var progress := float(state.get("progress", 0.0))
	var ahead := fposmod(crossing_offset - progress, route_length)
	var behind := fposmod(progress - crossing_offset, route_length)
	var consist_length := float(state.get("consist_length", 0.0))
	return ahead <= 28.0 or behind <= consist_length + 28.0


func _road_vehicle_is_on_track(crossing: Node2D, crossing_data: Dictionary) -> bool:
	var half_road := maxf(24.0, float(crossing_data.get("road_width", 96.0)) * 0.5)
	for candidate in get_nodes_in_group("vehicle"):
		if not candidate is Node2D or not is_instance_valid(candidate):
			continue
		if crossing.has_method("is_conflict_world_point"):
			if bool(crossing.call("is_conflict_world_point", (candidate as Node2D).global_position)):
				return true
			continue
		var local_position := crossing.to_local((candidate as Node2D).global_position)
		if absf(local_position.x) <= 42.0 and absf(local_position.y) <= half_road + 8.0:
			return true
	return false


func _save_viewport(path: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("VISUAL_ROAD_QA: viewport image unavailable for %s" % path)
		return false
	var absolute_path := ProjectSettings.globalize_path(path)
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("VISUAL_ROAD_QA: could not save %s (%s)" % [absolute_path, error_string(error)])
		return false
	print("VISUAL_ROAD_QA_IMAGE: %s" % absolute_path)
	return true
