extends RefCounted
## Drives the real Vehicle with throttle and steering on a verified road curve.
## Progress comes from displacement; obstacles never cause a teleport.
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var car
var curve: Curve3D
var sensor := 0.0
var gap := INF
var leader_speed := 0.0
var turns: Array[float] = []
var blocker: Object
var ray_origin := Vector3.ZERO
var hit_position := Vector3.ZERO
var hit_normal := Vector3.ZERO
var hit_side := 0.0
var desired_speed := 0.0
var holding := false
var look_target := Vector3.ZERO
var placement_validator: Callable
var lane := 0.0
var desired_lane := 0.0
var recoveries := 0
var _blocked_age := 0.0
var _recovery_cooldown := 0.0
var _reverse_remaining := 0.0
var _reverse_anchor := Vector3.ZERO
var _reverse_distance := 0.0
var _reverse_probe := 0.0
var _reverse_clear := false
var _pass_start := 0.0
var _clearance := PhysicsShapeQueryParameters3D.new()
var access_ready := true
var _access_probe := 0.0
var _arc_probe := 0.0
var _arc_ready := false
var _bypass_curve: Curve3D
var _bypass_probe := 0.0
var _bypass_ready := false
var _planned_radius := 0.0
var waiting_for_traffic := false
var traffic_wait_expired := false
var _traffic_wait_started := 0
var _traffic_wait_anchor := Vector3.ZERO
var _traffic_wait_seconds := 0.0
var _traffic_wait_limit := 0.0
var _traffic_wait_phase := ""
var _traffic_wait_phase_changes := 0
var _traffic_wait_context := {}
var _traffic_wait_key := Vector3i.ZERO
var _traffic_wait_heading := Vector3.ZERO
var _traffic_green_started := 0
var _yield_owner: CharacterBody3D
var _yield_key := Vector3i.ZERO
var _yielding := false
var _yield_block_age := 0.0
var _yield_sensor := 0.0
var _yield_owner_start := Vector3.ZERO
var _yield_owner_progress := 0.0
var _yield_attempts := 0
var _yield_completed := 0
var _yield_extra_reverse := false
var _sensor_lease_owner: CharacterBody3D
var _sensor_lease_previous_meta := false
var _sensor_lease_previous_partner: Variant
var _sensor_lease_grants := 0
var _sensor_lease_diagnostic := {}
var _owner_motion_query := PhysicsShapeQueryParameters3D.new()
var _owner_rotation_query := PhysicsShapeQueryParameters3D.new()
var _owner_supported_pose := Vector3.INF
var _admission_stage := ""
var _admission_failure := {}
var _support_count := 0
var _supported_pose := Vector3.INF
var _support_corners := PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
var _support_contacts := PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
var _support_normals := PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
var _support_colliders: Array[Object] = [null,null,null,null]

func setup(vehicle, road_curve: Curve3D) -> void:
	_revoke_owner_sensor_lease()
	car = vehicle
	curve = road_curve
	turns.clear()
	lane = 0
	desired_lane = 0
	recoveries = 0
	_blocked_age = 0
	_recovery_cooldown = 0
	_reverse_remaining = 0
	_reverse_distance = 0
	_bypass_curve = null
	_planned_radius = 0
	_yield_owner = null
	_yielding = false
	_yield_block_age = 0
	_yield_attempts = 0
	_yield_completed = 0
	_yield_extra_reverse = false
	_sensor_lease_grants = 0
	waiting_for_traffic = false
	_reset_traffic_wait()
	_clearance.shape = car.shape.shape
	_clearance.collision_mask = 7
	_clearance.exclude = [car.get_rid()]
	for i in range(1,curve.point_count-1):
		var incoming := curve.get_point_position(i-1).direction_to(curve.get_point_position(i))
		var outgoing := curve.get_point_position(i).direction_to(curve.get_point_position(i+1))
		if incoming.angle_to(outgoing) > .22: turns.append(curve.get_closest_offset(curve.get_point_position(i)))
	car.traffic = false
	car.player_damage_attribution = false
	car.set_external_driver(true)

