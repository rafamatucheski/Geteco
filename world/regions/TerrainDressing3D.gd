extends RefCounted
## Supplemental 3D forest floor. Coordinates and sampling use world metres (X/Z).
## Caller owns geographic exclusions and parents the result to its streamed chunk.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const CELL := 64.0
const MAX_GRASS := 144
const MAX_PEBBLES := 36
const MAX_ROCKS := 8
static var _grass: ArrayMesh
const NATIVE_ROCK := preload("res://world/regions/NativeRock.gd")
static var _materials: Dictionary = {}

static func build_chunk(rect: Rect2, region_id: String, height_at: Callable, is_reserved: Callable) -> Node3D:
	var job := begin(rect, region_id, height_at, is_reserved)
	step(job, INF)
	return job.root

## Versão retomável: `begin` prepara o trabalho e `step` avança até `budget_usec`, devolvendo
## true ao terminar (`job.root` é o resultado). O terreno de uma célula custava 40-95 ms num
## quadro só (centenas de alturas e reservas). A sequência de sorteios é a mesma de antes.
static func begin(rect: Rect2, region_id: String, height_at: Callable, is_reserved: Callable) -> Dictionary:
	var root := Node3D.new()
	root.name = "TerrainDressing3D"
	var job := {"root": root, "phase": 0, "index": 0, "rect": rect, "height_at": height_at, "is_reserved": is_reserved,
		"grass": [] as Array[Transform3D], "stones": [] as Array[Transform3D], "snow_stones": [] as Array[Transform3D],
		"large": [] as Array[Transform3D], "snow_large": [] as Array[Transform3D]}
	# A missing reservation provider must never put solids across authored gameplay.
	if region_id != "mountain" or not height_at.is_valid() or not is_reserved.is_valid() or not rect.has_area():
		job.phase = 3
		return job
	var rng := RandomNumberGenerator.new()
	rng.seed = 73013 + floori(rect.position.x / CELL) * 73856093 + floori(rect.position.y / CELL) * 19349663
	job.rng = rng
	job.area_ratio = clampf(rect.get_area() / (CELL * CELL), 0.0, 1.0)
	job.grass_count = ceili(MAX_GRASS * float(job.area_ratio))
	job.rock_count = ceili((MAX_PEBBLES + MAX_ROCKS) * float(job.area_ratio))
	job.solid_count = ceili(MAX_ROCKS * float(job.area_ratio))
	return job

static func step(job: Dictionary, budget_usec: float) -> bool:
	var began := Time.get_ticks_usec()
	var rect: Rect2 = job.rect
	var rng: RandomNumberGenerator = job.get("rng")
	var height_at: Callable = job.height_at
	var is_reserved: Callable = job.is_reserved
	var root: Node3D = job.root
	while int(job.phase) == 0 and int(job.index) < int(job.grass_count):
		job.index = int(job.index) + 1
		var point := _point(rect, rng)
		if not (_snow(point) or bool(is_reserved.call(point, 0.65))):
			var y := float(height_at.call(point))
			if is_finite(y) and _gentle(point, y, height_at, 0.5, 0.35):
				var size := rng.randf_range(0.65, 1.3)
				job.grass.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size)), Vector3(point.x, y - 0.03, point.y)))
		if Time.get_ticks_usec() - began >= budget_usec: return false
	if int(job.phase) == 0:
		job.phase = 1
		job.index = 0
	while int(job.phase) == 1 and int(job.index) < int(job.rock_count):
		var i := int(job.index)
		job.index = i + 1
		var solid := i < int(job.solid_count)
		var point := _point(rect, rng)
		var radius := rng.randf_range(0.55, 0.95) if solid else rng.randf_range(0.08, 0.19)
		# Keep full footprint inside this chunk and outside entrances, roads and water.
		if rect.grow(-radius).has_point(point) and not bool(is_reserved.call(point, radius + 0.6)):
			var y := float(height_at.call(point))
			if is_finite(y) and _gentle(point, y, height_at, radius, 0.25):
				var height := radius * rng.randf_range(0.55, 1.0)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius, height, radius * 0.8))
				# A malha tem base plana a -0,55 da altura: enterra só um pouco para assentar no chão.
				var transform := Transform3D(basis, Vector3(point.x, y + height * 0.42, point.y))
				if solid:
					if _snow(point): job.snow_large.append(transform)
					else: job.large.append(transform)
					_solid(root, transform)
				else:
					if _snow(point): job.snow_stones.append(transform)
					else: job.stones.append(transform)
		if Time.get_ticks_usec() - began >= budget_usec: return false
	if int(job.phase) == 1: job.phase = 2
	if int(job.phase) == 2:
		_batch(root, "Grass", _grass_mesh(), job.grass, Color("586643"), false)
		_batch_rocks(root, "Pebbles", job.stones, Color("8a8470"), false, 0)
		_batch_rocks(root, "SnowPebbles", job.snow_stones, Color("d4dde0"), false, 0)
		_batch_rocks(root, "Rocks", job.large, Color("7d8479"), true, 1)
		_batch_rocks(root, "SnowRocks", job.snow_large, Color("d2dce0"), true, 1)
		root.set_meta("grass_count", job.grass.size())
		root.set_meta("pebble_count", job.stones.size() + job.snow_stones.size())
		root.set_meta("solid_rock_count", job.large.size() + job.snow_large.size())
		job.phase = 3
	return true

static func _point(rect: Rect2, rng: RandomNumberGenerator) -> Vector2:
	return rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)

static func _snow(point: Vector2) -> bool:
	# Keep the original mountain's northern snow biome, independent of chunk borders.
	return preload("res://world/regions/WorldConnection3D.gd").mountain_weight(Vector3(point.x, 0, point.y)) >= 0.5 and point.y < (-1350.0 + CATALOG.MOUNTAIN_OFFSET.y) / 16.0

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
		material.vertex_color_use_as_albedo = true
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

## Divide as pedras em variantes de malha (pela posição, igual à colisão). A primeira mantém o nome
## original do lote para o editor de mundo; as outras ganham sufixo.
static func _batch_rocks(root: Node3D, label: String, transforms: Array[Transform3D], color: Color, shadows: bool, detail: int) -> void:
	var count := NATIVE_ROCK.variant_count()
	var groups: Array = []
	for i in count:
		var group: Array[Transform3D] = []
		groups.append(group)
	for transform in transforms: groups[NATIVE_ROCK.variant_for(transform.origin)].append(transform)
	for i in count:
		_batch(root, label if i == 0 else "%s_%d" % [label, i + 1], NATIVE_ROCK.mesh(i, detail), groups[i], color, shadows)

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
	# Pedras e seixos (poucos por chunk) são editáveis um a um no editor de mundo: ele os separa em
	# malhas. O renderizador dummy da prévia devolve identidade ao ler as instâncias, daí o registro.
	if label != "Grass":
		instance.set_meta("world_unit_explode",true)
		instance.set_meta("preview_instance_transforms",transforms)
	root.add_child(instance)

static func _solid(root: Node3D, transform: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	body.position = transform.origin
	body.collision_layer = 1
	body.collision_mask = 0
	var points := PackedVector3Array()
	for vertex in NATIVE_ROCK.hull(NATIVE_ROCK.variant_for(transform.origin)): points.append(transform.basis * vertex)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
