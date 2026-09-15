extends RefCounted
## Uma grade por tick substitui duas varreduras da população por pedestre.
## A margem cobre deslocamentos entre as consultas (a cada três ticks).
const CELL_SIZE := 128.0
const MOTION_MARGIN := 64.0
const GRID_REFRESH_TICKS := 3
static var _tree: WeakRef
static var _frame := -1
static var _cells: Dictionary = {}
static var _order: Dictionary = {}
static var _queries: Dictionary = {}

static func _refresh(actor: Node2D) -> void:
	var tree := actor.get_tree()
	var frame := Engine.get_physics_frames()
	var tree_changed: bool = _tree == null or _tree.get_ref() != tree
	if not tree_changed and _frame >= 0 and frame >= _frame and frame - _frame < GRID_REFRESH_TICKS:
		return
	_tree = weakref(tree)
	_frame = frame
	_cells.clear()
	_order.clear()
	_queries.clear()
	var actors := tree.get_nodes_in_group("authored_sidewalk_pedestrian")
	var included := {}
	for candidate in actors: included[candidate.get_instance_id()] = true
	for group in ["pedestrian", "damageable", "player"]:
		for candidate in tree.get_nodes_in_group(group):
			if not candidate is CharacterBody2D or included.has(candidate.get_instance_id()): continue
			included[candidate.get_instance_id()] = true
			actors.append(candidate)
	var active_index := 0
	for candidate_value in actors:
		var candidate := candidate_value as Node2D
		if not is_instance_valid(candidate): continue
		# Proximity-sleeping citizens keep their physical body for approaching
		# traffic, but they do not move or participate in visible social spacing.
		# They are indexed by the next grid refresh after activity wakes them.
		if candidate.get_meta("proximity_sleeping", false) or not candidate.can_process(): continue
		var cell := Vector2i((candidate.global_position / CELL_SIZE).floor())
		if not _cells.has(cell): _cells[cell] = []
		_cells[cell].append(candidate)
		_order[candidate.get_instance_id()] = active_index
		active_index += 1

static func neighbors(actor: Node2D, radius: float) -> Array:
	_refresh(actor)
	var actor_id := actor.get_instance_id()
	var cached: Dictionary = _queries.get(actor_id, {})
	if not cached.is_empty() and float(cached.radius) >= radius:
		var cache_valid := true
		for candidate in cached.neighbors:
			if not is_instance_valid(candidate) or not candidate.is_inside_tree():
				cache_valid = false
				break
		if cache_valid: return cached.neighbors
		_queries.erase(actor_id)
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
	_queries[actor_id] = {"radius": radius, "neighbors": result}
	return result
