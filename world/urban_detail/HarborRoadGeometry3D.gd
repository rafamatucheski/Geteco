@tool
extends RefCounted
class_name HarborRoadGeometry3D

## Native projection of the productive HarborRoadNetwork surface stack.
## Source authority: geodata/roads/UnifiedRoadNetwork2D.gd. Coordinates and
## widths arrive already converted to metres by NativeRegion.

const SOURCE_SCALE := 1.0 / 16.0
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const SIDEWALK_MARGIN := 42.0 * SOURCE_SCALE
const DASH_LENGTH := 28.0 * SOURCE_SCALE
const DASH_GAP := 26.0 * SOURCE_SCALE
const MIN_SEGMENT := 2.0 * SOURCE_SCALE

const ROAD_COLOR := Color("202932")
const ROAD_EDGE_COLOR := Color("151c23")
const SIDEWALK_COLOR := Color("aaa9a1")
const CURB_COLOR := Color("70767a")
const LANE_COLOR := Color("dfc84d")
const CROSSWALK_COLOR := Color("eeeade")
const TACTILE_COLOR := Color("d9ad34")
const STOP_LINE_COLOR := Color("f4f1e8")
const UNSIGNALIZED_SOURCE_POINTS := [
	Vector2(3750,3600),Vector2(3750,4770),Vector2(5750,4770),
	Vector2(7400,1700),Vector2(7700,1400),Vector2(7700,2000),Vector2(8000,1700),
]

# Revisão do catálogo usado pelo índice de acabamento dos chunks.
var context_revision := 0
var _roads: Array[Dictionary] = []
var _junctions: Array[Dictionary] = []
var _layers: Array[Dictionary] = []
var _materials: Dictionary = {}
var _crosswalk_white: Array[PackedVector2Array] = []
var _crosswalk_tactile: Array[PackedVector2Array] = []
var _crosswalk_stop: Array[PackedVector2Array] = []
var _crossing_masks: Array[PackedVector2Array] = []
var crossing_layout: Array[Dictionary] = []
var _earth_polygons: Array[PackedVector2Array] = []
var _earth_verge_triangles: Array = []


func configure(source_roads: Array[Dictionary], surfaces := true) -> void:
	context_revision += 1
	_roads.clear()
	_junctions.clear()
	_layers.clear()
	_crosswalk_white.clear()
	_crosswalk_tactile.clear()
	_crosswalk_stop.clear()
	_crossing_masks.clear()
	_earth_polygons.clear()
	_earth_verge_triangles.clear()
	for source in source_roads:
		if String(source.get("surface", "asphalt")) != "asphalt":
			continue
		var points := PackedVector2Array()
		for point_value in source.get("points", PackedVector3Array()):
			var point := point_value as Vector3
			points.append(Vector2(point.x, point.z))
		if points.size() < 2:
			continue
		_roads.append({
			"id": String(source.get("id", "road")).trim_prefix("road/"),
			"points": points,
			"width": float(source.get("width", 7.5)),
			"lanes_per_direction": int(source.get("lanes_per_direction",1)),
			"sidewalk_width": float(source.get("sidewalk_width",SIDEWALK_MARGIN)),
			"crossings": source.get("crossings",true),
			"crossing_offset": float(source.get("crossing_offset",0)),
			"crossing_depth": float(source.get("crossing_depth",30.0*SOURCE_SCALE)),
			"custom_crossing_depth": source.has("crossing_depth"),
			"crossing_entries": source.get("crossing_entries",{}),
		})
	_discover_junctions()
	if not surfaces:
		_prepare_crosswalks()
		return
	_layers = [
		_layer(SIDEWALK_COLOR, SIDEWALK_MARGIN * 2.0, 0.008),
		_layer(CURB_COLOR, 10.0 * SOURCE_SCALE, 0.014),
		_layer(ROAD_EDGE_COLOR, 4.0 * SOURCE_SCALE, 0.020),
		_layer(ROAD_COLOR, 0.0, 0.026),
	]
	# Rural branches are real roads in the editor/traffic network. Their surface
	# ends at the asphalt footprint, rather than painting over the junction.
	for road in source_roads:
		if road.get("surface","asphalt") != "earth": continue
		var flat := PackedVector2Array()
		for p in road.points: flat.append(Vector2(p.x,p.z))
		for polygon in Geometry2D.offset_polyline(flat,float(road.width)*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT):
			var pieces: Array[PackedVector2Array] = [polygon]
			for asphalt in _layers[-1].polygons:
				var remainder: Array[PackedVector2Array] = []
				for piece in pieces: remainder.append_array(Geometry2D.clip_polygons(piece,asphalt))
				pieces = remainder
			_earth_polygons.append_array(pieces)
	_earth_verge_triangles = preload("res://world/urban_detail/RuralRoadVerge.gd").prepare(_earth_polygons)
	_prepare_crosswalks()


