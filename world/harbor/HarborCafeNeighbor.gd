extends "res://world/shared/pedestrians/AuthoredSidewalkPedestrian.gd"
## Clientes circulam na frente do diner e fazem pausas nas mesas existentes.
var social_pause := 20.0
var gesture_clock := 0.0
var companion: Node2D

func _try_start_poi_visit() -> void:
	pass

func _ambient_walk_paused() -> bool:
	return social_pause > 0.0 or super._ambient_walk_paused()

func _pick_new_sidewalk_target() -> void:
	super._pick_new_sidewalk_target()
	if not is_scared:
		social_pause = randf_range(14.0, 32.0)

func _physics_process(delta: float) -> void:
	social_pause = maxf(0.0, social_pause - delta)
	gesture_clock += delta
	if is_scared:
		social_pause = 0.0
	if social_pause > 0.0 and is_instance_valid(companion):
		walk_dir = global_position.direction_to(companion.global_position)
	super._physics_process(delta)
	if social_pause > 0.0 and not is_dead and not is_incapacitated and not is_scared and _viewport_render_active:
		if right_upper_arm and right_lower_arm:
			right_upper_arm.rotation.x = -0.32 + sin(gesture_clock * 1.8) * 0.12
			right_lower_arm.rotation.x = -0.65 + sin(gesture_clock * 2.3) * 0.18

func is_socializing() -> bool:
	return social_pause > 0.0 and not is_dead and not is_incapacitated and not is_scared and visible