func tick(delta: float, hold: bool) -> void:
	if not is_instance_valid(car) or car.health <= 0 or curve == null: return
	car.set_external_driver(true)
	car.brake_input = hold
	car.throttle_input = 0.0
	holding = hold
	if hold:
		_revoke_owner_sensor_lease()
		return
	_recovery_cooldown = maxf(0,_recovery_cooldown-delta)
	if _reverse_remaining > 0:
		if _yielding: _tick_yield_gate(delta)
		# Prepare the steering target while making room. This only blends the
		# pursuit target; the vehicle still reverses straight with real physics.
		lane = move_toward(lane,desired_lane,delta*3.0)
		var reversed: float = Vector2(car.global_position.x-_reverse_anchor.x,car.global_position.z-_reverse_anchor.z).length()
		if reversed >= _reverse_distance:
			_reverse_remaining = 0
			car.brake_input = true
			return
		_reverse_probe -= delta
		if _reverse_probe <= 0:
			_reverse_probe = .16
			_reverse_clear = _rear_clear(.8)
		if not _reverse_clear:
			_reverse_remaining = 0
			car.brake_input = true
			return
		_reverse_remaining = maxf(0,_reverse_remaining-delta)
		# Counter-throttle moves the ordinary body backwards; no transform write.
		car.steer_input = 0
		car.brake_input = false
		car.throttle_input = clampf((-2.0-car.speed)*.65,-.65,0.0)
		desired_speed = -2.0
		return
	if _yielding:
		_tick_yield_gate(delta)
		car.steer_input = 0
		car.brake_input = true
		desired_speed = 0
		if not is_instance_valid(_yield_owner) or not JUNCTIONS.occupies(_yield_key,_yield_owner.get_instance_id()):
			_revoke_owner_sensor_lease()
			_yielding = false
			_yield_completed += 1
			_recovery_cooldown = 3.0
			# The actual obstructing occupant has cleared the crossing. This ends
			# its episode; the reverse itself never renewed the waiting clock.
			_reset_traffic_wait()
		else: _maintain_owner_sensor_lease()
		return
	if _bypass_curve != null:
		if car.speed < -.1:
			car.brake_input = true
			return
		_tick_bypass(delta)
		return
	var offset: float = curve.get_closest_offset(car.global_position)
	car.route_distance = offset
	var length := curve.get_baked_length()
	var in_access: bool = offset >= float(curve.get_meta("getaway_access_offset",INF))-1.0
	var look: float = clampf(2.5+absf(car.speed)*.1,2.5,3.0) if in_access else clampf(4.5+absf(car.speed)*.35,4.5,8.5)
	var target := curve.sample_baked(minf(offset+look,length),true)
	look_target = target
	var beyond := curve.sample_baked(minf(offset+look+1.0,length),true)
	var direction := target.direction_to(beyond)
	if direction.length_squared() < .1:
		direction = curve.sample_baked(maxf(0,length-1),true).direction_to(curve.sample_baked(length,true))
	var toward: Vector3 = target-car.global_position
	toward.y = 0
	var forward: Vector3 = -car.global_basis.z
	var alpha := forward.signed_angle_to(toward.normalized(),Vector3.UP)
	var bend := absf(toward.normalized().signed_angle_to(direction,Vector3.UP))
	var desired := lerpf(11.5,3.5,clampf(bend/.8,0,1))
	# Reuse the production crossing controller and reservations. A legitimate
	# red light/queue is waiting, not a failed escape or an overtaking target.
	# External driving does not call Vehicle._drive_traffic's sensing cadence.
	car._sense_tick = sensor-delta <= 0
	car.junction_wait = bool(car._junction_gate(length,true))
	waiting_for_traffic = car.junction_wait or _queue_wait_expected(blocker)
	if car.junction_wait: desired = minf(desired,sqrt(7.0*maxf(0,car.junction_gap-.4)))
	if in_access: desired = minf(desired,2.5)
	for turn in turns:
		if turn >= offset-2 and turn < offset+30:
			desired = minf(desired,sqrt(16.0+9.0*maxf(0,turn-offset-5.0)))
	sensor -= delta
	if sensor <= 0:
		sensor = .16
		gap = INF
		leader_speed = 0
		blocker = null
		var reach: float = 4.0+car.speed*car.speed/12.0
		var from: Vector3 = car.global_position+Vector3.UP*.65+forward*(car.half_length+.15)
		for side in [-.8,0.0,.8]:
			var origin: Vector3 = from+car.global_basis.x*car.half_width*side
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,origin+forward*reach,7,[car.get_rid()])
			var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty() and origin.distance_to(hit.position) < gap:
				gap = origin.distance_to(hit.position)
				blocker = hit.collider
				ray_origin = origin
				hit_position = hit.position
				hit_normal = hit.normal
				hit_side = side
				if hit.collider is CharacterBody3D: leader_speed = maxf(0,hit.collider.velocity.dot(forward))
	var person_blocking: bool = is_instance_valid(blocker) and blocker is CharacterBody3D and blocker.get("horizontal_velocity") == null and gap < 1.6 and leader_speed < .35
	waiting_for_traffic = car.junction_wait or _queue_wait_expected(blocker)
	_update_traffic_wait()
	var yielding_owner: CharacterBody3D = _reciprocal_crossing_owner()
	_yield_block_age = _yield_block_age+delta if yielding_owner != null and absf(float(car.speed)) < .3 else 0.0
	if _yield_block_age >= 1.5 and _recovery_cooldown <= 0 and _yield_attempts < 3:
		_recovery_cooldown = .5
		if _begin_crossing_yield(yielding_owner): return
	var vehicle_blocking := _stopped_vehicle_can_pass(blocker)
	_blocked_age = _blocked_age+delta if ((person_blocking and not waiting_for_traffic) or vehicle_blocking) and absf(car.speed) < .75 else 0.0
	if _blocked_age > 1.0 and _recovery_cooldown <= 0 and recoveries < 3:
		_recovery_cooldown = .5
		var plan := _plan_bypass()
		if not plan.is_empty():
			recoveries += 1
			_recovery_cooldown = 3.0
			_blocked_age = 0
			desired_lane = float(plan.lane)
			_bypass_curve = plan.curve
			_bypass_probe = 0
			_reverse_anchor = car.global_position
			_reverse_distance = float(plan.reverse_distance)
			_reverse_remaining = 3.0
			_reverse_probe = 0
			waiting_for_traffic = false
			_reset_traffic_wait()
			car.brake_input = true
			return
	if absf(desired_lane) > .1 and offset > _pass_start+10.0 and not person_blocking:
		if _lane_path_clear(offset,look,0.0): desired_lane = 0.0
	if not is_equal_approx(lane,desired_lane):
		var next_lane := move_toward(lane,desired_lane,delta*1.4)
		if _pose_clear(car.global_position+car.global_basis.x*(next_lane-lane),car.rotation.y): lane = next_lane
	var right := direction.cross(Vector3.UP).normalized()
	target += right*lane
	look_target = target
	toward = target-car.global_position
	toward.y = 0
	alpha = forward.signed_angle_to(toward.normalized(),Vector3.UP)
	bend = absf(toward.normalized().signed_angle_to(direction,Vector3.UP))
	desired = minf(desired,lerpf(11.5,3.5,clampf(bend/.8,0,1)))
	if absf(lane) > .1 or absf(desired_lane) > .1: desired = minf(desired,3.0)
	# Access/end targets can be clipped or curved. Steering follows the actual
	# chord to that target rather than the longer requested route lookahead.
	var steer_distance: float = maxf(.5,toward.length()) if in_access else look
	var steer_goal := clampf(atan2(5.0*sin(alpha),steer_distance)/.48,-1,1)
	if is_finite(gap):
		var passing_person: bool = absf(desired_lane) > .1 and is_instance_valid(blocker) and blocker is CharacterBody3D and blocker.get("horizontal_velocity") == null
		_arc_probe -= delta
		if passing_person and _arc_probe <= 0:
			_arc_probe = .16
			_arc_ready = _forward_arc_clear(steer_goal)
		if not passing_person: _arc_ready = false
		if passing_person and _arc_ready:
			# A straight beam may still see the person beside the chosen turn.
			# Low-speed motion is admitted by the real swept, turning hull.
			desired = minf(desired,2.5)
		else: desired = minf(desired,leader_speed+maxf(0,(gap-1.3)*1.1))
	desired = minf(desired,sqrt(maxf(0,10.0*(length-offset-.7))))
	car.steer_input = steer_goal
	if absf(alpha) > 1.5:
		car.steer_input = signf(alpha)
		desired = minf(desired,2.0)
	if in_access:
		_access_probe -= delta
		if _access_probe <= 0:
			_access_probe = .16
			access_ready = _access_clear(float(car.steer_input),desired)
		if not access_ready:
			waiting_for_traffic = false
			_reset_traffic_wait()
			car.brake_input = true
			desired_speed = 0
			return
	car.brake_input = desired < .2 and absf(car.speed) < 1.5
	car.throttle_input = clampf((desired-car.speed)*.65,-1,1) if not car.brake_input else 0.0
	desired_speed = desired

func _reset_traffic_wait() -> void:
	traffic_wait_expired = false
	_traffic_wait_started = 0
	_traffic_wait_seconds = 0
	_traffic_wait_limit = 0
	_traffic_wait_phase = ""
	_traffic_wait_phase_changes = 0
	_traffic_wait_context.clear()
	_traffic_green_started = 0