func build_chunk(parent: Node3D, rect: Rect2) -> void:
	if _layers.is_empty():
		return
	var clip := _rect_polygon(rect)
	preload("res://world/urban_detail/RuralRoadVerge.gd").build(parent,_earth_verge_triangles,clip)
	_add_clipped_surface(parent,"HarborEarthRoad",_earth_polygons,clip,0.023,preload("res://world/urban_detail/RuralGroundMaterial.gd").material())
	var sewer_opening := Rect2(CATALOG.HARBOR_SEWER_OPENING.position * SOURCE_SCALE, CATALOG.HARBOR_SEWER_OPENING.size * SOURCE_SCALE)
	var opening_clip := _rect_polygon(sewer_opening) if rect.intersects(sewer_opening) else PackedVector2Array()
	for layer in _layers:
		var clipped: Array[PackedVector2Array] = []
		for polygon_value in layer.polygons:
			var polygon := polygon_value as PackedVector2Array
			for piece_value in Geometry2D.intersect_polygons(polygon, clip):
				var piece := piece_value as PackedVector2Array
				if piece.size() >= 3:
					if opening_clip.is_empty():
						clipped.append(piece)
					else:
						for outside in Geometry2D.clip_polygons(piece, opening_clip):
							if outside.size() >= 3: clipped.append(outside)
		_add_surface(parent, "HarborRoad_%s" % layer.name, clipped, float(layer.y), layer.material)
	_add_clipped_surface(parent,"HarborCrosswalk",_crosswalk_white,clip,0.038,_material(CROSSWALK_COLOR))
	_add_clipped_surface(parent,"HarborTactile",_crosswalk_tactile,clip,0.039,_material(TACTILE_COLOR))
	_add_clipped_surface(parent,"HarborStopLine",_crosswalk_stop,clip,0.040,_material(STOP_LINE_COLOR))
	_build_markings(parent, rect)


func source_coverage_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for road in _roads:
		var points := road.points as PackedVector2Array
		for index in range(points.size() - 1):
			if points[index].distance_to(points[index + 1]) < MIN_SEGMENT:
				errors.append("%s segment %d is shorter than the V1 minimum" % [road.id, index])
	for junction in _junctions:
		if (junction.roads as Array).size() < 2:
			errors.append("orphan junction at %s" % junction.position)
	return errors


func _layer(color: Color, extra_width: float, y: float) -> Dictionary:
	var polygons: Array[PackedVector2Array] = []
	for road in _roads:
		var extra := float(road.sidewalk_width)*2 if is_equal_approx(extra_width,SIDEWALK_MARGIN*2) else extra_width
		var surfaces := Geometry2D.offset_polyline(
			road.points,
			(float(road.width) + extra) * 0.5,
			Geometry2D.JOIN_ROUND,
			Geometry2D.END_BUTT
		)
		for surface_value in surfaces:
			var surface := _counter_clockwise(surface_value as PackedVector2Array)
			if surface.size() >= 3:
				polygons.append(surface)
	for junction in _junctions:
		var patch := _junction_patch(junction, extra_width)
		if patch.size() >= 3:
			polygons.append(patch)
	return {
		"name": color.to_html(false),
		"polygons": polygons,
		"material": _material(color),
		"y": y,
	}


