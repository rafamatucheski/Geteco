extends RefCounted
const COLLISION_FACES := preload("res://world/chunk_bake/CollisionFaces.gd")

## Secret-lake surfaces only. NativeLake retains its original wet/dry domains.
## Geometry and static noise belong to the streamed lake; no frame loop or lights.
const SHADER := preload("res://world/regions/cargo_lake_surface.gdshader")
const WATER_Y := 0.042
const CAMP_Y := 0.08
const ISLAND_Y := 0.085
const LEVELS := [0.0, 0.25, 0.55, 0.80, 1.0]
var lake: Node3D
var terrain: RefCounted
var camp := PackedVector2Array()
var island := PackedVector2Array()
var shore := PackedVector2Array()
var _materials: Dictionary = {}
var _height_cache: Dictionary = {}
var _weight_cache: Dictionary = {}
var _color_cache: Dictionary = {}
var _wet_cache: Dictionary = {}
var _trail_mask: Texture2D
var _shore_triangles: Array[PackedVector3Array] = []

func build(owner_lake: Node3D, data: Dictionary) -> void:
	lake = owner_lake
	var region := lake.get_parent()
	while region != null and not (&"terrain" in region):
		region = region.get_parent()
	if region != null:
		terrain = region.get("terrain")
	if terrain != null:
		var bounds := Rect2(_shader_origin(), Vector2.ONE * 64.0)
		_trail_mask = ImageTexture.create_from_image(terrain._trail_blend.image_for(bounds))
	else:
		var empty_mask := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		empty_mask.fill(Color.BLACK)
		_trail_mask = ImageTexture.create_from_image(empty_mask)
	camp = lake._points(data.camp_ground, Vector2(180, 180))
	island = lake._points(data.is_rock, Vector2(245, -65))
	shore = lake._smooth(lake._clear_roads(lake._points(data.shore)))
	_polygon_mesh("GlacialShallows", lake.water_polygon, WATER_Y, 0, 2.0, false)
	_shore_mesh()
	_polygon_mesh("SmugglerCampsite", camp, CAMP_Y, 2, 1.0, true)
	_polygon_mesh("CacheIsland", island, ISLAND_Y, 3, 0.75, true)
	_thin_ice()
	_polygon_mesh("FrozenCascade", lake._points(data.frozen_fall), 0.09, 4, 0.6, false)
	_height_cache.clear()
	_weight_cache.clear()
	_color_cache.clear()
	_wet_cache.clear()

func _shader_origin() -> Vector2:
	return Vector2(floorf(lake.global_position.x / 64.0), floorf(lake.global_position.z / 64.0)) * 64.0

func _terrain_height(point: Vector2) -> float:
	if terrain == null:
		return 0.0
	var world := lake.to_global(Vector3(point.x, 0, point.y))
	return float(terrain.surface_height_at(Vector2(world.x, world.z))) - lake.global_position.y

## Local XZ; camp and island keep their complete authored footprints level.
## Margin interpolation uses the actual visible/colliding triangles, rather than
## an approximate height formula that could leave a rock floating over an edge.
func dry_height_at(point: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(point, camp):
		return CAMP_Y
	if Geometry2D.is_point_in_polygon(point, island):
		return ISLAND_Y
	for triangle in _shore_triangles:
		var a := Vector2(triangle[0].x, triangle[0].z)
		var ab := Vector2(triangle[1].x, triangle[1].z) - a
		var ac := Vector2(triangle[2].x, triangle[2].z) - a
		var determinant := ab.cross(ac)
		if absf(determinant) < 0.000001:
			continue
		var offset := point - a
		var u := offset.cross(ac) / determinant
		var v := ab.cross(offset) / determinant
		if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001:
			return triangle[0].y + (triangle[1].y - triangle[0].y) * u + (triangle[2].y - triangle[0].y) * v
	return _terrain_height(point)

func _edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return 0.0
	var nearest := INF
	for index in polygon.size():
		nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])))
	return nearest

