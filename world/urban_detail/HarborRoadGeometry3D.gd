@tool
extends RefCounted
class_name HarborRoadGeometry3D

## Native projection of the productive HarborRoadNetwork surface stack.
## Source authority: geodata/roads/UnifiedRoadNetwork2D.gd. Coordinates and
## widths arrive already converted to metres by NativeRegion.

const SOURCE_SCALE := 1.0 / 16.0
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const UNIFIED_BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
## Desgaste das ruas: macrovariação do asfalto (urban_wear) e umidade dos decalques do atlas.
const ROAD_WEAR := preload("res://world/shared/roads/HarborRoadWear.gd")
const SIDEWALK_MARGIN := 42.0 * SOURCE_SCALE
const DASH_LENGTH := 28.0 * SOURCE_SCALE
const DASH_GAP := 26.0 * SOURCE_SCALE
const MIN_SEGMENT := 2.0 * SOURCE_SCALE
# Conservative broad phase only: exact polygon clipping is unchanged.
const CLIP_BOUNDS_PADDING := 0.001

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
const DASH_WIDTH := 3.0 * SOURCE_SCALE
const DASH_Y := 0.038

## Tracinhos da faixa num MultiMeshInstance3D por cor e por trecho (medido em 2026-10-13: ~64
## MeshInstance3D "Dash" num trecho de 128x64 m do oeste, cada um com draw call própria).
## `GETECO_DASH_BATCH=0` volta a um MeshInstance3D por tracinho.
static var dash_batch_enabled := OS.get_environment("GETECO_DASH_BATCH") != "0"

# Revisão do catálogo usado pelo índice de acabamento dos chunks.
var context_revision := 0
var _roads: Array[Dictionary] = []
var _junctions: Array[Dictionary] = []
var _layers: Array[Dictionary] = []
var _materials: Dictionary = {}
## Contorno externo das ruas (calçada inteira e estradas de terra) do último chunk montado. Os pisos de
## baixo (lotes, concreto do porto, chão base) se recortam contra ele para ficar uma camada só.
var chunk_cover: Array[PackedVector2Array] = []
var _weather_wetness := 0.0
var _roughness_texture: Texture2D
var _coastal_material: ShaderMaterial
var _coastal_reflection_texture: Texture2D
var _coastal_reflection_projection := Projection.IDENTITY
var _coastal_reflection_enabled := false
var _road_end_blend := preload("res://world/urban_detail/RuralRoadEndBlend.gd").new()
var _crosswalk_white: Array[PackedVector2Array] = []
var _crosswalk_tactile: Array[PackedVector2Array] = []
var _crosswalk_stop: Array[PackedVector2Array] = []
var _crossing_masks: Array[PackedVector2Array] = []
var crossing_layout: Array[Dictionary] = []
var _earth_polygons: Array[PackedVector2Array] = []
var _earth_verge_triangles: Array = []
var _earth_bounds: Array[Rect2] = []
var _earth_verge_bounds: Array[Rect2] = []
var _crosswalk_white_bounds: Array[Rect2] = []
var _crosswalk_tactile_bounds: Array[Rect2] = []
var _crosswalk_stop_bounds: Array[Rect2] = []
var _sidewalk_details := preload("res://world/urban_detail/HarborSidewalkDetails.gd").new()
var _traffic_signs := preload("res://world/urban_detail/HarborTrafficSigns.gd").new()


func configure(source_roads: Array[Dictionary], surfaces := true) -> void:
	context_revision += 1
	_roads.clear()
	_mark_bounds.clear()
	_widest_road = 0.0
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
	_road_end_blend.configure(_roads)
	_discover_junctions()
	if not surfaces:
		_prepare_crosswalks()
		_prepare_clipping_bounds()
		_traffic_signs.configure(source_roads, crossing_layout)
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
	_prepare_clipping_bounds()
	_sidewalk_details.configure(source_roads, crossing_layout)
	_traffic_signs.configure(source_roads, crossing_layout)
	# Materiais do desgaste da rua prontos aqui (sob a cortina), não no primeiro trecho montado.
	ROAD_WEAR.prewarm()


