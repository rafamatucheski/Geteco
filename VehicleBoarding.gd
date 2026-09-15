extends Node
## Shared boarding motion; coordinates stay relative to the car, including on bridges.
var active := false
var exiting := false
var side := -1.0
var phase := "approach"
var car: CharacterBody2D
var actor: CharacterBody2D
var motion: Tween
var original_color := Color.WHITE
var offset := Vector2.ZERO
const POSE = preload("res://scripts/player/VehicleBoardingPose.gd")
var profile := "car"
var duration := 1.85
var progress := 0.0
var _start := Vector2.ZERO
var _door := Vector2.ZERO
var _seat := Vector2.ZERO
var _pose: RefCounted
var _interpolation := Node.PHYSICS_INTERPOLATION_MODE_INHERIT
var _z_index := 10
var cabin_occupant: Node3D
var _sprite_visible := true
var _uses_cabin := false
var _closing_exit := false
var _close_progress := 0.0

static func clear_occupant(vehicle: Node) -> void:
	if not "body_model" in vehicle or not is_instance_valid(vehicle.body_model): return
	var occupant: Node = vehicle.body_model.get_node_or_null("DanteCabinOccupant")
	if occupant != null:
		occupant.dispose()
		vehicle.body_model.remove_child(occupant)

static func profile_for(vehicle: Node) -> String:
	if vehicle.get_meta("vehicle_kind", "car") == "motorcycle": return "motorcycle"
	var id := String(vehicle.get("active_archetype_id")) if "active_archetype_id" in vehicle else ""
	var spec := VehicleCatalog.get_vehicle_spec(id)
	var model := String(spec.get("model_class", ""))
	if "Boxrunner" in model or "Towmaster" in model or "Pumper" in model or "Route" in model:
		return "truck"
	if "Van" in model or "Ranch" in model or "SUV" in model or "Summit" in model:
		return "high_car"
	return "car"

static func duration_for(vehicle: Node, entry_side: float) -> float:
	var kind := profile_for(vehicle)
	if kind == "motorcycle": return 1.45
	return (2.15 if kind == "truck" else 1.85) + (0.30 if entry_side > 0 else 0.0)

static func driver_exit_position(vehicle: CharacterBody2D, pedestrian: CharacterBody2D, exit_side: float) -> Vector2:
	# NPC drivers use the same authored opening and body-clearance rule.
	var probe = load("res://VehicleBoarding.gd").new()
	probe.car = vehicle
	probe.actor = pedestrian
	probe.side = exit_side
	var anchor := Vector2(-5, exit_side * 18)
	if is_instance_valid(vehicle._door_3d) and vehicle._door_3d.hinge != null:
		var hinge: Vector3 = vehicle._door_3d.hinge.position
		anchor = probe._project_anchor(Vector3(hinge.x + exit_side * 0.43, 0, vehicle._door_3d.entry_center_z))
	elif profile_for(vehicle) == "motorcycle":
		anchor = probe._project_anchor(Vector3(exit_side * 0.62, 0, 0.18))
	var landing: Vector2 = probe._door_landing(anchor)
	probe.free()
	return vehicle.to_global(landing) if landing.is_finite() else Vector2.INF

