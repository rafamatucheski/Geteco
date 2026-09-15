extends Node2D
## One conserved coach: reverse out of its bay, travel the district, return and exchange people.
const MODEL := preload("res://world/harbor/terminal/HarborTerminalMovingCoachModel.gd")
const PPM := 18.0
const FLOOR_Y := 0.76822128
const MODEL_SCALE := 0.50
var operations: Node2D
var architecture: Node2D
var platform_index := 0
var coach: CharacterBody2D
var coach_shape: CollisionShape2D
var coach_model: Node3D
var passenger_service: Node
var state := "parked"
var current_speed := 0.0
var door_amount := 0.0
var distance_travelled := 0.0
var completed_laps := 0
var bay_visits := 0
var entries := 0
var exits := 0
var blocked := false
var blocked_by := ""
var hold_remaining := 0.0
var route_progress := 0.0
var heading := Vector2.UP
var route := Curve2D.new()
var _external_view: SubViewport
var _external_camera: Camera3D
var _external_sprite: Sprite2D
var _external := false
var _merge_clear := false
var _visual_meshes: Array[GeometryInstance3D] = []
var gate_stop_progress := INF
var gate_passed := false
var _hull_direction := Vector2.INF
var _hull_shape: ConvexPolygonShape2D
var _last_synced_position := Vector2.INF
var _last_synced_heading := Vector2.INF
var _last_synced_doors := -1.0

func bay_x() -> float:
	return -141.0 + platform_index * 100.0

func _ready() -> void:
	coach = preload("res://world/harbor/terminal/HarborTerminalCoachBody.gd").new()
	coach.name = "IntercityCoach%02d" % (platform_index + 1)
	coach.collision_layer = 2
	coach.collision_mask = 1 | 2 | 4
	coach.safe_margin = 0.05
	coach.position = Vector2(bay_x(), -88)
	coach.add_to_group("harbor_terminal_coach")
	coach.add_to_group("vehicle")
	coach.set_meta("terminal_service", "intercity")
	coach_shape = CollisionShape2D.new()
	coach_shape.name = "Collision"
	coach_shape.shape = _shape_for_heading(heading)
	coach.add_child(coach_shape)
	add_child(coach)
	if is_instance_valid(architecture):
		coach_model = MODEL.new()
		coach_model.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		coach_model.livery = [Color("247d88"), Color("a44937"), Color("426493"), Color("ae813e")][platform_index]
		coach_model.operator_name = ["COSTA SUL", "VIAÇÃO SERRA", "EXPRESSO AZUL", "LITORAL"][platform_index]
		coach_model.fleet_number = str(2407 + platform_index * 131)
		coach_model.scale = Vector3.ONE * MODEL_SCALE
		architecture.model.add_child(coach_model)
		for node in coach_model.find_children("*", "GeometryInstance3D", true, false):
			_visual_meshes.append(node)
		_build_external_view()
	passenger_service = preload("res://world/harbor/terminal/HarborTerminalPassengerService.gd").new()
	passenger_service.operations = self
	add_child(passenger_service)
	hold_remaining = 1.0 + platform_index * 11.0
	if platform_index == 3:
		# One service is already arriving as play begins; the others finish boarding.
		state = "arriving"
		_set_route(_arrival_route())
		route_progress = route.get_closest_offset(Vector2(230, 168))
		coach.position = route.sample_baked(route_progress)
		heading = _route_heading(route_progress)
		operations.request_apron(self)
	coach_shape.shape = _shape_for_heading(heading)
	_sync_native(0.0)

