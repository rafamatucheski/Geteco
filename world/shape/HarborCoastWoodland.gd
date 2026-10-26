extends RefCounted
## Mata da faixa nova de Harbor (mundo orgânico, etapa 3): árvores e arbustos no chão natural de
## HarborCoast, fora da terra de antes, das ruas e de uma folga até a costa. Reaproveita as malhas e os
## materiais da mata do Lago Sereno (FishingWoodland): nenhum material novo, nada compila no jogo.
## Posições fixas (semente própria) calculadas uma vez no preparo da região; cada célula só monta as suas.
const COAST := preload("res://world/shape/HarborCoast.gd")
const WOODLAND := preload("res://world/places/fishing/FishingWoodland.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const CELL := 64.0
const SPACING := 9.0
const COAST_CLEAR := 7.0
const ROAD_CLEAR := 4.0
## Célula Vector2i -> {"trees": [...], "shrubs": [...]}.
static var _cells: Dictionary = {}

## old_land: terra de Harbor antes da costa curva (retângulos e terra extra); roads: pisos das ruas.
static func prepare(old_land: Array[PackedVector2Array], roads: Array) -> void:
	_cells.clear()
	var natural := COAST.natural_land()
	if natural.is_empty(): return
	var rng := RandomNumberGenerator.new()
	rng.seed = 26102026
	for polygon in natural:
		var bounds := GROUND_CUT.bounds(polygon)
		var near_old := old_land.filter(func(p: PackedVector2Array) -> bool: return GROUND_CUT.bounds(p).grow(2.0).intersects(bounds))
		var near_roads := roads.filter(func(p: PackedVector2Array) -> bool: return GROUND_CUT.bounds(p).grow(ROAD_CLEAR).intersects(bounds))
		var x := bounds.position.x
		while x < bounds.end.x:
			var z := bounds.position.y
			while z < bounds.end.y:
				var point := Vector2(x, z) + Vector2(rng.randf_range(-3.2, 3.2), rng.randf_range(-3.2, 3.2))
				var roll := rng.randf()
				var height := rng.randf_range(8.0, 12.8)
				var radius := rng.randf_range(.25, .39)
				var crown := rng.randf_range(5.2, 7.3)
				var variant := rng.randi_range(0, 2)
				var yaw := rng.randf() * TAU
				z += SPACING
				if roll > .78 or not _free(point, polygon, near_old, near_roads): continue
				var cell := _cell_of(point)
				if roll > .62: _cell(cell).shrubs.append({"point": Vector3(point.x, .30, point.y), "size": .7 + roll * .8, "yaw": yaw})
				else: _cell(cell).trees.append({"point": Vector3(point.x, 0, point.y), "height": height, "radius": radius, "crown": crown, "variant": variant, "yaw": yaw})
			x += SPACING

static func tree_count() -> int:
	var total := 0
	for cell in _cells.values(): total += cell.trees.size()
	return total

static func trees_in(rect: Rect2) -> Array:
	return _cells.get(_cell_of(rect.get_center()), {}).get("trees", [])

static func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var data: Dictionary = _cells.get(_cell_of(rect.get_center()), {})
	if data.is_empty(): return
	WOODLAND._prepare()
	var node := Node3D.new()
	node.name = "CoastWoodland"
	parent.add_child(node)
	var body := StaticBody3D.new()
	body.name = "CoastWoodlandTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)
	var batches := {}
	for tree in data.trees:
		var point: Vector3 = tree.point
		WOODLAND._put(batches, "trunk", point, Vector3(tree.radius / .04, tree.height, tree.radius / .04), tree.yaw)
		WOODLAND._put(batches, "crown_%d" % tree.variant, point + Vector3.UP * tree.height * .70, Vector3(tree.crown, tree.height * .54, tree.crown * .94), tree.yaw)
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = tree.radius
		shape.height = tree.height * .67
		collision.shape = shape
		collision.position = point + Vector3.UP * shape.height * .5
		body.add_child(collision)
	for shrub in data.shrubs:
		WOODLAND._put(batches, "shrub", shrub.point, Vector3(1.2, .65, 1.0) * shrub.size, shrub.yaw)
	for key in batches:
		var transforms: Array = batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = WOODLAND._meshes[key]
		multimesh.instance_count = transforms.size()
		for index in transforms.size(): multimesh.set_instance_transform(index, transforms[index])
		var display := MultiMeshInstance3D.new()
		display.name = "Coast_" + str(key)
		display.multimesh = multimesh
		display.material_override = WOODLAND._materials[key]
		if key == "shrub": display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(display)

static func _free(point: Vector2, polygon: PackedVector2Array, old_land: Array, roads: Array) -> bool:
	if not Geometry2D.is_point_in_polygon(point, polygon): return false
	for p in old_land:
		if Geometry2D.is_point_in_polygon(point, p): return false
	# Folga até a costa nova (o muro de pedra fica na beira).
	for i in polygon.size():
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])) < COAST_CLEAR:
			# Borda que encosta na terra de antes não é costa: só conta se do lado de fora for água.
			var closest := Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])
			var outside := closest + (closest - point).normalized() * 1.0
			if not old_land.any(func(p: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(outside, p)): return false
	for road in roads:
		for offset in [Vector2.ZERO, Vector2(ROAD_CLEAR, 0), Vector2(-ROAD_CLEAR, 0), Vector2(0, ROAD_CLEAR), Vector2(0, -ROAD_CLEAR)]:
			if Geometry2D.is_point_in_polygon(point + offset, road): return false
	return true

static func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.y / CELL))

static func _cell(key: Vector2i) -> Dictionary:
	if not _cells.has(key): _cells[key] = {"trees": [], "shrubs": []}
	return _cells[key]