func _update_traffic_wait(allow_progress_reset := true) -> void:
	var position: Vector3 = car.global_position
	# A queue that actually advances starts a fresh wait. Tiny physics jitter
	# or red->green/reservation/blocker changes cannot restart the same wait.
	if allow_progress_reset and _traffic_wait_started > 0 and Vector2(position.x-_traffic_wait_anchor.x,position.z-_traffic_wait_anchor.z).length() > .5:
		_reset_traffic_wait()
		return
	var now: int = Time.get_ticks_msec()
	if _traffic_wait_started == 0:
		if not waiting_for_traffic or absf(float(car.speed)) > .3: return
		var source: Object = car if car.junction_wait else _queued_signal_source(blocker)
		var context: Dictionary = _waiting_junction_context(source)
		if context.is_empty():
			waiting_for_traffic = false
			return
		_traffic_wait_started = now
		_traffic_wait_anchor = position
		_traffic_wait_phase = str(context.phase)
		_traffic_wait_limit = JUNCTIONS.CYCLE if context.phase != "stop" else JUNCTIONS.HOLD_LIMIT_MSEC/1000.0
		_traffic_wait_key = context.key_vector
		_traffic_wait_heading = context.heading_vector
		_traffic_wait_context = context
	var phase: String = JUNCTIONS.signal_state(_traffic_wait_key,_traffic_wait_heading)
	if _traffic_wait_phase != phase:
		_traffic_wait_phase = phase
		_traffic_wait_phase_changes += 1
	_traffic_wait_context.phase = phase
	if phase == "green":
		if _traffic_green_started == 0: _traffic_green_started = now
	else: _traffic_green_started = 0
	_traffic_wait_seconds = float(now-_traffic_wait_started)/1000.0
	traffic_wait_expired = _traffic_wait_seconds >= _traffic_wait_limit
	waiting_for_traffic = not traffic_wait_expired

func _reciprocal_crossing_owner() -> CharacterBody3D:
	if not is_instance_valid(blocker) or not blocker is CharacterBody3D or blocker.get("horizontal_velocity") == null: return null
	if blocker.get("blocker") != car or blocker.get("traffic") != true or blocker.get("controlled") == true or blocker.get("external_input") == true: return null
	if absf(float(blocker.get("speed"))) > .3 or blocker.get("blocked") != true: return null
	var key: Variant = blocker.get("_held_junction")
	if not key is Vector3i or not JUNCTIONS.has_reservation(key,blocker.get_instance_id()) or not JUNCTIONS.occupies(key,blocker.get_instance_id()): return null
	if car.get("_held_junction") != null or JUNCTIONS.has_reservation(key,car.get_instance_id()) or JUNCTIONS.occupies(key,car.get_instance_id()): return null
	return blocker as CharacterBody3D

func _begin_crossing_yield(owner: CharacterBody3D) -> bool:
	for distance: float in [2.0,1.5,1.0]:
		if not _rear_clear(distance+.3): continue
		_yield_owner = owner
		_yield_owner_start = owner.global_position
		_yield_owner_progress = 0
		_yield_key = owner.get("_held_junction")
		_yielding = true
		_yield_attempts += 1
		_yield_extra_reverse = false
		_yield_block_age = 0
		_yield_sensor = 0
		_reverse_anchor = car.global_position
		_reverse_distance = distance
		_reverse_remaining = 3.0
		_reverse_probe = 0
		car.brake_input = true
		return true
	return false

func _tick_yield_gate(delta: float) -> void:
	car.route_distance = curve.get_closest_offset(car.global_position)
	_yield_sensor -= delta
	car._sense_tick = _yield_sensor <= 0
	if car._sense_tick: _yield_sensor = .16
	car.junction_wait = bool(car._junction_gate(curve.get_baked_length(),true))
	waiting_for_traffic = car.junction_wait
	# Backing away clears space; it is not forward queue progress and must not
	# renew a stuck episode's clock or fabricate a signal-phase change.
	_update_traffic_wait(false)
	if is_instance_valid(_yield_owner):
		_yield_owner_progress = Vector2(_yield_owner.global_position.x-_yield_owner_start.x,_yield_owner.global_position.z-_yield_owner_start.z).length()

func _revoke_owner_sensor_lease() -> void:
	if is_instance_valid(_sensor_lease_owner) and _sensor_lease_owner.get_meta("jessica_sensor_yield_owner",0) == get_instance_id():
		# A native or external recovery may have replaced our pair/time. Leave
		# that recovery intact; revoke only the short permission still ours.
		if _unjam_partner(_sensor_lease_owner) == car and float(_sensor_lease_owner.get("unjam_time")) <= .15:
			_sensor_lease_owner.set("unjam_time",0.0)
			_sensor_lease_owner.set("sensor_clock",0.0)
			if _sensor_lease_previous_meta: _sensor_lease_owner.set_meta("unjam_partner",_sensor_lease_previous_partner)
			else: _sensor_lease_owner.remove_meta("unjam_partner")
		_sensor_lease_owner.remove_meta("jessica_sensor_yield_owner")
	_sensor_lease_owner = null

func _unjam_partner(body: Object) -> Variant:
	return body.get_meta("unjam_partner") if body.has_meta("unjam_partner") else null

func _maintain_owner_sensor_lease() -> void:
	var owner: CharacterBody3D = _yield_owner
	if not is_instance_valid(owner): _revoke_owner_sensor_lease(); return
	var owner_velocity: Vector3 = owner.get("horizontal_velocity")
	var car_velocity: Vector3 = car.get("horizontal_velocity")
	# At <=1.2m/s, native braking plus the 9/s velocity filter stops inside
	# the verified .35m corridor. Faster motion must use ordinary sensing.
	var normal: bool = owner.get("traffic") == true and owner.get("controlled") != true and owner.get("external_input") != true and owner.get("junction_wait") != true
	normal = normal and float(owner.get("backoff_time")) <= 0 and float(owner.get("bypass_side")) == 0 and not owner.has_meta("crash_stun")
	normal = normal and absf(float(owner.get("speed"))) <= 1.2 and owner_velocity.length() <= 1.25 and float(owner.get("speed")) >= 0
	normal = normal and absf(float(car.speed)) < .1 and car_velocity.length() < .1 and owner.is_on_floor() and owner.is_physics_processing()
	normal = normal and owner.get("blocker") == car and JUNCTIONS.has_reservation(_yield_key,owner.get_instance_id()) and JUNCTIONS.occupies(_yield_key,owner.get_instance_id())
	if not normal:
		_revoke_owner_sensor_lease()
		return
	var owned: bool = _sensor_lease_owner == owner and owner.get_meta("jessica_sensor_yield_owner",0) == get_instance_id() and _unjam_partner(owner) == car
	if not owned and (float(owner.get("unjam_time")) > 0 or _unjam_partner(owner) != null): return
	if owned and float(owner.get("unjam_time")) > .15:
		_revoke_owner_sensor_lease()
		return
	if not _owner_motion_clear(owner):
		_revoke_owner_sensor_lease()
		_try_extend_crossing_yield()
		return
	if not owned:
		_sensor_lease_owner = owner
		_sensor_lease_previous_meta = owner.has_meta("unjam_partner")
		_sensor_lease_previous_partner = _unjam_partner(owner)
		owner.set_meta("jessica_sensor_yield_owner",get_instance_id())
		owner.set_meta("unjam_partner",car)
	owner.set("unjam_time",.12)
	_sensor_lease_grants += 1