func begin(vehicle: CharacterBody2D, pedestrian: CharacterBody2D, approach: Vector2, entry_side: float, leaving := false) -> void:
	if pedestrian.has_meta("interior_actor_presentation"):
		pedestrian.get_meta("interior_actor_presentation").restore()
	exiting = leaving
	car = vehicle
	actor = pedestrian
	side = entry_side
	profile = profile_for(car)
	duration = duration_for(car, side)
	_interpolation = actor.physics_interpolation_mode
	_z_index = actor.z_index
	original_color = actor.modulate
	offset = car.to_local(approach)
	_start = offset
	active = true
	if "is_control_disabled" in actor:
		actor.is_control_disabled = true
	car.set_meta("vehicle_boarding", true)
	actor.show()
	actor.global_position = approach
	actor.global_rotation = 0.0
	# O ator e reposicionado em _process (ver abaixo), nao pela fisica. A
	# interpolacao de fisica interpola entre transforms de TICK e brigaria com
	# isso, atrasando o corpo em relacao a porta -- fica desligada no ator
	# durante o embarque e volta ao normal em _finish/cancel.
	actor.reset_physics_interpolation()
	actor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var half_width := 18.0
	var collider := car.get_node_or_null("Collision") as CollisionShape2D
	if collider != null and collider.shape is RectangleShape2D:
		half_width = collider.shape.size.y * 0.5
	var entry_x := 15.0 if profile == "truck" else -5.0
	_door = Vector2(entry_x, side * (half_width + 9.0))
	_seat = Vector2(entry_x, side * 6.0)
	# Native doors locate commercial entry at the cab, never the cargo box.
	if "_door_3d" in car and is_instance_valid(car._door_3d) and car._door_3d.hinge != null:
		var hinge: Vector3 = car._door_3d.hinge.position
		_door = _project_anchor(Vector3(hinge.x + side * 0.55, 0, car._door_3d.entry_center_z))
		_seat = _project_anchor(Vector3(hinge.x * 0.42, 0, car._door_3d.entry_center_z))
	elif profile == "motorcycle" and "body_model" in car and is_instance_valid(car.body_model):
		_door = _project_anchor(Vector3(side * 0.62, 0, 0.18))
		_seat = _project_anchor(Vector3(0, 0, 0.18))
	_pose = POSE.new()
	_pose.setup(actor)
	# O Dante Meshy passa a seguir as âncoras posadas pelo embarque.
	actor.set_meta("meshy_anchor_pose", true)
	if profile != "motorcycle" and "model_root" in actor and is_instance_valid(actor.model_root) and "_door_3d" in car and is_instance_valid(car._door_3d) and car._door_3d.hinge != null:
		clear_occupant(car)
		cabin_occupant = preload("res://scripts/player/VehicleCabinOccupant.gd").new()
		car.body_model.add_child(cabin_occupant)
		cabin_occupant.setup(car, actor, car._door_3d)
		_uses_cabin = true
		_sprite_visible = actor.sprite_3d_display.visible
		actor.sprite_3d_display.hide()
	elif profile == "motorcycle" and exiting and "model_root" in actor and is_instance_valid(actor.model_root):
		clear_occupant(car)
		cabin_occupant = preload("res://scripts/player/VehicleCabinOccupant.gd").new()
		car.body_model.add_child(cabin_occupant)
		cabin_occupant.setup(car, actor, null)
		_uses_cabin = true
		_sprite_visible = actor.sprite_3d_display.visible
		actor.sprite_3d_display.hide()
		car.body_model.rider.hide()
	elif profile == "motorcycle":
		actor.z_index = car.z_index + 1
	if exiting:
		# End at the actual doorway, not at a fixed offset from the vehicle's
		# centre (which is far behind the cab on trucks).
		var doorway := _project_anchor(cabin_occupant.doorway) if is_instance_valid(cabin_occupant) else _door
		var landing := _door_landing(doorway)
		if not landing.is_finite():
			exiting = false
			progress = 1.0
			_process(0.0)
			_finish()
			return
		_start = landing
	motion = create_tween()
	motion.tween_property(self, "progress", 1.0, duration)
	motion.tween_callback(_finish)
	_process(0.0)

