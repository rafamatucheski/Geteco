extends Node3D
## One physical heat and one waiting pair. Player admission reserves the strip;
## no background heat can overlap a player attempt. Everything is visit-owned.
const ROSTER = preload("res://activities/desert_drag/DragOpenRoster.gd")
const DRIVE = preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const AUDIO = preload("res://audio/desert_cars/DesertCarAudio.gd")
const DRIVER = preload("res://activities/desert_drag/DesertDragDriver.gd")
const SIGNALS = preload("res://activities/desert_drag/DesertDragSignals.gd")
const LAYOUT = preload("res://world/desert/DesertLayout.gd")
const MAX_CARS := 6
signal changed
var race
var session
var enabled := true
var heat: Array[Dictionary] = []
var waiting: Array[Dictionary] = []
var transit: Array[Dictionary] = []
var loaned: Dictionary = {}
var phase := "idle"
var clock := 0.0
var admission_clock := 0.0
var visitor_serial := 0
var heats_completed := 0
var pending := ""
var heats_ahead := 0
var registered_car: Node3D
var dispatching := false
var ready_clock := 0.0
var skip_current_heat := false
var last_admission_reason := ""
var blocked_phase := ""
var recovery_clock := 0.0
var _was_on_foot := false
var signals: Node3D
var status_layer: CanvasLayer
var status: Label

func configure(owner_race) -> void:
	race = owner_race
	session = race.session
	name = "OpenDragMeet"
	process_physics_priority = -4

func track_busy() -> bool:
	return not heat.is_empty()

func ticket() -> Dictionary:
	return {"queued":not pending.is_empty(),"position":1+heats_ahead if not pending.is_empty() else 0,
		"number":int(registered_car.get_meta("drag_entry_number",27)) if is_instance_valid(registered_car) else 27,
		"rival":pending,"heat":phase,"racing":track_busy(),"waiting":waiting.size(),
		"reason":last_admission_reason,"on_foot":not session.world.driving.occupied}

func request(identity: String, join_queue: bool) -> bool:
	if not enabled or race.active or not pending.is_empty() or not race.can_race(identity): return false
	var reason: String = race.start_block_reason()
	last_admission_reason = reason
	if not reason.is_empty(): session.show_message(reason); return false
	registered_car = session.world.driving.car
	ROSTER.attach_number(registered_car,27)
	pending = identity
	# Position one is the next opening after the current heat; position two
	# permits exactly one waiting NPC pair first. Never grow an unbounded queue.
	heats_ahead = 1 if join_queue else 0
	skip_current_heat = not heat.is_empty()
	ready_clock = 0.0
	_refresh()
	session.show_message("Inscrição #27 · %dª posição. Pode esperar a pé; volte ao seu carro quando chamado."%(1+heats_ahead))
	return true

