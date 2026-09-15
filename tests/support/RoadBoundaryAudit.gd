extends RefCounted
## Boundary probes must stay local to the edge: a fixed 0.12px offset can
## cross a second boundary in a narrow gap. Packed vectors use float32;
## probe four representable steps away, then classify with scalar float64.
const VECTOR_EPSILON := 1.1920928955078125e-7

static func prepare(polygons: Array) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	for polygon: PackedVector2Array in polygons:
		if polygon.size() < 3: continue
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon: bounds = bounds.expand(point)
		regions.append({"points": polygon, "bounds": bounds})
	return regions

static func contains(point: Vector2, regions: Array[Dictionary]) -> bool:
	for region in regions:
		var bounds: Rect2 = region.bounds
		if point.x < bounds.position.x or point.x > bounds.end.x or point.y < bounds.position.y or point.y > bounds.end.y:
			continue
		var polygon: PackedVector2Array = region.points
		var inside := false
		for index in polygon.size():
			var next := (index + 1) % polygon.size()
			# Subtract scalar components before multiplication. Vector cross
			# products near the map's distant vertices lose the small offset.
			var ay: float = float(polygon[index].y) - float(point.y)
			var by: float = float(polygon[next].y) - float(point.y)
			if (ay > 0.0) == (by > 0.0): continue
			var ax: float = float(polygon[index].x) - float(point.x)
			var bx: float = float(polygon[next].x) - float(point.x)
			if ax - ay * (bx - ax) / (by - ay) > 0.0:
				inside = not inside
		if inside: return true
	return false

static func is_boundary(segment: PackedVector2Array, regions: Array[Dictionary]) -> bool:
	if segment.size() != 2 or segment[0] == segment[1]: return false
	var normal := (segment[1] - segment[0]).normalized().orthogonal()
	for fraction in [0.25, 0.5, 0.75]:
		var point := segment[0].lerp(segment[1], fraction)
		var magnitude := maxf(1.0, maxf(absf(point.x), absf(point.y)))
		var epsilon := maxf(0.0001, magnitude * VECTOR_EPSILON * 4.0)
		if contains(point + normal * epsilon, regions) == contains(point - normal * epsilon, regions):
			return false
	return true
