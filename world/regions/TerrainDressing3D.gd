extends RefCounted
## Supplemental 3D forest floor. Coordinates and sampling use world metres (X/Z).
## Caller owns geographic exclusions and parents the result to its streamed chunk.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const CELL := 64.0
const MAX_GRASS := 144
const MAX_PEBBLES := 36
const MAX_ROCKS := 8
static var _grass: ArrayMesh
static var _rock: SphereMesh
static var _materials: Dictionary = {}

static func build_chunk(rect: Rect2, region_id: String, height_at: Callable, is_reserved: Callable) -> Node3D:
	var root := Node3D.new()
	root.name = "TerrainDressing3D"
	# A missing reservation provider must never put solids across authored gameplay.
	if region_id != "mountain" or not height_at.is_valid() or not is_reserved.is_valid() or not rect.has_area():
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = 73013 + floori(rect.position.x / CELL) * 73856093 + floori(rect.position.y / CELL) * 19349663
	var area_ratio := clampf(rect.get_area() / (CELL * CELL), 0.0, 1.0)
	var grass: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var snow_stones: Array[Transform3D] = []
	var large: Array[Transform3D] = []
	var snow_large: Array[Transform3D] = []
	for i in ceili(MAX_GRASS * area_ratio):
		var point := _point(rect, rng)
		if _snow(point) or bool(is_reserved.call(point, 0.65)): continue
		var y := float(height_at.call(point))
		if not is_finite(y) or not _gentle(point, y, height_at, 0.5, 0.35): continue
		var size := rng.randf_range(0.65, 1.3)
		grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size)), Vector3(point.x, y - 0.03, point.y)))
	for i in ceili((MAX_PEBBLES + MAX_ROCKS) * area_ratio):
		var solid := i < ceili(MAX_ROCKS * area_ratio)
		var point := _point(rect, rng)
		var radius := rng.randf_range(0.55, 0.95) if solid else rng.randf_range(0.08, 0.19)
		# Keep full footprint inside this chunk and outside entrances, roads and water.
		if not rect.grow(-radius).has_point(point) or bool(is_reserved.call(point, radius + 0.6)): continue
		var y := float(height_at.call(point))
		if not is_finite(y) or not _gentle(point, y, height_at, radius, 0.25): continue
		var height := radius * rng.randf_range(0.55, 1.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius, height, radius * 0.8))
		var transform := Transform3D(basis, Vector3(point.x, y + height * 0.65, point.y))
		if solid:
			if _snow(point): snow_large.append(transform)
			else: large.append(transform)
			_solid(root, transform)
		else:
			if _snow(point): snow_stones.append(transform)
			else: stones.append(transform)
	_batch(root, "Grass", _grass_mesh(), grass, Color("586643"), false)
	_batch(root, "Pebbles", _rock_mesh(), stones, Color("726e5b"), false)
	_batch(root, "SnowPebbles", _rock_mesh(), snow_stones, Color("bbc9cc"), false)
	_batch(root, "Rocks", _rock_mesh(), large, Color("646b62"), true)
	_batch(root, "SnowRocks", _rock_mesh(), snow_large, Color("b8c6cb"), true)
	root.set_meta("grass_count", grass.size())
	root.set_meta("pebble_count", stones.size() + snow_stones.size())
	root.set_meta("solid_rock_count", large.size() + snow_large.size())
	return root

static func _point(rect: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)

static func _snow(point: Vector2) -> bool:
	# Keep the original mountain's northern snow biome, independent of chunk borders.
	return point.y < (-1350.0 + CATALOG.MOUNTAIN_OFFSET.y) / 16.0

static func _gentle(point: Vector2, y: float, height_at: Callable, radius: float, tolerance: float) -> bool:
	for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var neighbour := float(height_at.call(point + axis * radius))
		if not is_finite(neighbour) or absf(neighbour - y) > tolerance: return false
	return true

static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[color] = material
	return _materials[color]

static func _grass_mesh() -> ArrayMesh:
	if _grass != null: return _grass
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 5:
		var angle := float(blade) * 2.4
		var base := Vector3(cos(angle), 0, sin(angle)) * 0.12
		var side := Vector3(-sin(angle), 0, cos(angle)) * 0.045
		var tip := base * 1.65 + Vector3.UP * (0.23 + float(blade % 3) * 0.07)
		surface.add_vertex(base - side)
		surface.add_vertex(tip)
		surface.add_vertex(base + side)
	surface.generate_normals()
	_grass = surface.commit()
	return _grass

static func _rock_mesh() -> SphereMesh:
	if _rock == null:
		_rock = SphereMesh.new()
		_rock.radius = 1.0
		_rock.height = 2.0
		_rock.radial_segments = 7
		_rock.rings = 3
	return _rock

static func _batch(root: Node3D, label: String, mesh: Mesh, transforms: Array[Transform3D], color: Color, shadows: bool) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = label
	instance.multimesh = multi
	instance.material_override = _material(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

static func _solid(root: Node3D, transform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	body.position = transform.origin
	body.collision_layer = 1
	body.collision_mask = 0
	var points := PackedVector3Array()
	for vertex in _rock_mesh().get_faces(): points.append(transform.basis * vertex)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