func _closest_on(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	var closest := point
	var distance := INF
	for index in polygon.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
		var next_distance := candidate.distance_squared_to(point)
		if next_distance < distance:
			closest = candidate
			distance = next_distance
	return closest

func _shore_weight(point: Vector2) -> float:
	var inside := _edge_distance(point, lake.water_polygon)
	var outside := _edge_distance(point, shore)
	return inside / maxf(inside + outside, 0.001)

func _shore_height(point: Vector2) -> float:
	if _height_cache.has(point):
		return _height_cache[point]
	var weight := _shore_weight(point)
	var drift := 0.07 + 0.035 * sin(point.x * 0.37 + point.y * 0.15)
	# The ramp approach and both sides of the original camp route stay low.
	var ramp := smoothstep(2.8, 5.2, absf(point.x)) if point.y > 8.0 else 1.0
	var result := lerpf(WATER_Y + 0.004, _terrain_height(point) + 0.004, weight)
	result += sin(PI * weight) * drift * ramp
	_height_cache[point] = result
	return result

func _ground_color(point: Vector2, height: float) -> Color:
	var key := Vector3(point.x, height, point.y)
	if _color_cache.has(key):
		return _color_cache[key]
	var world := lake.to_global(Vector3(point.x, height, point.y))
	var original_y := world.z * 16.0 + 4960.0
	var snow := 1.0 - smoothstep(-1500.0, -1200.0, original_y)
	var earth := Color("52634a").lerp(Color("72766b"), clampf(height / 7.5, 0.0, 1.0))
	var color := earth.lerp(Color("d2d9d9"), snow)
	_color_cache[key] = color
	return color

func _weight(point: Vector2, kind: int) -> float:
	var key := Vector3(point.x, float(kind), point.y)
	if _weight_cache.has(key):
		return _weight_cache[key]
	var weight := 1.0
	match kind:
		0: weight = clampf(_edge_distance(point, lake.water_polygon) / 2.8, 0.0, 1.0)
		1: weight = _shore_weight(point)
		2: weight = clampf(_edge_distance(point, camp) / 1.0, 0.0, 1.0)
		3: weight = clampf(_edge_distance(point, island) / 0.65, 0.0, 1.0)
	_weight_cache[key] = weight
	return weight

func _vertex(surface: SurfaceTool, point: Vector3, kind: int) -> void:
	var flat := Vector2(point.x, point.z)
	surface.set_color(_ground_color(flat, point.y))
	surface.set_uv(flat)
	if not _wet_cache.has(flat):
		var distance := _edge_distance(flat, lake.water_polygon)
		_wet_cache[flat] = distance if Geometry2D.is_point_in_polygon(flat, lake.water_polygon) else -distance
	surface.set_uv2(Vector2(_weight(flat, kind), float(_wet_cache[flat])))
	surface.add_vertex(point)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, kind: int) -> void:
	if (c - a).cross(b - a).y < 0.0:
		var temporary := b
		b = c
		c = temporary
	for point in [a, b, c]:
		_vertex(surface, point, kind)
	if kind == 1:
		_shore_triangles.append(PackedVector3Array([a, b, c]))

func _polygon_mesh(id: String, polygon: PackedVector2Array, height: float, kind: int, step: float, solid: bool) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index in range(0, indices.size(), 3):
		var a := polygon[indices[index]]
		var b := polygon[indices[index + 1]]
		var c := polygon[indices[index + 2]]
		var divisions := maxi(1, ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / step))
		for row in divisions:
			for column in divisions - row:
				var p := a + (b - a) * (float(row) / divisions) + (c - a) * (float(column) / divisions)
				var q := a + (b - a) * (float(row + 1) / divisions) + (c - a) * (float(column) / divisions)
				var r := a + (b - a) * (float(row) / divisions) + (c - a) * (float(column + 1) / divisions)
				_triangle(surface, Vector3(p.x, height, p.y), Vector3(q.x, height, q.y), Vector3(r.x, height, r.y), kind)
				if row + column < divisions - 1:
					p = q
					q = a + (b - a) * (float(row + 1) / divisions) + (c - a) * (float(column + 1) / divisions)
					_triangle(surface, Vector3(p.x, height, p.y), Vector3(q.x, height, q.y), Vector3(r.x, height, r.y), kind)
	_finish_mesh(id, surface, kind, solid)

