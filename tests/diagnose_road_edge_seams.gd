extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _inside(point: Vector2, polygons: Array) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon): return true
	return false

func _run() -> void:
	var world = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 4: await physics_frame
	var network = world.get_node("RoadNetwork")
	network._ensure_edge_cache()
	var file := FileAccess.open("D:/geteco/artifacts/road-edge-seams.var", FileAccess.WRITE)
	file.store_var(network._edge_layers)
	file.close()
	for layer_name in network._edge_layers:
		var layer: Dictionary = network._edge_layers[layer_name]
		for segment in layer.segments:
			var normal: Vector2 = (segment[1] - segment[0]).normalized().orthogonal()
			var middle: Vector2 = (segment[0] + segment[1]) * 0.5
			if _inside(middle + normal * 0.12, layer.sources) != _inside(middle - normal * 0.12, layer.sources): continue
			var probes := {}
			for epsilon in [0.001, 0.003, 0.01, 0.03, 0.06, 0.12, 0.3, 1.0]:
				probes[str(epsilon)] = [_inside(middle + normal * epsilon, layer.sources), _inside(middle - normal * epsilon, layer.sources)]
			print("SEAM ", layer_name, " start=", segment[0], " end=", segment[1], " length=", segment[0].distance_to(segment[1]), " probes=", probes)
			for index in layer.sources.size():
				var polygon: PackedVector2Array = layer.sources[index]
				var close: Array = []
				for i in polygon.size():
					if Geometry2D.get_closest_point_to_segment(middle, polygon[i], polygon[(i + 1) % polygon.size()]).distance_to(middle) < 1.0:
						close.append([polygon[i], polygon[(i + 1) % polygon.size()]])
				if not close.is_empty(): print("SOURCE ", index, " close=", close)
	world.queue_free()
	await process_frame
	quit()
