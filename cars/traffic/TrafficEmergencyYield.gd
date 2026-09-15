extends RefCounted
## A siren requests space on its approach corridor, not a city-wide stop.
const NOTICE_DISTANCE := 650.0
const ACTIVE_RADIUS := 760.0

static func has_priority(actor: Node) -> bool:
	if not is_instance_valid(actor) or not actor is Node2D or not actor.is_visible_in_tree(): return false
	if actor.has_method("has_emergency_priority"): return bool(actor.has_emergency_priority())
	return actor.get("is_siren_on") == true and actor.get("is_broken") != true

static func responders(tree: SceneTree) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for actor in tree.get_nodes_in_group("vehicle"):
		if has_priority(actor): result.append(actor)
	# Service vehicles do not all belong to the civilian vehicle group.
	for actor in tree.get_nodes_in_group("emergency_vehicle"):
		if has_priority(actor) and not result.has(actor): result.append(actor)
	return result

static func approaching(actor: Node2D, units: Array[Node2D]) -> Node2D:
	var nearest: Node2D
	var best := NOTICE_DISTANCE
	var axis := actor.global_transform.x.normalized()
	for unit in units:
		if unit == actor: continue
		var forward := unit.global_transform.x.normalized()
		if forward.dot(axis) < 0.65: continue
		var difference := actor.global_position - unit.global_position
		var ahead := difference.dot(forward)
		# Retain the shoulder while the responder's rear clears the car.
		if ahead < -110.0 or ahead > NOTICE_DISTANCE: continue
		if absf(difference.dot(forward.orthogonal())) > 68.0: continue
		if difference.length() < best:
			nearest = unit
			best = difference.length()
	return nearest

