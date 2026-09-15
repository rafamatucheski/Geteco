extends Node
## A single timeline keeps doors, both medics, cot and the actual patient together.
var ambulance: Node2D
var patient: CharacterBody2D
var crew: Array = []
var phase := "exit"
var elapsed := 0.0
var phase_time := 0.0
var stretcher: CharacterBody2D
var carrying := false
var delivered := false
var nav := preload("res://emergency/ResponderNavigation.gd").new()
var _entry_start := Vector2.ZERO
var _boarded := [false, false]
var hospital: Node2D
var hospital_delivery := false
var admitted := false
var _return_waypoint := [0, 0]
var work_zone: StaticBody2D
var formation := preload("res://emergency/MedicalFormationNavigation.gd").new()
var _service_goals: Array[Vector3] = []
var _service_index := 0
var _no_progress := 0.0
var _progress_pose := Vector3.INF
var _retreating := false
var _owns_patient := false
var _parking_route: Array[Vector2] = []
var _parking_route_index := 1
var danger := preload("res://emergency/RescueDanger.gd").new()

func hear_gunfire(origin: Vector2, end: Vector2) -> void:
	danger.hear(self, origin, end)
	for medic in crew:
		if is_instance_valid(medic): medic.danger_response.remember(origin, end)

func setup(unit: Node2D, target: CharacterBody2D, medics: Array) -> void:
	ambulance = unit
	patient = target
	crew = medics
	_parking_route.assign(unit.get_meta("ambulance_walk_route", []))
	unit.remove_meta("medical_abort_reason")
	unit.remove_meta("medical_abort_phase")
	unit.set_meta("medical_sequence", self)
	unit.set_meta("medical_phase", phase)
	_owns_patient = get_node("/root/NPCMedicalCare").claim_patient(patient, unit, self)
	for medic in crew:
		medic.set_meta("medical_managed", true)
		medic.set_meta("medical_collision_layer", medic.collision_layer)
		medic.set_meta("medical_collision_mask", medic.collision_mask)
		medic.velocity = Vector2.ZERO
		medic.z_index = unit.z_index - 1
		if medic.stretcher_mesh: medic.stretcher_mesh.hide()
		if medic.medical_kit: medic.medical_kit.hide()
		if unit.visual_3d: unit.visual_3d.open_door(medic.crew_side)
	work_zone = preload("res://emergency/MedicalRescueWorkZone.gd").new()
	unit.get_parent().add_child(work_zone)
	work_zone.sync(self)
	var depth := preload("res://emergency/MedicalOutdoorDepth.gd").new()
	depth.sequence = self
	add_child(depth)
	if not _owns_patient: _abort.call_deferred("patient_claim_failed")

func rear_point() -> Vector2:
	# Offset parking must not shorten extraction and trap the front handle
	# against the bumper. Reserve parking supplies the extra facade clearance.
	var distance := 78.0
	if not hospital_delivery: distance = preload("res://emergency/AmbulanceApproach.gd").rear_distance(ambulance)
	return ambulance.to_global(Vector2(-distance, 0))

func _set_phase(next: String) -> void:
	phase = next
	phase_time = 0
	formation.reset()
	_no_progress = 0.0
	_progress_pose = Vector3.INF
	if next == "crew_return": _return_waypoint = [0, 0]
	if next == "return_with_patient": _parking_route_index = _parking_route.size()-2
	ambulance.set_meta("medical_phase", phase)
	if is_instance_valid(work_zone): work_zone.sync(self)

