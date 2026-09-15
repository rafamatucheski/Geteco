extends RefCounted
## Authored floor path through a depot, swept with the real ambulance hull.
var cursor := 1

func tick(unit: CharacterBody2D, delta: float) -> bool:
	var points: PackedVector2Array = unit.get_meta("depot_departure_waypoints")
	if cursor >= points.size():
		unit.remove_meta("depot_departure_waypoints")
		unit.set_meta("depot_departure_pending", false)
		unit._lane_router.reset()
		return false
	var remaining: Vector2 = points[cursor] - unit.global_position
	if remaining.length() < .1:
		cursor += 1
		return true
	var step := minf(remaining.length(), minf(2.0, 65.0 * delta))
	var next := unit.global_position + remaining.normalized() * step
	# This existing mover checks the swept shape and intermediate headings;
	# parked vehicles and scenery keep their collision masks throughout.
	if unit._ambulance_approach._move_to(unit, next, remaining.angle(), delta):
		unit.current_speed = step / maxf(delta, .001)
		unit.velocity = remaining.normalized() * unit.current_speed
	else:
		unit.current_speed = 0
		unit.velocity = Vector2.ZERO
	return true
