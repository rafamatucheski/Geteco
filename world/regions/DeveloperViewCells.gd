extends RefCounted
## Células finitas que cruzam a área da câmera de desenvolvedor, recortadas pela geografia autorada.
static func select_cells(view: Rect2, bounds: Rect2, cell_size: float) -> Dictionary:
	var result := {}
	var clipped := view.intersection(bounds)
	if not clipped.has_area(): return result
	for x in range(floori(clipped.position.x / cell_size), ceili(clipped.end.x / cell_size)):
		for z in range(floori(clipped.position.y / cell_size), ceili(clipped.end.y / cell_size)):
			result[Vector2i(x,z)] = true
	return result

static func record_bounds(records: Dictionary, cell_size: float) -> Rect2:
	var bounds := Rect2()
	for key in records:
		var rect := Rect2(Vector2(key) * cell_size, Vector2.ONE * cell_size)
		bounds = bounds.merge(rect) if bounds.has_area() else rect
	return bounds

static func enqueue(region: Node) -> void:
	var added: Array[Vector2i] = []
	for key in region.developer_view_cells:
		if not region.chunks.has(key) and key not in region.pending: added.append(key)
	var center := Vector2(region.focus.x, region.focus.z) / float(region.CELL)
	added.sort_custom(func(a: Vector2i, b: Vector2i): return Vector2(a).distance_squared_to(center) < Vector2(b).distance_squared_to(center))
	region.pending.append_array(added)
