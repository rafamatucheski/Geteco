extends RefCounted
## Empty paved lot EAST of the orange neighbour. Leave the perimeter sidewalk free.
const CENTER := Vector3(67, 0, 94)
const FOOTPRINT := Rect2(60, 85.5, 14, 17)
const RADII := Vector2(4.65, 5.75)
const DEPTH := 1.65
const ENTRY := Vector3(70, .12, 101.5)

## Explicit A/B hook for the rendered benchmark, never a player setting.
static func enabled() -> bool: return not Engine.get_meta("skate_benchmark_baseline", false)

static func outline_scale(angle: float) -> float:
	return 1.0 + .09 * cos(angle * 3) + .04 * sin(angle * 2)

static func lip(angle: float) -> Vector2:
	return Vector2(CENTER.x, CENTER.z) + Vector2(cos(angle), sin(angle)) * RADII * outline_scale(angle)

static func height_at(point: Vector2) -> float:
	var normalized := (point - Vector2(CENTER.x, CENTER.z)) / RADII
	var r := normalized.length() / outline_scale(normalized.angle())
	if r >= 1.0: return .025
	return .025 - DEPTH * cos(clampf((r - .35) / .65, 0, 1) * PI * .5)

static func outside(rect: Rect2) -> Array[Rect2]:
	if not enabled(): return [rect] if rect.has_area() else []
	var overlap := rect.intersection(FOOTPRINT)
	if not overlap.has_area(): return [rect] if rect.has_area() else []
	var result: Array[Rect2] = []
	if overlap.position.y > rect.position.y: result.append(Rect2(rect.position, Vector2(rect.size.x, overlap.position.y - rect.position.y)))
	if overlap.end.y < rect.end.y: result.append(Rect2(rect.position.x, overlap.end.y, rect.size.x, rect.end.y - overlap.end.y))
	if overlap.position.x > rect.position.x: result.append(Rect2(rect.position.x, overlap.position.y, overlap.position.x - rect.position.x, overlap.size.y))
	if overlap.end.x < rect.end.x: result.append(Rect2(overlap.end.x, overlap.position.y, rect.end.x - overlap.end.x, overlap.size.y))
	return result