func _discover_junctions() -> void:
	for first_index in range(_roads.size()):
		var first := _roads[first_index]
		var first_points := first.points as PackedVector2Array
		for second_index in range(first_index + 1, _roads.size()):
			var second := _roads[second_index]
			var second_points := second.points as PackedVector2Array
			for first_segment in range(first_points.size() - 1):
				for second_segment in range(second_points.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(
						first_points[first_segment], first_points[first_segment + 1],
						second_points[second_segment], second_points[second_segment + 1]
					)
					if hit is Vector2:
						_add_junction(hit, first_index, second_index)


func _add_junction(position: Vector2, first: int, second: int) -> void:
	for junction_index in range(_junctions.size()):
		var junction := _junctions[junction_index]
		if (junction.position as Vector2).distance_to(position) <= 0.08:
			var indices := junction.roads as Array
			if not indices.has(first): indices.append(first)
			if not indices.has(second): indices.append(second)
			junction.roads = indices
			_junctions[junction_index] = junction
			return
	_junctions.append({"position": position, "roads": [first, second]})


func _junction_patch(junction: Dictionary, extra_width: float) -> PackedVector2Array:
	var center := junction.position as Vector2
	var cap_points := PackedVector2Array([center])
	var largest_outer_half := 0.0
	var arms: Array[Dictionary] = []
	for crossing_arm in _crossing_arms(junction):
		var road: Dictionary = crossing_arm.road
		var extra := float(road.sidewalk_width)*2 if is_equal_approx(extra_width,SIDEWALK_MARGIN*2) else extra_width
		var half_width := (float(crossing_arm.width) + extra) * 0.5
		largest_outer_half = maxf(largest_outer_half, float(road.width) * 0.5 + SIDEWALK_MARGIN)
		_add_arm(arms,crossing_arm.direction,half_width)
	var widest := 0.0
	for road_index_value in junction.roads:
		widest = maxf(widest, float(_roads[int(road_index_value)].width))
	var radius := widest * 0.68 + 14.0 * SOURCE_SCALE
	var core_limit := maxf(radius + 8.0 * SOURCE_SCALE, largest_outer_half + 2.0 * SOURCE_SCALE)
	for arm in arms:
		var half_width := minf(float(arm.half_width), core_limit)
		var radial_limit := sqrt(maxf(0.0, core_limit * core_limit - half_width * half_width))
		var cutback := minf(half_width + 8.0 * SOURCE_SCALE, radial_limit)
		var direction := arm.direction as Vector2
		var normal := direction.orthogonal()
		var cap_center := center + direction * cutback
		cap_points.append(cap_center - normal * half_width)
		cap_points.append(cap_center + normal * half_width)
	# O casco convexo só dos cortes chanfrava a quina externa de curvas em L (e a de
	# ruas que terminam no cruzamento): a calçada virava uma diagonal e sobrava um
	# triângulo de terreno. Cruzar as bordas de braços vizinhos devolve a quina em
	# esquadro, como uma rua de verdade.
	arms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.direction as Vector2).angle() < (b.direction as Vector2).angle())
	for index in range(arms.size()):
		var first: Dictionary = arms[index]
		var second: Dictionary = arms[(index + 1) % arms.size()]
		var first_direction := first.direction as Vector2
		var second_direction := second.direction as Vector2
		if absf(first_direction.cross(second_direction)) < 0.05: continue
		var first_half := minf(float(first.half_width), core_limit)
		var second_half := minf(float(second.half_width), core_limit)
		# Com ângulos ordenados, orthogonal() gira -90°: o lado de "first" que encara
		# "second" é -orthogonal() e o de "second" que encara "first" é +orthogonal().
		var hit: Variant = Geometry2D.line_intersects_line(
			center - first_direction.orthogonal() * first_half, first_direction,
			center + second_direction.orthogonal() * second_half, second_direction)
		if hit is Vector2 and center.distance_to(hit) <= core_limit * 2.0:
			cap_points.append(hit)
	return _counter_clockwise(Geometry2D.convex_hull(cap_points))


func _add_arm(arms: Array[Dictionary], direction: Vector2, half_width: float) -> void:
	for index in range(arms.size()):
		if (arms[index].direction as Vector2).dot(direction) >= 0.99862953475:
			arms[index].half_width = maxf(float(arms[index].half_width), half_width)
			return
	arms.append({"direction": direction.normalized(), "half_width": half_width})


