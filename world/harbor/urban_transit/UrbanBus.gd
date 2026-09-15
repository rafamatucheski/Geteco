extends "res://world/shared/traffic/TrafficVehicle.gd"
const TURNS := {"dock_street":["westgate_drive",-1],"westgate_drive":["foundry_avenue",1],"foundry_avenue":["quay_boulevard",1],"quay_boulevard":["dock_street",-1]}
var system: Node2D
var sections: Array[CharacterBody2D] = []
var history := PackedVector2Array()
const HISTORY_CAPACITY := 800
const MAX_ARTICULATION_ANGLE := deg_to_rad(44.0)
var _history_head := 0
var _history_count := 0
var doors := 0.0
var dwelling := true
var current_stop := 0
var next_stop := 0
var visits := 0
var distance_travelled := 0.0
var onboard: Array[Node2D] = []
var _joints: Node2D
var suspended := false
var _pending_section_poses: Array[Transform2D] = []
func _ready() -> void:
	target_length = 134.0
	speed = 118.0
	super._ready()
	active_archetype_id = "route_city"
	vehicle_id = active_archetype_id
	display_name = "510 • Expresso Articulado"
	vehicle_mass = 12.0
	max_health = 650
	health = max_health
	_setup_3d_model({"model_class":"res://world/harbor/urban_transit/UrbanBusModel.gd","target_length":134.0,"target_width":38.0},Color("c82d32"))
	# Project onto the road without lighting the bus's own flattened roof sprite.
	for light in [headlight, second_headlight]:
		if light: light.range_z_max = z_index-1
	body_viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	collision.shape = RectangleShape2D.new()
	collision.shape.size = Vector2(132,38)
	collision_layer = 2
	collision_mask = 7
	pedestrian_hitbox.monitoring = false
	add_to_group("urban_bus")
	_lane_motion_initialized = true
	_lane_motion_speed = 0
	for i in 1:
		var part := preload("res://world/shared/traffic/TrafficVehicle.tscn").instantiate() as CharacterBody2D
		part.set_script(preload("res://world/harbor/urban_transit/UrbanBusTrailer.gd"))
		part.name = "ArticulatedSection%d" % (i+2)
		part.lead_bus = self
		system.add_child(part)
		sections.append(part)
		part.tree_exiting.connect(_on_section_exiting.bind(part))
		add_collision_exception_with(part)
		part.add_collision_exception_with(self)
		for ray in ["FrontRay","FrontRayL","FrontRayR"]: get_node(ray).add_exception(part)
	history.resize(HISTORY_CAPACITY)
	_history_count = 240
	for i in _history_count: history[i] = global_position-global_transform.x*float(i)*2
	_update_sections(0)
	_joints = Node2D.new()
	_joints.z_index = 9
	system.add_child(_joints)
	_joints.draw.connect(_draw_joints)
	set_headlights(is_instance_valid(system.clock) and (system.clock.is_dark or system.clock.weather_state > 0))

func enter_vehicle(actor: CharacterBody2D) -> void:
	var was_detached := _detached_from_lane
	super.enter_vehicle(actor)
	if not is_driven_by_player or was_detached: return
	system.withdraw_bus(self)
	dwelling = false
	suspended = false
	doors = 0.0
	for body in [self]+sections:
		body.body_model.set_doors(0.0)
		body._body_render_visible = false

func _physics_process(delta: float) -> void:
	if not _detached_from_lane: return
	if sections.any(func(part): return part.is_broken): is_broken = true
	var previous := global_transform
	super._physics_process(delta)
	if previous != global_transform:
		var head := global_transform
		var proposed: Array[Dictionary] = [{"body":self,"pose":head}]
		var ahead := head
		for i in sections.size():
			var hitch := ahead.origin - ahead.x * (72.0 if i == 0 else 60.0)
			var direction := (hitch - sections[i].global_position).normalized()
			var pose := Transform2D(direction.angle(), hitch - direction * 62.0)
			proposed.append({"body":sections[i],"pose":pose})
			ahead = pose
		global_transform = previous
		# Sweep the whole convoy from its old pose, including reverse and turns.
		if not TRAFFIC_SWEEP.clear(self,proposed):
			global_transform = previous
			velocity = Vector2.ZERO
			set_meta("vehicle_safe_position",previous.origin)
			set_meta("vehicle_safe_transform",previous)
			return
		global_transform = head
		distance_travelled += previous.origin.distance_to(head.origin)
		for i in sections.size():
			var part := sections[i]
			var pose: Transform2D = proposed[i+1].pose
			part.velocity = (pose.origin-part.global_position)/maxf(delta,0.001)
			part.global_transform = pose
			part._lane_motion_speed = part.velocity.length()
			part.is_moving_on_lane = part.velocity.length()>1
		_joints.queue_redraw()