func _try_extend_crossing_yield() -> void:
	# One additional metre is allowed only by a demonstrated Jetta overlap,
	# real rear clearance and the same bounded recovery budget.
	if _yield_extra_reverse or _yield_attempts >= 3 or _recovery_cooldown > 0: return
	var collision: Dictionary = _sensor_lease_diagnostic.get("collider",{})
	if _sensor_lease_diagnostic.get("reason","") != "owner_hull_overlap" or int(collision.get("id",0)) != car.get_instance_id(): return
	_recovery_cooldown = .5
	if not _rear_clear(1.3): return
	_yield_extra_reverse = true
	_yield_attempts += 1
	_reverse_anchor = car.global_position
	_reverse_distance = 1.0
	_reverse_remaining = 3.0
	_reverse_probe = 0

func _owner_motion_clear(owner: CharacterBody3D) -> bool:
	var road: Curve3D = owner.get("route")
	if road == null or float(owner.get("health")) <= 0: return false
	var shape: CollisionShape3D = owner.get("shape")
	var space: PhysicsDirectSpaceState3D = owner.get_world_3d().direct_space_state
	_owner_motion_query.shape = shape.shape
	_owner_motion_query.collision_mask = 7
	_owner_motion_query.exclude = [owner.get_rid()]
	_owner_rotation_query.shape = owner.get("rotation_shape")
	_owner_rotation_query.collision_mask = 7
	_owner_rotation_query.exclude = [owner.get_rid()]
	var point: Vector3 = owner.global_position
	var yaw: float = owner.rotation.y
	var speed: float = owner.get("speed")
	var horizontal: Vector3 = owner.get("horizontal_velocity")
	var length: float = road.get_baked_length()
	var open: bool = bool(road.get_meta("traffic_open",false))
	var delta: float = 1.0/float(Engine.physics_ticks_per_second)
	var distance: float = 0
	var checked: Vector3 = point
	var checked_yaw: float = yaw
	_sensor_lease_diagnostic.clear()
	if not _owner_pose_clear(owner,point,yaw,shape,space): return false
	# Integrate the actual normal-traffic control law at physics cadence.
	# Check supported whole-hull poses/sweeps at <=4cm or <=.025rad changes.
	for i in 90:
		var offset: float = road.get_closest_offset(point)
		var near: Vector3 = road.sample_baked(minf(offset+2,length) if open else fposmod(offset+2,length),true)
		var far: Vector3 = road.sample_baked(minf(offset+5,length) if open else fposmod(offset+5,length),true)
		var bend: float = absf((near-point).normalized().signed_angle_to((far-near).normalized(),Vector3.UP))
		var desired: float = minf(2.5,lerpf(5.5,2.2,clampf(bend,0,1)))
		if open: desired = minf(desired,maxf(0,(length-offset-1)*1.5))
		speed = move_toward(speed,desired,(7.0 if desired < speed else 2.5)*delta)
		var look: float = lerpf(3.5,1.7,clampf(bend,0,1))
		var target: Vector3 = road.sample_baked(minf(offset+look,length) if open else fposmod(offset+look,length),true)
		var toward: Vector3 = target-point
		toward.y = 0
		var next_yaw: float = rotate_toward(yaw,atan2(-toward.x,-toward.z),delta*1.7)
		_owner_rotation_query.transform = Transform3D(Basis(Vector3.UP,next_yaw),point+Vector3.UP*shape.position.y)
		if absf(speed) > .2 and space.intersect_shape(_owner_rotation_query,1).is_empty(): yaw = next_yaw
		horizontal = horizontal.lerp(-Basis(Vector3.UP,yaw).z*speed,1.0-exp(-9.0*delta))
		var motion: Vector3 = horizontal*delta
		var step: float = Vector2(motion.x,motion.z).length()
		if distance+step > .35: motion *= (.35-distance)/maxf(.000001,step)
		point += motion
		distance += Vector2(motion.x,motion.z).length()
		if point.distance_to(checked) >= .04 or absf(angle_difference(checked_yaw,yaw)) >= .025 or distance >= .35-.000001:
			if not _owner_pose_clear(owner,point,yaw,shape,space): return false
			point = _owner_supported_pose
			var middle: float = lerp_angle(checked_yaw,yaw,.5)
			_owner_motion_query.transform = Transform3D(Basis(Vector3.UP,middle),checked+Basis(Vector3.UP,middle)*shape.position)
			_owner_motion_query.motion = point-checked
			var safe: PackedFloat32Array = space.cast_motion(_owner_motion_query)
			_owner_motion_query.motion = Vector3.ZERO
			if safe[0] < 1:
				_sensor_lease_diagnostic = {"reason":"owner_swept_hull","point":str(point),"yaw":yaw,"safe_fraction":safe[0],"distance":distance}
				return false
			checked = point
			checked_yaw = yaw
		if distance >= .35-.000001:
			_sensor_lease_diagnostic = {"reason":"supported_owner_motion","distance":distance,"point":str(point),"yaw":yaw}
			return true
	_sensor_lease_diagnostic = {"reason":"owner_preview_no_progress","distance":distance}
	return false

func _owner_pose_clear(owner: CharacterBody3D, point: Vector3, yaw: float, shape: CollisionShape3D, space: PhysicsDirectSpaceState3D) -> bool:
	var basis: Basis = Basis(Vector3.UP,yaw)
	var height: float = -INF
	for x: float in [-float(owner.get("half_width"))*.8,float(owner.get("half_width"))*.8]:
		for z: float in [-float(owner.get("half_length"))*.8,float(owner.get("half_length"))*.8]:
			var corner: Vector3 = point+basis*Vector3(x,0,z)
			var ray := PhysicsRayQueryParameters3D.create(corner+Vector3.UP*.4,corner-Vector3.UP*.3,1,[owner.get_rid()])
			var hit: Dictionary = space.intersect_ray(ray)
			if hit.is_empty() or absf(float(hit.position.y)-point.y) > .25:
				_sensor_lease_diagnostic = {"reason":"owner_ground_missing","corner":str(corner)}
				return false
			height = maxf(height,float(hit.position.y))
	_owner_supported_pose = Vector3(point.x,height+.0003,point.z)
	_owner_motion_query.transform = Transform3D(basis,_owner_supported_pose+basis*shape.position)
	_owner_motion_query.motion = Vector3.ZERO
	var hits: Array[Dictionary] = space.intersect_shape(_owner_motion_query,1)
	if not hits.is_empty():
		_sensor_lease_diagnostic = {"reason":"owner_hull_overlap","point":str(_owner_supported_pose),"yaw":yaw,"collider":_collider_description(hits[0].get("collider"))}
		return false
	return true

