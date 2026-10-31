@tool
extends RefCounted
## Detalhes de calçamento rentes, em streaming. As coordenadas fonte já estão em metros.
## Sem colisão, luzes, callbacks por quadro ou mudanças em rotas de pedestres/trânsito.

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const CELL := 64.0
const DEFAULT_SIDEWALK := 2.625
const CURB_HALF := 0.3125
const COLORS := [Color("747872"), Color("555c5b"), Color("30393b")]

var _features: Array[Dictionary] = []
var _cells: Dictionary = {}
var _masks: Array[Dictionary] = []
var _road_masks: Array[Dictionary] = []
var _materials: Array[StandardMaterial3D] = []


func configure(roads: Array[Dictionary], crossing_layout: Array[Dictionary]) -> void:
	_features.clear()
	_cells.clear()
	_masks.clear()
	_road_masks.clear()
	for opening in CATALOG.sewer_openings():
		_mask(_rect_polygon(Rect2(opening.position / 16.0, opening.size / 16.0)))
	# O carregamento adiado evita a dependência túnel -> geometria de estrada na hora do parse.
	for cut in load("res://world/urban_detail/CanalTunnel3D.gd").open_cuts():
		_mask(_rect_polygon((cut as Rect2).grow(0.25)))
	if BRIDGE.enabled():
		_mask(BRIDGE.east_footprint())
		_mask(BRIDGE.north_footprint())
	for junction in crossing_layout:
		var junction_radius := 2.0
		for entry in junction.get("entries", []):
			junction_radius = maxf(junction_radius, float(entry.width) * 0.68 + 1.5)
		if junction.has("position"):
			_mask(_rect_polygon(Rect2(junction.position - Vector2.ONE * junction_radius, Vector2.ONE * junction_radius * 2.0)))
		for entry in junction.get("entries", []):
			if not bool(entry.get("enabled", false)): continue
			_mask(_quad(entry.position, entry.direction, float(entry.depth) + 1.2,
				float(entry.width) + 2.0 * float(entry.sidewalk) + 0.5))
	# Toda área de estrada é uma exclusão, incluindo acessos de terra/serviço.
	# Assim a decoração não continua atravessando um cruzamento em T ou outra pista.
	for road_index in roads.size():
		var road: Dictionary = roads[road_index]
		var points := _flat_points(road)
		if points.size() < 2: continue
		_mask_authored_crossing(road, points)
		for polygon in Geometry2D.offset_polyline(points, float(road.get("width", 7.5)) * 0.5 + 0.42,
				Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
			_road_masks.append({"polygon": polygon, "bounds": _bounds(polygon), "road": road_index})
	for road_index in roads.size():
		var road: Dictionary = roads[road_index]
		var id := str(road.get("id", ""))
		if str(road.get("surface", "asphalt")) != "asphalt": continue
		if "bridge" in id or "tunnel" in id: continue
		var sidewalk := float(road.get("sidewalk_width", DEFAULT_SIDEWALK))
		if sidewalk < 0.95: continue
		var points := _flat_points(road)
		var half := float(road.get("width", 7.5)) * 0.5
		var travelled := 0.0
		for segment in range(points.size() - 1):
			var start := points[segment]
			var length := start.distance_to(points[segment + 1])
			if length < 0.1: continue
			var direction := start.direction_to(points[segment + 1])
			var normal := direction.orthogonal()
			# Set back from bends/end caps. Existing textured paving covers corners.
			var end_margin := minf(maxf(2.0, sidewalk + half * 0.2), length * 0.45)
			var step := ceilf((travelled + end_margin) / 2.4) * 2.4 - travelled
			while step < length - end_margin:
				for side in [-1.0, 1.0]:
					var span := sidewalk - CURB_HALF - 0.16
					var center: Vector2 = start + direction * step + normal * float(side) * (half + CURB_HALF + 0.08 + span * 0.5)
					_queue(_quad(center, direction, 0.035, span), 0, 0.012, road_index)
					var curb: Vector2 = start + direction * step + normal * float(side) * (half + 0.19)
					_queue(_quad(curb, direction, 0.028, 0.22), 0, 0.018, road_index)
				step += 2.4
			# Tampas de acesso a serviços são raras; sem texto decorativo nem borda elevada.
			step = ceilf((travelled + end_margin + 1.0) / 23.0) * 23.0 - travelled
			while step < length - end_margin - 1.0:
				for side in [-1.0, 1.0]:
					var center: Vector2 = start + direction * step + normal * float(side) * (half + minf(sidewalk - 0.45, 1.2))
					var cover := _quad(center, direction, 0.62, 0.5)
					if _allowed(cover, road_index):
						_store(cover, 1, 0.0125)
						_store(_quad(center, direction, 0.52, 0.4), 0, 0.014)
						for offset in [-0.18, 0.18]:
							_store(_quad(center + direction * offset, direction, 0.025, 0.09), 2, 0.0155)
				step += 23.0
			# Bocas de lobo ficam rentes na faixa do meio-fio, longe da faixa de caminhada.
			step = ceilf((travelled + end_margin + 1.0) / 18.0) * 18.0 - travelled
			while step < length - end_margin - 1.0:
				for side in [-1.0, 1.0]:
					var center: Vector2 = start + direction * step + normal * float(side) * (half + 0.19)
					var drain := _quad(center, direction, 0.72, 0.23)
					if _allowed(drain, road_index):
						_store(drain, 1, 0.018)
						for slot in 6:
							_store(_quad(center + direction * (-0.275 + float(slot) * 0.11), direction, 0.045, 0.15), 2, 0.02)
				step += 18.0
			travelled += length


func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var selected: Dictionary = {}
	for cell in _cell_keys(rect):
		for feature_index in _cells.get(cell, []): selected[feature_index] = true
	if selected.is_empty(): return
	var vertices := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var normals := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var clip := _rect_polygon(rect)
	for feature_index in selected:
		var feature: Dictionary = _features[feature_index]
		if not rect.intersects(feature.bounds, true): continue
		for polygon in Geometry2D.intersect_polygons(feature.polygon, clip):
			var triangles := Geometry2D.triangulate_polygon(polygon)
			for index in triangles:
				var point: Vector2 = polygon[index]
				vertices[feature.material].append(Vector3(point.x, feature.y, point.y))
				normals[feature.material].append(Vector3.UP)
	var mesh := ArrayMesh.new()
	_prepare_materials()
	for group in 3:
		if vertices[group].is_empty(): continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices[group]
		arrays[Mesh.ARRAY_NORMAL] = normals[group]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[group])
	if mesh.get_surface_count() == 0: return
	var instance := MeshInstance3D.new()
	instance.name = "HarborSidewalkDetails"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _flat_points(road: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in road.get("points", PackedVector3Array()):
		if point is Vector3: result.append(Vector2(point.x, point.z))
		elif point is Vector2: result.append(point)
	return result


func _mask_authored_crossing(road: Dictionary, points: PackedVector2Array) -> void:
	# As duas travessias da Ashbend são autoradas fora do WorldCrossingLayout.
	var id := str(road.get("id", "")).get_file()
	if id not in ["cobra_approach", "cobra_court_northwest"] or not bool(road.get("crossings", true)): return
	var total := 0.0
	for i in range(points.size() - 1): total += points[i].distance_to(points[i + 1])
	var target := total * (0.78 if id == "cobra_approach" else 0.90)
	for i in range(points.size() - 1):
		var length := points[i].distance_to(points[i + 1])
		if length < 0.001: continue
		if target <= length:
			var direction := points[i].direction_to(points[i + 1])
			var center := points[i] + direction * clampf(target + float(road.get("crossing_offset", 0.0)), 0.0, length)
			_mask(_quad(center, direction, float(road.get("crossing_depth", 1.625)) + 1.2,
				float(road.get("width", 7.5)) + float(road.get("sidewalk_width", DEFAULT_SIDEWALK)) * 2.0 + 0.5))
			return
		target -= length


func _mask(polygon: PackedVector2Array) -> void:
	_masks.append({"polygon": polygon, "bounds": _bounds(polygon)})


func _allowed(polygon: PackedVector2Array, road_index: int) -> bool:
	var bounds := _bounds(polygon)
	for mask in _masks:
		if bounds.intersects(mask.bounds, true) and not Geometry2D.intersect_polygons(polygon, mask.polygon).is_empty(): return false
	for mask in _road_masks:
		if int(mask.road) == road_index: continue
		if bounds.intersects(mask.bounds, true) and not Geometry2D.intersect_polygons(polygon, mask.polygon).is_empty(): return false
	return true


func _queue(polygon: PackedVector2Array, material: int, y: float, road_index: int) -> void:
	if _allowed(polygon, road_index): _store(polygon, material, y)


func _store(polygon: PackedVector2Array, material: int, y: float) -> void:
	var bounds := _bounds(polygon)
	var index := _features.size()
	_features.append({"polygon": polygon, "bounds": bounds, "material": material, "y": y})
	for cell in _cell_keys(bounds):
		if not _cells.has(cell): _cells[cell] = []
		_cells[cell].append(index)


func _cell_keys(rect: Rect2) -> Array[Vector2i]:
	var keys: Array[Vector2i] = []
	for x in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
		for z in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
			keys.append(Vector2i(x, z))
	return keys


func _prepare_materials() -> void:
	if not _materials.is_empty(): return
	for color in COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		material.metallic_specular = 0.12
		_materials.append(material)


func _quad(center: Vector2, direction: Vector2, length: float, width: float) -> PackedVector2Array:
	var forward := direction * length * 0.5
	var side := direction.orthogonal() * width * 0.5
	var polygon := PackedVector2Array([center - forward - side, center + forward - side, center + forward + side, center - forward + side])
	if Geometry2D.is_polygon_clockwise(polygon): polygon.reverse()
	return polygon


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


func _bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty(): return Rect2()
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: result = result.expand(point)
	return result