func cancel_ticket(notify := true, reason := "Inscrição na fila cancelada.") -> void:
	if pending.is_empty(): return
	if race.has_method("cancel_waiting_context"): race.cancel_waiting_context(reason)
	pending = ""
	heats_ahead = 0
	ready_clock = 0.0
	last_admission_reason = ""
	_clear_registration_number()
	_refresh()
	if notify: session.show_message(reason)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(session) or not session.ready_for_play: return
	var here: bool = enabled and session.state.region_id=="desert" and session.state.place_id.is_empty()
	var observer: Vector3 = session.world.player.global_position
	var along: float = clampf(race._offset(observer),-160.0,1010.0)
	here = here and observer.distance_to(race.start_point+race.direction*along)<180.0
	if not here or session.world.gameplay.health<=0 or session.rescue_pending or session.arrest_pending:
		clear_visit(); return
	if session.modal or session.get_tree().paused or session.is_transition_blocked(): return
	if session.world.gameplay.stars>0:
		clear_visit(); return
	if not pending.is_empty():
		if not is_instance_valid(registered_car) or registered_car.health<=0 or registered_car.engine_disabled:
			cancel_ticket(true,"Inscrição cancelada: o carro inscrito não pode correr.")
		elif session.world.driving.occupied and session.world.driving.car!=registered_car:
			cancel_ticket(true,"Inscrição cancelada: você trocou de carro.")
		elif _was_on_foot == session.world.driving.occupied:
			_was_on_foot = not session.world.driving.occupied
			_refresh()
	if not _healthy():
		clear_visit(); return
	_advance_transit(delta)
	if race.active: return
	admission_clock -= delta
	if admission_clock<=0 and heat.size()+waiting.size()+transit.size()<MAX_CARS:
		admission_clock = 1.5
		_admit()
	if heat.is_empty() and not pending.is_empty() and heats_ahead==0:
		_dispatch(delta)
		return
	if heat.is_empty():
		if waiting.size()==2: _promote()
		return
	clock += delta
	if phase=="blocked":
		_try_resume_blocked(delta)
		return
	if phase=="lining":
		var lined := true
		for i in heat.size():
			var entry: Dictionary = heat[i]
			var remaining: float = -race._offset(entry.car.global_position)
			entry.car.rotation.y = rotate_toward(entry.car.rotation.y,race.grid(i).basis.get_euler().y,delta*2.0)
			entry.drive.speed_mps = minf(3.0,maxf(0.0,remaining/maxf(delta,.001)))
			race._move_car(entry,delta)
			lined = lined and remaining<.08
		if lined:
			for entry in heat:
				entry.drive.speed_mps = 0.0
				entry.car.speed = 0.0
				entry.car.velocity = Vector3.ZERO
			phase = "staging"; clock = 0.0
			_refresh()
	elif phase=="staging":
		for entry in heat: entry.drive.stage(delta,.53)
		signals.set_countdown(2.5-clock)
		if clock>=2.5:
			for entry in heat: entry.drive.launch()
			phase = "racing"; clock = 0.0
			_refresh()
	elif phase=="racing":
		for entry in heat:
			var drive = entry.drive
			if is_finite(float(entry.finish)):
				race._step_runoff(entry,delta,800.0)
			else:
				if drive.rpm>=drive.ideal_shift_rpm: drive.shift_up()
				drive.step(delta,1.0 if clock>.24 else 0.0,false)
			race._move_car(entry,delta)
			if race._offset(entry.car.global_position)>=800.0 and not is_finite(float(entry.finish)): entry.finish = clock
		if heat.all(func(e): return is_finite(float(e.finish)) and e.drive.speed_mps<.15):
			phase = "finished"
			_refresh()
	if phase=="finished":
		_release_heat()
	# Keep the physical heat and the player's place while the obstruction is
	# present. Recovery never teleports a car or awards a fictional finish.
	elif clock>45.0 and phase in ["lining","racing"]:
		blocked_phase = phase
		phase = "blocked"
		recovery_clock = 0.0
		for entry in heat:
			entry.drive.speed_mps = 0.0
			entry.car.speed = 0.0
			entry.car.velocity = Vector3.ZERO
			entry.car.throttle_input = 0.0
			entry.car.brake_input = true
		last_admission_reason = "Pista obstruída · sua posição está reservada."
		_refresh()

func _try_resume_blocked(delta: float) -> void:
	for entry in heat: entry.drive.follow_external_motion(0.0,0.0,delta)
	recovery_clock -= delta
	if recovery_clock>0.0: return
	recovery_clock = .5
	for entry in heat:
		if is_finite(float(entry.finish)): continue
		if entry.car.test_move(entry.car.global_transform,race.direction*.8): return
	phase = blocked_phase if blocked_phase in ["lining","racing"] else "lining"
	blocked_phase = ""
	clock = 0.0
	for entry in heat:
		if not is_finite(float(entry.finish)): entry.drive.gear = 1
	last_admission_reason = ""
	_refresh()

func _healthy() -> bool:
	for entry in heat+waiting+transit:
		if not is_instance_valid(entry.car) or entry.car.health<=0 or entry.car.engine_disabled: return false
		if session.world.driving.car==entry.car and session.world.driving.occupied: return false
	return true