static func start_exit(vehicle: CharacterBody2D, pedestrian: CharacterBody2D) -> void:
	if not is_instance_valid(pedestrian):
		vehicle.force_exit_vehicle()
		return
	var transition: Node = vehicle._boarding if is_instance_valid(vehicle._boarding) else null
	var opening := true
	if is_instance_valid(transition) and transition.active:
		if transition.exiting: return
	else:
		var destination: Vector2 = vehicle._get_safe_exit_position()
		var preferred := -1.0 if vehicle.to_local(destination).y <= 0 else 1.0
		for exit_side in [preferred, -preferred]:
			vehicle._animate_car_door(exit_side, duration_for(vehicle, exit_side) - 0.25)
			transition = load("res://VehicleBoarding.gd").new()
			vehicle.add_child(transition)
			vehicle._boarding = transition
			transition.begin(vehicle, pedestrian, destination, exit_side, true)
			if transition.active: break
		if not transition.active: return
		transition.progress = 1.0
		opening = false
	transition.reverse_to_exit(opening)

func _door_landing(doorway: Vector2) -> Vector2:
	# Only a small outward step is allowed. Check the complete pedestrian body
	# against the scene and vehicle before restoring physical collisions.
	var shapes := actor.find_children("", "CollisionShape2D", true, false)
	for step in range(0, 25, 2):
		var point := car.to_global(doorway) + car.global_transform.y.normalized() * side * float(step)
		var clear := true
		for shape: CollisionShape2D in shapes:
			if shape.shape == null or shape.get_parent() != actor: continue
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape.shape
			query.transform = Transform2D(0.0, actor.global_scale, 0.0, point) * shape.transform
			query.collision_mask = actor.collision_mask | car.collision_layer | 1
			query.exclude = [actor.get_rid(), car.get_rid()]
			var hull := car.get_node_or_null("Collision") as CollisionShape2D
			if hull != null and hull.shape != null and shape.shape.collide(query.transform, hull.shape, hull.global_transform):
				clear = false
				break
			var hits := actor.get_world_2d().direct_space_state.intersect_shape(query, 1)
			if not hits.is_empty():
				clear = false
				break
		if clear: return car.to_local(point)
	return Vector2.INF

func reverse_to_exit(open_door := true) -> void:
	exiting = true
	if motion: motion.kill()
	# Reverse from the current pose if entry was interrupted; never jump seats.
	var seconds := maxf(0.45, duration * progress)
	if open_door: car._animate_car_door(side, seconds - 0.25)
	motion = create_tween()
	motion.tween_property(self, "progress", 0.0, seconds)
	if profile != "motorcycle":
		motion.tween_callback(func(): _closing_exit = true)
		motion.tween_property(self, "_close_progress", 1.0, 0.40)
	motion.tween_callback(_finish_exit)
	_process(0.0)

func _finish_exit() -> void:
	if motion: motion.kill()
	progress = 0.0
	_closing_exit = false
	_process(0.0)
	active = false
	phase = "outside"
	_restore_actor()
	if is_instance_valid(car):
		clear_occupant(car)
		car.remove_meta("vehicle_boarding")
		car._complete_exit_vehicle(car.to_global(_start))
	queue_free()

func _project_anchor(point: Vector3) -> Vector2:
	if car.has_meta("interior_vehicle_presentation"):
		return car.to_local(car.get_meta("interior_vehicle_presentation").project_anchor(point))
	var view: Camera3D = car.body_viewport.get_camera_3d()
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.force_update_transform()
	var display: Sprite2D = car.visual if "visual" in car else car.sprite
	car.body_model.rotation.y = -car.global_rotation - PI * 0.5
	display.global_rotation = 0.0
	var pixel := view.unproject_position(car.body_model.to_global(point))
	var world: Vector2 = display.to_global(pixel - Vector2(car.body_viewport.size) * 0.5)
	# Actor origin is near the waist in its separate perspective viewport.
	if "viewport_3d" in actor and is_instance_valid(actor.viewport_3d):
		var foot: Vector2 = actor.viewport_3d.get_camera_3d().unproject_position(Vector3.ZERO)
		world -= (foot - Vector2(actor.viewport_3d.size) * 0.5) * actor.sprite_3d_display.scale
	return car.to_local(world)

