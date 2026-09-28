extends RefCounted
## Fine room-local routing uses the native solid footprints. Its grid is
## shared by visitors, rebuilt on room/solid changes, and never moves bodies.
const CELL := .65
var room: Node3D
var grid: AStarGrid2D
var origin := Vector2.ZERO
var extent := Vector2i.ZERO
var _solid_count := -1

func configure(next_room: Node3D) -> void:
	room = next_room
	grid = null
	_solid_count = -1

func path(start: Vector3, finish: Vector3) -> PackedVector3Array:
	if not is_instance_valid(room) or not room.has_method("is_floor_clear") or not "definition" in room: return PackedVector3Array()
	var solids: Variant = room.get("solid_bounds")
	var count: int = solids.size() if solids is Array else 0
	if grid == null or count != _solid_count:
		_build()
		_solid_count = count
	if grid == null: return PackedVector3Array()
	var from := _nearest(room.to_local(start))
	var to := _nearest(room.to_local(finish))
	if from.x < 0 or to.x < 0: return PackedVector3Array()
	var result := PackedVector3Array()
	for cell in grid.get_id_path(from, to, false):
		var point := Vector3(origin.x + cell.x * CELL, room.to_local(start).y, origin.y + cell.y * CELL)
		result.append(room.to_global(point))
	return result

func _build() -> void:
	var size: Vector2 = room.definition.get("size", Vector2.ZERO)
	if size.x <= 0 or size.y <= 0 or size.x > 80 or size.y > 80: return
	origin = -size * .5 + Vector2.ONE * .4
	extent = Vector2i(floori((size.x - .8) / CELL) + 1, floori((size.y - .8) / CELL) + 1)
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, extent)
	grid.cell_size = Vector2.ONE * CELL
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for x in extent.x:
		for y in extent.y:
			var point := Vector3(origin.x + x * CELL, 0, origin.y + y * CELL)
			grid.set_point_solid(Vector2i(x, y), not room.is_floor_clear(point, .34 + CELL * .5))

func _nearest(point: Vector3) -> Vector2i:
	var center := Vector2i(roundi((point.x - origin.x) / CELL), roundi((point.z - origin.y) / CELL))
	var best := Vector2i(-1, -1)
	var distance := INF
	for x in range(-2, 3):
		for y in range(-2, 3):
			var cell := center + Vector2i(x, y)
			if not grid.region.has_point(cell) or grid.is_point_solid(cell): continue
			var candidate := Vector2(origin.x + cell.x * CELL, origin.y + cell.y * CELL)
			var remaining := candidate.distance_squared_to(Vector2(point.x, point.z))
			if remaining < distance:
				distance = remaining
				best = cell
	return best