func _shore_mesh() -> void:
	if shore.size() < 3 or lake.water_polygon.size() < 3:
		return
	var water: PackedVector2Array = lake.water_polygon
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in water.size():
		var first := water[index]
		var second := water[(index + 1) % water.size()]
		var outer_first := _closest_on(first, shore)
		var outer_second := _closest_on(second, shore)
		for level in LEVELS.size() - 1:
			var quad := PackedVector2Array([first.lerp(outer_first, LEVELS[level]), second.lerp(outer_second, LEVELS[level]), second.lerp(outer_second, LEVELS[level + 1]), first.lerp(outer_first, LEVELS[level + 1])])
			var pieces: Array[PackedVector2Array] = [quad]
			# Exact dry footprints and authored road clearance remain unobstructed.
			var exclusions: Array[PackedVector2Array] = [camp, island]
			exclusions.append_array(lake._road_buffers)
			for exclusion in exclusions:
				var clipped: Array[PackedVector2Array] = []
				for piece in pieces:
					clipped.append_array(Geometry2D.clip_polygons(piece, exclusion))
				pieces = clipped
			for piece in pieces:
				var indices := Geometry2D.triangulate_polygon(piece)
				for triangle in range(0, indices.size(), 3):
					var a := piece[indices[triangle]]
					var b := piece[indices[triangle + 1]]
					var c := piece[indices[triangle + 2]]
					_triangle(surface, Vector3(a.x, _shore_height(a), a.y), Vector3(b.x, _shore_height(b), b.y), Vector3(c.x, _shore_height(c), c.y), 1)
	_finish_mesh("GlacialShore", surface, 1, true)

func _material(kind: int) -> ShaderMaterial:
	if not _materials.has(kind):
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("surface_kind", float(kind))
		material.set_shader_parameter("world_origin", Vector2(lake.global_position.x, lake.global_position.z))
		material.set_shader_parameter("trail_mask", _trail_mask)
		preload("res://world/regions/WorldConnection3D.gd").configure_ground_material(material)
		_materials[kind] = material
	return _materials[kind]

func _finish_mesh(id: String, surface: SurfaceTool, kind: int, solid: bool) -> MeshInstance3D:
	surface.generate_normals()
	surface.index()
	# Malha e colisão das mesmas arrays da CPU: create_trimesh_shape lia a malha de volta da GPU (auditoria 19/10).
	var built: Array = COLLISION_FACES.commit_with_shape(surface)
	var mesh: ArrayMesh = built[0]
	var part := MeshInstance3D.new()
	part.name = id
	part.mesh = mesh
	part.material_override = _material(kind)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lake.add_child(part)
	part.set_instance_shader_parameter("origin", _shader_origin())
	if solid:
		var body := StaticBody3D.new()
		body.name = "SurfaceSupport"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("cargo_lake_surface", id)
		var collision := CollisionShape3D.new()
		collision.shape = built[1]
		body.add_child(collision)
		part.add_child(body)
	return part

func _thin_ice() -> void:
	var positions: Array[Vector2] = [Vector2(-135, -75), Vector2(95, -60), Vector2(-95, 65), Vector2(45, 80), Vector2(-54, -177), Vector2(-31, -168), Vector2(-66, -158)]
	var scales := [0.85, 0.6, 1.0, 0.55, 0.8, 0.5, 0.4]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in positions.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7823 + index * 193
		var polygon := PackedVector2Array()
		for corner in 11:
			var angle := TAU * corner / 11.0
			var radius := rng.randf_range(0.76, 1.12)
			var point := Vector2(cos(angle) * 22, sin(angle) * 13) * radius
			polygon.append((point.rotated(index * 1.17) * float(scales[index]) + positions[index]) / 16.0)
		var centre := positions[index] / 16.0
		for corner in polygon.size():
			var a := polygon[corner]
			var b := polygon[(corner + 1) % polygon.size()]
			var inner_a := a.lerp(centre, 0.12)
			var inner_b := b.lerp(centre, 0.12)
			_triangle(surface, Vector3(centre.x, 0.082, centre.y), Vector3(inner_a.x, 0.082, inner_a.y), Vector3(inner_b.x, 0.082, inner_b.y), 4)
			_triangle(surface, Vector3(inner_a.x, 0.082, inner_a.y), Vector3(a.x, 0.048, a.y), Vector3(b.x, 0.048, b.y), 4)
			_triangle(surface, Vector3(inner_a.x, 0.082, inner_a.y), Vector3(b.x, 0.048, b.y), Vector3(inner_b.x, 0.082, inner_b.y), 4)
	_finish_mesh("FracturedIce", surface, 4, false)
