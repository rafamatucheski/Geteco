extends RefCounted
## Driveways cross the actual street sidewalk, wide enough for rear wheel offtracking.
const FOREGROUND_LAYER := 128
const STREET_HANDOFF_Y := 80.0

static func driveway_rects() -> Array[Rect2]:
	return [Rect2(210, 80, 80, 56), Rect2(320, 80, 80, 56)]

static func driveway_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for rect in driveway_rects():
		result.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	return result