func _queued_signal_source(body: Object) -> Object:
	var visited: Dictionary = {}
	var current: Object = body
	for i in 5:
		if not is_instance_valid(current) or not current is Node3D or current.get("horizontal_velocity") == null or visited.has(current.get_instance_id()): return null
		visited[current.get_instance_id()] = true
		if current.get("junction_wait") == true: return current
		if current.get("traffic") != true or current.get("controlled") == true: return null
		var next: Variant = current.get("blocker")
		if not next is Object: return null
		current = next
	return null

func _waiting_junction_context(source: Object, include_held := false) -> Dictionary:
	if not is_instance_valid(source): return {}
	var source_route: Curve3D = source.get("route")
	var entries: Variant = source.get("_junction_list")
	if source_route == null or not entries is Array: return {}
	var length: float = source_route.get_baked_length()
	var open: bool = bool(source_route.get_meta("traffic_open",false))
	var half_length: float = float(source.get("half_length"))
	for junction: Dictionary in entries:
		var key: Vector3i = junction.key
		var ahead: float = float(source.call("_route_ahead",float(junction.offset),length,open))
		if ahead <= -(JUNCTIONS.EXIT+half_length) or ahead > float(junction.get("approach_distance",JUNCTIONS.APPROACH)): continue
		if not include_held and (source.get("_held_junction") == key or source.get("_clearing_junctions").has(key)): continue
		var heading: Vector3 = junction.get("heading",Vector3.ZERO)
		if heading.length_squared() < .0001:
			var offset: float = float(junction.offset)
			var before: Vector3 = source_route.sample_baked(maxf(0,offset-12.0) if open else fposmod(offset-12.0,length),true)
			heading = before.direction_to(source_route.sample_baked(maxf(0,offset-8.0) if open else fposmod(offset-8.0,length),true))
		var stop_gap: float = ahead-half_length-JUNCTIONS.stop_line(key)
		if junction.has("stop_offset"): stop_gap = float(source.call("_route_ahead",float(junction.stop_offset),length,open))-half_length
		return {"vehicle_id":source.get("vehicle_id"),"key":str(key),"heading":str(heading),
			"key_vector":key,"heading_vector":heading,"stop_gap":stop_gap,
			"phase":JUNCTIONS.signal_state(key,heading),"junction_gap":source.get("junction_gap")}
	return {}

func _queue_wait_expected(body: Object) -> bool:
	var visited := {}
	var current: Object = body
	for i in 5:
		if not is_instance_valid(current) or not current is Node3D or current.get("horizontal_velocity") == null or visited.has(current.get_instance_id()): return false
		visited[current.get_instance_id()] = true
		if current.get("junction_wait") == true: return true
		if current.get("traffic") != true or current.get("controlled") == true: return false
		if str(current.get_meta("traffic_yield_state","")) != "": return true
		var next: Variant = current.get("blocker")
		if not next is Object: return false
		current = next
	return false

func _stopped_vehicle_can_pass(body: Object) -> bool:
	if not is_instance_valid(body) or not body is CharacterBody3D or body.get("horizontal_velocity") == null: return false
	if gap >= 1.6 or absf(float(body.get("speed"))) > .3: return false
	if body.get("controlled") == true or body.get("external_input") == true: return false
	if not _bypass_signal_permitted(): return false
	# Parked cars and an actual blocked traffic vehicle can use the same
	# whole-maneuver admission as pedestrians; ordinary moving queues cannot.
	if body.get("traffic") != true: return true
	# A nested queue can report stall_time=0 throughout successive greens.
	# Use our measured stationary episode and the actual release phase instead.
	if _traffic_green_started > 0 and Time.get_ticks_msec()-_traffic_green_started >= 3000 and body.get("blocked") == true: return true
	if _queue_wait_expected(body): return false
	return body.get("blocked") == true and float(body.get("stall_time")) >= 3.0

func _bypass_signal_permitted() -> bool:
	if car.junction_wait: return false
	var context: Dictionary = _waiting_junction_context(car,true)
	if context.is_empty(): return true
	if context.phase == "green": return true
	var key: Vector3i = context.key_vector
	# A body already beyond its stop line clears its leased crossing. A stopped
	# approach may not begin an overtaking maneuver on amber/red.
	return (context.phase == "stop" or float(context.stop_gap) < -1.5) and JUNCTIONS.has_reservation(key,car.get_instance_id())

func _plan_bypass() -> Dictionary:
	# A side-position test alone cannot establish a reachable steering path.
	# Plan both supported reverse travel and a complete S-shaped lane change.
	var reverses: Array[float] = [4.5,3.0,2.1,1.8,1.5,1.2,.9,.6,0.0]
	# WHEELBASE/tan(.48) = 4.80m. Every alternative respects the real steering
	# limit. Prefer the original 6m/4.5m maneuver, but admit a shorter reverse
	# for either a vehicle or a pedestrian when another car occupies the rear.
	var radii: Array[float] = [6.0,5.6,5.2,5.0]
	var forward: Vector3 = -car.global_basis.z
	var right: Vector3 = car.global_basis.x
	var preferred: float = -signf(hit_side)*3.4 if absf(hit_side) > .1 else -3.4
	var shifts: Array[float] = [preferred,-preferred]
	if is_instance_valid(blocker) and blocker is CharacterBody3D and blocker.get("horizontal_velocity") == null:
		# A walking capsule needs less lateral room than another vehicle. This
		# also keeps the passing hull inside a street bounded by shop fronts.
		shifts.append_array([signf(preferred)*1.4,-signf(preferred)*1.4,signf(preferred)*1.8,-signf(preferred)*1.8])
	for reverse_distance: float in reverses:
		# Leave the same physical stopping reserve behind the chosen reverse.
		if not _rear_clear(reverse_distance+.3): continue
		var start: Vector3 = car.global_position-forward*reverse_distance
		for radius: float in radii:
			for shift: float in shifts:
				var path: Curve3D = _build_bypass_curve(start,forward,right,radius,shift)
				if _maneuver_clear(path):
					_planned_radius = radius
					return {"curve":path,"lane":shift,"radius":radius,"reverse_distance":reverse_distance}
	return {}

