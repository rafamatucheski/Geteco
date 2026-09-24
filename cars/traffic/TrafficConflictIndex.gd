extends RefCounted
## A snapshot for one activity decision. Sleeping bodies are absent from the
## physics space, but their authored shapes still describe the queue correctly.
## Rebuilt once per decision: no stale transforms/strong refs across unloads.
const CELL_SIZE := 256.0
var _actors: Dictionary = {}
var _lane_entries: Dictionary = {}
var _lane_leaders: Dictionary = {}
var _segment := SegmentShape2D.new()
var stats := {"indexed_actors": 0, "indexed_shapes": 0, "nearby_candidates": 0, "shape_tests": 0,
	"lanes_indexed": 0, "lane_entries": 0, "ordinary_candidates": 0, "ordinary_roots": 0,
	"ordinary_lane_queries": 0, "ordinary_leaders_woken": 0, "ordinary_chains_truncated": 0}

func build(tree: SceneTree, ordinary_activity_area := Rect2()) -> void:
	var ordinary_paths := _active_lane_paths(tree, ordinary_activity_area)
	var seen := {}
	for group in [&"vehicle", &"authored_sidewalk_pedestrian", &"pedestrian"]:
		for value in tree.get_nodes_in_group(group):
			if not is_instance_valid(value) or not value is Node2D: continue
			var actor: Node2D = value
			if actor.is_queued_for_deletion() or seen.has(actor.get_instance_id()): continue
			seen[actor.get_instance_id()] = true
			var cell := Vector2i((actor.global_position / CELL_SIZE).floor())
			if not _actors.has(cell): _actors[cell] = []
			_actors[cell].append(actor)
			stats.indexed_actors += 1
			if actor.is_in_group("vehicle") and ordinary_paths.has(_lane_path(actor)):
				_index_lane_actor(actor)
	_finalize_lanes()

func _active_lane_paths(tree: SceneTree, area: Rect2) -> Dictionary:
	var paths := {}
	if not area.has_area(): return paths
	for value in tree.get_nodes_in_group(&"vehicle"):
		if not is_instance_valid(value) or not value is Node2D: continue
		var actor := value as Node2D
		if actor.is_queued_for_deletion() or actor.get_meta("proximity_sleeping", false): continue
		if not actor.can_process() or not area.has_point(actor.global_position): continue
		var path := _lane_path(actor)
		if path != null: paths[path] = true
	return paths

func _lane_path(actor: Node2D) -> Path2D:
	var follow := actor.get_parent() as PathFollow2D
	if follow == null: return null
	var path := follow.get_parent() as Path2D
	if path == null or path.curve == null: return null
	return path

func _index_lane_actor(actor: Node2D) -> void:
	var follow := actor.get_parent() as PathFollow2D
	if follow == null: return
	var path := _lane_path(actor)
	if path == null: return
	if not _lane_entries.has(path): _lane_entries[path] = []
	_lane_entries[path].append({"actor": actor, "follow": follow, "progress": follow.progress})
	stats.lane_entries += 1

func _finalize_lanes() -> void:
	for path_value in _lane_entries:
		var path := path_value as Path2D
		var entries: Array = _lane_entries[path_value]
		if path == null or entries.size() < 2: continue
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.progress) < float(b.progress))
		stats.lanes_indexed += 1
		for index in entries.size():
			var next_index := index + 1
			if next_index >= entries.size():
				var follow := entries[index].follow as PathFollow2D
				if follow == null or not follow.loop or not bool(path.get_meta("traffic_lane_loop", false)):
					continue
				next_index = 0
			var actor := entries[index].actor as Node2D
			var leader := entries[next_index].actor as Node2D
			if actor != null and leader != null and actor != leader:
				_lane_leaders[actor.get_instance_id()] = leader

func active_vehicles(area: Rect2) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if not area.has_area(): return result
	var first := Vector2i((area.position / CELL_SIZE).floor())
	var last := Vector2i((area.end / CELL_SIZE).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for actor in _actors.get(Vector2i(x, y), []):
				stats.ordinary_candidates += 1
				if not actor.is_in_group("vehicle") or actor.get_meta("proximity_sleeping", false): continue
				if not actor.can_process() or not area.has_point(actor.global_position): continue
				result.append(actor)
	stats.ordinary_roots += result.size()
	return result

func sleeping_lane_leader(actor: Node2D) -> Node2D:
	stats.ordinary_lane_queries += 1
	var leader = _lane_leaders.get(actor.get_instance_id())
	if not is_instance_valid(leader) or not leader is Node2D: return null
	if not leader.get_meta("proximity_sleeping", false): return null
	return leader

func near(point: Vector2, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var reach := Vector2.ONE * radius
	var first := Vector2i(((point - reach) / CELL_SIZE).floor())
	var last := Vector2i(((point + reach) / CELL_SIZE).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for actor in _actors.get(Vector2i(x, y), []):
				stats.nearby_candidates += 1
				if actor.global_position.distance_squared_to(point) < radius * radius:
					result.append(actor)
	return result

func sleeping_blockers(sensor: RayCast2D, actor: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if not sensor.collide_with_bodies: return result
	var start := sensor.global_position
	var end := sensor.to_global(sensor.target_position)
	# Respect the nearest live obstacle (including walls). Dormant bodies in
	# this free corridor are conservatively eligible, then their sensors extend
	# the dependency chain. No simulation or collision layers change here.
	if sensor.is_colliding(): end = sensor.get_collision_point()
	if start.is_equal_approx(end): return result
	_segment.a = start
	_segment.b = end
	# Traffic hulls can overlap the sensor while their origin sits in the next
	# spatial cell (long trucks are the important case). Search one cell beyond
	# the ray bounds, then inspect authored shape owners only for those local
	# candidates. This avoids rebuilding every dormant shape in five cities.
	var rect := Rect2(start, end - start).abs().grow(CELL_SIZE)
	var first := Vector2i((rect.position / CELL_SIZE).floor())
	var last := Vector2i((rect.end / CELL_SIZE).floor())
	var checked := {}
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for value in _actors.get(Vector2i(x, y), []):
				if not value is PhysicsBody2D: continue
				var candidate := value as PhysicsBody2D
				var candidate_id := candidate.get_instance_id()
				if candidate == actor or checked.has(candidate_id): continue
				checked[candidate_id] = true
				if not candidate.get_meta("proximity_sleeping", false): continue
				if (candidate.collision_layer & sensor.collision_mask) == 0: continue
				var hit := false
				for owner_id in candidate.get_shape_owners():
					if candidate.is_shape_owner_disabled(owner_id): continue
					var shape_transform := candidate.global_transform * candidate.shape_owner_get_transform(owner_id)
					for shape_index in candidate.shape_owner_get_shape_count(owner_id):
						var shape := candidate.shape_owner_get_shape(owner_id, shape_index)
						if shape == null: continue
						stats.indexed_shapes += 1
						stats.shape_tests += 1
						if _segment.collide(Transform2D.IDENTITY, shape, shape_transform):
							hit = true
							break
					if hit: break
				if hit: result.append(candidate)
	return result
