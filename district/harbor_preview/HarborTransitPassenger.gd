extends "res://AnimatedPedestrian3D.gd"
## Bounded terminal population. Reuse the articulated civilian model and physics.
var transit_state := "waiting"
var destination := Vector2.ZERO

func _pick_new_sidewalk_target() -> void:
	walk_target = destination

func _navigate_towards(_dest: Vector2, move_speed: float, delta: float) -> Vector2:
	if transit_state == "onboard" or global_position.distance_to(destination) <= 3.0:
		return Vector2.ZERO
	return (destination - global_position).limit_length(move_speed * delta) / maxf(delta, 0.001)

func set_destination(point: Vector2, state: String) -> void:
	destination = point
	walk_target = point
	transit_state = state
	# Visibility alone does not remove a CharacterBody from physics queries.
	collision_layer = 0 if state == "onboard" else 4
