extends SceneTree

func _initialize() -> void:
	var port := preload("res://world/regions/OriginalSouthPort.gd")
	var layout := preload("res://world/regions/OriginalSouthPortLayout.gd")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var owners: Array[PackedVector2Array] = []
	for row in data.harbor_land:
		owners.append(layout.rect_polygon(Rect2(row[0],row[1],row[2],row[3])))
	var original := port.extra_surfaces()
	var exposed := port.extra_surfaces(data.harbor_land)
	var failures: Array[String] = []
	for polygon in exposed:
		for owner in owners:
			for overlap in Geometry2D.intersect_polygons(polygon,owner):
				if area(overlap) > .01: failures.append("Overlapping port ground owners")
		owners.append(polygon)
	# Entire access corridor, including its city/quay joins and both shoulders.
	for x in range(2840,3910,13):
		for y in range(2030,3760,13):
			var point := Vector2(x,y)
			var expected := false
			for polygon in original:
				expected = expected or Geometry2D.is_point_in_polygon(point,polygon)
			if not expected: continue
			var supported := false
			for polygon in owners:
				supported = supported or Geometry2D.is_point_in_polygon(point,polygon)
			if not supported: failures.append("Lost access support at "+str(point))
	print("PORT_GROUND_OWNERSHIP failures=",failures)
	quit(0 if failures.is_empty() else 1)

func area(polygon: PackedVector2Array) -> float:
	var result := 0.0
	for i in polygon.size(): result += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(result)*.5