func _physics_process(delta: float) -> void:
	if state == "stolen":
		passenger_service.update(delta)
		return
	var before := coach.position
	coach.set_meta("terminal_yielding_to_lane", state == "departing" and not _merge_clear)
	blocked = false
	blocked_by = ""
	if state == "parked":
		hold_remaining = maxf(0.0, hold_remaining - delta)
		if hold_remaining <= 0.0:
			bay_visits += 1
			passenger_service.begin_stop()
			state = "exchange"
	elif state == "exchange":
		door_amount = move_toward(door_amount, 1.0, delta * 1.25)
		if passenger_service.phase == "complete":
			state = "closing"
			hold_remaining = 1.2
	elif state == "closing":
		hold_remaining = maxf(0.0, hold_remaining - delta)
		if hold_remaining <= 0:
			door_amount = move_toward(door_amount, 0.0, delta * 1.1)
			if door_amount <= 0.0 and operations.request_apron(self):
				state = "reversing"
				passenger_service.phase = "away"
				_set_route(_reverse_route())
	elif state == "gear_change":
		hold_remaining -= delta
		if hold_remaining <= 0:
			state = "departing"
			_merge_clear = false
			_set_route(_departure_route())
	elif state == "return_wait":
		if operations.request_apron(self):
			state = "arriving"
			_set_route(_arrival_route())
	else:
		_advance(delta)
	_sync_native(before.distance_to(coach.position))
	passenger_service.update(delta)

func _set_route(next: Curve2D) -> void:
	route = next
	route_progress = 0.0
	current_speed = 0.0
	gate_stop_progress = operations.configure_gate_route(self) if operations.has_method("configure_gate_route") else INF
	gate_passed = false

func steal_coach(actor: CharacterBody2D) -> void:
	if state == "stolen" or not is_instance_valid(actor) or actor.get("is_control_disabled") == true: return
	var original := coach
	var driven := preload("res://world/shared/traffic/TrafficVehicle.tscn").instantiate() as CharacterBody2D
	driven.set_script(preload("res://world/harbor/terminal/HarborTerminalDrivenCoach.gd"))
	driven.service = self
	driven.position = original.position
	driven.rotation = heading.angle()
	add_child(driven)
	driven.collision.shape = original.get_node("Collision").shape.duplicate()
	var points: PackedVector2Array = driven.collision.shape.points
	for i in points.size(): points[i] = points[i].rotated(-driven.rotation)
	driven.collision.shape.points = points
	original.collision_layer = 0
	original.collision_mask = 0
	driven.enter_vehicle(actor)
	if not driven.is_driven_by_player:
		original.collision_layer = 2
		original.collision_mask = 7
		driven.queue_free()
		return
	driven._detached_from_lane = true
	coach = driven
	coach_shape = driven.collision
	state = "stolen"
	current_speed = 0.0
	door_amount = 0.0
	operations.release_apron(self)
	passenger_service.cancel_service()
	if operations.coach == original: operations.coach = driven
	original.remove_from_group("vehicle")
	original.queue_free()

