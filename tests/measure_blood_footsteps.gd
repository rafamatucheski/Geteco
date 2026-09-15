extends "res://tests/measure_game_frame_stability.gd"
## Production scene, same checkpoint/settings and finite wall-clock sampling.
var wounded: Array[Node2D] = []
var effect_timer := 0.0
var peak_marks := 0
var peak_pools := 0

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	if label == "driving":
		Input.action_release("move_up")
		var candidates := get_nodes_in_group("pedestrian")
		candidates.sort_custom(func(a,b): return a.global_position.distance_squared_to(car.global_position) < b.global_position.distance_squared_to(car.global_position))
		for actor in candidates.slice(0, 12):
			wounded.append(actor)
			preload("res://world/shared/combat/BodyWound.gd").apply(actor)
		print("BLOOD_LOAD actors=", wounded.size())
	await super._sample(output, label, seconds, car)
	print("BLOOD_PEAK marks=", peak_marks, " pools=", peak_pools)

func _hold_scenario_clock() -> void:
	super._hold_scenario_clock()
	if wounded.is_empty(): return
	effect_timer += process_frame_delta()
	if effect_timer >= 6.0:
		effect_timer = 0.0
		for actor in wounded:
			if is_instance_valid(actor): preload("res://world/shared/combat/BodyWound.gd").apply(actor)
	var system := get_first_node_in_group("blood_transfer_system")
	if system != null: peak_marks = maxi(peak_marks, system.marks.size())
	peak_pools = maxi(peak_pools, get_nodes_in_group("ground_blood").size())

func process_frame_delta() -> float:
	return root.get_process_delta_time()
