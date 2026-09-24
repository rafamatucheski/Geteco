extends Node
## A short prelude owned by VehicleBoarding. The extracted person shares the
## vehicle's depth buffer until their feet reach the clear exterior landing.
var car: CharacterBody2D
var victim: CharacterBody2D
var boarding: Node
var progress := 0.0
var duration := 1.8
var completed := false
var side := -1.0
var bike := false
var landing := Vector2.ZERO
var rig: Node3D
var rest := Transform3D.IDENTITY
var seat := Vector3.ZERO
var outside := Vector3.ZERO
var initial_lean := 0.0
var released := false

func prepare(vehicle: CharacterBody2D, person: CharacterBody2D, destination: Vector2, entry_side: float) -> bool:
	car = vehicle
	victim = person
	landing = destination
	side = entry_side
	bike = car.is_motorcycle
	# Terminal coaches keep their authored model in the terminal's shared 3D
	# world. Their drivable collision body intentionally has no private viewport,
	# so it cannot host this shared-depth extraction animation.
	if not is_instance_valid(car.body_model) or not is_instance_valid(car.body_viewport) \
	or car.body_viewport.get_camera_3d() == null:
		return false
	initial_lean = car.body_model.rotation.z if bike else 0.0
	duration = (3.0 if person != null else 1.6) if bike else 1.8
	if bike: car.body_model.set_meta("fallen_motorcycle", true)
	if not is_instance_valid(victim): return true
	victim.setup(car, destination, false)
	victim.global_position = destination
	victim.hide()
	victim.set_physics_process(false)
	victim.set_process(false)
	victim.collision_layer = 0
	if bike:
		var identity := int(car.get_meta("driver_appearance_seed", randi_range(0, 119)))
		car.set_meta("driver_appearance_seed", identity)
		victim.configure_motorcycle_identity(identity, car.body_model.rider_jacket.albedo_color, car.body_model.rider_helmet.albedo_color)
	rig = victim.driver_model
	rest = rig.transform
	rig.reparent(car.body_model, false)
	rig.set_process(false)
	seat = Vector3(side * 0.28, -0.40, 0.10)
	if bike:
		seat = Vector3(0, car.body_model._seat_y - 0.82, 0.25)
	elif is_instance_valid(car._door_3d) and car._door_3d.hinge != null:
		seat = Vector3(side * minf(absf(car._door_3d.hinge.position.x) * 0.34, 0.32), maxf(0, car._door_3d.hinge.position.y - 0.40) - 0.40, car._door_3d.entry_center_z + 0.20)
	rig.position = seat
	rig.rotation = Vector3(0, PI, 0)
	return true

func bind_boarding(transition: Node) -> void:
	boarding = transition
	if is_instance_valid(victim): outside = _floor_point(landing)
	if not bike and is_instance_valid(car._door_3d):
		# Door opening follows the hand reaching the handle, not the key press.
		if car._door_3d.animation: car._door_3d.animation.kill()
		car._door_3d.hinge.rotation.y = 0.0

func _floor_point(world: Vector2) -> Vector3:
	var display: Sprite2D = car.visual
	var camera: Camera3D = car.body_viewport.get_camera_3d()
	var pixel := display.to_local(world) + Vector2(car.body_viewport.size) * 0.5
	var origin := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	return car.body_model.to_local(origin - ray * (origin.y / ray.y))

func update_pose() -> void:
	if completed or not is_instance_valid(boarding): return
	var t := progress
	var pulling := is_instance_valid(victim)
	var pull_t := minf(t / 0.55, 1.0) if bike and pulling else t
	var lift_t := clampf((t - 0.55) / 0.45, 0, 1) if pulling else t
	var approach := smoothstep(0, 0.22, pull_t if pulling else t)
	boarding.phase = "extract" if pulling and not released else "lift_motorcycle"
	boarding.offset = boarding._start.lerp(boarding._door, approach)
	boarding.actor.global_position = car.to_global(boarding.offset)
	boarding._pose.apply_theft(boarding.actor, side, pull_t, car.global_rotation, bike and (released or not pulling), lift_t)
	if is_instance_valid(boarding.cabin_occupant):
		boarding.cabin_occupant.rotation = Vector3.ZERO
		boarding.cabin_occupant.update_pose(boarding.actor, 0.18 * approach)
	if not bike and is_instance_valid(car._door_3d):
		car._door_3d.hinge.rotation.y = side * 1.12 * smoothstep(0.20, 0.38, t)
	if pulling and not released:
		var drag := smoothstep(0.38, 0.94, pull_t)
		rig.transform = rest
		rig.position = seat.lerp(outside, drag)
		rig.rotation = Vector3(0.20 * sin(drag * PI), PI + side * 0.7 * drag, side * 0.20 * sin(drag * PI))
		for i in rig.limbs.size():
			rig.limbs[i].rotation.x = (-1.1 if i % 2 == 0 else -0.7) * (1.0 - drag)
		if pull_t >= 1.0: _release()
	if bike:
		var lean := initial_lean
		if pulling: lean = lerpf(initial_lean, side * 1.15, smoothstep(0.25, 0.95, pull_t))
		if released or not pulling: lean = lerpf(side * 1.15 if pulling else initial_lean, 0.0, smoothstep(0.22, 0.92, lift_t))
		car.body_model.rotation.z = lean
		# People brace on the ground; they must not rotate with the lifted bike.
		var upright := Transform3D(Basis(Vector3.BACK, -lean), Vector3.ZERO)
		if is_instance_valid(boarding.cabin_occupant):
			boarding.cabin_occupant.transform = upright * boarding.cabin_occupant.transform
		if pulling and not released: rig.transform = upright * rig.transform
	car.body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _release() -> void:
	if released or not is_instance_valid(victim) or victim.is_queued_for_deletion(): return
	released = true
	if is_instance_valid(rig):
		rig.reparent(victim.driver_viewport, false)
		rig.transform = rest
		for limb in rig.limbs: limb.rotation = Vector3.ZERO
	victim.setup(car, landing)
	victim.collision_layer = 4
	victim.show()
	victim.set_physics_process(true)
	victim.set_process(true)
	victim.driver_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func finish() -> void:
	if completed: return
	_release()
	completed = true
	if is_instance_valid(car):
		if is_instance_valid(boarding) and is_instance_valid(boarding.cabin_occupant): boarding.cabin_occupant.rotation = Vector3.ZERO
		if bike and is_instance_valid(car.body_model):
			car.body_model.rotation.z = 0.0
			car.body_model.lean = 0.0
			car.body_model.remove_meta("fallen_motorcycle")
		elif is_instance_valid(boarding):
			car._animate_car_door(side, boarding.duration * 0.82 - 0.60)
	queue_free()

func _exit_tree() -> void:
	if not completed and is_instance_valid(car) and is_instance_valid(victim) and not victim.is_queued_for_deletion(): _release()