func _admit() -> void:
	var path: Array[Vector3] = []
	for road in LAYOUT.roads():
		if str(road.id)!="desert_drag_access": continue
		for point in road.points:
			if point.x>=-1100.0: path.append(Vector3(point.x,.08,point.z))
	if path.size()<2 or not _point_out_of_view(path[0],90.0): return
	if (heat+waiting+transit).any(func(e): return e.car.global_position.distance_to(path[0])<10.0): return
	var identity: String = ROSTER.IDS[visitor_serial%ROSTER.IDS.size()]
	var pose := Transform3D(Basis.looking_at(path[1]-path[0],Vector3.UP),path[0])
	var region = session.world.production.regions.get("desert")
	if not is_instance_valid(region) or not region.prepare_collision_at(pose.origin): return
	var car = session.world.production.spawn_vehicle(str(ROSTER.CARS[identity].car),pose.origin,pose.basis.get_euler().y)
	if not is_instance_valid(car): return
	if car.get_meta("awaiting_ground",false) or not session.world.production.vehicle_position_clear(car,pose.origin,pose.basis.get_euler().y):
		car.queue_free(); return
	visitor_serial += 1
	car.vehicle_id = "open_drag_%d_%d"%[get_instance_id(),visitor_serial]
	car.set_meta("race_owned",true)
	car.set_meta("desert_drag_physics",true)
	car.set_meta("open_drag_owned",true)
	car.input_locked = true
	car.set_physics_process(false)
	var drive = DRIVE.new()
	drive.configure(str(ROSTER.CARS[identity].car))
	drive.race_mode = true
	drive.launch_blend_seconds = .35
	car.set_meta("desert_powertrain",drive)
	DRIVER.attach(car,identity)
	ROSTER.attach_number(car,int(ROSTER.CARS[identity].number))
	var sound = AUDIO.new()
	sound.bind(car,drive)
	car.add_child(sound)
	transit.append({"car":car,"drive":drive,"sound":sound,"identity":identity,"lane":-1,"finish":INF,"travel":0.0,"path":path,"waypoint":1,"routing":"arrival"})
	_refresh()

func _promote() -> void:
	heat = waiting.duplicate()
	waiting.clear()
	phase = "lining"
	clock = 0.0
	if not is_instance_valid(signals):
		signals = SIGNALS.new()
		add_child(signals)
		signals.configure(race.start_point,race.direction,800.0)
	signals.set_countdown(3.0)
	_refresh()

func _release_heat() -> void:
	for entry in heat: _return_entry(entry)
	heat.clear()
	heats_completed += 1
	# The running heat at registration is not the extra waiting pair.
	if not pending.is_empty() and heats_ahead>0:
		if skip_current_heat: skip_current_heat = false
		else: heats_ahead -= 1
	phase = "idle"
	clock = 0.0
	_refresh()

func _dispatch(delta: float) -> void:
	if not session.world.driving.occupied:
		_set_admission_reason("Sua vez · entre no carro #27 junto ao quadro.")
		return
	ready_clock += delta
	var reason: String = race.start_block_reason()
	if not reason.is_empty():
		_set_admission_reason(reason)
		return
	var identity := pending
	if ROSTER.CARS.has(identity):
		var candidates := waiting.filter(func(e): return int(e.lane)==1)
		if candidates.is_empty():
			_set_admission_reason("Aguardando o adversário chegar pelo acesso.")
			return
		var entry: Dictionary = candidates[0]
		identity = str(entry.identity)
		var remaining: float = -race._offset(entry.car.global_position)
		if remaining>.05:
			entry.car.rotation.y = rotate_toward(entry.car.rotation.y,race.grid(1).basis.get_euler().y,delta*2.0)
			entry.drive.speed_mps = minf(3.0,remaining/maxf(delta,.001))
			race._move_car(entry,delta)
			_set_admission_reason("Adversário alinhando.")
			return
	dispatching = true
	# Waiting visitors remain behind the grid. The player's heat owns the tree.
	if is_instance_valid(signals): signals.queue_free(); signals = null
	var started: bool = race.start_rival(identity)
	if not started and not pending.is_empty(): _set_admission_reason("Pista ou alinhamento obstruído · sua posição está reservada.")
	dispatching = false
	if started:
		pending = ""
		heats_ahead = 0
		last_admission_reason = ""
		_refresh()

func _set_admission_reason(reason: String) -> void:
	if last_admission_reason==reason: return
	last_admission_reason = reason
	_refresh()

func _out_of_view(car: Node3D) -> bool:
	return _point_out_of_view(car.global_position,110.0)