func _build_bypass_curve(start: Vector3, forward: Vector3, right: Vector3, radius: float, shift: float) -> Curve3D:
	var angle: float = acos(1.0-absf(shift)/(2.0*radius))
	var sign_side: float = signf(shift)
	var path: Curve3D = Curve3D.new()
	path.bake_interval = .15
	path.add_point(start)
	for i in range(1,17):
		var a: float = angle*float(i)/16.0
		path.add_point(start+forward*radius*sin(a)+right*sign_side*radius*(1.0-cos(a)))
	var middle: Vector3 = path.get_point_position(path.point_count-1)
	for i in range(1,17):
		var a: float = angle*float(i)/16.0
		var longitude: float = radius*(sin(angle)-sin(angle-a))
		var lateral: float = radius*(cos(angle-a)-cos(angle))
		path.add_point(middle+forward*longitude+right*sign_side*lateral)
	var passed: Vector3 = path.get_point_position(path.point_count-1)
	var pass_length: float = _passing_length(passed,forward)
	for i in range(1,ceili(pass_length)+1): path.add_point(passed+forward*minf(float(i),pass_length))
	var returning: Vector3 = path.get_point_position(path.point_count-1)
	for i in range(1,17):
		var a: float = angle*float(i)/16.0
		path.add_point(returning+forward*radius*sin(a)-right*sign_side*radius*(1.0-cos(a)))
	var return_middle: Vector3 = path.get_point_position(path.point_count-1)
	for i in range(1,17):
		var a: float = angle*float(i)/16.0
		path.add_point(return_middle+forward*radius*(sin(angle)-sin(angle-a))-right*sign_side*radius*(cos(angle-a)-cos(angle)))
	path.set_meta("traffic_open",true)
	return path

func _passing_length(passed: Vector3, forward: Vector3) -> float:
	var distance: float = 5.0
	var current: Object = blocker
	var visited: Dictionary = {}
	for i in 5:
		if not is_instance_valid(current) or not current is Node3D or current.get("horizontal_velocity") == null or visited.has(current.get_instance_id()): break
		visited[current.get_instance_id()] = true
		if absf(float(current.get("speed"))) > .3: break
		var radius: float = absf(current.global_basis.z.dot(forward))*float(current.get("half_length"))+absf(current.global_basis.x.dot(forward))*float(current.get("half_width"))
		distance = maxf(distance,(current.global_position-passed).dot(forward)+radius+float(car.half_length)+.6)
		var next: Variant = current.get("blocker")
		if not next is Object: break
		current = next
	return minf(distance,45.0)

func _maneuver_clear(path: Curve3D) -> bool:
	var previous := path.get_point_position(0)
	var previous_yaw: float = car.rotation.y
	if not _pose_clear(previous,previous_yaw): return false
	for i in range(1,path.point_count):
		var point := path.get_point_position(i)
		var direction := previous.direction_to(point)
		var yaw := atan2(-direction.x,-direction.z)
		if not _pose_clear(point,yaw) or not _sweep_clear(previous,point,lerp_angle(previous_yaw,yaw,.5)): return false
		previous = point
		previous_yaw = yaw
	return true

func _tick_bypass(delta: float) -> void:
	var offset: float = _bypass_curve.get_closest_offset(car.global_position)
	var length: float = _bypass_curve.get_baked_length()
	car.route_distance = curve.get_closest_offset(car.global_position)
	car._sense_tick = _bypass_probe-delta <= 0
	car.junction_wait = bool(car._junction_gate(curve.get_baked_length(),true))
	if offset >= length-1.0 and car.global_position.distance_to(_bypass_curve.get_point_position(_bypass_curve.point_count-1)) < 2.0:
		_bypass_curve = null
		lane = 0
		desired_lane = 0
		return
	var target: Vector3 = _bypass_curve.sample_baked(minf(offset+2.0,length),true)
	var toward: Vector3 = target-car.global_position
	toward.y = 0
	var alpha: float = (-car.global_basis.z).signed_angle_to(toward.normalized(),Vector3.UP)
	var steer_goal: float = clampf(atan2(5.0*sin(alpha),maxf(.5,toward.length()))/.48,-1,1)
	_bypass_probe -= delta
	if _bypass_probe <= 0:
		_bypass_probe = .12
		_bypass_ready = _forward_arc_clear(steer_goal)
	look_target = target
	_arc_ready = _bypass_ready
	car.steer_input = steer_goal
	car.brake_input = not _bypass_ready
	desired_speed = 3.0 if _bypass_ready else 0.0
	if car.junction_wait: desired_speed = minf(desired_speed,sqrt(7.0*maxf(0,float(car.junction_gap)-.4)))
	car.brake_input = car.brake_input or desired_speed < .2
	car.throttle_input = clampf((desired_speed-car.speed)*.65,-1,1) if _bypass_ready else 0.0

func _find_bypass(offset: float, look: float) -> float:
	# Same local passing-lane idea as CobraRaceDriver, with production full-hull
	# admission and four supported wheel corners instead of a point-only test.
	var preferred := -signf(hit_side)*3.4 if absf(hit_side) > .1 else -3.4
	for alternative in [preferred,-preferred,preferred*.76,-preferred*.76]:
		if absf(alternative-desired_lane) < .1: continue
		if _lane_path_clear(offset,look,alternative): return alternative
	return INF

func _lane_path_clear(offset: float, look: float, alternative: float) -> bool:
	var at := curve.sample_baked(offset,true)
	var forward := at.direction_to(curve.sample_baked(minf(offset+1,curve.get_baked_length()),true))
	var right := forward.cross(Vector3.UP).normalized()
	var actual_lane: float = (car.global_position-at).dot(right)
	var target: Vector3 = car.global_position+right*(alternative-actual_lane)
	# Validate the whole lateral transition, not only its destination.
	for weight in [.25,.5,.75,1.0]:
		if not _pose_clear(car.global_position.lerp(target,weight),car.rotation.y): return false
	if not _sweep_clear(car.global_position,target,car.rotation.y): return false
	var elevation: float = car.global_position.y-at.y
	for distance in [1.5,3.0,maxf(4.5,look)]:
		var cursor := minf(offset+distance,curve.get_baked_length()-.2)
		var point := curve.sample_baked(cursor,true)
		var direction := point.direction_to(curve.sample_baked(minf(cursor+.2,curve.get_baked_length()),true))
		point += direction.cross(Vector3.UP).normalized()*alternative+Vector3.UP*elevation
		if not _pose_clear(point,atan2(-direction.x,-direction.z)): return false
	return true

func _rear_clear(distance: float) -> bool:
	var end: Vector3 = car.global_position+car.global_basis.z*distance
	for weight in [.25,.5,.75,1.0]:
		if not _pose_clear(car.global_position.lerp(end,weight),car.rotation.y): return false
	return _sweep_clear(car.global_position,end,car.rotation.y)