func _process(delta: float) -> void:
	var weather: Node = system.clock
	var lights_on: bool = is_instance_valid(weather) and (weather.is_dark or weather.weather_state > 0)
	if lights_on != is_night_or_storm: set_headlights(lights_on)
	_update_3d_orientation(delta)
	if not _detached_from_lane: advance_on_lane(delta)

func set_headlights(active: bool) -> void:
	super.set_headlights(active)
	if is_instance_valid(body_model): body_model.set_running_lights(active and not is_broken)
	_body_render_visible = false
	for part in sections:
		if is_instance_valid(part) and not part.is_queued_for_deletion():
			part.set_headlights(active)

func _on_section_exiting(part: CharacterBody2D) -> void:
	# Sections also inherit wreck cleanup. Drop ownership before they are freed.
	sections.erase(part)
	suspended = true
	is_broken = true
	_lane_motion_speed = 0.0
	velocity = Vector2.ZERO
	is_moving_on_lane = false
	if is_instance_valid(_joints): _joints.queue_redraw()

func advance_on_lane(delta: float) -> void:
	var old_doors := doors
	doors = move_toward(doors,1.0 if dwelling else 0.0,delta*1.8)
	if old_doors != doors:
		for body in [self]+sections:
			body.body_model.set_doors(doors)
			body._body_render_visible = false
	if dwelling or doors > 0 or is_broken or suspended:
		_lane_motion_speed = 0
		velocity = Vector2.ZERO
		is_moving_on_lane = false
		return
	for section in sections:
		if section.is_broken:
			is_broken = true
			return
	var follow := get_parent() as PathFollow2D
	if follow == null: return
	var lane := follow.get_parent() as Path2D
	_choose_turn(lane,follow)
	var previous := global_position
	_pending_section_poses.clear()
	super.advance_on_lane(delta)
	velocity = (global_position-previous)/maxf(delta,0.001)
	var travelled := previous.distance_to(global_position)
	distance_travelled += travelled
	if travelled > 0.05:
		if history[_history_head].distance_to(global_position)>=1.5:
			_history_head = posmod(_history_head - 1, HISTORY_CAPACITY)
			history[_history_head] = global_position
			_history_count = mini(_history_count + 1, HISTORY_CAPACITY)
		if _pending_section_poses.size() == sections.size():
			_apply_section_poses(_pending_section_poses, delta)
		else:
			_update_sections(delta)
		_pending_section_poses.clear()
		_joints.queue_redraw()
	var stop: Node2D = system.stops[next_stop]
	follow = get_parent() as PathFollow2D
	if follow != null and follow.get_parent() == stop.lane and absf(follow.progress-stop.offset)<1:
		current_stop = next_stop
		dwelling = true
		_lane_motion_speed = 0
		visits += 1
		system.bus_arrived(self,stop)

func _traffic_control_zone_motion(path: Path2D, follow: PathFollow2D) -> Dictionary:
	var motion := super._traffic_control_zone_motion(path,follow)
	var stop: Node2D = system.stops[next_stop]
	if path == stop.lane:
		var remaining: float = stop.offset-follow.progress
		if remaining >= -0.5:
			motion.allowed_advance = minf(motion.allowed_advance,maxf(0,remaining))
			motion.target_speed = minf(motion.target_speed,sqrt(maxf(0,180*remaining)))
	return motion

func _choose_turn(lane: Path2D, follow: PathFollow2D) -> void:
	if lane.is_in_group("unified_lane_connector"): return
	var controller := _get_junction_traffic_controller()
	if controller == null: return
	var road := String(lane.get_meta("traffic_road_id","")).get_file()
	if not TURNS.has(road): return
	var next: Dictionary = controller._next_lane_junction(lane,follow,int(lane.get_meta("traffic_road_index",-1)))
	if next.is_empty(): return
	var straight := ""
	for connection: Dictionary in controller._connections_from_lane.get(String(lane.get_meta("traffic_lane_id","")),[]):
		if int(connection.junction_index) != int(next.junction_index): continue
		var target: Path2D = system.network.get_lane_path(connection.to_lane_id)
		if target == null: continue
		if String(connection.to_road_id).get_file() == TURNS[road][0] and int(target.get_meta("traffic_direction",0)) == TURNS[road][1]:
			follow.set_meta("traffic_planned_connection_id",connection.connection_id)
			return
		if connection.get("movement","") == "straight": straight = connection.connection_id
	if not straight.is_empty(): follow.set_meta("traffic_planned_connection_id",straight)

func depart() -> void:
	if suspended or is_broken: return
	dwelling = false
	next_stop = (current_stop+1)%system.stops.size()

func door_position() -> Vector2: return to_global(Vector2(34,-30))

func _pose_behind(distance: float) -> Transform2D:
	return _section_pose(distance, global_position)

func _history_point_behind(distance: float, head: Vector2) -> Vector2:
	var previous := head
	for age in _history_count:
		var point := history[(_history_head + age) % HISTORY_CAPACITY]
		var span := previous.distance_to(point)
		if span > 0.001:
			if distance <= span: return previous.lerp(point, distance / span)
			distance -= span
		previous = point
	return previous