func _prepare_crosswalks() -> void:
	crossing_layout = preload("res://world/editing/WorldCrossingLayout.gd").build(self)
	for junction in crossing_layout:
		for entry in junction.entries:
			if entry.enabled:
				_append_crossing(entry.position,entry.direction,entry.width,entry.depth,entry.sidewalk,true,false)
			if entry.stop_line:
				var normal: Vector2 = entry.direction.orthogonal()
				_crosswalk_stop.append(_quad(entry.stop_position+normal*entry.width*.25,entry.direction,3.0*SOURCE_SCALE,entry.width*.5))
	# HarborSafety.gd authors exactly two unsignalized Ashbend crossings by
	# road-relative fraction. They replace zebra fans at the ring topology seams.
	_append_road_crossing("cobra_approach",0.78,26.0*SOURCE_SCALE,42.0*SOURCE_SCALE)
	_append_road_crossing("cobra_court_northwest",0.90,26.0*SOURCE_SCALE,42.0*SOURCE_SCALE)


func _append_road_crossing(road_id: String, t: float, depth: float, _sidewalk_reach: float) -> void:
	for road in _roads:
		if String(road.id).get_file()!=road_id: continue
		if not road.crossings: return
		var sample:=_sample_polyline(road.points as PackedVector2Array,t)
		if sample.is_empty(): return
		var points: PackedVector2Array = road.points
		var wanted: Vector2 = sample.position+sample.tangent*float(road.crossing_offset)
		var segment := int(_closest_segment(wanted,points).segment)
		var center := Geometry2D.get_closest_point_to_segment(wanted,points[segment],points[segment+1])
		_append_crossing(center,points[segment].direction_to(points[segment+1]),float(road.width),float(road.crossing_depth) if road.custom_crossing_depth else depth,float(road.sidewalk_width))
		return


func _append_crossing(center: Vector2,direction: Vector2,road_width: float,depth: float,sidewalk_reach: float,junction_crossing: bool = false, stops := true)->void:
	var normal: Vector2=direction.orthogonal()
	_crossing_masks.append(_quad(center,direction,depth+3.0,road_width))
	var stripe_at: float=-road_width*.5+6.0*SOURCE_SCALE
	var stripe_end: float=road_width*.5-6.0*SOURCE_SCALE
	while stripe_at<=stripe_end+.0001:
		_crosswalk_white.append(_quad(center+normal*stripe_at,direction,depth*.86,8.0*SOURCE_SCALE))
		stripe_at+=15.0*SOURCE_SCALE
	for side in [-1.0,1.0]:
		var tactile_offset:=minf(sidewalk_reach*.5,12.0*SOURCE_SCALE)
		var pad_center: Vector2=center+normal*float(side)*(road_width*.5+tactile_offset)
		if sidewalk_reach > .1: _crosswalk_tactile.append(_quad(pad_center,direction,depth,minf(sidewalk_reach,12.0*SOURCE_SCALE)))
		# At a junction only the approaching lane stops, outside the crossing.
		if not stops or (junction_crossing and side < 0): continue
		var stop_center: Vector2=center+direction*float(side)*(depth*.5+16.0*SOURCE_SCALE)
		stop_center += normal*float(side)*road_width*.25
		_crosswalk_stop.append(_quad(stop_center,direction,3.0*SOURCE_SCALE,road_width*.5))


func _sample_polyline(points: PackedVector2Array,t: float)->Dictionary:
	if points.size()<2: return {}
	var total:=0.0
	for index in range(points.size()-1): total+=points[index].distance_to(points[index+1])
	if total<=0.0001: return {}
	var target:=clampf(t,0.0,1.0)*total
	var travelled:=0.0
	for index in range(points.size()-1):
		var length:=points[index].distance_to(points[index+1])
		if target<=travelled+length or index==points.size()-2:
			var local:=clampf((target-travelled)/maxf(length,0.0001),0.0,1.0)
			return {"position":points[index].lerp(points[index+1],local),"tangent":points[index].direction_to(points[index+1])}
		travelled+=length
	return {}


