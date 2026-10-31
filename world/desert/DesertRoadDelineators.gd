extends RefCounted
## Orientação esparsa nas rodovias abertas, fora do acostamento de cascalho existente de 2.4 m.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const BATCH := preload("res://world/shared/roads/RoadDelineatorBatches.gd")
const SPACING := 28.0
var _points: Array[Transform3D] = []


func configure(roads: Array[Dictionary], geometry) -> void:
	_points.clear()
	var approaches: Array = RELICS.approach_paths()
	for road in roads:
		if str(road.id) not in ["desert_route_66", "desert_west_highway", "desert_salt_highway", "desert_main_street"]: continue
		var points: PackedVector3Array = road.points
		var half := float(road.width) * 0.5
		var travelled := 0.0
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			var direction := a.direction_to(b)
			var normal := Vector3(direction.z, 0, -direction.x).normalized()
			var step := fposmod(SPACING * 0.5 - travelled, SPACING)
			while step < length - 0.001:
				var center := a + direction * step
				for side: float in [-1.0, 1.0]:
					var point: Vector3 = center + normal * side * (half + 3.15)
					var flat := Vector2(point.x, point.z)
					# Preserve bridge/toll transition, town frontage and activity access.
					if point.z > -465.0: continue
					if road.id == "desert_main_street" and point.x > -410.0 and point.x < -60.0: continue
					if ROADSIDE.reserved(flat, 4.0) or not LAYOUT.drag_reservation_clear(flat, 4.0): continue
					if not LAYOUT.road_clear(flat, -1.5): continue
					if _near_junction(flat, geometry.junctions) or _near_approach(flat, approaches): continue
					point.y = geometry._height(flat)
					_points.append(Transform3D(Basis(Vector3.UP, atan2(direction.x, direction.z)), point))
				step += SPACING
			travelled += length


func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var selected: Array[Transform3D] = []
	for transform in _points:
		if rect.has_point(Vector2(transform.origin.x, transform.origin.z)): selected.append(transform)
	BATCH.build(parent, selected, "DesertDelineator")


func _near_junction(point: Vector2, junctions: Array) -> bool:
	for junction: Dictionary in junctions:
		if point.distance_to(junction.at) < 15.0: return true
	return false


func _near_approach(point: Vector2, approaches: Array) -> bool:
	for points: Array in approaches:
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) < 4.0: return true
	return false
