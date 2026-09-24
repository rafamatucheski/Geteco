extends RefCounted
## Traffic reservation is not a ballistic surface. All real solids still win
## by distance, including vehicles inside the reservation.
static func cast(source: Node2D, from: Vector2, to: Vector2, mask: int, excluded: Array[RID] = [], areas := false) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, excluded)
	query.collide_with_areas = areas
	query.hit_from_inside = areas
	var space := source.get_world_2d().direct_space_state
	var result := space.intersect_ray(query)
	while not result.is_empty():
		var col = result.collider
		if is_instance_valid(col) and (col.is_in_group("medical_rescue_work_zone") or _is_corpse(col)):
			var next_excluded := query.exclude
			next_excluded.append(result.rid)
			var actor = col.get_meta("combat_actor") if col.has_meta("combat_actor") else col
			if is_instance_valid(actor) and actor is CollisionObject2D:
				next_excluded.append((actor as CollisionObject2D).get_rid())
			query.exclude = next_excluded
			result = space.intersect_ray(query)
		else:
			break
	return result

static func _is_corpse(collider: Object) -> bool:
	if not is_instance_valid(collider):
		return false
	var actor: Object = collider
	if actor.has_meta("combat_actor"):
		actor = actor.get_meta("combat_actor")
	if not is_instance_valid(actor):
		return false
	if actor.get("is_dead") == true or actor.get("is_incapacitated") == true:
		return true
	return false