func _advance(delta: float) -> void:
	if state == "departing" and coach.position.y >= 89.0 and not _merge_clear:
		# Wait with the whole nose behind the street. Reserve enough clear road
		# for the entire turn, so yielding cars cannot trap a half-merged coach.
		var merge_query := PhysicsShapeQueryParameters2D.new()
		var merge_space := RectangleShape2D.new()
		merge_space.size = Vector2(265, 70)
		merge_query.shape = merge_space
		merge_query.transform = Transform2D(0.0, to_global(Vector2(312.5, 167)))
		merge_query.collision_mask = 2 | 4
		merge_query.exclude = [coach.get_rid()]
		var traffic := get_world_2d().direct_space_state.intersect_shape(merge_query, 1)
		if not traffic.is_empty():
			blocked = true
			blocked_by = str(traffic[0].collider.get_path())
			current_speed = 0.0
			coach.velocity = Vector2.ZERO
			return
		_merge_clear = true
		coach.set_meta("terminal_yielding_to_lane", false)
	var remaining := route.get_baked_length() - route_progress
	var limit := 14.0 if state == "reversing" else (74.0 if state == "road" else 29.0)
	var desired := minf(limit, sqrt(maxf(0.0, 2.0 * 22.0 * remaining)))
	var rescue_clearance := _rescue_clearance(maxf(limit, current_speed))
	var gate_clearance: float = operations.gate_clearance(self) if operations.has_method("gate_clearance") else INF
	rescue_clearance = minf(rescue_clearance, gate_clearance)
	desired = minf(desired, sqrt(2.0 * 22.0 * rescue_clearance))
	current_speed = move_toward(current_speed, desired, 21.0 * delta)
	var advance := minf(current_speed * delta, minf(remaining, rescue_clearance))
	if advance <= 0.001 and rescue_clearance < 0.01:
		current_speed = 0.0
		coach.velocity = Vector2.ZERO
		blocked = true
		blocked_by = "gate_authorization" if gate_clearance < .01 else "medical_rescue_work_zone"
		return
	var target := route.sample_baked(route_progress + advance)
	var lookahead := minf(route_progress + maxf(2.0, advance), route.get_baked_length())
	var next_heading := _route_heading(lookahead)
	if state == "reversing":
		next_heading = -next_heading
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape_for_heading(next_heading)
	query.transform = Transform2D(0.0, to_global(route.sample_baked(lookahead)))
	query.collision_mask = 1 | 2 | 4
	query.exclude = [coach.get_rid()]
	var space := get_world_2d().direct_space_state
	var obstacles := space.intersect_shape(query, 32)
	var motion := (target - coach.position).limit_length(advance)
	var straight := heading.dot(next_heading) > 0.9999 and motion.dot(heading) > 0.0
	var current_query := PhysicsShapeQueryParameters2D.new()
	current_query.shape = query.shape
	current_query.transform = coach.global_transform
	current_query.collision_mask = 1 | 2 | 4
	current_query.exclude = [coach.get_rid()]
	var current_contacts := space.intersect_shape(current_query, 32)
	var rear_contacts: Array[Node2D] = []
	if straight:
		for contact in current_contacts:
			if _contact_is_behind(contact.collider, heading): rear_contacts.append(contact.collider)
	for contact in current_contacts:
		if not rear_contacts.has(contact.collider):
			blocked_by = str(contact.collider.get_path())
			blocked = true
			current_speed = 0.0
			coach.velocity = Vector2.ZERO
			return
	for obstacle in obstacles:
		if not rear_contacts.has(obstacle.collider):
			blocked_by = str(obstacle.collider.get_path())
			blocked = true
			current_speed = 0.0
			coach.velocity = Vector2.ZERO
			return
	# A turning car can touch the rear of a stationary coach. Moving straight
	# away decreases that overlap; kinematic recovery would instead shove the
	# coach sideways and desynchronise its route. Keep every front obstacle and
	# sweep the actual motion, then clear only this existing rear contact.
	var clearing_rear := not rear_contacts.is_empty() and rear_contacts.size() == current_contacts.size()
	coach_shape.shape = _shape_for_heading(next_heading)
	coach.velocity = motion / maxf(delta, 0.001)
	var before_motion := coach.position
	var contact: KinematicCollision2D
	if clearing_rear:
		var sweep := PhysicsShapeQueryParameters2D.new()
		sweep.shape = coach_shape.shape
		sweep.transform = coach.global_transform
		sweep.motion = motion
		sweep.collision_mask = 1 | 2 | 4
		sweep.exclude = [coach.get_rid()]
		if space.cast_motion(sweep)[0] < 1.0:
			blocked = true
			current_speed = 0.0
			coach.velocity = Vector2.ZERO
			return
		coach.position += motion
	else:
		contact = coach.move_and_collide(motion, false, 0.0)
	heading = next_heading
	var actual_motion := coach.position - before_motion
	distance_travelled += actual_motion.length()
	# move_and_collide can accept only part of the step. Continue from that
	# real position on the next tick instead of correcting back to old progress.
	route_progress = route.get_closest_offset(coach.position)
	if contact:
		blocked_by = str(contact.get_collider().get_path())
		blocked = true
		current_speed = 0.0
		coach.velocity = Vector2.ZERO
		return
	if remaining - advance <= 0.01:
		current_speed = 0.0
		coach.velocity = Vector2.ZERO
		_route_finished()

