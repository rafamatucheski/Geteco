extends RefCounted
## Shared, branched oak for the immediate surroundings of purchasable homes.
const BAKED := preload("res://assets/urban_detail/residential_tree.res")
static func near_home(point: Vector3) -> bool:
	for center in [Vector3(250.0/16,0,150.0/16),Vector3(2624.0/16,0,1984.0/16),Vector3(4915.0/16,0,-860.0/16)]:
		if Vector2(point.x-center.x,point.z-center.z).length() < 23: return true
	return false

static func mesh() -> ArrayMesh:
	return BAKED
