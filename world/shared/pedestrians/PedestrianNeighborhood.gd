extends RefCounted
## Uma grade por tick substitui duas varreduras da população por pedestre.
## A margem cobre deslocamentos entre as consultas (a cada três ticks).
const CELL_SIZE := 128.0
const MOTION_MARGIN := 64.0
static var _tree: WeakRef
static var _frame := -1
static var _cells: Dictionary = {}
static var _order: Dictionary = {}

static func neighbors(actor: Node2D, radius: float) -> Array:
	var tree := actor.get_tree()
	var frame := Engine.get_physics_frames()
	if _tree == null or _tree.get_ref() != tree or frame != _frame:
		_tree = weakref(tree)
		_frame = frame
		_cells.clear()
		_order.clear()
		var actors := tree.get_nodes_in_group("authored_sidewalk_pedestrian")
		for index in actors.size():
			var candidate := actors[index] as Node2D
			if not is_instance_valid(candidate): continue
			var cell := Vector2i((candidate.global_position / CELL_SIZE).floor())
			if not _cells.has(cell): _cells[cell] = []
			_cells[cell].append(candidate)
			_order[candidate.get_instance_id()] = index
	var reach := Vector2.ONE * (radius + MOTION_MARGIN)
	var first := Vector2i(((actor.global_position - reach) / CELL_SIZE).floor())
	var last := Vector2i(((actor.global_position + reach) / CELL_SIZE).floor())
	var result: Array = []
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for candidate in _cells.get(Vector2i(x, y), []):
				if is_instance_valid(candidate) and candidate.is_inside_tree():
					result.append(candidate)
	# O espaçamento escolhe o primeiro vizinho: conserva a ordem da árvore.
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return int(_order[a.get_instance_id()]) < int(_order[b.get_instance_id()]))
	return result
