@tool
extends "res://district/roads/UnifiedRoadNetwork2D.gd"

## Streets retain the shared renderer, lane graph and validation unchanged.
## The harbor's authored terrain supplies land, quays and water instead of the
## generic rectangular grass background used by the existing districts.
func _draw_grass_ground() -> void:
	pass


const EDGE_EPSILON := 0.02
var _edge_revision := -1
var _edge_builds := 0
var _edge_layers: Dictionary = {}


func _build_junction_surface_geometry(junction: Dictionary, extra_width: float) -> Dictionary:
	var geometry := super._build_junction_surface_geometry(junction, extra_width)
	if _is_authored_street_corner(geometry.arms):
		return _rounded_street_corner(junction, extra_width, geometry)
	# The three degree-two seams of Ashbend's circle are continuations, not
	# intersections. Extend the actual authored adjacent segments through their
	# common point; a tangent-cap convex hull would swell the outside of the bend.
	if (junction.roads as Array).size() != 2:
		return geometry
	for index in junction.roads:
		if not String(_roads[int(index)].id).get_file().begins_with("cobra_court_"):
			return geometry
	var first_points: PackedVector2Array = _roads[int(junction.roads[0])].points
	var second_points: PackedVector2Array = _roads[int(junction.roads[1])].points
	var center := Vector2.INF
	for first in [first_points[0],first_points[-1]]:
		for second in [second_points[0],second_points[-1]]:
			if first.distance_to(second)<0.02:
				center = first
	if not center.is_finite():
		return geometry
	var arms: Array[Dictionary] = []
	var branches: Array[PackedVector2Array] = []
	for index in junction.roads:
		var road: Dictionary = _roads[int(index)]
		var points: PackedVector2Array = road.points
		if points.size() < 2:
			return geometry
		var at_start := points[0].distance_to(center) < points[-1].distance_to(center)
		var branch := PackedVector2Array()
		for step in points.size():
			var point := points[step] if at_start else points[points.size()-1-step]
			branch.append(point)
			if point.distance_to(center)>=30.0:
				break
		branches.append(branch)
		var neighbor := branch[-1]
		var span := center.distance_to(neighbor)
		var direction := (neighbor-center).normalized()
		arms.append({"direction":direction,"angle":direction.angle(),"half_width":(float(road.width)+extra_width)*0.5,"outer_half_width":float(road.width)*0.5+SIDEWALK_MARGIN,"road_indices":[int(index)],"rendered_road_indices":[int(index)],"hidden_road_indices":[],"cutback":span})
	var line := branches[0].duplicate()
	line.reverse()
	line.append_array(branches[1].slice(1))
	var half_width: float = float(arms[0].half_width)
	var polygons := Geometry2D.offset_polyline(line, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	if polygons.size() != 1 or polygons[0].size() < 3:
		return geometry
	geometry.polygon = _counter_clockwise_polygon(polygons[0])
	geometry.arms = arms
	geometry.extent_limit = _surface_polygon_maximum_extent(geometry.polygon, junction.position)
	geometry.construction = "authored_curve_continuation"
	geometry.component_count = 1
	geometry.beveled_sector_count = 0
	return geometry


func _is_authored_street_corner(arms: Array) -> bool:
	if arms.size() != 2:
		return false
	if absf(Vector2(arms[0].direction).dot(Vector2(arms[1].direction))) > 0.001:
		return false
	for arm in arms:
		if not (arm.hidden_road_indices as Array).is_empty():
			return false
		for index in arm.road_indices:
			var id := String(_roads[int(index)].id).get_file()
			if id.begins_with("cobra_") or id.begins_with("map2_"):
				return false
	return true


func _rounded_street_corner(junction: Dictionary, extra_width: float, geometry: Dictionary) -> Dictionary:
	# One shared centre for the inner fillet across all four materials keeps
	# the 42px sidewalk continuous. Outer radii follow the actual road widths.
	# The ribbon, lane graph and collision masks are NOT rebuilt or relocated.
	var arms: Array = geometry.arms
	var a: Vector2 = arms[0].direction
	var b: Vector2 = arms[1].direction
	var hx := float(arms[1].half_width)
	var hy := float(arms[0].half_width)
	var radius := maxf(6.0, 48.0 - extra_width * 0.5)
	var extent := Vector2(hx + radius, hy + radius)
	var local_points := PackedVector2Array([Vector2(-hx, extent.y), Vector2(-hx, 0)])
	for step in range(1, 25):
		var angle := float(step) / 24.0 * PI * 0.5
		local_points.append(Vector2(-hx * cos(angle), -hy * sin(angle)))
	local_points.append(Vector2(extent.x, -hy))
	local_points.append(Vector2(extent.x, hy))
	for step in range(1, 25):
		var angle := float(step) / 24.0 * PI * 0.5
		local_points.append(extent - Vector2(sin(angle), cos(angle)) * radius)
	var polygon := PackedVector2Array()
	for point in local_points:
		polygon.append(Vector2(junction.position) + a * point.x + b * point.y)
	geometry.polygon = _counter_clockwise_polygon(polygon)
	geometry.extent_limit = _surface_polygon_maximum_extent(geometry.polygon, junction.position)
	geometry.construction = "rounded_street_corner"
	geometry.component_count = 1
	geometry.beveled_sector_count = 0
	return geometry


func _draw() -> void:
	super._draw()
	_ensure_edge_cache()
	for layer_name in ["sidewalk", "curb"]:
		var openings := _collect_edge_openings(layer_name == "sidewalk")
		var layer: Dictionary = _edge_layers.get(layer_name, {})
		var color := Color("#616c68") if layer_name == "sidewalk" else Color("#dbcfb5")
		var width := 2.0 if layer_name == "sidewalk" else 2.3
		# Independent segments with identical style can share one draw command.
		# Keep every authored opening and the original sidewalk/curb layer order.
		var lines := PackedVector2Array()
		for segment in _visible_edge_segments(layer.get("segments", []), openings):
			lines.append(segment[0])
			lines.append(segment[1])
		if not lines.is_empty():
			draw_multiline(lines, color, width, true)


func _ensure_edge_cache() -> void:
	if _edge_revision == get_routing_revision():
		return
	_edge_revision = get_routing_revision()
	_edge_builds += 1
	_edge_layers.clear()
	for layer in [{"id": "sidewalk", "extra": SIDEWALK_MARGIN * 2.0}, {"id": "curb", "extra": 10.0}]:
		var polygons := _collect_edge_surfaces(float(layer.extra))
		_edge_layers[String(layer.id)] = _union_boundary(polygons)


func _collect_edge_surfaces(extra_width: float) -> Array[PackedVector2Array]:
	# Exactly the filled ribbons and patches used by the inherited material pass;
	# never invent another centerline, junction radius, collision or traffic mesh.
	var polygons: Array[PackedVector2Array] = []
	for road in _roads:
		if not bool(road.render):
			continue
		for polygon in Geometry2D.offset_polyline(road.points, (float(road.width) + extra_width) * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
			if polygon.size() >= 3 and not Geometry2D.is_polygon_clockwise(polygon):
				polygons.append(polygon)
	for junction in _junctions:
		var geometry := _build_junction_surface_geometry(junction, extra_width)
		var polygon: PackedVector2Array = geometry.polygon
		if polygon.size() >= 3 and not Geometry2D.triangulate_polygon(polygon).is_empty():
			polygons.append(polygon)
	return polygons


func _union_boundary(polygons: Array[PackedVector2Array]) -> Dictionary:
	# Native polygon Boolean operations preserve the closed frontier even for
	# densely sampled curves. Holes are voids, never merged as filled polygons.
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for source in polygons:
		holes = _subtract_from_edge_holes(holes, source)
		var candidate := source
		var new_holes: Array[PackedVector2Array] = []
		var index := 0
		while index < outers.size():
			var merged := Geometry2D.merge_polygons(candidate, outers[index])
			var merged_outers: Array[PackedVector2Array] = []
			var merged_holes: Array[PackedVector2Array] = []
			for polygon in merged:
				if Geometry2D.is_polygon_clockwise(polygon):
					merged_holes.append(_counter_clockwise_polygon(polygon))
				else:
					merged_outers.append(polygon)
			if merged_outers.size() != 1:
				index += 1 # disconnected island; retain both outer frontiers
				continue
			new_holes = _subtract_from_edge_holes(new_holes, outers[index])
			new_holes.append_array(merged_holes)
			candidate = merged_outers[0]
			outers.remove_at(index)
			index = 0
		outers.append(candidate)
		holes.append_array(new_holes)
	var segments: Array[PackedVector2Array] = []
	var loops: Array[PackedVector2Array] = []
	var contours := outers.duplicate()
	for hole in holes:
		var reversed := hole.duplicate()
		reversed.reverse()
		contours.append(reversed)
	for polygon in contours:
		if polygon.size() < 3:
			continue
		var loop: PackedVector2Array = polygon.duplicate()
		if loop[0].distance_to(loop[-1]) > 0.001:
			loop.append(loop[0])
		loops.append(loop)
		for index in range(loop.size()-1):
			if loop[index].distance_to(loop[index+1]) > 0.001:
				segments.append(PackedVector2Array([loop[index],loop[index+1]]))
	return {"sources":polygons,"segments":segments,"contours":loops,"open_chains":0}


func _subtract_from_edge_holes(holes: Array[PackedVector2Array], filled: PackedVector2Array) -> Array[PackedVector2Array]:
	var remaining: Array[PackedVector2Array] = []
	for hole in holes:
		var reversed := Geometry2D.is_polygon_clockwise(hole)
		for piece in Geometry2D.clip_polygons(_counter_clockwise_polygon(hole), filled):
			if reversed:
				piece.reverse()
			remaining.append(piece)
	return remaining


func _collect_edge_openings(include_alleys: bool = false) -> Array[PackedVector2Array]:
	var openings: Array[PackedVector2Array] = []
	var composition := get_parent()
	if composition == null:
		return openings
	for candidate in composition.find_children("*", "Node2D", true, false):
		if candidate.has_method("get_secret_drive"):
			var drive: PackedVector2Array = candidate.get_secret_drive()
			if drive.size() >= 2:
				# Clip the authored 64px driveway only up to its terminal centreline.
				# A butt cap is essential: extending beyond the endpoint would also
				# erase the opposite/north curb of the 84px approach road.
				var terminal := PackedVector2Array([drive[-2], drive[-1]])
				for ribbon in Geometry2D.offset_polyline(terminal, 32.0, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
					var opening := PackedVector2Array()
					for point in ribbon:
						opening.append(to_local(candidate.to_global(point)))
					openings.append(opening)
		if candidate.has_method("get_spatial_audit"):
			var accesses: Variant = candidate.get("accesses")
			if accesses is Array:
				for access in accesses:
					openings.append(_edge_rect_polygon(candidate, (access.bounds as Rect2).grow(5.0)))
		if candidate.has_method("get_crossing_data"):
			var depth := float(candidate.get("crossing_depth")) + 10.0
			var span := float(candidate.get("road_width")) + float(candidate.get("sidewalk_reach")) * 2.0 + 12.0
			openings.append(_edge_rect_polygon(candidate, Rect2(-Vector2(depth, span) * 0.5, Vector2(depth, span))))
		if include_alleys and candidate.has_method("get_alley_definitions"):
			var definitions: Variant = candidate.call("get_alley_definitions")
			if definitions is Array:
				for alley in definitions:
					if not bool(alley.get("pedestrian_only", false)):
						continue
					var points: PackedVector2Array = alley.get("points", PackedVector2Array())
					for index in range(points.size() - 1):
						var segment := PackedVector2Array([points[index], points[index + 1]])
						for source_polygon in Geometry2D.offset_polyline(segment, (float(alley.width) + 4.0) * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
							var polygon := PackedVector2Array()
							for point in source_polygon:
								polygon.append(to_local(candidate.to_global(point)))
							openings.append(polygon)
	return openings


func _edge_rect_polygon(source: Node2D, bounds: Rect2) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		polygon.append(to_local(source.to_global(point)))
	return polygon


func _visible_edge_segments(segments: Array, openings: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var visible: Array[PackedVector2Array] = []
	var clip_shapes: Array[PackedVector2Array] = []
	for opening in openings:
		# Native clipping rounds curved intersections. A subpixel outward
		# margin prevents a retained segment from sitting on the mask itself.
		var expanded := Geometry2D.offset_polygon(opening, EDGE_EPSILON, Geometry2D.JOIN_MITER)
		clip_shapes.append(expanded[0] if expanded.size()==1 else opening)
	for segment in segments:
		var pieces: Array[PackedVector2Array] = [segment]
		for clip_shape in clip_shapes:
			var remaining: Array[PackedVector2Array] = []
			for piece in pieces:
				remaining.append_array(Geometry2D.clip_polyline_with_polygon(piece, clip_shape))
			pieces = remaining
			if pieces.is_empty():
				break
		visible.append_array(pieces)
	return visible


func get_road_edge_audit() -> Dictionary:
	_ensure_edge_cache()
	var openings := _collect_edge_openings()
	var layers := _edge_layers.duplicate(true)
	for layer_name in layers:
		var layer: Dictionary = layers[layer_name]
		var layer_openings := _collect_edge_openings(layer_name == "sidewalk")
		layer["openings"] = layer_openings
		layer["visible_segments"] = _visible_edge_segments(layer.segments, layer_openings)
	return {"revision": _edge_revision, "builds": _edge_builds, "layers": layers, "openings": openings}