func _rescue_clearance(speed: float) -> float:
	var guard := preload("res://world/shared/emergency/MedicalRescueWorkZone.gd")
	if not guard.has_zones(coach): return INF
	var distance := 0.0
	while distance <= speed * speed / 44.0 + 20.0:
		var offset := minf(route_progress + distance, route.get_baked_length())
		var direction := _route_heading(offset)
		if state == "reversing": direction = -direction
		if guard.blocks_hull(coach, _shape_for_heading(direction), Transform2D(0.0, to_global(route.sample_baked(offset)))):
			return maxf(0.0, distance - 8.0)
		distance += 4.0
	return INF

func _contact_is_behind(other: Node, direction: Vector2) -> bool:
	if not other is Node2D or not other.is_in_group("vehicle"): return false
	var collision := other.get_node_or_null("Collision") as CollisionShape2D
	if collision == null or collision.shape == null: return false
	var bounds := collision.shape.get_rect()
	for corner in [bounds.position, bounds.position + Vector2(bounds.size.x, 0), bounds.end, bounds.position + Vector2(0, bounds.size.y)]:
		# Every part of the other hull must lie behind our centre. Translation
		# in this direction can then only remove rear overlap, never deepen it.
		if (collision.to_global(corner) - coach.global_position).dot(direction) >= -2.0: return false
	return true

func _route_finished() -> void:
	match state:
		"reversing":
			state = "gear_change"
			hold_remaining = 1.1
		"departing":
			exits += 1
			operations.release_apron(self)
			state = "road"
			_set_route(_road_route())
		"road":
			state = "return_wait"
		"arriving":
			entries += 1
			completed_laps += int(exits > completed_laps)
			operations.release_apron(self)
			state = "parked"
			hold_remaining = 1.5

func _route_heading(offset: float) -> Vector2:
	return (route.sample_baked(minf(offset + 0.2, route.get_baked_length())) - route.sample_baked(maxf(0.0, offset - 0.2))).normalized()

func _curve() -> Curve2D:
	var value := Curve2D.new()
	value.bake_interval = 1.0
	return value

func _arc(curve: Curve2D, center: Vector2, radius: float, start: float, end: float) -> void:
	# Dense arc points preserve the physical centreline and continuous steering.
	for index in range(1, 33):
		var angle := lerpf(start, end, float(index) / 32.0)
		curve.add_point(center + Vector2(cos(angle), sin(angle)) * radius)

func _reverse_route() -> Curve2D:
	var value := _curve()
	value.add_point(Vector2(bay_x(), -88))
	value.add_point(Vector2(bay_x(), -10))
	_arc(value, Vector2(bay_x() - 30, -10), 30, 0, PI / 2)
	return value

func _departure_route() -> Curve2D:
	var value := _curve()
	value.add_point(Vector2(bay_x() - 30, 20))
	value.add_point(Vector2(205, 20))
	_arc(value, Vector2(205, 65), 45, -PI / 2, 0)
	value.add_point(Vector2(250, 125))
	_arc(value, Vector2(293, 125), 43, PI, PI / 2)
	return value

func _road_route() -> Curve2D:
	var value := _curve()
	value.add_point(Vector2(293, 168))
	value.add_point(Vector2(423, 168))
	_arc(value, Vector2(423, 113), 55, PI / 2, 0)
	value.add_point(Vector2(478, -583))
	_arc(value, Vector2(423, -583), 55, 0, -PI / 2)
	value.add_point(Vector2(-323, -638))
	_arc(value, Vector2(-323, -583), 55, -PI / 2, -PI)
	value.add_point(Vector2(-378, 113))
	_arc(value, Vector2(-323, 113), 55, PI, PI / 2)
	return value

func _arrival_route() -> Curve2D:
	var value := _curve()
	value.add_point(Vector2(-323, 168))
	value.add_point(Vector2(305, 168))
	_arc(value, Vector2(305, 113), 55, PI / 2, 0)
	value.add_point(Vector2(360, 70))
	_arc(value, Vector2(305, 70), 55, 0, -PI / 2)
	value.add_point(Vector2(bay_x() + 45, 15))
	_arc(value, Vector2(bay_x() + 45, -30), 45, PI / 2, PI)
	value.add_point(Vector2(bay_x(), -88))
	return value

