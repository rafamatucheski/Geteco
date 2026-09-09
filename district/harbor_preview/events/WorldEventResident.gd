extends "res://district/mountain_pass/WinterResident.gd"

var route := PackedVector2Array()
var route_index := 0
var finished := false
var travel_speed := 28.0

func _physics_process(delta: float) -> void:
	if is_dead: return
	if route_index < route.size():
		var goal := route[route_index]
		velocity = global_position.direction_to(goal) * travel_speed
		if global_position.distance_to(goal) < 7:
			route_index += 1
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		finished = true
	model.walking = velocity.length() > 1
	if model.walking: model.rotation.y = -velocity.angle()+PI*0.5
	render_clock += delta
	var viewer := get_tree().get_first_node_in_group("player") as Node2D
	if render_clock > 0.10 and viewer and viewer.global_position.distance_to(global_position)<1000:
		model._process(render_clock)
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