func _prepare_clipping_bounds() -> void:
	# Rebuilt after every configure, including surfaces=false and empty data.
	_earth_bounds = _polygon_bounds_list(_earth_polygons)
	_crosswalk_white_bounds = _polygon_bounds_list(_crosswalk_white)
	_crosswalk_tactile_bounds = _polygon_bounds_list(_crosswalk_tactile)
	_crosswalk_stop_bounds = _polygon_bounds_list(_crosswalk_stop)
	_earth_verge_bounds.clear()
	for triangle in _earth_verge_triangles:
		_earth_verge_bounds.append(_polygon_bounds(triangle.points))


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	return bounds


func _polygon_bounds_list(polygons: Array[PackedVector2Array]) -> Array[Rect2]:
	var bounds: Array[Rect2] = []
	for polygon in polygons: bounds.append(_polygon_bounds(polygon))
	return bounds


func build_chunk(parent: Node3D, rect: Rect2) -> void:
	if _layers.is_empty():
		return
	var clip := _rect_polygon(rect)
	var clip_bounds := rect.abs().grow(CLIP_BOUNDS_PADDING)
	var verge: Array = []
	for index in _earth_verge_triangles.size():
		if clip_bounds.intersects(_earth_verge_bounds[index], true):
			verge.append(_earth_verge_triangles[index])
	preload("res://world/urban_detail/RuralRoadVerge.gd").build(parent,verge,clip)
	chunk_cover = _add_clipped_surface(parent,"HarborEarthRoad",_earth_polygons,clip,0.023,preload("res://world/urban_detail/RuralGroundMaterial.gd").material(),_earth_bounds)
	var opening_clips: Array[PackedVector2Array] = []
	for opening in CATALOG.sewer_openings():
		var sewer_opening := Rect2(opening.position * SOURCE_SCALE, opening.size * SOURCE_SCALE)
		if rect.intersects(sewer_opening): opening_clips.append(_rect_polygon(sewer_opening))
	# O corredor novo é dono do piso inteiro, incluindo os antigos tapa-vãos.
	# Recortar a autoria regional evita sobreposição e mantém o grafo das vias.
	if UNIFIED_BRIDGE.enabled() and rect.intersects(UNIFIED_BRIDGE.east_bounds()):
		opening_clips.append(UNIFIED_BRIDGE.east_footprint())
	if UNIFIED_BRIDGE.enabled() and rect.intersects(Rect2(328.75,-374.25,36.55,126.0)):
		opening_clips.append(UNIFIED_BRIDGE.north_footprint())
	var chunk_layers: Array = []
	for layer in _layers:
		var clipped: Array[PackedVector2Array] = []
		for polygon_index in range(layer.polygons.size()):
			if not clip_bounds.intersects(layer.bounds[polygon_index], true): continue
			var polygon: PackedVector2Array = layer.polygons[polygon_index]
			for piece_value in Geometry2D.intersect_polygons(polygon, clip):
				var piece := piece_value as PackedVector2Array
				if piece.size() >= 3:
					if opening_clips.is_empty():
						clipped.append(piece)
					else:
						var remaining: Array[PackedVector2Array] = [piece]
						for opening_clip in opening_clips:
							var next: Array[PackedVector2Array] = []
							for part in remaining: next.append_array(Geometry2D.clip_polygons(part, opening_clip))
							remaining = next
						for outside in remaining:
							if outside.size() >= 3: clipped.append(outside)
		# Junction patches and crossing road corridors share positive area.
		# Dissolve those overlaps inside each layer before cutting its inner ring.
		# This also prevents duplicate faces within a single MeshInstance.
		var owned: Array[PackedVector2Array] = []
		for piece in clipped:
			owned.append_array(preload("res://world/urban_detail/GroundCut.gd").subtract_exact([piece],owned))
		chunk_layers.append(owned)
	# As quatro faixas (calçada, meio-fio, borda, asfalto) são offsets concêntricos da mesma rua. Cheias,
	# o centro da rua era pintado 4 vezes (medido em 2026-10-13: ~150 mil m² de chão repetido no porto).
	# Cada faixa vira um anel sem a área da faixa de dentro; a de dentro (asfalto) e a colisão não mudam.
	if not chunk_layers.is_empty(): chunk_cover.append_array(chunk_layers[0])
	for index in range(chunk_layers.size() - 1):
		chunk_layers[index] = _without_inner(chunk_layers[index], chunk_layers[index + 1])
	for index in chunk_layers.size():
		var layer: Dictionary = _layers[index]
		_add_surface(parent, "HarborRoad_%s" % layer.name, chunk_layers[index], float(layer.y), layer.material)
	_add_clipped_surface(parent,"HarborCrosswalk",_crosswalk_white,clip,0.038,_material(CROSSWALK_COLOR),_crosswalk_white_bounds)
	_add_clipped_surface(parent,"HarborTactile",_crosswalk_tactile,clip,0.039,_material(TACTILE_COLOR),_crosswalk_tactile_bounds)
	_add_clipped_surface(parent,"HarborStopLine",_crosswalk_stop,clip,0.040,_material(STOP_LINE_COLOR),_crosswalk_stop_bounds)
	_build_markings(parent, rect)
	_sidewalk_details.build_chunk(parent, rect)
	_traffic_signs.build_chunk(parent, rect)


