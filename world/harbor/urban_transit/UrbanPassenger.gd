extends "res://world/harbor/HarborTransitPassenger.gd"
var home_stop := 0
var destination_stop := 1
var activity := "trabalho"
var rest_time := 0.0
var trips := 0
var stop: Node2D
var bus: Node2D
var waypoints := PackedVector2Array()
var boarding_bodies: Array[PhysicsBody2D] = []
func _update_viewport_render_state(delta: float) -> void:
	if has_meta("interior_actor_presentation"):
		_viewport_render_active = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		super._update_viewport_render_state(delta)

func allow_boarding(vehicle: Node2D) -> void:
	for body in [vehicle]+vehicle.sections:
		if not boarding_bodies.has(body): boarding_bodies.append(body)
		preload("res://systems/CollisionExceptionLifetime.gd").add(self, body)
		preload("res://systems/CollisionExceptionLifetime.gd").add(body, self)
func restore_collisions() -> void:
	for body in boarding_bodies:
		if is_instance_valid(body):
			remove_collision_exception_with(body)
			body.remove_collision_exception_with(self)
	boarding_bodies.clear()
func walk_route(points: PackedVector2Array, state: String) -> void:
	waypoints = points
	show()
	set_physics_process(true)
	set_destination(waypoints[0] if not waypoints.is_empty() else global_position,state)
func _physics_process(delta: float) -> void:
	if transit_state == "onboard": return
	# Gate the transit-specific waypoint work before the shared pedestrian pass.
	# Without this, every commuter still checked its route at 60 Hz even though
	# ambient movement below was already limited to 30 Hz.
	if not _prepare_ambient_physics_step(delta):
		return
	_ambient_step_prepared = true
	delta = _ambient_prepared_delta
	if not waypoints.is_empty() and global_position.distance_to(waypoints[0])<5:
		waypoints.remove_at(0)
		if not waypoints.is_empty(): set_destination(waypoints[0],transit_state)
	if waypoints.is_empty() and transit_state in ["walking_to_activity","off_duty"]: restore_collisions()
	super._physics_process(delta)
	_ambient_step_prepared = false