func _point_out_of_view(point: Vector3, minimum_distance: float) -> bool:
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return true
	if session.world.player.global_position.distance_to(point)<minimum_distance: return false
	return camera.is_position_behind(point) or not get_viewport().get_visible_rect().grow(80).has_point(camera.unproject_position(point))

func take_opponent(identity: String):
	for entry in waiting:
		if str(entry.identity)!=identity: continue
		waiting.erase(entry)
		loaned = entry
		return entry.car
	return null

func reclaim_opponent(car: Node3D) -> bool:
	if loaned.is_empty() or loaned.car!=car or car.health<=0: return false
	car.set_meta("desert_drag_physics",true)
	car.set_physics_process(false)
	car.input_locked = true
	_return_entry(loaned)
	loaned = {}
	return true

func _return_entry(entry: Dictionary) -> void:
	if entry.has("launch_body"):
		entry.launch_body.reset()
		entry.erase("launch_body")
	var path: Array[Vector3] = []
	for point in LAYOUT.drag_return_points(): path.append(Vector3(point.x,.08,point.y))
	entry.path = path
	entry.waypoint = 0
	entry.routing = "return"
	entry.finish = INF
	entry.erase("runoff_deceleration")
	entry.car.remove_meta("drag_service_brake_slip")
	entry.drive.reset()
	transit.append(entry)

func _advance_transit(delta: float) -> void:
	for entry in transit.duplicate():
		var path: Array = entry.path
		var car = entry.car
		if int(entry.waypoint)>=path.size():
			if str(entry.routing)=="queue":
				entry.drive.reset()
				car.speed = 0.0; car.velocity = Vector3.ZERO
				waiting.append(entry)
				transit.erase(entry)
				_refresh()
			elif waiting.size()+transit.filter(func(e): return str(e.routing)=="queue").size()<2:
				var occupied := waiting+transit.filter(func(e): return str(e.routing)=="queue")
				var lane := 1 if occupied.any(func(e): return int(e.lane)==0) else 0
				entry.lane = lane
				entry.path = [race.grid(lane).origin-race.direction*14.0]
				entry.waypoint = 0
				entry.routing = "queue"
			else:
				car.speed = 0.0; car.velocity = Vector3.ZERO
			continue
		var target: Vector3 = path[int(entry.waypoint)]
		var offset: Vector3 = target-car.global_position
		offset.y = 0.0
		if offset.length()<.65:
			entry.waypoint += 1
			continue
		var forward := offset.normalized()
		var blocked := false
		var safe_speed := INF
		for other in heat+waiting+transit:
			if other.car==car: continue
			var gap: Vector3 = other.car.global_position-car.global_position
			if gap.dot(forward)>0.0 and absf(gap.dot(forward.cross(Vector3.UP)))<2.2:
				safe_speed = minf(safe_speed,sqrt(20.0*maxf(0.0,gap.dot(forward)-7.0)))
				if gap.dot(forward)<7.0: blocked = true
		if session.world.driving.occupied and session.world.driving.car!=car:
			var gap: Vector3 = session.world.driving.car.global_position-car.global_position
			if gap.dot(forward)>0.0 and absf(gap.dot(forward.cross(Vector3.UP)))<2.4:
				safe_speed = minf(safe_speed,sqrt(20.0*maxf(0.0,gap.dot(forward)-8.0)))
				if gap.dot(forward)<8.0: blocked = true
		var yaw := atan2(-forward.x,-forward.z)
		var turn := absf(angle_difference(car.rotation.y,yaw))
		var target_speed := 5.0 if turn>.16 or str(entry.routing)=="queue" else (24.0 if str(entry.routing)=="return" else 12.0)
		# Brake before a bend, not after reaching its first short arc segment.
		var ahead_distance := offset.length()
		var previous_direction := forward
		for index in range(int(entry.waypoint),mini(path.size()-1,int(entry.waypoint)+4)):
			var segment: Vector3 = path[index+1]-path[index]
			if previous_direction.dot(segment.normalized())<.99:
				target_speed = minf(target_speed,sqrt(25.0+20.0*maxf(0.0,ahead_distance-2.0)))
				break
			ahead_distance += segment.length()
			previous_direction = segment.normalized()
		target_speed = minf(target_speed,safe_speed)
		target_speed = minf(target_speed,offset.length()/maxf(delta,.001))
		var speed := move_toward(float(car.speed),0.0 if blocked else target_speed,delta*10.0)
		car.rotation.y = rotate_toward(car.rotation.y,yaw,delta*2.5)
		var motion: Vector3 = -car.global_basis.z*speed
		var region = session.world.production.regions.get("desert")
		if not is_instance_valid(region) or not region.prepare_collision_at(car.global_position+motion*delta): continue
		var before: Vector3 = car.global_position
		# Match Vehicle's grounded contract: floor snap keeps support without
		# pressing a grounded hull into the next coplanar triangle's edge.
		var vertical_speed: float = 0.0 if car.is_on_floor() else car.velocity.y-18.0*delta
		car.velocity = motion+Vector3.UP*vertical_speed
		car.move_and_slide()
		var moved: Vector3 = car.global_position-before
		car.speed = Vector2(moved.x,moved.z).length()/maxf(delta,.001)
		car.horizontal_velocity = Vector3(moved.x,0,moved.z)/maxf(delta,.001)
		car.throttle_input = .25 if speed>.1 else 0.0
		car.brake_input = blocked
		entry.drive.follow_external_motion(car.speed,car.throttle_input,delta)
		car.wheel_spin += moved.length()/.355
		for wheel in car.wheels: wheel.rotation.x = car.wheel_spin
		car.distance_travelled += moved.length()
		if is_instance_valid(car.effects): car.effects.physics_tick(delta,motion)