func _physics_process(delta: float) -> void:
	if is_instance_valid(work_zone): work_zone.sync(self)
	if not is_instance_valid(ambulance) or ambulance.is_broken or not ambulance.visible or not is_instance_valid(patient):
		_abort("vehicle_or_patient_unavailable")
		return
	var care := get_node("/root/NPCMedicalCare")
	if patient.get("is_dead") == true:
		_abort("confirmed_death")
		care.report_injury(patient)
		care.witness_called(patient)
		return
	var identity: String = patient.get_meta("medical_identity", "")
	if care.incidents.has(identity) and care.incidents[identity].phase == "fading":
		_abort("patient_cleanup")
		return
	for i in crew.size():
		if _boarded[i]: continue
		if not is_instance_valid(crew[i]) or crew[i].is_dead:
			_abort("crew_lost")
			return
	if danger.update(self, delta): return
	elapsed += delta
	phase_time += delta
	if elapsed > 160 and phase not in ["transport", "access_blocked"]:
		_blocked("sequence_timeout")
		return
	if phase_time > 18 and phase in ["exit", "fetch", "take_handles", "take_loaded_handles", "crew_return", "crew_boarding"]:
		_blocked("crew_access_blocked")
		return
	match phase:
		"exit":
			var ready := phase_time >= .5
			for i in 2:
				var medic: CharacterBody2D = crew[i]
				if phase_time < .35 + i * .18:
					ready = false
					continue
				if not _move(medic, ambulance.get_crew_exit_point(medic.crew_side, 8), delta, 37): ready = false
			if ready:
				for medic in crew:
					medic.remove_collision_exception_with(ambulance)
					ambulance.visual_3d.close_door(medic.crew_side)
				_set_phase("close_front")
		"close_front":
			if phase_time >= .45: _set_phase("fetch")
		"fetch":
			if _pair_to(rear_point(), delta, false):
				ambulance.visual_3d.set_rear_doors(true)
				# The bay is a close transfer: the cot's leading end reaches the
				# vestibule as soon as it clears the ambulance, so open that door
				# before unloading rather than walking a medic through glass.
				if hospital_delivery: hospital.set_emergency_door_open(true)
				_set_phase("open_rear")
		"open_rear":
			if phase_time >= .8:
				var owner_node := ambulance.get_parent()
				var start := ambulance.to_global(Vector2(-22, 0))
				if not is_instance_valid(stretcher):
					stretcher = preload("res://emergency/MedicalStretcher.gd").new()
					stretcher.position = owner_node.to_local(start) if owner_node is Node2D else start
					owner_node.add_child(stretcher)
				stretcher.global_position = start
				stretcher.heading = ambulance.global_rotation
				stretcher.orient(Vector2.ZERO)
				stretcher.z_index = ambulance.z_index - 2
				stretcher.add_collision_exception_with(ambulance)
				for medic in crew:
					stretcher.add_collision_exception_with(medic)
					medic.add_collision_exception_with(stretcher)
				_entry_start = stretcher.global_position
				stretcher.show()
				if hospital_delivery:
					stretcher.update_patient()
					patient.show()
				_set_phase("unload_stretcher")
		"unload_stretcher":
			if not _slide_cot(rear_point(), delta, 28):
				if hospital_delivery: stretcher.update_patient()
				_pair_to(rear_point(), delta, false)
				if phase_time > 8: _blocked("rear_unloading_blocked")
				return
			if hospital_delivery: stretcher.update_patient()
			_pair_to(rear_point(), delta, false)
			if phase_time >= 2.1:
				ambulance.visual_3d.set_rear_doors(false)
				stretcher.remove_collision_exception_with(ambulance)
				_set_phase("take_handles")
		"take_handles":
			if _pair_to(stretcher.global_position, delta):
				_set_phase("hospital_approach" if hospital_delivery else "approach_patient")
		"approach_patient":
			if _service_goals.is_empty(): _find_service_goals()
			if _service_index >= _service_goals.size():
				_blocked("patient_inaccessible")
				return
			var station := _service_goals[_service_index]
			var goal := _parking_waypoint(Vector2(station.x,station.y), false)
			var angle := station.z if goal.distance_to(Vector2(station.x,station.y)) < .1 else INF
			if _move_stretcher(goal, delta, angle) and stretcher.global_position.distance_to(patient.global_position) <= 38:
				_set_phase("treat")
		"treat":
			if not _pair_to(stretcher.global_position, delta):
				phase_time = 0
				return
			for medic in crew: _care_pose(medic, minf(1, phase_time / .6), delta)
			if phase_time >= 2.8:
				if not get_node("/root/NPCMedicalCare").begin_carry(patient, ambulance, self):
					_abort("patient_claim_failed")
					return
				stretcher.load_patient(patient)
				carrying = true
				_set_phase("lift_patient")
		"lift_patient":
			stretcher.update_patient(phase_time / 2.4)
			for medic in crew: _care_pose(medic, 1.0 - smoothstep(.3, 2.4, phase_time), delta)
			if phase_time >= 2.4: _set_phase("take_loaded_handles")
		"take_loaded_handles":
			stretcher.update_patient()
			if _pair_to(stretcher.global_position, delta): _set_phase("return_with_patient")
		"return_with_patient":
			if _move_stretcher(_parking_waypoint(rear_point(), true), delta) and stretcher.global_position.distance_to(rear_point()) < 4: _set_phase("align_to_load")
		"align_to_load":
			var angle: float = ambulance.global_rotation
			if absf(angle_difference(stretcher.heading,angle)) > PI*.5: angle += PI
			if absf(angle_difference(stretcher.heading,angle)) > .01:
				_move_stretcher(rear_point(), delta, angle)
				return
			stretcher.update_patient()
			var ready := _pair_to(stretcher.global_position, delta, false)
			var alignment := absf(angle_difference(stretcher.heading, ambulance.global_rotation))
			if ready and minf(alignment, absf(PI - alignment)) < .025:
				ambulance.visual_3d.set_rear_doors(true)
				_set_phase("open_to_load")
		"open_to_load":
			stretcher.update_patient()
			if phase_time >= .8:
				_entry_start = stretcher.global_position
				_set_phase("load_patient")
		"load_patient":
			# Keep one depth for the complete slide: the bodywork naturally masks
			# the cot instead of swapping its z-index halfway through the door.
			stretcher.add_collision_exception_with(ambulance)
			if not _slide_cot(ambulance.to_global(Vector2(-18, 0)), delta, 25):
				stretcher.update_patient()
				if phase_time > 8: _blocked("rear_loading_blocked")
				return
			stretcher.update_patient()
			_pair_to(rear_point() + ambulance.global_transform.x * minf(12, phase_time * 5), delta, false)
			if phase_time >= 2.4:
				if carrying and not admitted:
					get_node("/root/NPCMedicalCare").board_patient(patient, ambulance)
					delivered = true
				stretcher.hide()
				ambulance.visual_3d.set_rear_doors(false)
				_set_phase("close_rear")
		"close_rear":
			if phase_time >= .8: _set_phase("crew_return")
		"crew_return":
			var ready := true
			for i in crew.size():
				if not _return_around_rear(i, delta): ready = false
			if ready:
				for i in 2:
					crew[i].add_collision_exception_with(ambulance)
					ambulance.visual_3d.open_door(crew[i].crew_side)
				_set_phase("crew_boarding")
		"crew_boarding":
			for i in 2:
				if _boarded[i] or phase_time < .4 + i * .2: continue
				var medic: CharacterBody2D = crew[i]
				var point: Vector2 = ambulance.get_crew_spawn_point(medic.crew_side, 8)
				if _move(medic, point, delta, 30):
					_boarded[i] = true
					ambulance.visual_3d.close_door(medic.crew_side)
					medic.hide()
					medic.set_deferred("collision_layer", 0)
					medic.set_deferred("collision_mask", 0)
					if not hospital_delivery: ambulance.on_paramedic_embarked(medic)
			if _boarded[0] and _boarded[1]:
				if _retreating:
					for medic in crew: medic.queue_free()
					queue_free()
				elif hospital_delivery:
					_finish_hospital()
				else:
					_set_phase("transport")
		"hospital_approach":
			# The old +17 station fitted the cot centre but placed the leading
			# medic inside the ambulance's rear hull. Use the actual doorway.
			if _move_stretcher(hospital.get_admission_door_position(), delta):
				hospital.set_emergency_door_open(true)
				_set_phase("hospital_open")
		"hospital_open":
			if phase_time >= .7: _set_phase("hospital_inside")
		"hospital_inside":
			if _move_stretcher(hospital.get_admission_inside_position(), delta):
				# No hidden hand-off on the street: the same patient crosses the
				# threshold before becoming an inpatient.
				patient.hide()
				stretcher.release_patient()
				carrying = false
				admitted = true
				get_node("/root/NPCMedicalCare").complete_hospital_admission(patient, ambulance)
				_set_phase("hospital_handoff")
		"hospital_handoff":
			# Admission is the terminal handoff: both attendants and the cot
			# are inside the vestibule. No second outdoor loading cycle can
			# hold the shared entrance or restart an already completed rescue.
			if phase_time >= 2.5: _finish_hospital()
		"hospital_return_cot":
			if _move_stretcher(rear_point(), delta):
				_set_phase("align_to_load")
		"access_blocked":
			for medic in crew: _move(medic, medic.global_position, delta, 0)
	danger.finish_pose(self)
	for medic in crew:
		if is_instance_valid(medic):
			medic.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if medic.is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _parking_waypoint(goal: Vector2, returning: bool) -> Vector2:
	if hospital_delivery or _parking_route.is_empty(): return goal
	if returning:
		if _parking_route_index <= 0: return goal
		if stretcher.global_position.distance_to(_parking_route[_parking_route_index]) < 6: _parking_route_index -= 1
	else:
		if _parking_route_index >= _parking_route.size()-1: return goal
		if stretcher.global_position.distance_to(_parking_route[_parking_route_index]) < 6: _parking_route_index += 1
	return _parking_route[_parking_route_index]

