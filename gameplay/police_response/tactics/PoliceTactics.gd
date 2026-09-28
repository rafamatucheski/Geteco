extends RefCounted
## Bounded decisions shared by native officers. Tactical points are admitted
## by capsule/floor queries; normal navigation and physical movement prevail.
const RADII := [7.0, 7.0, 9.0, 12.0, 10.0]
const SPEEDS := [3.3, 3.6, 3.5, 3.4, 2.7]
const NAMES := ["approach", "flank", "cover_team", "contain", "controlled_advance"]
var _capsule: CapsuleShape3D

static func doctrine(tier: int) -> String:
	return NAMES[clampi(tier, 0, NAMES.size() - 1)]

static func desired_offset(tier: int, slot: int, away: Vector3) -> Vector3:
	away.y = 0.0
	if away.length_squared() < .01: away = Vector3.BACK
	away = away.normalized()
	var side := Vector3(-away.z, 0, away.x)
	var sign_side := -1.0 if slot % 2 == 0 else 1.0
	match clampi(tier, 0, 4):
		1: return away * 4.5 + side * sign_side * 5.0
		2: return away * 8.0 + side * sign_side * 2.5
		3:
			var angle := float(posmod(slot, 6)) * TAU / 6.0
			return Vector3(cos(angle), 0, sin(angle)) * 12.0
		4: return away * 9.0 + side * sign_side * 2.0
	return away * RADII[0]

func plan(officer: CharacterBody3D, target: Vector3, hostile: bool, elapsed: float) -> Dictionary:
	var tier := clampi(int(officer.get("tier")), 0, 4)
	var slot := int(officer.get_meta("police_tactic_slot", officer.get_instance_id() % 6))
	var result := {"goal": target, "speed": SPEEDS[tier], "hold": false, "doctrine": doctrine(tier)}
	if not hostile: return result
	var away := officer.global_position - target
	away.y = 0.0
	var distance := away.length()
	if distance > 24.0: return result
	var offset := desired_offset(tier, slot, away)
	var wanted := target + offset
	wanted.y = officer.global_position.y
	if tier == 2 and float(officer.get("reload_timer")) > 0.0:
		var cover := _cover_point(officer, target, away)
		if cover.is_finite():
			result.goal = cover
			result.doctrine = "reload_in_cover"
			return result
	# Alternate pairs covering one another, with slower bounds for the Army.
	if tier in [2, 4] and bool(officer.get("sees_player")) and distance <= 18.0:
		var phase := int(elapsed / (2.4 if tier == 2 else 3.0)) % 2
		if slot % 2 != phase and distance >= 5.0:
			result.goal = officer.global_position
			result.hold = true
			return result
	if point_clear(officer, wanted):
		result.goal = wanted
		return result
	for weight in [.65, .35]:
		var alternate: Vector3 = target + offset * weight
		alternate.y = officer.global_position.y
		if point_clear(officer, alternate):
			result.goal = alternate
			return result
	result.goal = target if point_clear(officer, target) else officer.global_position
	return result

func point_clear(officer: CharacterBody3D, point: Vector3, mask := 5) -> bool:
	if not point.is_finite() or not officer.is_inside_tree(): return false
	var space := officer.get_world_3d().direct_space_state
	var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .4, point - Vector3.UP * .65, 1)
	var floor_hit := space.intersect_ray(floor_ray)
	if floor_hit.is_empty() or floor_hit.normal.y < .7: return false
	if float(floor_hit.position.y) > point.y + .18: return false
	return space.intersect_shape(_query(officer, point, mask), 1).is_empty()

func segment_clear(officer: CharacterBody3D, from: Vector3, to: Vector3) -> bool:
	if not from.is_finite() or not to.is_finite() or not officer.is_inside_tree(): return false
	var query := _query(officer, from, 5)
	query.motion = to - from
	query.motion.y = 0.0
	var result := officer.get_world_3d().direct_space_state.cast_motion(query)
	return result.size() == 2 and result[0] >= .995

func _query(officer: CharacterBody3D, point: Vector3, mask: int) -> PhysicsShapeQueryParameters3D:
	if _capsule == null:
		_capsule = CapsuleShape3D.new()
		_capsule.radius = .32
		_capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform.origin = point + Vector3.UP * .88
	query.collision_mask = mask
	query.exclude = [officer.get_rid()]
	return query

func _cover_point(officer: CharacterBody3D, target: Vector3, away: Vector3) -> Vector3:
	if away.length_squared() < .01: away = Vector3.BACK
	var side := Vector3(-away.z, 0, away.x).normalized()
	var space := officer.get_world_3d().direct_space_state
	for offset in [side * 2.0, -side * 2.0, side * 3.5, -side * 3.5]:
		var point: Vector3 = officer.global_position + offset
		if not point_clear(officer, point): continue
		var ray := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 1.2, point + Vector3.UP * 1.2, 5, [officer.get_rid()])
		if not space.intersect_ray(ray).is_empty(): return point
	return Vector3.INF
