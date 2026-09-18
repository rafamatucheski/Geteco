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
			for section in mapped:
				var bounds := Rect2()
				if not section.points.is_empty():
					bounds = Rect2(section.points[0], Vector2.ZERO)
					for point: Vector2 in section.points:
						bounds = bounds.expand(point)
				section["bounds"] = bounds.grow(40.0)
			minimap.canvas.draw.connect(_draw_rail)
			set_process(false)
			return

func _draw_rail() -> void:
	if not is_instance_valid(minimap): return
	var canvas: Control = minimap.canvas
	var scale_val: float = minimap.SCALE
	var map_area := Rect2(minimap.center - minimap.MAP_SIZE / (2.0 * scale_val), minimap.MAP_SIZE / scale_val)
	for section in mapped:
		if section.has("bounds") and not map_area.intersects(section.bounds):
			continue
		var line := PackedVector2Array()
		for point: Vector2 in section.points: line.append(minimap.project(point))
		if line.size() < 2: continue
		canvas.draw_polyline(line, Color("26312d"), 3.5, true)
		canvas.draw_polyline(line, Color("d8c48b"), 1.2, true)
