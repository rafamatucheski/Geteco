extends RefCounted
## One slow, collision-swept maneuver. Progress is physical displacement, never time.
var car: CharacterBody3D
var start := Vector3.ZERO
var finish := Vector3.ZERO
var forward := Vector3.FORWARD
var reverse := false
var progress := 0.0
var length := 1.0
var blocked_seconds := 0.0
var elapsed := 0.0
var active := false
var last_blocker: Dictionary = {}
var pulling_out := false

func begin(vehicle: CharacterBody3D, destination: Vector3, direction: Vector3, backwards: bool, departure := false) -> void:
	car = vehicle
	start = car.global_position
	finish = destination
	forward = direction.normalized()
	reverse = backwards
	pulling_out = departure
	length = maxf(start.distance_to(finish), .1)
	progress = 0.0
	car.traffic = false
	car.set_external_driver(true)
	car.set_physics_process(false)
	car.set_meta("roadside_maneuver", true)
	active = true

func point(t: float) -> Vector3:
	# Cubic tangent follows the existing lane and ends parallel inside the bay.
	var direction := -forward if reverse else forward
	var handle := minf(length * .40, 5.5)
	# Pull out into the adjacent lane before reaching the neighbouring parked
	# bumper. Arrival's long approach tangent would drive straight into it.
	var start_handle := .8 if pulling_out else handle
	var finish_handle := minf(3.0,length*.4) if pulling_out else handle
	return start.bezier_interpolate(start + direction * start_handle, finish - direction * finish_handle, finish, t)

func step(delta: float) -> int:
	if not active or not is_instance_valid(car) or car.is_queued_for_deletion(): return -1
	if car.health <= 0 or car.has_meta("crash_stun"):
		stop()
		return -1
	elapsed += delta
	var next := minf(1.0, progress + delta * (1.45 if reverse else 2.1) / length)
	var destination := point(next)
	var tangent := point(minf(next + .015, 1.0)) - point(maxf(next - .015, 0.0))
	if reverse: tangent = -tangent
	var yaw := atan2(-tangent.x, -tangent.z)
	var candidate_yaw := rotate_toward(car.rotation.y, yaw, delta * .75)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.shape.shape
	query.transform = Transform3D(Basis(Vector3.UP, candidate_yaw), car.global_position + Vector3.UP * (car.shape.position.y + .06))
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	var overlaps := car.get_world_3d().direct_space_state.intersect_shape(query, 1)
	if not overlaps.is_empty():
		if last_blocker.is_empty(): _remember_blocker(overlaps[0].collider, "rotation_overlap")
		blocked_seconds += delta
	else:
		car.rotation.y = candidate_yaw
		var before := car.global_position
		var movement := destination - before
		movement.y = 0
		car.velocity = movement / maxf(delta, .001)
		car.velocity.y = -1.0 if car.is_on_floor() else car.velocity.y - 20 * delta
		car.move_and_slide()
		var actual := car.global_position - before
		actual.y = 0
		if actual.length() > movement.length() * .65 or movement.length() < .005:
			progress = next
			blocked_seconds = 0
		else:
			if last_blocker.is_empty() and car.get_slide_collision_count() > 0:
				_remember_blocker(car.get_slide_collision(0).get_collider(), "motion_collision")
			blocked_seconds += delta
		car.speed = actual.length() / maxf(delta, .001) * (-1 if reverse else 1)
		for wheel in car.wheels:
			if is_instance_valid(wheel): wheel.rotate_x(-car.speed * delta / .34)
	if blocked_seconds > 5.0 or elapsed > 28.0:
		stop()
		return -1
	if progress >= 1.0:
		stop()
		return 1
	return 0

func _remember_blocker(body: Object, kind: String) -> void:
	last_blocker = {"kind":kind,"path":str(body.get_path()) if body is Node and body.is_inside_tree() else str(body),
		"progress":progress,"position":str(car.global_position),"yaw":car.rotation.y}

func diagnostic() -> Dictionary:
	return {"start":str(start),"finish":str(finish),"position":str(car.global_position),"progress":progress,
		"elapsed":elapsed,"blocked_seconds":blocked_seconds,"reverse":reverse,"blocker":last_blocker}

func stop() -> void:
	active = false
	if not is_instance_valid(car): return
	car.set_external_driver(false)
	car.speed = 0
	car.velocity = Vector3.ZERO
	car.horizontal_velocity = Vector3.ZERO
	car.remove_meta("roadside_maneuver")
	car.set_physics_process(true)