func _process(_delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not is_instance_valid(car):
		cancel()
		return
	var t := progress
	if t < 0.18:
		phase = "approach"
		offset = _start.lerp(_door, smoothstep(0.0, 0.18, t))
	elif t < 0.32:
		phase = "reach"
		offset = _door
	elif t < 0.56:
		phase = "mount" if profile == "motorcycle" else "step"
		offset = _door.lerp(_seat, 0.32 * smoothstep(0.32, 0.56, t))
	elif t < 0.80:
		phase = "mount" if profile == "motorcycle" else "enter"
		offset = _door.lerp(_seat, lerpf(0.32, 1.0, smoothstep(0.56, 0.80, t)))
	else:
		phase = "change_seat" if side > 0 and profile != "motorcycle" and t < 0.90 and car.get("taxi_passenger") != true else "close"
		offset = _seat
	actor.global_position = car.to_global(offset)
	actor.global_rotation = 0.0
	_pose.apply(actor, profile, side, t, car.global_rotation)
	if is_instance_valid(cabin_occupant):
		cabin_occupant.update_pose(actor, t)
		if exiting:
			# Once fully outside the doorway, use the pedestrian viewport again.
			# Otherwise its head can hit the small vehicle viewport's top edge
			# while walking away. Project the same 3D foot anchor for continuity.
			var outside := t < 0.18
			cabin_occupant.visible = not outside
			actor.sprite_3d_display.visible = _sprite_visible if outside else false
			if outside:
				var door_origin := _project_anchor(cabin_occupant.doorway)
				actor.global_position = car.to_global(_start.lerp(door_origin, smoothstep(0.0,0.18,t)))
	elif profile == "motorcycle":
		actor.modulate.a = original_color.a * (1.0 - smoothstep(0.96, 1.0, t))
	else:
		# Legacy flat vehicles use their body layer to cover the seated actor.
		actor.z_index = car.z_index - 1 if t > 0.56 else _z_index
	if _closing_exit:
		phase = "close_outside"
		_pose.apply_close(actor, side, _close_progress, car.global_rotation)

func _restore_actor() -> void:
	if not is_instance_valid(actor): return
	if _pose != null: _pose.restore()
	actor.remove_meta("meshy_anchor_pose")
	if _uses_cabin and is_instance_valid(actor.sprite_3d_display): actor.sprite_3d_display.visible = _sprite_visible
	actor.modulate = original_color
	actor.z_index = _z_index
	actor.global_rotation = 0.0
	actor.physics_interpolation_mode = _interpolation
	actor.reset_physics_interpolation()
	if "is_control_disabled" in actor: actor.is_control_disabled = false

func _finish() -> void:
	if not is_instance_valid(car) or not is_instance_valid(actor):
		cancel()
		return
	active = false
	phase = "seated"
	if is_instance_valid(cabin_occupant):
		_pose.apply(actor, profile, side, 1.0, car.global_rotation)
		cabin_occupant.settle(actor)
	actor.hide()
	_restore_actor()
	car.remove_meta("vehicle_boarding")
	if car.has_method("refresh_motorcycle_rider"): car.refresh_motorcycle_rider()
	car._drive_input_armed = false
	actor.global_position = car.global_position
	actor.reset_physics_interpolation()
	queue_free()

func cancel() -> void:
	if motion: motion.kill()
	active = false
	if is_instance_valid(car): car.remove_meta("vehicle_boarding")
	_restore_actor()
	if is_instance_valid(car): clear_occupant(car)
	queue_free()

func _exit_tree() -> void:
	if not active: return
	if motion: motion.kill()
	if is_instance_valid(car): car.remove_meta("vehicle_boarding")
	_restore_actor()
	if is_instance_valid(car): clear_occupant(car)
	if not is_instance_valid(actor): return
	actor.show()
	actor.set_physics_process(true)
	for shape in actor.find_children("", "CollisionShape2D", true, false):
		shape.set_deferred("disabled", false)