func _native_yaw(direction: Vector2) -> float:
	return atan2(direction.x, direction.y / FLOOR_Y)

func _shape_for_heading(direction: Vector2) -> ConvexPolygonShape2D:
	# Straight travel and parked presentation repeatedly request the same hull.
	# Replace the resource on a turn; never mutate a shape held by a query/body.
	if direction == _hull_direction and _hull_shape != null: return _hull_shape
	var shape := ConvexPolygonShape2D.new()
	var points := PackedVector2Array()
	var basis := Basis(Vector3.UP, _native_yaw(direction))
	for corner in [Vector3(-1.60, 0, -5.95), Vector3(1.60, 0, -5.95), Vector3(1.60, 0, 5.95), Vector3(-1.60, 0, 5.95)]:
		var floor_point: Vector3 = basis * corner * MODEL_SCALE * PPM
		points.append(Vector2(floor_point.x, floor_point.z * FLOOR_Y))
	shape.points = points
	_hull_direction = direction
	_hull_shape = shape
	return shape

func _build_external_view() -> void:
	# The same model remains in one 3D world. A small tracking viewport keeps it
	# visible when it leaves the terminal render, with matching floor projection.
	_external_view = SubViewport.new()
	_external_view.size = Vector2i(320, 256)
	_external_view.transparent_bg = true
	_external_view.world_3d = architecture.viewport_3d.find_world_3d()
	_external_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_external_view)
	_external_camera = Camera3D.new()
	_external_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_external_camera.size = 14.0
	_external_camera.cull_mask = 1 << (platform_index + 2)
	_external_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_external_view.add_child(_external_camera)
	_external_camera.position = Vector3(0, 24, 20)
	_external_camera.look_at(Vector3.ZERO)
	_external_camera.make_current()
	_external_sprite = Sprite2D.new()
	_external_sprite.z_as_relative = false
	_external_sprite.z_index = 10
	_external_sprite.texture = _external_view.get_texture()
	var rendered_meter := _external_camera.unproject_position(Vector3.RIGHT).distance_to(_external_camera.unproject_position(Vector3.ZERO))
	_external_sprite.scale = Vector2.ONE * PPM / rendered_meter
	add_child(_external_sprite)
	_external_sprite.hide()
	architecture.camera_3d.cull_mask = 1

func _sync_native(distance: float) -> void:
	if not is_instance_valid(coach_model):
		return
	var unchanged := coach.position.is_equal_approx(_last_synced_position) and heading.is_equal_approx(_last_synced_heading) and is_equal_approx(door_amount, _last_synced_doors)
	if unchanged and distance <= 0.0001:
		return
	_last_synced_position = coach.position
	_last_synced_heading = heading
	_last_synced_doors = door_amount
	var floor_point: Vector3 = architecture.floor_from_local(coach.position)
	coach_model.position = floor_point
	coach_model.rotation.y = _native_yaw(heading)
	coach_model.update_motion(distance / (PPM * MODEL_SCALE), door_amount)
	# Switch before the long nose reaches the street layer, otherwise the
	# terminal composite can be covered by road paint while the coach straddles it.
	var front_y := -INF
	for corner in _shape_for_heading(heading).points:
		front_y = maxf(front_y, coach.position.y + corner.y)
	var exterior: bool = front_y >= 80.0 or coach.position.x < -210 or coach.position.x > 410 or coach.position.y < -270
	if exterior != _external:
		_external = exterior
		for mesh in _visual_meshes:
			mesh.layers = 1 << (platform_index + 2) if exterior else 1
		_external_sprite.visible = exterior
	_external_camera.position = floor_point + Vector3(0, 24, 20)
	_external_sprite.position = coach.position
	_external_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if exterior else SubViewport.UPDATE_DISABLED
	architecture.request_redraw()

func _exit_tree() -> void:
	if is_instance_valid(coach_model):
		coach_model.queue_free()
