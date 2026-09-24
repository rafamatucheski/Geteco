extends "res://world/mountain_pass/WinterResident.gd"

var route := PackedVector2Array()
var route_index := 0
var finished := false
var travel_speed := 28.0
var impact_velocity := Vector2.ZERO
var _gait_distance := 0.0

func _create_model() -> Node3D:
	return preload("res://world/harbor/cemetery/CemeteryResidentModel.gd").new()

func _ready() -> void:
	super._ready()
	add_to_group("world_event_resident")

func _physics_process(delta: float) -> void:
	if is_dead:
		impact_velocity = preload("res://guns/combat/VehiclePersonImpact.gd").move_falling_body(self, impact_velocity, delta)
		super._physics_process(delta)
		return
	if _process_danger(delta): return
	var before := global_position
	if route_index < route.size():
		var goal := route[route_index]
		velocity = _navigation.movement(self, goal, travel_speed, delta)
		var arrival_radius := 7.0 if route_index == route.size() - 1 else 14.0
		if global_position.distance_to(goal) < arrival_radius:
			route_index += 1
		preload("res://characters/pedestrians/PersonMotion.gd").move_actor(self)
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

func react_to_assault(origin: Vector2) -> void:
	if is_dead: return
	danger_response.remember(origin, global_position)
	panic_timer = maxf(panic_timer, 9.0)

func take_damage(amount: int, source: Variant = null) -> void:
	var attacker := get_meta("combat_attacker", null) as Node2D
	if is_instance_valid(attacker):
		react_to_assault(attacker.global_position)
		for witness in get_tree().get_nodes_in_group("world_event_resident"):
			if witness == self or not is_instance_valid(witness) or not witness.has_method("react_to_assault"):
				continue
			if witness.get_world_2d() == get_world_2d() and witness.global_position.distance_to(global_position) <= 180.0:
				witness.react_to_assault(attacker.global_position)
	super.take_damage(amount, source)

func arrest_and_respawn() -> void:
	set_meta("ambient_crime",false)
	finished=true
	queue_free()

func get_run_over(impact: Vector2, is_player_driver: bool = false) -> void:
	if is_dead or not impact.is_finite() or impact.length() < 35.0: return
	impact_velocity = impact.limit_length(600.0) * 0.75
	set_meta("bullet_impulse", impact)
	take_damage(100, is_player_driver)