func _release_car(car: Node3D) -> void:
	if not is_instance_valid(car): return
	if session.world.driving.occupied and session.world.driving.car==car:
		car.remove_meta("race_owned")
		car.remove_meta("open_drag_owned")
		car.remove_meta("desert_drag_physics")
		car.set_physics_process(true)
		car.input_locked = session.modal
		var driver = car.get_node_or_null("DragRivalDriver")
		if is_instance_valid(driver): driver.queue_free()
	else:
		car.queue_free()

func clear_visit() -> void:
	# Consuming a ticket transfers ownership to the race. Only an outstanding
	# registration may disarm its context when the ambient visit is released.
	if not pending.is_empty(): cancel_ticket(false,"Você saiu do encontro.")
	for entry in heat+waiting+transit: _release_car(entry.car)
	heat.clear(); waiting.clear(); transit.clear()
	phase = "idle"; clock = 0.0; blocked_phase = ""; recovery_clock = 0.0
	last_admission_reason = ""
	if is_instance_valid(signals): signals.queue_free(); signals = null
	_clear_registration_number()
	if is_instance_valid(status_layer): status_layer.hide()

func _clear_registration_number() -> void:
	if is_instance_valid(registered_car):
		var badge = registered_car.get_node_or_null("DragEntryNumber")
		if is_instance_valid(badge):
			registered_car.remove_child(badge)
			badge.queue_free()
		if registered_car.has_meta("drag_entry_number"): registered_car.remove_meta("drag_entry_number")
	registered_car = null

func _refresh() -> void:
	if not is_instance_valid(status_layer):
		status_layer = CanvasLayer.new()
		status_layer.layer = 36
		add_child(status_layer)
		status = Label.new()
		status.position = Vector2(28,220)
		status.add_theme_font_size_override("font_size",22)
		status.add_theme_color_override("font_color",Color("ffcf78"))
		status.add_theme_color_override("font_shadow_color",Color.BLACK)
		status.add_theme_constant_override("shadow_offset_x",2)
		status.add_theme_constant_override("shadow_offset_y",2)
		status_layer.add_child(status)
	status_layer.visible = not pending.is_empty() and not race.active
	var instruction := "Sua vez: pare junto ao quadro" if heat.is_empty() and heats_ahead==0 else "Aguardando largada"
	if not last_admission_reason.is_empty(): instruction = last_admission_reason
	elif not session.world.driving.occupied: instruction = "Pode esperar a pé · carro #27 inscrito"
	status.text = "#27 · %dª posição · %s"%[1+heats_ahead,instruction]
	changed.emit()

func _exit_tree() -> void:
	if is_instance_valid(session): clear_visit()
