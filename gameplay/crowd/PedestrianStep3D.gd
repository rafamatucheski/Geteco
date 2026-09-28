extends RefCounted
## Only authored paving may be stepped onto. Furniture is never a stair.
const MAX_HEIGHT := 0.20
const MARGIN := 0.001

static func try_step(body: CharacterBody3D, motion: Vector3) -> void:
	if not body.is_on_floor() or body.velocity.y > 0.0 or motion.length_squared() < 0.000001: return
	var hit := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, motion, hit, MARGIN): return
	var obstacle := hit.get_collider() as StaticBody3D
	if obstacle == null or not obstacle.get_meta("pedestrian_step", false): return
	var top := obstacle.to_global(Vector3.UP * float(obstacle.get_meta("pedestrian_step_top", 0.0))).y
	var height := top - body.global_position.y + MARGIN
	if height <= MARGIN or height > MAX_HEIGHT: return
	# Sweep the full capsule up and forward. Never teleport through a
	# wall, ceiling, person or prop, and never change horizontal travel distance.
	var lift := Vector3.UP * height
	if body.test_move(body.global_transform, lift, null, MARGIN): return
	var raised := body.global_transform.translated(lift)
	if body.test_move(raised, motion, null, MARGIN): return
	# The blocking box itself supplies the support height. A downward capsule
	# cast at the rounded lip reports a steep normal at low walking speeds,
	# incorrectly rejecting exactly the same step that running can climb.
	body.global_position.y += height
