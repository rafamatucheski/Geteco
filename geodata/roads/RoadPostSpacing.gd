extends RefCounted
## Clearance for mast arms and signal housings, not just the small foundation.
const CLEARANCE := 40.0

static func is_clear(owner: Node2D, world_point: Vector2, ignored_parent: Node = null) -> bool:
	for post in owner.get_tree().get_nodes_in_group("fragile_road_post"):
		if post == owner or post.is_queued_for_deletion(): continue
		if ignored_parent != null and post.get_parent() == ignored_parent: continue
		if post.global_position.distance_squared_to(world_point) < CLEARANCE * CLEARANCE:
			return false
	return true
