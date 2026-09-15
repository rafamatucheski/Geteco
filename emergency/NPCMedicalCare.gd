extends Node
## One incident per resident, independent of district streaming and save slots.
var residents := {}
var incidents := {}
var _scan_clock := 0.0
const UNATTENDED_SECONDS := 30.0
const RESCUE_LIMIT_SECONDS := 120.0
const FADE_SECONDS := 5.0
const RETURN_SECONDS := 20.0
const MAX_INCIDENT_SECONDS := 300.0
const MAX_OBSERVERS := 4
const REPORTED_WAIT_SECONDS := 180.0

func _ready() -> void:
	get_tree().node_added.connect(_node_added)
	get_node("/root/CampaignState").campaign_started.connect(_reset)

func _reset() -> void:
	incidents.clear()
	residents.clear()

func _node_added(node: Node) -> void:
	# Responders can be removed before the deferred registration runs (scene
	# teardown or boarding). Passing a freed typed Node fails before _register
	# can perform its validity check, so resolve the id at execution time.
	if node is CharacterBody2D: _register_id.call_deferred(node.get_instance_id())

func _register_id(actor_id: int) -> void:
	var actor := instance_from_id(actor_id)
	if is_instance_valid(actor): _register(actor)

func _register(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not "is_dead" in actor or not "health" in actor: return
	if actor.is_in_group("player") or actor.get_script().resource_path == "res://characters/Player.gd": return
	if not actor.is_node_ready(): await actor.ready
	if not is_instance_valid(actor): return
	var scene := get_tree().current_scene
	if scene == null: return
	var key: String = actor.get_meta("medical_identity", "")
	if key.is_empty():
		var path := String(scene.get_path_to(actor))
		if "@" in path:
			path = "%s:%d:%d:%s" % [actor.get_script().resource_path, roundi(actor.global_position.x), roundi(actor.global_position.y), str(actor.get("appearance_seed"))]
		key = scene.scene_file_path + ":" + path
		actor.set_meta("medical_identity", key)
	if residents.has(key) and residents[key].actor == actor: return
	residents[key] = {"actor":actor, "home":actor.global_position, "health":maxi(1, int(actor.health)), "physics":actor.is_physics_processing(), "mode":actor.process_mode, "layer":actor.collision_layer, "mask":actor.collision_mask}
	var coroner := get_node_or_null("/root/CoronerCare")
	if coroner and coroner.restore_actor(actor): return
	var saved: Dictionary = records().get(key, {})
	if saved.is_empty(): return
	residents[key].home = Vector2(saved.get("home_x", actor.global_position.x), saved.get("home_y", actor.global_position.y))
	if saved.get("phase", "") == "recycling":
		actor.is_dead = true
		actor.health = 0
		actor.set_meta("medical_pending", true)
		actor.hide()
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		return
	if saved.get("phase", "") == "discharged":
		_recover(key)
		records().erase(key)
	elif saved.get("phase", "") == "hospital":
		actor.set_meta("medical_pending", true)
		actor.hide()
		actor.set_physics_process(false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.collision_layer = 0
		actor.collision_mask = 0
	elif saved.get("phase", "") == "down":
		actor.global_position = Vector2(saved.get("incident_x",actor.global_position.x),saved.get("incident_y",actor.global_position.y))
		actor.health = 0
		actor.is_dead = bool(saved.get("fatal", float(saved.get("days", 2.0)) > 1.0))
		if "is_incapacitated" in actor: actor.is_incapacitated = not actor.is_dead
		if actor.has_method("_start_fall"): actor._start_fall()
		report_injury(actor)

func records() -> Dictionary:
	return get_node("/root/CampaignState").npc_medical_care

func model_for(actor: Node) -> Node3D:
	for key in ["model_root", "driver_model", "model"]:
		if key in actor and is_instance_valid(actor.get(key)): return actor.get(key)
	return null

func viewport_for(actor: Node) -> SubViewport:
	for key in ["viewport", "viewport_3d", "driver_viewport"]:
		if key in actor and actor.get(key) is SubViewport: return actor.get(key)
	return null

func report_injury(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor is CharacterBody2D or actor.is_in_group("player"): return
	if not "is_dead" in actor or not "health" in actor: return
	if actor.get("is_dead") != true and actor.get("is_incapacitated") != true: return
	actor.set_meta("medical_pending", true)
	if not actor.has_meta("medical_identity"): _register(actor)
	var key: String = actor.get_meta("medical_identity", "")
	if actor.is_dead and not actor.is_in_group("mountain_wildlife"):
		var coroner := get_node_or_null("/root/CoronerCare")
		if coroner:
			if actor.get_meta("service_complete",false) and coroner.records().has(key): return
			if coroner.records().get(key, {}).get("phase", "") in ["carrying", "transport", "morgue", "cemetery", "burial", "awaiting_plot", "recovery", "buried", "unrecovered"]: return
			coroner.register_death(actor)
	if key.is_empty() or incidents.has(key) or records().get(key, {}).get("phase", "") == "hospital": return
	if records().get(key, {}).get("phase", "") == "recycling": return
	var prior_age := float(records().get(key, {}).get("cleanup_age", 0.0))
	var home: Vector2 = residents[key].home
	records()[key] = {"phase":"down", "home_x":home.x, "home_y":home.y, "incident_x":actor.global_position.x, "incident_y":actor.global_position.y, "days":2.0 if actor.is_dead else 1.0, "cleanup_age":0.0}
	records()[key].fatal = actor.is_dead
	incidents[key] = {"actor":actor, "phase":"noticed", "age":prior_age, "retry":0.0, "witness":null, "unit":null, "carrier":null, "observers":{}}

func _process(delta: float) -> void:
	if get_tree().paused: return
	# Only fading casualties need per-frame work; discovery stays at 2 Hz.
	for incident in incidents.values():
		if incident.phase != "fading" or not is_instance_valid(incident.actor): continue
		incident.fade = minf(FADE_SECONDS, float(incident.get("fade", 0.0)) + delta)
		incident.actor.modulate.a = 1.0 - incident.fade / FADE_SECONDS
		if incident.actor.has_meta("explosion_remains"):
			var remains: Variant = incident.actor.get_meta("explosion_remains")
			if is_instance_valid(remains): remains.modulate.a = incident.actor.modulate.a
	_scan_clock += delta
	if _scan_clock < 0.5: return
	var elapsed := _scan_clock
	_scan_clock = 0
	for key in residents.keys():
		var actor: Variant = residents[key].actor
		if not is_instance_valid(actor):
			residents.erase(key)
			incidents.erase(key)
			continue
		if actor.get("is_dead") == true or actor.get("is_incapacitated") == true:
			report_injury(actor)
		elif not actor.has_meta("medical_pending") and actor.health > 0 and actor.health <= float(residents[key].health)*.25:
			if "is_incapacitated" in actor: actor.is_incapacitated = true
			else: actor.is_dead = true
			if actor.has_method("_start_fall"): actor._start_fall()
			elif "fall_presentation" in actor: actor.fall_presentation.start(actor,model_for(actor),viewport_for(actor))
			elif "fall" in actor: actor.fall.start(actor,model_for(actor),viewport_for(actor))
			report_injury(actor)
	# Dispatch scarce units by urgency, with age eventually promoting every
	# waiting casualty. Dictionary insertion order must not decide who is saved.
	var pending := incidents.keys()
	pending.sort_custom(func(a: String, b: String) -> bool: return _dispatch_priority(incidents[a]) > _dispatch_priority(incidents[b]))
	for key in pending:
		var incident: Dictionary = incidents[key]
		# Mission retries and finite encounters can free a patient between scans.
		# Keep the reference untyped until the validity guard has accepted it.
		var actor: Variant = incident.actor
		if not is_instance_valid(actor):
			incidents.erase(key)
			continue
		if not records().has(key):
			incidents.erase(key)
			continue
		incident.age += elapsed
		if actor.is_dead and is_instance_valid(incident.unit) and incident.unit.get("type") == 1:
			var ambulance: Node = incident.unit
			var sequence: Node = ambulance.get_meta("medical_sequence") if ambulance.has_meta("medical_sequence") else null
			if is_instance_valid(sequence): sequence._abort("confirmed_death")
			ambulance.target = null
			ambulance.is_returning_to_base = true
			incident.unit = null
			incident.carrier = null
			incident.phase = "reported"
			incident.retry = 0.0
		records()[key].cleanup_age = incident.age
		if _cleanup_incident(key, elapsed): continue
		if actor.is_in_group("mountain_wildlife"): continue
		incident.retry -= elapsed
		var point: Vector2 = incident.unit.global_position if incident.phase == "transport" and is_instance_valid(incident.unit) else actor.global_position
		records()[key].incident_x = point.x
		records()[key].incident_y = point.y
		if incident.phase == "transport":
			if not is_instance_valid(incident.unit) or incident.unit.is_broken or not incident.unit.visible or incident.unit.target != actor:
				retry_patient(actor)
			continue
		if incident.phase == "carrying":
			if not is_instance_valid(incident.carrier): retry_patient(actor, actor.global_position)
			continue
		if incident.phase == "dispatched":
			if actor.is_dead and is_instance_valid(incident.unit) and incident.unit.get("type") == 3 and incident.unit.visible and not incident.unit.is_broken and not incident.unit.is_returning_to_base:
				var assigned_target: Variant = incident.unit.target
				if is_instance_valid(assigned_target) and get_node("/root/CoronerCare").identity(assigned_target) == key: continue
				if incident.unit.service_targets.any(func(candidate): return is_instance_valid(candidate) and get_node("/root/CoronerCare").identity(candidate) == key): continue
			if is_instance_valid(incident.unit) and incident.unit.visible and not incident.unit.is_broken and incident.unit.target == actor and not incident.unit.is_returning_to_base: continue
			incident.phase = "reported"
		if incident.phase == "noticed":
			_notice_by_responder(actor, incident, elapsed)
			if incident.phase == "noticed" and not is_instance_valid(incident.witness):
				var witness := _nearest_witness(actor)
				if witness:
					incident.witness = _add_observer(witness, actor, incident, true)
			# Wait for a real witness to finish calling, including after an
			# interrupted call. Elapsed time alone cannot report the casualty.
		if incident.phase in ["noticed", "reported"]:
			_gather_observers(actor, incident)
		if incident.phase == "reported" and incident.retry <= 0:
			incident.retry = 4.0
			var director := _nearest_director(actor)
			if director:
				var service := "coroner" if actor.is_dead else "ambulance"
				var unit: Node = director.request_dispatch(service, actor)
				if is_instance_valid(unit):
					if actor.is_dead: get_node("/root/CoronerCare").assigned(actor, unit)
					incident.unit = unit
					incident.phase = "dispatched"
					incident.rescue_age = 0.0
	_advance_recycling(elapsed)
	var clock := get_tree().get_first_node_in_group("day_night_manager")
	if clock != null and clock.is_dynamic_time and get_tree().get_first_node_in_group("medical_campaign_clock") == null:
		advance_days(elapsed / maxf(1.0, float(clock.day_length_seconds)))

func _dispatch_priority(incident: Dictionary) -> float:
	var actor: Variant = incident.actor
	var living: bool = is_instance_valid(actor) and actor.get("is_dead") != true
	return float(incident.age) + (60.0 if living else 0.0)

func _notice_by_responder(patient: CharacterBody2D, incident: Dictionary, delta: float) -> void:
	# A responder radios what they can actually see without abandoning their
	# current assignment or borrowing the civilian phone animation.
	var observed := false
	for group in ["paramedic", "firefighter", "police_officer"]:
		for responder in get_tree().get_nodes_in_group(group):
			if not responder is CharacterBody2D or responder == patient or not responder.is_visible_in_tree(): continue
			if responder.get("is_dead") == true or responder.get("is_incapacitated") == true: continue
			if responder.get_world_2d() != patient.get_world_2d(): continue
			if responder.global_position.distance_squared_to(patient.global_position) > 260.0 * 260.0: continue
			var ray := PhysicsRayQueryParameters2D.create(responder.global_position, patient.global_position, 3, [responder.get_rid(), patient.get_rid()])
			if not patient.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
			observed = true
			break
		if observed: break
	incident.responder_sight = float(incident.get("responder_sight", 0.0)) + delta if observed else 0.0
	if incident.responder_sight >= 1.0: witness_called(patient)

func _nearest_witness(patient: Node2D) -> CharacterBody2D:
	var best: CharacterBody2D
	var distance := 650.0 * 650.0
	for item in residents.values():
		var candidate: CharacterBody2D = item.actor
		if not is_instance_valid(candidate) or candidate == patient or not candidate.is_visible_in_tree(): continue
		if not _can_observe(candidate, patient): continue
		if candidate.is_in_group("paramedic") or candidate.is_in_group("police_officer") or candidate.get("is_gangster") == true: continue
		var d := candidate.global_position.distance_squared_to(patient.global_position)
		if candidate.get_parent() == patient.get_parent(): d *= 0.6
		if d < distance:
			distance = d
			best = candidate
	return best

func _can_observe(candidate: CharacterBody2D, patient: Node2D) -> bool:
	if candidate == patient or candidate.is_in_group("player") or candidate.modulate.a < 0.1: return false
	if candidate.is_dead or candidate.get("is_incapacitated") == true or candidate.get("is_scared") == true: return false
	if candidate.has_meta("medical_witness") or candidate.has_meta("medical_pending") or candidate.has_meta("medical_managed"): return false
	if candidate.is_in_group("paramedic") or candidate.is_in_group("police_officer") or candidate.is_in_group("firefighter") or candidate.is_in_group("mortician") or candidate.get("is_gangster") == true: return false
	if candidate.get_world_2d() != patient.get_world_2d(): return false
	var sight := PhysicsRayQueryParameters2D.create(candidate.global_position, patient.global_position, 3, [candidate.get_rid(), patient.get_rid()])
	return candidate.get_world_2d().direct_space_state.intersect_ray(sight).is_empty()

func _add_observer(candidate: CharacterBody2D, patient: CharacterBody2D, incident: Dictionary, caller: bool) -> Node:
	var response := preload("res://emergency/MedicalWitness.gd").new()
	response.actor = candidate
	response.patient = patient
	response.calls_for_help = caller
	if not response.reserve_position():
		response.free()
		return null
	candidate.add_child(response)
	incident.observers[candidate.get_instance_id()] = true
	return response

func _gather_observers(patient: CharacterBody2D, incident: Dictionary) -> void:
	if incident.observers.size() >= MAX_OBSERVERS: return
	for item in residents.values():
		var candidate: CharacterBody2D = item.actor
		if not is_instance_valid(candidate) or not candidate.is_visible_in_tree(): continue
		if incident.observers.has(candidate.get_instance_id()): continue
		if candidate.global_position.distance_squared_to(patient.global_position) > 220.0 * 220.0: continue
		if not _can_observe(candidate, patient): continue
		_add_observer(candidate, patient, incident, false)
		if incident.observers.size() >= MAX_OBSERVERS: break

func _nearest_director(patient: Node2D) -> Node:
	var address := patient
	if patient.get("is_dead") == true:
		address = preload("res://emergency/CoronerInteriorAccess.gd").target_for(patient)
		if address == null: return null
	var best: Node
	var distance := INF
	for director in get_tree().get_nodes_in_group("emergency_depot_director"):
		if not director.can_process(): continue
		var service := "coroner" if patient.get("is_dead") == true else "ambulance"
		var depot: Node2D = director._choose_depot(service, address.global_position)
		if depot == null: continue
		var d := depot.global_position.distance_squared_to(address.global_position)
		if d < distance:
			distance = d
			best = director
	return best

func witness_called(patient: Node) -> void:
	var key: String = patient.get_meta("medical_identity", "")
	if incidents.has(key) and incidents[key].phase == "noticed": incidents[key].phase = "reported"

func claim_patient(patient: Node, unit: Node, carrier: Node) -> bool:
	if not is_instance_valid(patient): return false
	if patient.get("is_dead") == true: return false
	report_injury(patient)
	var key: String = patient.get_meta("medical_identity", "")
	if not incidents.has(key): return false
	var incident: Dictionary = incidents[key]
	if incident.phase in ["carrying", "transport", "fading"]: return false
	if is_instance_valid(incident.unit) and incident.unit != unit: return false
	if is_instance_valid(incident.carrier) and incident.carrier != carrier: return false
	incident.unit = unit
	incident.carrier = carrier
	incident.phase = "dispatched"
	patient.remove_meta("medical_access_failure")
	return true

func defer_inaccessible(patient: Node, unit: Node, reason: String) -> void:
	var key: String = patient.get_meta("medical_identity", "")
	if not incidents.has(key) or incidents[key].unit != unit: return
	retry_patient(patient,patient.global_position)
	incidents[key].retry = 30.0
	incidents[key].access_failure = reason
	patient.set_meta("medical_access_failure",reason)

func begin_carry(patient: Node, unit: Node, carrier: Node) -> bool:
	if is_instance_valid(patient) and patient.get("is_dead") == true: return false
	if not is_instance_valid(patient) or patient.is_in_group("player") or (patient.get_script() != null and patient.get_script().resource_path == "res://characters/Player.gd"): return false
	report_injury(patient)
	var key: String = patient.get_meta("medical_identity", "")
	if not incidents.has(key) or incidents[key].phase in ["carrying", "transport", "fading"]: return false
	if is_instance_valid(incidents[key].unit) and incidents[key].unit != unit: return false
	if is_instance_valid(incidents[key].carrier) and incidents[key].carrier != carrier: return false
	incidents[key].phase = "carrying"
	incidents[key].unit = unit
	incidents[key].carrier = carrier
	if patient.has_meta("explosion_remains"):
		var remains: Variant = patient.get_meta("explosion_remains")
		if is_instance_valid(remains): remains.queue_free()
		patient.remove_meta("explosion_remains")
	patient.hide()
	patient.set_physics_process(false)
	patient.process_mode = Node.PROCESS_MODE_DISABLED
	return true

func board_patient(patient: Node, unit: Node) -> void:
	var key: String = patient.get_meta("medical_identity", "")
	if not incidents.has(key) or incidents[key].phase == "fading": return
	if is_instance_valid(incidents[key].unit) and incidents[key].unit != unit: return
	incidents[key].phase = "transport"
	incidents[key].unit = unit
	patient.hide()
	patient.set_physics_process(false)
	patient.process_mode = Node.PROCESS_MODE_DISABLED
	var arrival := _hospital_arrival.bind(key)
	if not unit.arrived_at_depot.is_connected(arrival):
		unit.arrived_at_depot.connect(arrival, CONNECT_ONE_SHOT)

func _hospital_arrival(unit: Node, _depot: String, key: String) -> void:
	if not incidents.has(key) or incidents[key].unit != unit or incidents[key].phase != "transport": return
	# At an authored emergency entrance the vehicle arrival is only parking;
	# admission happens after the stretcher actually crosses the hospital door.
	if bool(unit.get_meta("hospital_unloading", false)): return
	complete_hospital_admission(incidents[key].actor, unit)

func complete_hospital_admission(patient: Node, unit: Node) -> void:
	if patient.get("is_dead") == true:
		retry_patient(patient)
		return
	var key: String = patient.get_meta("medical_identity", "")
	if not incidents.has(key) or incidents[key].unit != unit or incidents[key].phase == "fading": return
	patient.hide()
	records()[key].phase = "hospital"
	records()[key].remaining_days = records()[key].days
	incidents.erase(key)

func retry_patient(patient: Node, at: Variant = null) -> void:
	if not is_instance_valid(patient): return
	var key: String = patient.get_meta("medical_identity", "")
	if not incidents.has(key) or incidents[key].phase == "fading": return
	if at is Vector2: patient.global_position = at
	elif is_instance_valid(incidents[key].unit): patient.global_position = incidents[key].unit.global_position + Vector2(0, 60)
	patient.show()
	patient.modulate.a = 1
	patient.process_mode = residents[key].mode
	patient.set_physics_process(true)
	incidents[key].phase = "reported"
	incidents[key].unit = null
	incidents[key].carrier = null
	incidents[key].retry = 2.0

func advance_days(days: float) -> void:
	if not is_finite(days) or days <= 0: return
	for key in records().keys():
		var record: Dictionary = records()[key]
		if record.get("phase", "") != "hospital": continue
		record.remaining_days = maxf(0, float(record.get("remaining_days", record.days)) - days)
		if record.remaining_days > 0: continue
		if residents.has(key) and is_instance_valid(residents[key].actor):
			_recover(key)
			records().erase(key)
		else:
			record.phase = "discharged"

func _recover(key: String, point: Vector2 = Vector2.INF) -> void:
	if get_node("/root/CoronerCare").records().has(key): return
	var item: Dictionary = residents[key]
	var actor: CharacterBody2D = item.actor
	if "fall_presentation" in actor: actor.fall_presentation.reset()
	elif "fall" in actor: actor.fall.reset()
	if actor.has_method("_abort_visit"): actor._abort_visit()
	actor.is_dead = false
	for flag in ["is_incapacitated", "is_flying", "emergency_rescue_in_progress", "is_scared", "is_arrested"]:
		if flag in actor: actor.set(flag, false)
	actor.health = int(actor.get("max_health")) if "max_health" in actor else int(item.health)
	actor.velocity = Vector2.ZERO
	if "fly_velocity" in actor: actor.fly_velocity = Vector2.ZERO
	actor.global_position = Vector2(records()[key].home_x, records()[key].home_y) if point == Vector2.INF else point
	actor.collision_layer = item.layer
	actor.collision_mask = item.mask
	for shape in actor.find_children("*", "CollisionShape2D", true, false): shape.set_deferred("disabled", false)
	actor.modulate.a = 1
	actor.show()
	actor.process_mode = item.mode
	actor.remove_meta("medical_pending")
	actor.remove_meta("medical_managed")
	if "walk_target" in actor: actor.walk_target = actor.global_position
	if actor.has_method("_pick_new_sidewalk_target"): actor._pick_new_sidewalk_target()
	actor.set_physics_process(item.physics)
	actor.reset_physics_interpolation()
	if actor.has_method("on_medical_discharge"): actor.on_medical_discharge()

func _cleanup_incident(key: String, _elapsed: float) -> bool:
	var incident: Dictionary = incidents[key]
	var actor: CharacterBody2D = incident.actor
	# The bank owns its casualties until the visitor leaves; no timed removal
	# or street ambulance may interrupt the visible robbery/death sequence.
	var room := actor.get_parent()
	if room.has_method("actor_present") and room.actor_present(): return true
	# Confirmed deaths belong to custody, never to the hospital/repopulation
	# timeout. Obstructed or busy services remain pending and retry.
	if actor.is_dead and not actor.is_in_group("mountain_wildlife"):
		if incident.phase == "noticed" and incident.age >= 180.0 and get_node("/root/WorldRenewal").outside_view(actor,actor.global_position):
			get_node("/root/CoronerCare").mark_unrecovered(actor)
			incidents.erase(key)
			records().erase(key)
			return true
		return false
	var active_rescue: bool = incident.phase in ["dispatched", "carrying", "transport"]
	var limit := RESCUE_LIMIT_SECONDS if active_rescue else UNATTENDED_SECONDS
	# A reported queue cannot expire on the 30s unattended-corpse timer. Give
	# each dispatched crew its own deadline instead of inheriting the queue age.
	if incident.phase == "reported": limit = REPORTED_WAIT_SECONDS
	var cleanup_age := float(incident.age)
	if active_rescue:
		incident.rescue_age = float(incident.get("rescue_age", 0.0)) + _elapsed
		cleanup_age = incident.rescue_age
	if actor.is_in_group("mountain_wildlife"): limit = UNATTENDED_SECONDS
	if incident.phase != "fading" and cleanup_age < limit and incident.age < MAX_INCIDENT_SECONDS: return false
	if incident.phase != "fading":
		incident.phase = "fading"
		incident.fade = 0.0
		# Revoke the target before hiding it; a late rescue callback cannot
		# board or re-show a corpse that has entered housekeeping.
		if is_instance_valid(incident.unit) and incident.unit.get("target") == actor:
			incident.unit.target = null
			incident.unit.is_returning_to_base = true
	incident.fade = float(incident.get("fade", 0.0))
	actor.modulate.a = 1.0 - clampf(incident.fade / FADE_SECONDS, 0, 1)
	if actor.has_meta("explosion_remains"):
		var remains: Variant = actor.get_meta("explosion_remains")
		if is_instance_valid(remains): remains.modulate.a = actor.modulate.a
	if incident.fade < FADE_SECONDS: return true
	actor.hide()
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if actor.has_meta("explosion_remains"):
		var remains: Variant = actor.get_meta("explosion_remains")
		if is_instance_valid(remains): remains.queue_free()
		actor.remove_meta("explosion_remains")
	records()[key].phase = "recycling"
	records()[key].remaining_seconds = RETURN_SECONDS
	incidents.erase(key)
	return true

func _advance_recycling(elapsed: float) -> void:
	var renewal := get_node("/root/WorldRenewal")
	for key in records().keys():
		var record: Dictionary = records()[key]
		if get_node("/root/CoronerCare").records().has(key): continue
		if record.get("phase", "") == "hospital":
			record.recovery_age = float(record.get("recovery_age", 0.0)) + elapsed
			if record.recovery_age >= RESCUE_LIMIT_SECONDS:
				record.phase = "recycling"
				record.remaining_seconds = RETURN_SECONDS
		# Unloaded residents must not keep a permanent casualty in the save.
		if not residents.has(key):
			if record.get("phase", "") == "down":
				record.cleanup_age = float(record.get("cleanup_age", 0.0)) + elapsed
				if record.cleanup_age >= RESCUE_LIMIT_SECONDS + FADE_SECONDS:
					record.phase = "recycling"
					record.remaining_seconds = RETURN_SECONDS
		if record.get("phase", "") != "recycling": continue
		record.remaining_seconds = maxf(0, float(record.get("remaining_seconds", RETURN_SECONDS)) - elapsed)
		if record.remaining_seconds > 0: continue
		if not residents.has(key):
			records().erase(key)
			continue
		var actor: CharacterBody2D = residents[key].actor
		if not is_instance_valid(actor): continue
		# Campaign opponents remain defeated; their mission owns replacement.
		if actor.get_parent().is_in_group("cobra_campaign_encounter"):
			records().erase(key)
			residents.erase(key)
			continue
		var point := _replacement_point(key, renewal)
		if point == Vector2.INF: continue
		_recover(key, point)
		_resume_responder(actor)
		records().erase(key)

func _resume_responder(actor: CharacterBody2D) -> void:
	for service in [["ambulance", "_start_return_to_ambulance"], ["fire_truck", "_start_return_to_truck"], ["hearse", "_start_return_to_hearse"]]:
		if not actor.has_method(service[1]): continue
		var vehicle: Variant = actor.get(service[0])
		if not is_instance_valid(vehicle) or not vehicle.visible or vehicle.get("is_broken") == true:
			actor.set(service[0], null)
		actor.target = null
		if "boarding_started" in actor: actor.boarding_started = false
		actor.call(service[1])
		return

func _replacement_point(key: String, renewal: Node) -> Vector2:
	var item: Dictionary = residents[key]
	var actor: CharacterBody2D = item.actor
	var points := PackedVector2Array()
	# Authored routes keep people on sidewalks, wildlife in its own habitat.
	if "route_points" in actor:
		for point in actor.route_points: points.append(point)
	if actor.is_in_group("mountain_wildlife"):
		for offset in [Vector2(120,0), Vector2(-120,0), Vector2(0,120), Vector2(0,-120)]: points.append(item.home + offset)
	points.append(item.home)
	for point in points:
		if actor.global_position.distance_squared_to(point) < 80.0 * 80.0: continue
		if renewal.outside_view(actor, point) and renewal.free_position(actor, point): return point
	# Stationary residents may return home after the player leaves the area.
	if renewal.outside_view(actor, item.home) and renewal.free_position(actor, item.home): return item.home
	return Vector2.INF
