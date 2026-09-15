extends "res://world/mountain_pass/WinterResident.gd"

var route := PackedVector2Array()
var route_index := 0
var finished := false
var travel_speed := 28.0
var impact_velocity := Vector2.ZERO
var _gait_distance := 0.0

func _create_model() -> Node3D:
	return preload("res://world/harbor/cemetery/CemeteryResidentModel.gd").new()

func _physics_process(delta: float) -> void:
	if is_dead:
		impact_velocity = preload("res://world/shared/combat/VehiclePersonImpact.gd").move_falling_body(self, impact_velocity, delta)
		super._physics_process(delta)
		return
	if _process_danger(delta): return
	var before := global_position
	if route_index < route.size():
		var goal := route[route_index]
		velocity = global_position.direction_to(goal) * travel_speed
		if global_position.distance_to(goal) < 7:
			route_index += 1
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		finished = true
	var travelled := global_position.distance_to(before)
	_gait_distance += travelled
	model.walking = travelled > .001
	model.motion_speed = travelled / maxf(delta, .001)
	if model.walking: model.rotation.y = -velocity.angle()+PI*0.5
	render_clock += delta
	var viewer := get_tree().get_first_node_in_group("player") as Node2D
	if render_clock >= (1.0 / 30.0 if model.walking and "travel_metres" in model else .10) and viewer and viewer.global_position.distance_to(global_position)<1000:
		var direction := velocity.normalized()
		var axis := Vector3(direction.x, 0, direction.y)
		var pixels := presentation_camera.unproject_position(axis).distance_to(presentation_camera.unproject_position(Vector3.ZERO)) * presentation_sprite.scale.x * model.scale.x
		if "travel_metres" in model: model.travel_metres = _gait_distance / maxf(pixels, .001)
		model._process(render_clock)
		_gait_distance = 0.0
		viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		render_clock=0

func set_route(points: PackedVector2Array) -> void:
	route=points
	route_index=0
	finished=false

func arrest_and_respawn() -> void:
	set_meta("ambient_crime",false)
	finished=true
	queue_free()

func get_run_over(impact: Vector2, is_player_driver: bool = false) -> void:
	if is_dead or not impact.is_finite() or impact.length() < 35.0: return
	impact_velocity = impact.limit_length(600.0) * 0.75
	set_meta("bullet_impulse", impact)
	take_damage(100, is_player_driver)