func _pair_to(point: Vector2, delta: float, handles := true) -> bool:
	var ready := true
	var axis: Vector2 = Vector2.from_angle(stretcher.heading) if is_instance_valid(stretcher) else ambulance.global_transform.x
	for i in 2:
		var side_distance := 13.0 if hospital_delivery else 19.0
		var offset := axis * (25 if i == 0 else -25) if handles else axis.orthogonal() * side_distance * (1 if i == 0 else -1)
		if not _move(crew[i], point + offset, delta, 62, handles): ready = false
	return ready

func _move(medic: CharacterBody2D, point: Vector2, delta: float, speed := 72.0, hands := false) -> bool:
	var direction := point - medic.global_position
	var ready := direction.length() < (.2 if hands else 3.0)
	medic.velocity = Vector2.ZERO if ready else medic._navigate_towards(point, speed, delta)
	var before := medic.global_position
	medic.move_and_slide()
	var facing := direction
	if hands and is_instance_valid(stretcher): facing = stretcher.global_position - medic.global_position
	_animate_move(medic,(medic.global_position-before)/maxf(delta,.001),facing,delta,hands)
	return ready

func _animate_move(medic: CharacterBody2D, motion: Vector2, facing: Vector2, delta: float, hands: bool) -> void:
	medic.velocity = motion
	medic.torso_node.rotation.x = lerpf(medic.torso_node.rotation.x,0,minf(1,delta*8))
	if facing.length_squared() > .01:
		medic.model_root.rotation.y = lerp_angle(medic.model_root.rotation.y, -facing.angle() - PI * .5, minf(1, delta * 7))
	medic.walk_clock += motion.length()*delta*.15
	var step := sin(medic.walk_clock) * .36 * clampf(motion.length() / 62, 0, 1)
	medic.left_upper_leg.rotation.x = lerpf(medic.left_upper_leg.rotation.x, step, minf(1, delta * 12))
	medic.right_upper_leg.rotation.x = lerpf(medic.right_upper_leg.rotation.x, -step, minf(1, delta * 12))
	medic.left_lower_leg.rotation.x = maxf(0, -step * .8)
	medic.right_lower_leg.rotation.x = maxf(0, step * .8)
	medic.left_upper_arm.rotation.x = lerpf(medic.left_upper_arm.rotation.x,  .8 if hands else step * .6, minf(1, delta * 8))
	medic.right_upper_arm.rotation.x = lerpf(medic.right_upper_arm.rotation.x,  .8 if hands else -step * .6, minf(1, delta * 8))
	medic.left_lower_arm.rotation.x = lerpf(medic.left_lower_arm.rotation.x, .55 if hands else 0.0, minf(1, delta * 8))
	medic.right_lower_arm.rotation.x = lerpf(medic.right_lower_arm.rotation.x, .55 if hands else 0.0, minf(1, delta * 8))
	medic.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _care_pose(medic: CharacterBody2D, amount: float, delta: float) -> void:
	medic.torso_node.rotation.x = .45 * amount
	medic.left_upper_arm.rotation.x = 1.05 * amount
	medic.right_upper_arm.rotation.x = 1.05 * amount + sin(elapsed * 3) * .06 * amount
	medic.left_upper_leg.rotation.x = -.32 * amount
	medic.right_upper_leg.rotation.x = -.32 * amount
	medic.left_lower_leg.rotation.x = .65 * amount
	medic.right_lower_leg.rotation.x = .65 * amount
	medic.model_root.rotation.y = lerp_angle(medic.model_root.rotation.y, -(patient.global_position - medic.global_position).angle() - PI * .5, minf(1, delta * 6))
	medic.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _return_around_rear(index: int, delta: float) -> bool:
	var medic: CharacterBody2D = crew[index]
	var exit_point: Vector2 = ambulance.get_crew_exit_point(medic.crew_side, 8)
	var half_length := 45.0
	var shape: CollisionShape2D = ambulance.get_node_or_null("CollisionShape2D")
	if shape and shape.shape is RectangleShape2D: half_length = shape.shape.size.x * .5
	# Axis-aligned corners preserve a walkable gap behind the body; a single
	# diagonal target asked the coarse navigation grid to cut this corner.
	var rear_x := -half_length - 12.0
	var outside_side := ambulance.to_local(exit_point).y
	var points := [ambulance.to_global(Vector2(rear_x, medic.crew_side * 13)), ambulance.to_global(Vector2(rear_x, outside_side)), exit_point]
	var stage: int = _return_waypoint[index]
	if stage >= points.size(): return true
	if _move(medic, points[stage], delta, 56): _return_waypoint[index] += 1
	return _return_waypoint[index] >= points.size()

