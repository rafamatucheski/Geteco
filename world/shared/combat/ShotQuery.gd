extends RefCounted
## Traffic reservation is not a ballistic surface. All real solids still win
## by distance, including vehicles inside the reservation.
static func cast(source: Node2D, from: Vector2, to: Vector2, mask: int, excluded: Array[RID] = [], areas := false) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, excluded)
	query.collide_with_areas = areas
	query.hit_from_inside = areas
	var space := source.get_world_2d().direct_space_state
	var result := space.intersect_ray(query)
	while not result.is_empty() and result.collider.is_in_group("medical_rescue_work_zone"):
		var next_excluded := query.exclude
		next_excluded.append(result.rid)
		query.exclude = next_excluded
		result = space.intersect_ray(query)
	return result
