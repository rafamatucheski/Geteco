extends Node
## Usa a projeção já existente do minimapa e mantém os trilhos fora do GPS viário.
var rail: Node2D
var minimap: Node
var mapped: Array[Dictionary] = []
var _elapsed := 0.0

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5: return
	_elapsed = 0.0
	for candidate in get_tree().get_nodes_in_group("minimap"):
		if candidate.get("world") == rail.get_parent():
			minimap = candidate
			mapped = rail.get_regional_route_data().sections
			minimap.canvas.draw.connect(_draw_rail)
			set_process(false)
			return

func _draw_rail() -> void:
	if not is_instance_valid(minimap): return
	var canvas: Control = minimap.canvas
	for section in mapped:
		var line := PackedVector2Array()
		for point: Vector2 in section.points: line.append(minimap.project(point))
		if line.size() < 2: continue
		canvas.draw_polyline(line, Color("26312d"), 4.0, true)
		canvas.draw_polyline(line, Color("d8c48b"), 1.4, true)
		for i in range(0, line.size() - 1, 2):
			var normal := line[i].direction_to(line[i+1]).orthogonal() * 2.6
			canvas.draw_line(line[i] - normal, line[i] + normal, Color("d8c48b"), 1.0, true)
	var train := rail.get_node_or_null("AmbientTrain")
	if train != null and float(train.get_rail_state().locomotive_opacity) > 0.5:
		var point: Vector2 = minimap.project(train.global_position)
		if Rect2(Vector2(6,6), minimap.MAP_SIZE-Vector2(12,12)).has_point(point):
			canvas.draw_circle(point, 5.0, Color("152021"))
			canvas.draw_rect(Rect2(point-Vector2(2,3),Vector2(4,6)),Color("f2ce6e"))