func _move_stretcher(point: Vector2, delta: float, heading: float = INF) -> bool:
	var direction := point - stretcher.global_position
	if _wait_for_rail(direction):
		elapsed -= delta
		stretcher.velocity = Vector2.ZERO
		for medic in crew: _move(medic, medic.global_position, delta, 0, true)
		return false
	formation.configure(stretcher, crew)
	var at := formation.pose()
	var ready := true
	for i in 2:
		if crew[i].global_position.distance_to(formation.handles(at,i)) > .3: ready = false
	if not ready:
		_pair_to(stretcher.global_position, delta)
	else:
		var next := formation.next_pose(point,heading,delta,39 if carrying else 46)
		# All participants pass the same swept preflight before anybody moves.
		var clear := true
		for i in 2:
			if crew[i].test_move(crew[i].global_transform,formation.handles(next,i)-crew[i].global_position): clear = false
		if clear:
			stretcher.move_and_collide(Vector2(next.x,next.y)-stretcher.global_position)
			stretcher.set_heading(next.z)
			for i in 2:
				var medic: CharacterBody2D = crew[i]
				var before := medic.global_position
				medic.move_and_collide(formation.handles(next,i)-before)
				_animate_move(medic,(medic.global_position-before)/maxf(delta,.001),stretcher.global_position-medic.global_position,delta,true)
		else: formation.reset()
	if carrying: stretcher.update_patient()
	if _progress_pose == Vector3.INF or formation._distance(_progress_pose,formation.pose()) > 3:
		_progress_pose = formation.pose()
		_no_progress = 0
	else: _no_progress += delta
	if _no_progress > 4 and phase == "approach_patient":
		if not _parking_route.is_empty(): _parking_route.clear()
		else: _service_index += 1
		formation.reset()
		_no_progress = 0
	if _no_progress > 4 and phase == "return_with_patient" and not _parking_route.is_empty():
		_parking_route.clear()
		formation.reset()
		_no_progress = 0
	if _no_progress > 12: _blocked("formation_route_blocked")
	return ready and direction.length() < .3 and (not is_finite(heading) or absf(angle_difference(stretcher.heading,heading)) < .01)