func _forward_arc_clear(steer_goal: float) -> bool:
	# Predict the same bicycle steering used by Vehicle._drive_player. Each
	# short segment checks full-hull admission, ground and a swept volume.
	var point: Vector3 = car.global_position
	var yaw: float = car.rotation.y
	var wheel: float = car.steering
	for i in 6:
		var distance := .30
		wheel = move_toward(wheel,steer_goal*.48,.24)
		var next_yaw := yaw+distance/2.5*tan(wheel)
		var middle_yaw := lerp_angle(yaw,next_yaw,.5)
		var next_point := point-Basis(Vector3.UP,middle_yaw).z*distance
		if not _pose_clear(next_point,next_yaw) or not _sweep_clear(point,next_point,middle_yaw): return false
		point = next_point
		yaw = next_yaw
	return true

func _pose_clear(point: Vector3, yaw: float) -> bool:
	var supported := _supported_point(point,yaw)
	_supported_pose = supported
	if not supported.is_finite():
		_record_admission_failure("unsupported_ground",point,yaw)
		return false
	var admitted := not placement_validator.is_valid() or bool(placement_validator.call(supported,yaw))
	var basis := Basis(Vector3.UP,yaw)
	_clearance.transform = Transform3D(basis,supported+basis*car.shape.position)
	_clearance.motion = Vector3.ZERO
	var hits: Array[Dictionary] = car.get_world_3d().direct_space_state.intersect_shape(_clearance,1)
	if not hits.is_empty():
		_record_admission_failure("hull_overlap",point,yaw,supported,hits[0].get("collider"))
		return false
	if not admitted:
		_record_admission_failure("production_admission",point,yaw,supported)
		return false
	return true

func _supported_point(point: Vector3, yaw: float) -> Vector3:
	var basis := Basis(Vector3.UP,yaw)
	var space = car.get_world_3d().direct_space_state
	# Keep this local surface detour on supported ground at the current grade;
	# a tunnel roof/floor far below the street is not an admissible passing lane.
	var height := -INF
	_support_count = 0
	for x in [-car.half_width*.8,car.half_width*.8]:
		for z in [-car.half_length*.8,car.half_length*.8]:
			var corner: Vector3 = point+basis*Vector3(x,0,z)
			var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(corner+Vector3.UP*.4,corner-Vector3.UP*.3,1,[car.get_rid()])
			var hit: Dictionary = space.intersect_ray(ray)
			_support_corners[_support_count] = corner
			_support_contacts[_support_count] = hit.get("position",Vector3.INF)
			_support_normals[_support_count] = hit.get("normal",Vector3.ZERO)
			_support_colliders[_support_count] = hit.get("collider")
			_support_count += 1
			if hit.is_empty() or absf(float(hit.position.y)-point.y) > .25: return Vector3.INF
			height = maxf(height,float(hit.position.y))
	# This is only the pose used by admission queries. Vehicle still climbs
	# the real curb ramp through move_and_slide; no body is repositioned.
	return Vector3(point.x,height+.0003,point.z)

func _access_clear(steer_goal: float, target_speed: float) -> bool:
	_admission_failure.clear()
	# A road tangent is not a reachable future yaw. Integrate the same wheel
	# limit/rate and bicycle yaw used by Vehicle._drive_player, then admit the
	# complete supported hull along each short segment of actual forward travel.
	var point: Vector3 = car.global_position
	var yaw: float = car.rotation.y
	var wheel: float = car.steering
	var prediction_speed: float = maxf(.5,maxf(absf(float(car.speed)),target_speed))
	for i in 10:
		var distance: float = .15
		wheel = move_toward(wheel,steer_goal*.48,2.0*distance/prediction_speed)
		var next_yaw: float = yaw+distance/2.5*tan(wheel)
		var middle_yaw: float = lerp_angle(yaw,next_yaw,.5)
		var next_point: Vector3 = point-Basis(Vector3.UP,middle_yaw).z*distance
		_admission_stage = "access_bicycle_pose"
		if not _pose_clear(next_point,next_yaw):
			_admission_failure.predicted_distance = float(i+1)*distance
			_admission_failure.steer_goal = steer_goal
			_admission_failure.predicted_wheel = wheel
			_admission_stage = ""
			return false
		next_point = _supported_pose
		_admission_stage = "access_bicycle_sweep"
		if not _sweep_clear(point,next_point,middle_yaw):
			_admission_failure.predicted_distance = float(i+1)*distance
			_admission_failure.steer_goal = steer_goal
			_admission_failure.predicted_wheel = wheel
			_admission_stage = ""
			return false
		point = next_point
		yaw = next_yaw
	_admission_stage = ""
	return true

func _sweep_clear(start: Vector3, end: Vector3, yaw: float) -> bool:
	var basis := Basis(Vector3.UP,yaw)
	_clearance.transform = Transform3D(basis,start+basis*car.shape.position)
	_clearance.motion = end-start
	var safe: PackedFloat32Array = car.get_world_3d().direct_space_state.cast_motion(_clearance)
	_clearance.motion = Vector3.ZERO
	if safe[0] >= 1.0: return true
	# Query the failed swept pose for evidence; never move the actual vehicle.
	var contact: Vector3 = start+(end-start)*minf(1.0,safe[1]+.001/maxf(.001,start.distance_to(end)))
	_clearance.transform = Transform3D(basis,contact+basis*car.shape.position)
	var hits: Array[Dictionary] = car.get_world_3d().direct_space_state.intersect_shape(_clearance,1)
	var rest: Dictionary = car.get_world_3d().direct_space_state.get_rest_info(_clearance)
	var body: Object = hits[0].get("collider") if not hits.is_empty() else null
	_record_admission_failure("swept_hull",contact,yaw,end,body)
	_admission_failure.sweep_start = str(start)
	_admission_failure.sweep_end = str(end)
	_admission_failure.safe_fraction = safe[0]
	_admission_failure.unsafe_fraction = safe[1]
	_admission_failure.contact_point = str(rest.get("point",Vector3.INF))
	_admission_failure.contact_normal = str(rest.get("normal",Vector3.ZERO))
	return false

func _record_admission_failure(reason: String, point: Vector3, yaw: float, supported: Vector3 = Vector3.INF, body: Object = null) -> void:
	var supports: Array[Dictionary] = []
	for i in _support_count:
		supports.append({"corner":str(_support_corners[i]),"contact":str(_support_contacts[i]),
			"normal":str(_support_normals[i]),"collider":_collider_description(_support_colliders[i])})
	_admission_failure = {"stage":_admission_stage,"reason":reason,"point":str(point),"yaw":yaw,
		"supported_point":str(supported),"collider":_collider_description(body),"supports":supports}

