extends RefCounted
## Chunk-owned, batched route edges. The full 14 m haul aisle stays driveable.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const BATCH := preload("res://world/mining/MiningBatch.gd")
const MARKER_SPACING := 12.0
static var _stations: Array[Dictionary] = []

static func _route_stations() -> Array[Dictionary]:
	if not _stations.is_empty(): return _stations
	var points := LAYOUT.haul_points()
	var travelled := 0.0
	var next_marker := 10.0
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		var length_value := a.distance_to(b)
		while next_marker <= travelled + length_value:
			var point := a.lerp(b, (next_marker - travelled) / maxf(length_value, .001))
			var tangent := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			_stations.append({"point": point - LAYOUT.CENTER, "side": Vector3(-tangent.z, 0, tangent.x), "yaw": atan2(tangent.x, tangent.z)})
			next_marker += MARKER_SPACING
		travelled += length_value
	return _stations

static func build(parent: Node3D, local_rect: Rect2, height_at: Callable) -> void:
	var batch: RefCounted = null
	var stations := _route_stations()
	for index in stations.size():
		var record := stations[index]
		for direction in [-1.0, 1.0]:
			var point: Vector3 = record.point + record.side * direction * 7.8
			var planar := Vector2(point.x, point.z)
			if not local_rect.has_point(planar): continue
			if LAYOUT.SECRET_RESERVE.grow(4).has_point(planar): continue
			# Do not put markers on another winding of the same road.
			if LAYOUT.haul_sample(planar).x < 7.25: continue
			if batch == null: batch = BATCH.new(parent, "MineHaulRouteEdges", LAYOUT.CENTER)
			point.y = float(height_at.call(planar + Vector2(LAYOUT.CENTER.x, LAYOUT.CENTER.z)))
			batch.box("HaulEdgePost", point + Vector3.UP * .64, Vector3(.16, 1.28, .16), "yellow", true)
			batch.box("HaulEdgeDarkBand", point + Vector3.UP * .72, Vector3(.175, .26, .175), "rubber")
			# Reflective collars read from both descent and ascent, without lights.
			batch.box("HaulEdgeReflector", point + Vector3.UP * 1.15, Vector3(.18, .18, .18), "white")
			if index % 3 != 0 or point.y > -.8: continue
			var berm: Vector3 = record.point + record.side * direction * 9.3
			var berm_xz := Vector2(berm.x, berm.z)
			if not local_rect.has_point(berm_xz) or LAYOUT.haul_sample(berm_xz).x < 8.5: continue
			# Small blasted-rock berms sit outside the shoulder. Sample the full
			# footprint, including the downhill flank of each excavated bench.
			var tangent := Vector3(sin(float(record.yaw)), 0, cos(float(record.yaw)))
			var base := INF
			for end in [-1.0, 0.0, 1.0]:
				for flank in [-.65, .65]:
					var foot: Vector3 = berm + tangent * end + record.side * flank
					base = minf(base, float(height_at.call(Vector2(foot.x + LAYOUT.CENTER.x, foot.z + LAYOUT.CENTER.z))))
			berm.y = base + .26
			batch.rock("HaulShoulderBerm", berm, Vector3(1.3, .82, 2.5), "ore_light", true, float(record.yaw))
	if batch != null: batch.finish()