func _slide_cot(point: Vector2, delta: float, speed: float) -> bool:
	formation.configure(stretcher,crew)
	var from := formation.pose()
	var motion := (point-stretcher.global_position).limit_length(speed*delta)
	var to := from + Vector3(motion.x,motion.y,0)
	if not formation.clear_motion(from,to,false): return false
	stretcher.move_and_collide(motion)
	return stretcher.global_position.distance_to(point) < .2

func _find_service_goals() -> void:
	formation.configure(stretcher,crew)
	var excluded: Array[RID] = [patient.get_rid(),stretcher.get_rid()]
	for medic in crew: excluded.append(medic.get_rid())
	for i in 16:
		var radial := Vector2.from_angle(i*TAU/16)
		var point: Vector2 = patient.global_position + radial*27
		var ray := PhysicsRayQueryParameters2D.create(point,patient.global_position,3,excluded)
		if not patient.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
		for angle in [stretcher.heading, radial.angle()+PI*.5]:
			var at := Vector3(point.x,point.y,angle)
			if formation.clear_motion(at,at): _service_goals.append(at)
	_service_goals.sort_custom(func(a: Vector3,b: Vector3): return formation._distance(formation.pose(),a)<formation._distance(formation.pose(),b))
	if _service_goals.size() > 4: _service_goals.resize(4)

