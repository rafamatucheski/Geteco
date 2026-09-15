extends "res://world/harbor/events/WorldEventResident.gd"
var arrested := false
var face_target := Vector2.ZERO

func _ready() -> void:
	lines.clear()
	super._ready()
	add_to_group("damageable")
	speech_panel.hide()

func _create_model() -> Node3D:
	return preload("res://world/harbor/events/StreetIncidentModel.gd").new()

func _physics_process(delta: float) -> void:
	if is_dead:
		fall_presentation.update(delta)
		return
	if _process_danger(delta): return
	velocity = Vector2.ZERO
	if route_index < route.size():
		var goal := route[route_index]
		if global_position.distance_to(goal) < 8:
			route_index += 1
		else:
			velocity = _navigation.movement(self,goal,minf(travel_speed,global_position.distance_to(goal)*3),delta)
			if preload("res://world/harbor/HarborPedestrianRoutes.gd").crossing_wait(self,goal): velocity = Vector2.ZERO
	move_and_slide()
	finished = route_index >= route.size()
	model.walking = velocity.length() > 1
	if model.walking:
		model.rotation.y = lerp_angle(model.rotation.y,-velocity.angle()+PI*.5,minf(1,delta*8))
	elif face_target != Vector2.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y,-global_position.direction_to(face_target).angle()+PI*.5,minf(1,delta*4))
	_refresh_resident_visual(delta)

func pose(gesture: String, look_at_point: Vector2) -> void:
	set_route(PackedVector2Array())
	velocity = Vector2.ZERO
	model.gesture = gesture
	face_target = look_at_point

func arrest_and_respawn() -> void:
	# The officer's normal, sight-checked arrest drives this transition.
	arrested = true
	pose("arrested",face_target)