func _crossing_arms(junction: Dictionary) -> Array[Dictionary]:
	var arms: Array[Dictionary] = []
	var center: Vector2=junction.position as Vector2
	var indices: Array = junction.roads.duplicate()
	indices.sort_custom(func(a,b): return _roads[a].id < _roads[b].id)
	for road_index_value in indices:
		var road:=_roads[int(road_index_value)]
		var points:=road.points as PackedVector2Array
		for i in range(points.size()-1):
			if Geometry2D.get_closest_point_to_segment(center,points[i],points[i+1]).distance_to(center) > .08: continue
			for side in [-1,1]:
				var endpoint := points[i] if side < 0 else points[i+1]
				var length := center.distance_to(endpoint)
				if length <= .08: continue
				var direction := center.direction_to(endpoint)
				# Extra control points on a straight road do not shorten its approach.
				var cursor := i if side < 0 else i+1
				while cursor+side >= 0 and cursor+side < points.size():
					var next := points[cursor+side]
					if points[cursor].direction_to(next).dot(direction) < .9999: break
					length += points[cursor].distance_to(next)
					cursor += side
				_merge_crossing_arm(arms,direction,float(road.width),road,side,length)
	return arms


func _merge_crossing_arm(arms: Array[Dictionary],direction: Vector2,width: float,road: Dictionary,side := 1,length := 1000.0)->void:
	for index in arms.size():
		if (arms[index].direction as Vector2).dot(direction)>=.99862953475:
			arms[index].width=maxf(float(arms[index].width),width)
			arms[index].length=minf(float(arms[index].length),length)
			return
	arms.append({"direction":direction.normalized(),"width":width,"road":road,"side":side,"length":length})


func _is_unsignalized(metric_point: Vector2)->bool:
	var source_point: Vector2=metric_point/SOURCE_SCALE
	for point in UNSIGNALIZED_SOURCE_POINTS:
		if source_point.distance_to(point)<1.0: return true
	return false


func _quad(center: Vector2,forward: Vector2,forward_size: float,side_size: float)->PackedVector2Array:
	var f: Vector2=forward.normalized()*forward_size*.5
	var s: Vector2=forward.normalized().orthogonal()*side_size*.5
	return _counter_clockwise(PackedVector2Array([center-f-s,center+f-s,center+f+s,center-f+s]))


func _add_clipped_surface(parent: Node3D,label: String,source: Array[PackedVector2Array],clip: PackedVector2Array,y: float,material: Material)->void:
	var clipped: Array[PackedVector2Array]=[]
	for polygon in source:
		for piece_value in Geometry2D.intersect_polygons(polygon,clip):
			var piece:=piece_value as PackedVector2Array
			if piece.size()>=3: clipped.append(piece)
	_add_surface(parent,label,clipped,y,material)


func _closest_segment(point: Vector2, points: PackedVector2Array) -> Dictionary:
	var result := {"segment": -1, "distance": INF}
	for index in range(points.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])
		var distance := point.distance_to(closest)
		if distance < float(result.distance):
			result = {"segment": index, "distance": distance}
	return result


func _build_markings(parent: Node3D, rect: Rect2) -> void:
	var mark_parent := Node3D.new()
	mark_parent.name = "HarborLaneMarkings"
	var count := 0
	for road in _roads:
		if String(road.id).begins_with("mountain_bridge_"): continue
		var points := road.points as PackedVector2Array
		var travelled := 0.0
		for index in range(points.size() - 1):
			var a := points[index]
			var b := points[index + 1]
			var segment_length := a.distance_to(b)
			if segment_length < MIN_SEGMENT: continue
			var direction := a.direction_to(b)
			var walked := 0.0
			while walked < segment_length - 0.001:
				var phase := fmod(travelled + walked, DASH_LENGTH + DASH_GAP)
				var drawing := phase < DASH_LENGTH
				var remaining := (DASH_LENGTH - phase) if drawing else (DASH_LENGTH + DASH_GAP - phase)
				var step := minf(remaining, segment_length - walked)
				if drawing and step > 0.03:
					var from := a + direction * walked
					var to := a + direction * (walked + step)
					var midpoint := (from + to) * 0.5
					# Half-open chunk ownership: padding duplicated coplanar paint
					# in adjacent chunks while streaming across their border.
					if rect.has_point(midpoint) and not _marking_hits_junction(midpoint) and not _marking_hits_junction(from) and not _marking_hits_junction(to):
						_add_mark(mark_parent, from, to, count)
						count += 1
						if int(road.get("lanes_per_direction",1)) == 2:
							for side in [-1,1]:
								var offset: Vector2 = Vector2(-direction.y,direction.x)*float(road.width)*.25*side
								_add_mark(mark_parent,from+offset,to+offset,count,true)
								count += 1
				walked += maxf(step, 0.03)
			travelled += segment_length
	if count > 0: parent.add_child(mark_parent)
	else: mark_parent.free()