## `outer` menos a união de `inner`, já recortados ao chunk (GroundCut cuida do sentido dos polígonos e
## de recortes que abririam buraco).
func _without_inner(outer: Array[PackedVector2Array], inner: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	return preload("res://world/urban_detail/GroundCut.gd").subtract(outer, inner)

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
		"bounds": _polygon_bounds_list(polygons),
		"material": _coastal_asphalt_material() if color == ROAD_COLOR else _material(color),
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


func _add_clipped_surface(parent: Node3D,label: String,source: Array[PackedVector2Array],clip: PackedVector2Array,y: float,material: Material,bounds: Array[Rect2] = [])->Array[PackedVector2Array]:
	var clipped: Array[PackedVector2Array]=[]
	var clip_bounds := _polygon_bounds(clip).grow(CLIP_BOUNDS_PADDING)
	var use_bounds := bounds.size() == source.size()
	for polygon_index in source.size():
		if use_bounds and not clip_bounds.intersects(bounds[polygon_index], true): continue
		var polygon: PackedVector2Array = source[polygon_index]
		for piece_value in Geometry2D.intersect_polygons(polygon,clip):
			var piece:=piece_value as PackedVector2Array
			if piece.size()>=3: clipped.append(piece)
	_add_surface(parent,label,clipped,y,material)
	return clipped


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
	# Cor (html) -> Array[Transform3D]; só usado com o lote ligado.
	var batches := {}
	# CanalTunnel3D.carve_chunk recorta a pintura sobre as rampas abertas, mas só em MeshInstance3D:
	# tracinho que encosta numa rampa continua peça solta para ser recortado. `load` (não preload):
	# o túnel já pré-carrega este script.
	var tunnel_cuts: Array[Rect2] = []
	if dash_batch_enabled:
		for cut in load("res://world/urban_detail/CanalTunnel3D.gd").open_cuts():
			if (cut as Rect2).intersects(rect.grow(1.0)): tunnel_cuts.append(cut)
	# Folga da célula: o tracinho conta pelo ponto do meio, mas início e fim são testados (meio tracinho) e
	# o deslocamento da faixa vai até meia largura da rua mais larga.
	if marking_cull_enabled:
		if _widest_road <= 0.0:
			for road in _roads: _widest_road = maxf(_widest_road, float(road.width))
		_filter_junctions(rect.grow(DASH_LENGTH + _widest_road * 0.5 + 1.0))
	for road_index in _roads.size():
		var road: Dictionary = _roads[road_index]
		if String(road.id).begins_with("mountain_bridge_"): continue
		var styles := _marking_styles(road)
		if styles.is_empty(): continue
		var points := road.points as PackedVector2Array
		# Folga = maior deslocamento lateral das faixas (meia largura) + o tracinho; fora dela nada é emitido.
		var reach := float(road.width) * 0.5 + 1.0
		if marking_cull_enabled and not _road_mark_bounds(road_index, points, reach).intersects(rect): continue
		var travelled := 0.0
		for index in range(points.size() - 1):
			var a := points[index]
			var b := points[index + 1]
			var segment_length := a.distance_to(b)
			if segment_length < MIN_SEGMENT: continue
			# Trecho longe da célula: só soma o comprimento, para a fase do tracejado seguir igual.
			if marking_cull_enabled and not Rect2(a, Vector2.ZERO).expand(b).grow(reach).intersects(rect):
				travelled += segment_length
				continue
			var direction := a.direction_to(b)
			var walked := 0.0
			while walked < segment_length - 0.001:
				var phase := fmod(travelled + walked, DASH_LENGTH + DASH_GAP)
				var drawing := phase < DASH_LENGTH
				var remaining := (DASH_LENGTH - phase) if drawing else (DASH_LENGTH + DASH_GAP - phase)
				var step := minf(remaining, segment_length - walked)
				if step > 0.03:
					var from := a + direction * walked
					var to := a + direction * (walked + step)
					for style in styles:
						if not drawing and not bool(style.solid): continue
						var offset := direction.orthogonal() * float(style.offset)
						count += _emit_mark(mark_parent, batches, rect, tunnel_cuts, from + offset, to + offset, count, bool(style.white))
				walked += maxf(step, 0.03)
			travelled += segment_length
	_cell_filter_active = false
	for color_key in batches: _add_mark_batch(mark_parent, Color(color_key), batches[color_key])
	if count > 0: parent.add_child(mark_parent)
	else: mark_parent.free()


## Pintura por célula (24/10): cada célula andava todos os tracinhos de TODAS as ruas do mapa e só descartava
## no fim (`rect.has_point`), 4,9 ms em média e até 10 ms por célula do porto (oeste, editor; o chão de uma
## célula, stream.harbor.surfaces, custava 13–27 ms no release). Ruas e trechos fora da célula (com a folga do
## deslocamento das faixas) são pulados; o trecho pulado ainda soma ao `travelled`, então a fase e o
## resultado são os mesmos. GETECO_MARKING_CULL=0 volta a andar tudo (A/B).
static var marking_cull_enabled := OS.get_environment("GETECO_MARKING_CULL") != "0"
var _mark_bounds: Dictionary = {}

var _widest_road := 0.0
func _road_mark_bounds(key: int, points: PackedVector2Array, reach: float) -> Rect2:
	if not _mark_bounds.has(key):
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		_mark_bounds[key] = bounds.grow(reach)
	return _mark_bounds[key]


## Brazilian longitudinal paint: yellow separates opposing traffic, white separates
## lanes of one direction. Follow the same inbound/outbound convention as the graph.
## Curbed urban streets have no artificial shoulder line or parking prohibition.
func _marking_styles(road: Dictionary) -> Array[Dictionary]:
	var styles: Array[Dictionary] = []
	var road_id := String(road.id)
	var one_way := road_id.contains("inbound") or road_id.contains("outbound")
	var lanes := int(road.get("lanes_per_direction", 1))
	var width := float(road.width)
	if width < 5.0 and not one_way: return styles
	if one_way:
		if lanes >= 2: styles.append({"offset": 0.0, "white": true, "solid": false})
	elif lanes >= 2:
		# Double continuous centre line on four-lane undivided avenues. The
		# parallel white broken lines retain the adjacent overtaking lanes.
		for side in [-1.0, 1.0]:
			styles.append({"offset": side * 0.20, "white": false, "solid": true})
			styles.append({"offset": side * width * 0.25, "white": true, "solid": false})
	else:
		styles.append({"offset": 0.0, "white": false, "solid": false})
	if width >= 6.5 and float(road.sidewalk_width) <= 0.1:
		for side in [-1.0, 1.0]:
			styles.append({"offset": side * (width * 0.5 - 0.35), "white": true, "solid": true})
	return styles


func _emit_mark(parent: Node3D, batches: Dictionary, rect: Rect2, tunnel_cuts: Array[Rect2], from: Vector2, to: Vector2, index: int, white: bool) -> int:
	var midpoint := (from + to) * 0.5
	# Test the actual offset lane, not only the road centre. Keep half-open
	# chunk ownership and the bridge/tunnel surface owners from the old paint.
	if not rect.has_point(midpoint): return 0
	for point in [from, midpoint, to]:
		if UNIFIED_BRIDGE.owns_surface_point(point) or _marking_hits_junction(point): return 0
	if dash_batch_enabled and not _mark_touches(tunnel_cuts, from, to): _queue_mark(batches, from, to, white)
	else: _add_mark(parent, from, to, index, white)
	return 1


func _marking_hits_junction(point: Vector2) -> bool:
	var masks: Array = _cell_masks if _cell_filter_active else _crossing_masks
	for mask in masks:
		if Geometry2D.is_point_in_polygon(point,mask): return true
	if _cell_filter_active:
		for junction in _cell_junctions:
			if point.distance_to(junction[0]) < junction[1]: return true
		return false
	for junction in _junctions:
		if point.distance_to(junction.position) < _junction_reach(junction): return true
	return false

func _junction_reach(junction: Dictionary) -> float:
	var widest := 0.0
	for road_index_value in junction.roads:
		widest = maxf(widest, float(_roads[int(road_index_value)].width))
	return widest * 0.68 + 14.0 * SOURCE_SCALE

## Só cruzamentos e faixas de pedestre que alcançam `area` (a célula com a folga dos tracinhos): o teste
## por ponto percorria os do mapa inteiro para cada tracinho. Mesma decisão: quem fica fora de `area`
## não pode conter nem estar perto de um ponto dentro dela.
var _cell_filter_active := false
var _cell_masks: Array = []
var _cell_junctions: Array = []
func _filter_junctions(area: Rect2) -> void:
	_cell_masks.clear()
	_cell_junctions.clear()
	for mask in _crossing_masks:
		if _polygon_bounds(mask).intersects(area, true): _cell_masks.append(mask)
	for junction in _junctions:
		var reach := _junction_reach(junction)
		var position: Vector2 = junction.position
		if area.grow(reach).has_point(position): _cell_junctions.append([position, reach])
	_cell_filter_active = true


func _add_mark(parent: Node3D, from: Vector2, to: Vector2, index: int, same_direction := false) -> void:
	var delta := to - from
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Dash_%04d" % index
	var paint := PlaneMesh.new()
	paint.size = Vector2(DASH_WIDTH, delta.length())
	mesh_instance.mesh = paint
	# Road paint receives shadows, but has no raised sides to cast a crawling
	# subpixel shadow onto itself/asphalt as the camera moves.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _material(CROSSWALK_COLOR if same_direction else LANE_COLOR)
	mesh_instance.position = Vector3((from.x + to.x) * 0.5, DASH_Y, (from.y + to.y) * 0.5)
	mesh_instance.rotation.y = atan2(delta.x, delta.y)
	parent.add_child(mesh_instance)


## Caixa do tracinho (com folga da largura) contra os recortes; mesma ideia de CanalTunnel3D._touches.
func _mark_touches(cuts: Array[Rect2], from: Vector2, to: Vector2) -> bool:
	if cuts.is_empty(): return false
	var bounds := Rect2(from, Vector2.ZERO).expand(to).grow(DASH_WIDTH)
	for cut in cuts:
		if bounds.intersects(cut): return true
	return false


## Mesma posição, rumo e comprimento de `_add_mark`: plano de 1 m esticado em Z pelo comprimento.
## A escala só no eixo do comprimento mantém a normal para cima (luz igual à peça solta).
func _queue_mark(batches: Dictionary, from: Vector2, to: Vector2, same_direction := false) -> void:
	var delta := to - from
	var key := (CROSSWALK_COLOR if same_direction else LANE_COLOR).to_html(false)
	if not batches.has(key): batches[key] = []
	var basis := Basis(Vector3.UP, atan2(delta.x, delta.y)) * Basis.from_scale(Vector3(1.0, 1.0, delta.length()))
	batches[key].append(Transform3D(basis, Vector3((from.x + to.x) * 0.5, DASH_Y, (from.y + to.y) * 0.5)))


func _add_mark_batch(parent: Node3D, color: Color, transforms: Array) -> void:
	var paint := PlaneMesh.new()
	paint.size = Vector2(DASH_WIDTH, 1.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = paint
	multimesh.instance_count = transforms.size()
	for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "DashBatch_%s" % color.to_html(false)
	instance.multimesh = multimesh
	# Mesma regra da peça solta: tinta recebe sombra, mas não projeta.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = _material(color)
	parent.add_child(instance)


## Transformações globais e cor de todos os tracinhos sob `root`, nos dois modos (soltos ou em lote).
## Para testes e contagens: [{"transform": Transform3D, "color": String, "cast_shadow": int}].
static func dash_marks(root: Node) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	for mark in root.find_children("Dash_*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mark as MeshInstance3D).mesh
		var xform: Transform3D = mark.global_transform if mark.is_inside_tree() else _local_to(root, mark)
		# Recortado pelo túnel vira ArrayMesh: o comprimento passa a ser o que sobrou da caixa.
		var length := (mesh as PlaneMesh).size.y if mesh is PlaneMesh else (mesh.get_aabb().size.z if mesh != null else 0.0)
		xform.basis = xform.basis * Basis.from_scale(Vector3(1.0, 1.0, length))
		marks.append({"transform": xform, "color": mark.material_override.albedo_color.to_html(false), "cast_shadow": mark.cast_shadow})
	for batch in root.find_children("DashBatch_*", "MultiMeshInstance3D", true, false):
		var multimesh: MultiMesh = batch.multimesh
		var base: Transform3D = batch.global_transform if batch.is_inside_tree() else _local_to(root, batch)
		for index in multimesh.instance_count:
			marks.append({"transform": base * multimesh.get_instance_transform(index), "color": batch.material_override.albedo_color.to_html(false), "cast_shadow": batch.cast_shadow})
	return marks


static func _local_to(root: Node, node: Node3D) -> Transform3D:
	var xform := node.transform
	var walk := node.get_parent()
	while walk != null and walk != root:
		if walk is Node3D: xform = (walk as Node3D).transform * xform
		walk = walk.get_parent()
	if root is Node3D: xform = (root as Node3D).transform * xform
	return xform


func _add_surface(parent: Node3D, label: String, polygons: Array[PackedVector2Array], y: float, material: Material) -> void:
	if (material is StandardMaterial3D or material == _coastal_material) and (label.ends_with(ROAD_COLOR.to_html(false)) or label.ends_with(ROAD_EDGE_COLOR.to_html(false)) or label.ends_with(SIDEWALK_COLOR.to_html(false)) or label.ends_with(CURB_COLOR.to_html(false))):
		for polygon in polygons:
			if _road_end_blend.affects(_polygon_bounds(polygon)):
				material=_road_end_blend.material(material)
				break
	var vertices := PackedVector3Array()
	# O asfalto precisa de normais para receber luz solar e sombras dos prédios.
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var mesh_indices := PackedInt32Array()
	for polygon in polygons:
		var indices := Geometry2D.triangulate_polygon(polygon)
		if indices.is_empty():
			continue
		var vertex_offset := vertices.size()
		for point in polygon:
			vertices.append(Vector3(point.x, y, point.y))
			normals.append(Vector3.UP)
			uvs.append(point / 4.0)
		for index in indices:
			mesh_indices.append(vertex_offset + index)
	if vertices.is_empty(): return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = mesh_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	# Flat paving receives shadows but must not cast onto the neighbouring
	# coplanar paving layers: their centimetre offsets produce moving shadow tiles.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		for index in mesh_indices:
			var vertex := vertices[index]
			flat.append(Vector3(vertex.x, 0.0, vertex.z))
		var shape := CollisionShape3D.new()
		var trimesh := ConcavePolygonShape3D.new()
		trimesh.set_faces(flat)
		shape.shape = trimesh
		body.add_child(shape)
		parent.add_child(body)


func _material(color: Color) -> StandardMaterial3D:
	if color == SIDEWALK_COLOR:
		return preload("res://world/urban_detail/HarborPaving.gd").material()
	var key := color.to_html()
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if color == ROAD_COLOR:
		material.albedo_texture = _asphalt_texture()
		material.roughness_texture = _weather_roughness_texture()
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_apply_wetness(material)
	# A face superior já está voltada para a câmera; renderizar ambos os lados
	# fazia o material tratar parte do piso como verso e inverter sua iluminação.
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_materials[key] = material
	return material


func set_weather_wetness(value: float) -> void:
	value = clampf(value,0.0,1.0)
	if absf(value-_weather_wetness)<.002: return
	_weather_wetness = value
	ROAD_WEAR.set_wetness(value)
	var key := ROAD_COLOR.to_html()
	if _materials.has(key): _apply_wetness(_materials[key])
	if _coastal_material != null:
		_coastal_material.set_shader_parameter("wetness",value)
		_road_end_blend.sync_material(_coastal_material)

func _coastal_asphalt_material() -> ShaderMaterial:
	if _coastal_material != null: return _coastal_material
	if UNIFIED_BRIDGE.enabled():
		_coastal_material = preload("res://world/regions/unified_bridge/UnifiedRoadAsphalt.gd").material()
		_coastal_material.set_shader_parameter("wetness",_weather_wetness)
		_coastal_material.set_shader_parameter("urban_wear",ROAD_WEAR.asphalt_amount())
		_apply_coastal_reflection()
		return _coastal_material
	# Keep _material's StandardMaterial3D contract for bridges/tunnels and
	# external consumers; the streamed Harbor road shares this planar receiver.
	var base := _material(ROAD_COLOR)
	_coastal_material = ShaderMaterial.new()
	_coastal_material.shader = preload("res://world/urban_detail/coastal_wet_asphalt.gdshader")
	_coastal_material.set_shader_parameter("base_texture",base.albedo_texture)
	_coastal_material.set_shader_parameter("roughness_texture",base.roughness_texture)
	_coastal_material.set_shader_parameter("wetness",_weather_wetness)
	_coastal_material.set_shader_parameter("urban_wear",ROAD_WEAR.asphalt_amount())
	_apply_coastal_reflection()
	return _coastal_material

func set_coastal_reflection(texture: Texture2D, projection: Projection, enabled: bool) -> void:
	_coastal_reflection_texture = texture
	_coastal_reflection_projection = projection
	_coastal_reflection_enabled = enabled and texture != null
	_apply_coastal_reflection()

func _apply_coastal_reflection() -> void:
	if _coastal_material == null: return
	_coastal_material.set_shader_parameter("reflection_texture",_coastal_reflection_texture)
	_coastal_material.set_shader_parameter("reflection_projection",_coastal_reflection_projection)
	_coastal_material.set_shader_parameter("reflection_enabled",_coastal_reflection_enabled)
	if _coastal_reflection_texture != null:
		var size := _coastal_reflection_texture.get_size()
		_coastal_material.set_shader_parameter("reflection_texel_size",Vector2(1.0/maxf(size.x,1.0),1.0/maxf(size.y,1.0)))
	_road_end_blend.sync_material(_coastal_material)

func _apply_wetness(material: StandardMaterial3D) -> void:
	material.albedo_color = Color.WHITE.darkened(_weather_wetness*.32)
	# Keep rain-darkened aggregate predominant. Large roughness differences
	# turned filtered sky reflections into bright contour lines across the road.
	# A narrow, soft response leaves stronger reflections to lights and puddles.
	# Dry aggregate has no wet film, preserving the approved matte dry look.
	material.roughness = lerpf(1.0,.56,_weather_wetness)
	material.metallic_specular = smoothstep(.08,1.0,_weather_wetness)*.22
	_road_end_blend.sync_material(material)

func _weather_roughness_texture() -> Texture2D:
	if _roughness_texture != null: return _roughness_texture
	var image := Image.create_empty(128,128,false,Image.FORMAT_L8)
	var noise := FastNoiseLite.new()
	noise.seed = 13102026
	noise.frequency = 1.0
	for y in 128:
		for x in 128:
			# Periodic coordinates keep the four-metre UV tile continuous at
			# road and chunk edges. The tiny range avoids drawing a noise pattern
			# with the sky reflection: wet roughness stays between .532 and .56.
			var a := TAU*float(x)/128.0
			var b := TAU*float(y)/128.0
			var periodic := Vector3((2.0+cos(b))*cos(a),(2.0+cos(b))*sin(a),sin(b))
			var basin := noise.get_noise_3dv(periodic*.72)
			var edge := noise.get_noise_3dv(periodic*2.1+Vector3(17,3,11))
			var value := lerpf(.95,1.0,smoothstep(-.40,.40,basin+edge*.08))
			image.set_pixel(x,y,Color(value,value,value))
	image.generate_mipmaps()
	_roughness_texture = ImageTexture.create_from_image(image)
	return _roughness_texture

func _asphalt_texture() -> Texture2D:
	var image := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 2147
	noise.frequency = 1.0
	for y in 128:
		for x in 128:
			var a := TAU*float(x)/128.0
			var b := TAU*float(y)/128.0
			var periodic := Vector3((2.0+cos(b))*cos(a),(2.0+cos(b))*sin(a),sin(b))
			var grain := noise.get_noise_3dv(periodic*9.0)
			var aggregate := noise.get_noise_3dv(periodic*23.0+Vector3(29,0,11))
			var wear := clampf(.80+grain*.085+aggregate*.045,.65,.94)
			# Neutral charcoal lets warm sunlight and cool sky supply the hue.
			image.set_pixel(x,y,Color(.19*wear,.205*wear,.22*wear))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x,rect.position.y), rect.end, Vector2(rect.position.x,rect.end.y)])


func _counter_clockwise(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if result.size() > 1 and result[0].distance_to(result[-1]) <= 0.0001: result.resize(result.size()-1)
	if Geometry2D.is_polygon_clockwise(result): result.reverse()
	return result
# O recorte transfere apenas a superfície à ponte; as vias continuam no grafo.
