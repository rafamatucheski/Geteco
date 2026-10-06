extends RefCounted
## One-time ground projection; no per-fragment nodes or per-frame physics.
const FLOOR_MASK := 1 # Static world only; native vehicles are on layer 4.
# Roads collide at y=0 but render at +.026; pull-offs render at +.030.
# Clear those visual paving overlays by 6 mm, remaining below 4 cm from the
# actual support plane (including bridges/slopes), never at window height.
const LIFT := .036
const RAY_DEPTH := 48.0

static func triangle(space: PhysicsDirectSpaceState3D, center: Vector3, offsets: Array[Vector3], baseline := false) -> PackedVector3Array:
	var result := PackedVector3Array()
	# Explicit measurement fixture reproduces the former airborne plane without
	# reverting shared source files. Normal gameplay always projects the ground.
	if baseline:
		for offset: Vector3 in offsets: result.append(center+offset+Vector3.UP*.045)
		return result
	var support := _support(space,center)
	if support.is_empty(): return result
	var normal: Vector3 = support.normal
	for offset: Vector3 in offsets:
		var hit := _support(space,center+offset)
		if hit.is_empty(): return PackedVector3Array()
		# A single shard cannot bridge a curb, cliff or hole. Compare every corner
		# with the center's actual support plane while allowing a sloping floor.
		if (hit.normal as Vector3).dot(normal)<.94: return PackedVector3Array()
		if absf(((hit.position as Vector3)-(support.position as Vector3)).dot(normal))>.035:
			return PackedVector3Array()
		result.append((hit.position as Vector3)+(hit.normal as Vector3)*LIFT)
	return result

static func _support(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.15,point+Vector3.DOWN*RAY_DEPTH,FLOOR_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).y<.55: return {}
	return hit