func _blocked(reason: String) -> void:
	ambulance.set_meta("medical_abort_reason",reason)
	ambulance.set_meta("medical_abort_phase",phase)
	if not carrying and not hospital_delivery and not _retreating:
		get_node("/root/NPCMedicalCare").defer_inaccessible(patient,ambulance,reason)
		_owns_patient = false
		_retreating = true
		elapsed = 0.0
		if is_instance_valid(stretcher): _set_phase("return_with_patient")
		else: _set_phase("crew_return")
	else:
		# Terminal, observable failure. Do not despawn/drive away with crew outside.
		_set_phase("access_blocked")
		set_physics_process(false)

func _wait_for_rail(direction: Vector2) -> bool:
	for crossing in get_tree().get_nodes_in_group("rail_level_crossing"):
		if not crossing.has_method("should_stop_vehicle") or not crossing.should_stop_vehicle(): continue
		var at: Vector2 = crossing.to_local(stretcher.global_position)
		var travel: Vector2 = crossing.global_transform.basis_xform_inv(direction)
		if absf(at.y) > float(crossing.road_width) * .5 + 35: continue
		# The lead responder must still be outside the gate when the entire
		# team stops. A team already committed clears the track together.
		var outside := absf(at.x) - float(crossing.gate_offset)
		if outside >= 30 and outside < 95 and travel.x * at.x < 0: return true
	return false

func finish_transport_without_entrance() -> void:
	if is_instance_valid(stretcher): stretcher.release_patient()
	for medic in crew:
		if is_instance_valid(medic): medic.queue_free()
	queue_free()