func _section_pose(distance: float, head: Vector2) -> Transform2D:
	# Two axle samples give continuous yaw through baked curve points. A single
	# history segment tangent made the entire trailer snap to the next angle.
	var front := _history_point_behind(distance - 34.0, head)
	var rear := _history_point_behind(distance + 34.0, head)
	return Transform2D((front - rear).angle(), (front + rear) * 0.5)

func _constrained_section_poses(head: Transform2D) -> Array[Transform2D]:
	# A tight generated connector can put two distant history tangents more
	# than 60 degrees apart. Applying those poses independently makes adjacent
	# bodies overlap and the convoy sweep then (correctly) refuses every next
	# step. Model the actual hinges instead: each trailer follows the history
	# heading up to its steering limit and remains attached to the preceding
	# rear hitch. The remaining turn is taken as a wider trailer arc.
	var poses: Array[Transform2D] = []
	var ahead := head
	for index in sections.size():
		var desired := _section_pose(134.0 + index * 120.0, head.origin)
		var ahead_angle := ahead.get_rotation()
		var joint_angle := clampf(
			angle_difference(ahead_angle, desired.get_rotation()),
			-MAX_ARTICULATION_ANGLE,
			MAX_ARTICULATION_ANGLE
		)
		var trailer_angle := ahead_angle + joint_angle
		var trailer_axis := Vector2.from_angle(trailer_angle)
		var rear_hitch := ahead.origin - ahead.x.normalized() * (72.0 if index == 0 else 60.0)
		var pose := Transform2D(trailer_angle, rear_hitch - trailer_axis * 62.0)
		poses.append(pose)
		ahead = pose
	return poses

func can_apply_lane_pose(head: Transform2D) -> bool:
	var proposed: Array[Dictionary] = [{"body": self, "pose": head}]
	_pending_section_poses.clear()
	var section_poses := _constrained_section_poses(head)
	for i in sections.size():
		var pose := section_poses[i]
		_pending_section_poses.append(pose)
		proposed.append({"body": sections[i], "pose": pose})
	var clear := TRAFFIC_SWEEP.clear(self, proposed)
	if not clear: _pending_section_poses.clear()
	return clear

func _sections_clear() -> bool:
	var follow := get_parent() as PathFollow2D
	if follow == null: return false
	return _lane_step_is_clear(follow.get_parent(), follow, minf(14.0, _lane_motion_speed * get_process_delta_time()))

func _update_sections(delta: float) -> void:
	_apply_section_poses(_constrained_section_poses(global_transform), delta)

func _apply_section_poses(poses: Array[Transform2D], delta: float) -> void:
	for i in sections.size():
		var part := sections[i]
		var pose: Transform2D = poses[i]
		part.velocity = (pose.origin-part.global_position)/maxf(delta,0.001) if delta > 0 else Vector2.ZERO
		part.global_transform = pose
		part._lane_motion_speed = part.velocity.length()
		part.is_moving_on_lane = part.velocity.length()>1

func occupies_junction(center: Vector2, radius: float) -> bool:
	return TRAFFIC_FLOW.occupies_junction(self, center, radius)

func get_traffic_bodies() -> Array:
	return [self] + sections

func get_traffic_storage_length() -> float:
	return 132.0 if sections.is_empty() else 134.0 + (sections.size() - 1) * 120.0 + 66.0 + 66.0

func _draw_joints() -> void:
	var bodies := [self]+sections
	for i in sections.size():
		var ahead: Node2D = bodies[i]
		var behind: Node2D = bodies[i+1]
		var front: Vector2 = ahead.global_position-ahead.global_transform.x*(64 if i == 0 else 52)
		var rear: Vector2 = behind.global_position+behind.global_transform.x*52
		var a := ahead.global_transform.y*18
		var b := behind.global_transform.y*18
		var up := Vector2(0,-20)
		var contour := Geometry2D.convex_hull(PackedVector2Array([front+a,front-a,rear-b,rear+b,front+a+up,front-a+up,rear-b+up,rear+b+up]))
		_joints.draw_colored_polygon(contour,Color("596064"))
		for rib in 9:
			var t := float(rib)/8
			var side_a := (front+a).lerp(rear+b,t)
			var side_b := (front-a).lerp(rear-b,t)
			_joints.draw_polyline(PackedVector2Array([side_a,side_a+up,side_b+up,side_b]),Color("232b2e"),2,true)

func _exit_tree() -> void:
	# Lane handoffs temporarily exit the tree. The director owns the trailers.
	if is_instance_valid(system) and system.is_inside_tree():
		var owned: Array = []
		owned.append_array(sections)
		owned.append(_joints)
		system.call_deferred("cleanup_removed_bus",weakref(self),owned)
