extends Node2D
## Shared exterior geodata. Internal region seams disappear in the union;
## the remaining coast owns both the visible seawall and its physical body.
const SOUTH := preload("res://world/harbor/HarborSouthPortLayout.gd")
const NORTH_ACCESS := preload("res://world/harbor/HarborNorthAccess.gd")
const SALVAGE := preload("res://world/shared/salvage/SalvageLocation.gd")
const WATER := preload("res://world/shared/nature/WaterPresentation.gd")
const WALL_WIDTH := 12.0
const FALLBACK := Vector2(715, 1800)
var contours: Array[PackedVector2Array] = []
var _bounds: Array[Rect2] = []
var _last_safe: Dictionary = {}
var _elapsed := 0.0

func _ready() -> void:
	name = "WorldPerimeter"
	add_to_group("world_perimeter")
	contours = build_contours()
	for polygon in contours:
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon: bounds = bounds.expand(point)
		_bounds.append(bounds)
	_build_coast()

static func build_contours() -> Array[PackedVector2Array]:
	var surfaces: Array[PackedVector2Array] = []
	for land in [
		preload("res://world/harbor/HarborDistrict.gd").LAND_BOUNDS,
		Rect2(-1450, 1070, 1850, 1320),
		Rect2(SALVAGE.HARBOR_CENTER + SALVAGE.LAND.position, SALVAGE.LAND.size),
		preload("res://world/harbor/HarborEastDistrict.gd").EAST_LAND,
		preload("res://world/harbor/HarborNorthDistrict.gd").NORTH_LAND,
		preload("res://world/harbor/HarborNorthDistrict.gd").HIGHWAY_LAND,
		preload("res://world/harbor/cobras/CobraNeighborhood.gd").LAND,
		preload("res://world/harbor/HarborWaterfront.gd").BRIDGE_OPENING,
		preload("res://world/harbor/HarborWaterfront.gd").GANGWAY_BOUNDS,
		# Continuous mountain bridge, including its walkable shoulders.
		Rect2(6480, -4732, 2475, 345),
	]: surfaces.append(SOUTH.rect_polygon(land))
	var mountain_outline := preload("res://world/mountain_pass/MountainLandGeometry.gd").outline()
	var mountain_offset := preload("res://world/shared/rail/HarborMountainRailRoute.gd").MOUNTAIN_OFFSET
	surfaces.append(Transform2D(0.0, mountain_offset) * mountain_outline)
	surfaces.append_array(SOUTH.surfaces())
	surfaces.append_array(NORTH_ACCESS.water_cutouts())
	var waterfront := preload("res://world/harbor/HarborWaterfront.gd").new()
	surfaces.append(waterfront._deck_polygon())
	waterfront.free()
	for road in preload("res://world/harbor/HarborMountainConnector.gd").road_definitions():
		surfaces.append_array(Geometry2D.offset_polyline(road.points, 100.0, Geometry2D.JOIN_ROUND, Geometry2D.END_SQUARE))
	var result: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for surface in surfaces:
		var remaining_holes: Array[PackedVector2Array] = []
		for hole in holes:
			remaining_holes.append_array(Geometry2D.clip_polygons(hole, surface))
		holes = remaining_holes
		var merged := surface
		var i := 0
		while i < result.size():
			var union := Geometry2D.merge_polygons(merged, result[i])
			var outers: Array[PackedVector2Array] = []
			for polygon in union:
				if not Geometry2D.is_polygon_clockwise(polygon): outers.append(polygon)
			if outers.size() == 1:
				merged = outers[0]
				for polygon in union:
					if Geometry2D.is_polygon_clockwise(polygon): holes.append(polygon)
				result.remove_at(i)
				i = 0
			else:
				i += 1
		result.append(merged)
	for hole in holes:
		if not Geometry2D.is_polygon_clockwise(hole): hole.reverse()
		result.append(hole)
	for index in result.size():
		var closed := result[index].duplicate()
		closed.append(closed[0])
		closed = _simplify(closed)
		closed.remove_at(closed.size() - 1)
		result[index] = closed
	return result