func _marking_hits_junction(point: Vector2) -> bool:
	for mask in _crossing_masks:
		if Geometry2D.is_point_in_polygon(point,mask): return true
	for junction in _junctions:
		var widest := 0.0
		for road_index_value in junction.roads:
			widest = maxf(widest, float(_roads[int(road_index_value)].width))
		if point.distance_to(junction.position) < widest * 0.68 + 14.0 * SOURCE_SCALE:
			return true
	return false


func _add_mark(parent: Node3D, from: Vector2, to: Vector2, index: int, same_direction := false) -> void:
	var delta := to - from
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Dash_%04d" % index
	var paint := PlaneMesh.new()
	paint.size = Vector2(3.0 * SOURCE_SCALE, delta.length())
	mesh_instance.mesh = paint
	# Road paint receives shadows, but has no raised sides to cast a crawling
	# subpixel shadow onto itself/asphalt as the camera moves.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _material(CROSSWALK_COLOR if same_direction else LANE_COLOR)
	mesh_instance.position = Vector3((from.x + to.x) * 0.5, 0.038, (from.y + to.y) * 0.5)
	mesh_instance.rotation.y = atan2(delta.x, delta.y)
	parent.add_child(mesh_instance)


func _add_surface(parent: Node3D, label: String, polygons: Array[PackedVector2Array], y: float, material: Material) -> void:
	var vertices := PackedVector3Array()
	# O asfalto precisa de normais para receber luz solar e sombras dos prédios.
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for polygon in polygons:
		var indices := Geometry2D.triangulate_polygon(polygon)
		for index in indices:
			var point := polygon[index]
			vertices.append(Vector3(point.x, y, point.y))
			normals.append(Vector3.UP)
			uvs.append(point / 4.0)
	if vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	parent.add_child(instance)
	if label.ends_with(ROAD_COLOR.to_html(false)):
		var body := StaticBody3D.new()
		body.name = label + "Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		# Colisão no nível do terreno, não nos 2,6 cm do asfalto visual: a borda de
		# um plano sem espessura acima do chão vira parede para a caixa do carro,
		# e a viatura roubada no pátio da delegacia (ou qualquer carro vindo de
		# terreno fora da rua) parava seca ao encostar na pista.
		var flat := PackedVector3Array()
		for vertex in vertices: flat.append(Vector3(vertex.x, 0.0, vertex.z))
		var shape := CollisionShape3D.new()
		var trimesh := ConcavePolygonShape3D.new()
		trimesh.set_faces(flat)
		shape.shape = trimesh
		body.add_child(shape)
		parent.add_child(body)


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if color == ROAD_COLOR:
		material.albedo_texture = _asphalt_texture()
		material.albedo_color = Color.WHITE
	# A face superior já está voltada para a câmera; renderizar ambos os lados
	# fazia o material tratar parte do piso como verso e inverter sua iluminação.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[key] = material
	return material


func _asphalt_texture() -> Texture2D:
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 2147
	noise.frequency = .085
	for y in 128:
		for x in 128:
			var grain := noise.get_noise_2d(float(x), float(y))
			var aggregate := noise.get_noise_2d(float(x) * 2.7 + 29.0, float(y) * 2.7)
			var wear := clampf(.76 + grain * .13 + aggregate * .065, .56, .94)
			image.set_pixel(x, y, Color(.17 * wear, .22 * wear, .255 * wear))
	return ImageTexture.create_from_image(image)


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)])


func _counter_clockwise(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if result.size() > 1 and result[0].distance_to(result[-1]) <= 0.0001: result.resize(result.size()-1)
	if Geometry2D.is_polygon_clockwise(result): result.reverse()
	return result
