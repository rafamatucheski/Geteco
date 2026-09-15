extends SceneTree
const AUDIT := preload("res://tests/support/RoadBoundaryAudit.gd")
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func _initialize() -> void:
	for origin in [Vector2.ZERO, Vector2(6000, -4600), Vector2(-6000, 4600)]:
		var polygons: Array[PackedVector2Array] = [
			rect_polygon(Rect2(origin, Vector2(100, 20))),
			rect_polygon(Rect2(origin + Vector2(0, 20.06), Vector2(100, 20)))]
		var regions := AUDIT.prepare(polygons)
		var real_edge := PackedVector2Array([origin + Vector2(10, 20), origin + Vector2(90, 20)])
		check(AUDIT.is_boundary(real_edge, regions), "real boundary remains valid across a 0.06px gap at " + str(origin))
		var internal := PackedVector2Array([origin + Vector2(10, 10), origin + Vector2(90, 10)])
		check(not AUDIT.is_boundary(internal, regions), "reject a real internal seam at " + str(origin))
		var near_internal := PackedVector2Array([origin + Vector2(10, 19.99), origin + Vector2(90, 19.99)])
		check(not AUDIT.is_boundary(near_internal, regions), "reject a seam only 0.01px inside the surface at " + str(origin))
		var detached := PackedVector2Array([origin + Vector2(10, 50), origin + Vector2(90, 50)])
		check(not AUDIT.is_boundary(detached, regions), "reject a detached contour at " + str(origin))
		var tiny := PackedVector2Array([origin + Vector2(50, 20), origin + Vector2(50.02, 20)])
		check(AUDIT.is_boundary(tiny, regions), "short boundary is resolved without ignoring it at " + str(origin))
		check(not AUDIT.is_boundary(PackedVector2Array([origin, origin]), regions), "reject a degenerate edge")
	print("ROAD_BOUNDARY_PRECISION failures=", failures)
	quit(0 if failures.is_empty() else 1)
