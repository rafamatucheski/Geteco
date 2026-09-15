extends RefCounted
## Broad phase por tick; a regra exata de travessia continua no chamador.
const CELL_SIZE := 256.0
const CROSSING_HALF_WIDTH := preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd").CROSSING_HALF_WIDTH
static var _tree: WeakRef
static var _frame := -1
static var _cells: Dictionary = {}

static func near(actor: Node2D) -> Array:
	var tree := actor.get_tree()
	var frame := Engine.get_physics_frames()
	if _tree == null or _tree.get_ref() != tree or frame != _frame:
		_tree = weakref(tree)
		_frame = frame
		_cells.clear()
		for crossing in tree.get_nodes_in_group("road_crossing_area"):
			var half_width: float = crossing.road_width * 0.5 + 40.0
			var bounds: Rect2 = crossing.global_transform * Rect2(-CROSSING_HALF_WIDTH, -half_width, CROSSING_HALF_WIDTH * 2, half_width * 2)
			var first := Vector2i((bounds.position / CELL_SIZE).floor())
			var last := Vector2i((bounds.end / CELL_SIZE).floor())
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var cell := Vector2i(x, y)
					if not _cells.has(cell): _cells[cell] = []
					_cells[cell].append(crossing)
	return _cells.get(Vector2i((actor.global_position / CELL_SIZE).floor()), [])