func start_hospital_admission(entrance: Node2D) -> void:
	hospital = entrance
	hospital_delivery = true
	if ambulance.siren_audio: ambulance.siren_audio.stop()
	elapsed = 0
	_boarded = [false, false]
	ambulance.is_returning_to_base = false
	ambulance.is_acting = true
	ambulance.current_speed = 0
	ambulance.velocity = Vector2.ZERO
	ambulance.set_meta("hospital_unloading", true)
	for medic in crew:
		medic.global_position = ambulance.get_crew_spawn_point(medic.crew_side, 8)
		medic.reset_physics_interpolation()
		medic.set_deferred("collision_layer", medic.get_meta("medical_collision_layer"))
		medic.set_deferred("collision_mask", medic.get_meta("medical_collision_mask"))
		medic.show()
		medic.add_collision_exception_with(ambulance)
		ambulance.visual_3d.open_door(medic.crew_side)
	_set_phase("exit")

func _finish_hospital() -> void:
	hospital.set_emergency_door_open(false)
	preload("res://audio/police_dispatch/EmergencyServiceRadio.gd").play_at(ambulance, &"medical_admission")
	_set_phase("parked")
	ambulance.finish_hospital_parking()
	for medic in crew:
		if is_instance_valid(medic): medic.queue_free()
	queue_free()

func _abort(reason := "interrupted") -> void:
	if is_instance_valid(ambulance):
		ambulance.set_meta("medical_abort_reason", reason)
		ambulance.set_meta("medical_abort_phase", phase)
	if is_instance_valid(stretcher): stretcher.release_patient()
	var claim_valid := false
	if is_instance_valid(patient):
		var care := get_node("/root/NPCMedicalCare")
		var incident: Dictionary = care.incidents.get(patient.get_meta("medical_identity",""),{})
		claim_valid = incident.get("unit") == ambulance
	if claim_valid and carrying and not admitted and is_instance_valid(patient):
		get_node("/root/NPCMedicalCare").retry_patient(patient, patient.global_position if not delivered or hospital_delivery else null)
	elif claim_valid and _owns_patient and not delivered and not admitted and is_instance_valid(patient):
		get_node("/root/NPCMedicalCare").retry_patient(patient, patient.global_position)
	if is_instance_valid(hospital): hospital.set_emergency_door_open(false)
	if is_instance_valid(ambulance):
		ambulance.set_meta("hospital_unloading", false)
		var director := _assigned_director()
		if director and director.has_method("release_medical_admission"): director.release_medical_admission(ambulance)
	for medic in crew:
		if is_instance_valid(medic) and not medic.is_dead:
			if is_instance_valid(stretcher): medic.remove_collision_exception_with(stretcher)
			if not medic.visible:
				medic.queue_free()
				continue
			medic.remove_meta("medical_managed")
			medic.torso_node.rotation.x = 0
			medic._start_return_to_ambulance()
	queue_free()

func _assigned_director() -> Node:
	if not is_instance_valid(ambulance): return null
	var owner_id := int(ambulance.get_meta("harbor_director_id", 0))
	if owner_id != 0:
		var owner := instance_from_id(owner_id)
		if is_instance_valid(owner): return owner
	for director in get_tree().get_nodes_in_group("emergency_depot_director"):
		if director._vehicle_assignments.has(ambulance.get_instance_id()): return director
	return null

func _exit_tree() -> void:
	if is_instance_valid(work_zone): work_zone.detach_sequence()
	for medic in crew:
		if is_instance_valid(medic) and is_instance_valid(stretcher): medic.remove_collision_exception_with(stretcher)
	if is_instance_valid(stretcher): stretcher.queue_free()
	if is_instance_valid(ambulance):
		ambulance.remove_meta("medical_sequence")
		ambulance.remove_meta("medical_threat")
		ambulance.remove_meta("medical_threat_response")
		if ambulance.visual_3d:
			ambulance.visual_3d.set_rear_doors(false)
			for side in [-1.0, 1.0]: ambulance.visual_3d.close_door(side)