static func _simplify(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2: return points
	var farthest := 0
	var distance := 0.5
	for i in range(1, points.size() - 1):
		var projected := Geometry2D.get_closest_point_to_segment(points[i], points[0], points[-1])
		var candidate := points[i].distance_to(projected)
		if candidate > distance:
			distance = candidate
			farthest = i
	if farthest == 0: return PackedVector2Array([points[0], points[-1]])
	var left := _simplify(points.slice(0, farthest + 1))
	left.remove_at(left.size() - 1)
	left.append_array(_simplify(points.slice(farthest)))
	return left

func contains_point(point: Vector2) -> bool:
	var inside := false
	for i in contours.size():
		if _bounds[i].has_point(point) and Geometry2D.is_point_in_polygon(point, contours[i]):
			if Geometry2D.is_polygon_clockwise(contours[i]): return false
			inside = true
	return inside

func _build_coast() -> void:
	# Clip in strips so ocean polygons never contain unrepresentable holes.
	# They sit above existing oversized backdrop terrain, below ground props.
	var ocean := Node2D.new()
	ocean.name = "OuterOcean"
	ocean.z_index = 0
	add_child(ocean)
	for x in range(-10000, 25000, 1000):
		var pieces: Array[PackedVector2Array] = [SOUTH.rect_polygon(Rect2(x, -18000, 1000, 34000))]
		for land in contours:
			if Geometry2D.is_polygon_clockwise(land): continue
			var clipped: Array[PackedVector2Array] = []
			for piece in pieces: clipped.append_array(Geometry2D.clip_polygons(piece, land))
			pieces = clipped
		for piece in pieces:
			var water := Polygon2D.new()
			water.polygon = piece
			water.color = Color("204754")
			WATER.apply(water)
			ocean.add_child(water)
	for hole in contours:
		if not Geometry2D.is_polygon_clockwise(hole): continue
		var water := Polygon2D.new()
		water.polygon = hole
		water.color = Color("204754")
		WATER.apply(water)
		ocean.add_child(water)
	for contour in contours:
		for i in contour.size():
			var a := contour[i]
			var b := contour[(i + 1) % contour.size()]
			if a.distance_squared_to(b) < 0.01: continue
			var body := StaticBody2D.new()
			body.position = (a + b) * 0.5
			body.rotation = (b - a).angle()
			body.collision_layer = 1
			body.collision_mask = 0
			body.add_to_group("world_boundary")
			body.add_to_group("traffic_hard_boundary")
			var shape := RectangleShape2D.new()
			shape.size = Vector2(a.distance_to(b) + WALL_WIDTH, WALL_WIDTH)
			var collision := CollisionShape2D.new()
			collision.shape = shape
			body.add_child(collision)
			body.set_meta("boundary_aabb_local", Rect2(-shape.size * 0.5, shape.size))
			add_child(body)
		var closed := contour.duplicate()
		closed.append(closed[0])
		for layer in [{"offset":Vector2(0, 6),"width":18.0,"color":Color("303e40")}, {"offset":Vector2.ZERO,"width":WALL_WIDTH,"color":Color("8e9892")}, {"offset":Vector2(0,-3),"width":3.0,"color":Color("bac0ae")}]:
			var line := Line2D.new()
			line.points = closed
			line.position = layer.offset
			line.width = layer.width
			line.default_color = layer.color
			line.z_index = 3
			add_child(line)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return
	# Interiors use distant coordinates and own their collision/recovery.
	if player.get_meta("harbor_interior", false) or player.get_meta("mountain_interior", false): return
	if player.has_meta("police_exterior_position"): return
	var travel := get_node_or_null("/root/RegionTravel")
	var car: Node2D = travel.controlled_car() if travel != null else null
	recover_actor(car if car != null else player)

func recover_actor(actor: Node2D) -> bool:
	var id := actor.get_instance_id()
	var valid := contains_point(actor.global_position)
	if valid and actor.is_inside_tree():
		var query := PhysicsPointQueryParameters2D.new()
		query.position = actor.global_position
		query.collision_mask = 1
		for hit in get_world_2d().direct_space_state.intersect_point(query):
			if hit.collider.is_in_group("building_geodata"):
				valid = false
				break
	if valid:
		_last_safe[id] = actor.global_position
		return false
	actor.global_position = _last_safe.get(id, FALLBACK)
	if actor is CharacterBody2D: actor.velocity = Vector2.ZERO
	actor.reset_physics_interpolation()
	return true