func _collider_description(body: Object) -> Dictionary:
	if not is_instance_valid(body): return {}
	var result := {"id":body.get_instance_id(),"class":body.get_class()}
	if body is Node: result.path = str(body.get_path())
	if body is Node3D: result.position = str(body.global_position)
	if body is CollisionObject3D:
		result.layer = body.collision_layer
		result.mask = body.collision_mask
	return result

func _debug_blocker_chain() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var visited: Dictionary = {}
	var current: Object = blocker
	for i in 5:
		if not is_instance_valid(current): break
		if visited.has(current.get_instance_id()):
			result.append({"cycle_to_id":current.get_instance_id()})
			break
		visited[current.get_instance_id()] = true
		var entry: Dictionary = _collider_description(current)
		if not current is CharacterBody3D or current.get("horizontal_velocity") == null:
			result.append(entry)
			break
		entry.vehicle_id = current.get("vehicle_id")
		entry.speed = current.get("speed")
		entry.velocity = str(current.velocity)
		entry.traffic = current.get("traffic")
		entry.controlled = current.get("controlled")
		entry.external_input = current.get("external_input")
		entry.blocked = current.get("blocked")
		entry.stall_time = current.get("stall_time")
		entry.junction_wait = current.get("junction_wait")
		entry.approach = _waiting_junction_context(current,true)
		entry.held = _debug_leases(current)
		result.append(entry)
		var next: Variant = current.get("blocker")
		if not next is Object: break
		current = next
	return result

func _debug_leases(body: Object) -> Dictionary:
	var result: Dictionary = {"held_key":str(body.get("_held_junction")),"clearing_keys":str(body.get("_clearing_junctions"))}
	var key: Variant = body.get("_held_junction")
	if not key is Vector3i: return result
	var registered: Dictionary = JUNCTIONS.owners.get(key,{})
	result.registered = registered.has(body.get_instance_id())
	result.physically_inside = JUNCTIONS.occupies(key,body.get_instance_id())
	var owners: Array[Dictionary] = []
	for id: int in registered:
		if owners.size() >= 8: break
		var owner: Object = instance_from_id(id) if is_instance_id_valid(id) else null
		var token: Array = registered[id]
		owners.append({"id":id,"vehicle_id":owner.get("vehicle_id") if is_instance_valid(owner) else null,
			"axis_a":token[0],"age_ms":Time.get_ticks_msec()-int(token[1]),"physically_inside":JUNCTIONS.occupies(key,id)})
	result.owners = owners
	return result

func _debug_vehicle_controls() -> Dictionary:
	if not is_instance_valid(car): return {}
	var contacts: Array[Dictionary] = []
	for i in mini(4,car.get_slide_collision_count()):
		var collision: KinematicCollision3D = car.get_slide_collision(i)
		contacts.append({"collider":_collider_description(collision.get_collider()),
			"point":str(collision.get_position()),"normal":str(collision.get_normal())})
	return {"position":str(car.global_position),"velocity":str(car.velocity),"controlled":car.controlled,
		"external_input":car.external_input,"brake":car.brake_input,"throttle":car.throttle_input,"steer":car.steer_input,
		"physics":car.is_physics_processing(),"input_locked":car.input_locked,"engine_disabled":car.engine_disabled,
		"sense_tick":car._sense_tick,"exit_blocked":car._exit_blocked,"exit_wait":car._exit_wait,
		"yaw":car.rotation.y,"wheel_steering":car.steering,
		"junction_wait":car.junction_wait,"junction_gap":car.junction_gap,"held":_debug_leases(car),"contacts":contacts}

func debug_snapshot() -> Dictionary:
	# Called only by a diagnostic/test; normal driving does not serialize nodes.
	var obstacle := {}
	if is_instance_valid(blocker):
		obstacle = {"id":blocker.get_instance_id(),"class":blocker.get_class()}
		if blocker is Node:
			obstacle.path = str(blocker.get_path())
			obstacle.groups = blocker.get_groups()
		if blocker is Node3D: obstacle.position = str(blocker.global_position)
		if blocker is CollisionObject3D:
			obstacle.layer = blocker.collision_layer
			obstacle.mask = blocker.collision_mask
		if blocker is CharacterBody3D and blocker.get("horizontal_velocity") != null:
			obstacle.vehicle_id = blocker.get("vehicle_id")
			obstacle.archetype = blocker.get("archetype")
			obstacle.traffic = blocker.get("traffic")
			obstacle.controlled = blocker.get("controlled")
			obstacle.external_input = blocker.get("external_input")
			obstacle.yaw = blocker.global_rotation.y
			obstacle.velocity = str(blocker.velocity)
			obstacle.horizontal_velocity = str(blocker.get("horizontal_velocity"))
			obstacle.junction_wait = blocker.get("junction_wait")
			obstacle.stall_time = blocker.get("stall_time")
			obstacle.blocked = blocker.get("blocked")
			var next: Variant = blocker.get("blocker")
			obstacle.blocker = str(next.get_path()) if next is Node and next.is_inside_tree() else str(next)
	return {"gap":gap if is_finite(gap) else null,"leader_speed":leader_speed,"holding":holding,
		"waiting_for_traffic":waiting_for_traffic,
		"traffic_wait_expired":traffic_wait_expired,"traffic_wait_seconds":_traffic_wait_seconds,
		"traffic_wait_limit":_traffic_wait_limit,"traffic_wait_phase_changes":_traffic_wait_phase_changes,
		"traffic_green_seconds":float(Time.get_ticks_msec()-_traffic_green_started)/1000.0 if _traffic_green_started > 0 else 0,
		"traffic_wait_context":_traffic_wait_context.duplicate(true),
		"admission_failure":_admission_failure.duplicate(true),
		"vehicle_controls":_debug_vehicle_controls(),"blocker_chain":_debug_blocker_chain(),
		"crossing_yield":{"active":_yielding,"attempts":_yield_attempts,"completed":_yield_completed,
			"key":str(_yield_key),"owner":_collider_description(_yield_owner),"owner_progress":_yield_owner_progress,
			"reverse_distance":_reverse_distance,"pair_age":_yield_block_age,"sensor_lease_grants":_sensor_lease_grants,
			"extra_reverse":_yield_extra_reverse,
			"sensor_lease_preview":_sensor_lease_diagnostic.duplicate(true)},
		"access_ready":access_ready,"bypass_arc_clear":_arc_ready,"bypass_plan_active":_bypass_curve != null,
		"lane":lane,"desired_lane":desired_lane,"recoveries":recoveries,"blocked_age":_blocked_age,"reverse_remaining":_reverse_remaining,"reverse_distance":_reverse_distance,
		"planned_radius":_planned_radius,
		"desired_speed":desired_speed,"look_target":str(look_target),"ray_origin":str(ray_origin),
		"hit_position":str(hit_position),"hit_normal":str(hit_normal),"hit_side":hit_side,"blocker":obstacle}
