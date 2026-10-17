extends SceneTree
const SURFACE = preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
var failures := 0
func area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in polygon.size(): sum += (polygon[i]-polygon[0]).cross(polygon[(i+1)%polygon.size()]-polygon[0])
	return absf(sum)*.5
func _initialize() -> void:
	var paving = SURFACE.new()
	paving.configure()
	var maximum_error := 0.0
	var overlaps := 0.0
	var rounded := 0
	for source in paving._visible_surfaces:
		var parts = paving._rounded_parts(source,source.rect)
		var polygons: Array[PackedVector2Array] = []
		var covered := 0.0
		for part in parts:
			for polygon in part.polygons:
				covered += area(polygon)
				polygons.append(polygon)
				if polygon.size() > 4: rounded += 1
		maximum_error = maxf(maximum_error,absf(covered-source.rect.get_area()))
		for i in polygons.size():
			for j in range(i+1,polygons.size()):
				for overlap in Geometry2D.intersect_polygons(polygons[i],polygons[j]): overlaps += area(overlap)
		# Splitting a lot at an arbitrary streaming boundary preserves its area.
		var left: Rect2 = source.rect
		left.size.x *= .5
		var right: Rect2 = source.rect
		right.position.x = left.end.x
		right.size.x -= left.size.x
		var split_area := 0.0
		for clip in [left,right]:
			for part in paving._rounded_parts(source,clip):
				for polygon in part.polygons: split_area += area(polygon)
		maximum_error = maxf(maximum_error,absf(covered-split_area))
	if maximum_error > .005 or overlaps > .005 or rounded == 0: failures += 1
	var chunk := Node3D.new()
	root.add_child(chunk)
	paving.build_chunk(chunk,Rect2(25,25,64,64))
	if chunk.get_child_count() > 7: failures += 1
	if preload("res://world/urban_detail/GroundCut.gd").failed_triangulations != 0: failures += 1
	print("ROUNDED_PAVING failures=",failures," max_area_error_m2=",maximum_error," overlap_m2=",overlaps," curved_parts=",rounded," chunk_meshes=",chunk.get_child_count())
	chunk.free()
	quit(0 if failures == 0 else 1)
