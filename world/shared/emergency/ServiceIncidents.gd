extends Node
## A finite queue of local incidents; the pool remains the hard fleet limit.
const RADIUS := 550.0
const MAX_INCIDENTS := 24
const SUPPRESSION := preload("res://world/shared/emergency/FireSuppression.gd")
var incidents: Array[Dictionary] = []
var director: Node
var elapsed := 0.0
var serial := 0

func request(service: String, target: Node2D) -> Node:
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return null
	if service == "coroner" and target is CharacterBody2D:
		get_node("/root/NPCMedicalCare").report_injury(target)
	if service == "coroner":
		target = preload("res://world/shared/emergency/CoronerInteriorAccess.gd").target_for(target)
		if target == null: return null
	if target.has_meta("explosion_remains"):
		target = target.get_meta("explosion_remains") as Node2D
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return null
	if not _pending(target, service): return null
	for incident in incidents:
		if incident.service == service and incident.targets.has(target):
			_try_dispatch(incident)
			return incident.vehicle if is_instance_valid(incident.vehicle) else null
	var capacity := 3 if service == "fire" else 8
	for incident in incidents:
		var unit: Node = incident.vehicle if is_instance_valid(incident.vehicle) else null
		if unit and unit.get_meta("service_incident_key", "") != incident.key: unit = null
		if incident.service != service or incident.targets.size() >= capacity: continue
		if unit and (unit.is_returning_to_base or unit.is_heading_to_cemetery or unit.is_broken): continue
		if target.global_position.distance_to(incident.origin) > RADIUS: continue
		incident.targets.append(target)
		if service == "fire": target.set_meta("fire_response_assigned", true)
		if unit: unit.add_service_target(target)
		_try_dispatch(incident)
		return incident.vehicle if is_instance_valid(incident.vehicle) else null
	if incidents.size() >= MAX_INCIDENTS: return null
	serial += 1
	var incident := {"service": service, "origin": target.global_position, "targets": [target], "vehicle": null, "key": str(get_instance_id()) + ":" + str(serial)}
	if service == "fire": target.set_meta("fire_response_assigned", true)
	incidents.append(incident)
	_try_dispatch(incident)
	return incident.vehicle if is_instance_valid(incident.vehicle) else null

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 1.0: return
	elapsed = 0.0
	for incident in incidents.duplicate():
		incident.targets = incident.targets.filter(func(t): return _pending(t, incident.service))
		if incident.targets.is_empty():
			incidents.erase(incident)
			continue
		_try_dispatch(incident)

func _try_dispatch(incident: Dictionary) -> void:
	var unit: Node = incident.vehicle if is_instance_valid(incident.vehicle) else null
	if unit and unit.get_meta("service_incident_key", "") != incident.key: unit = null
	if unit and unit.visible and not unit.is_broken:
		if not unit.is_returning_to_base and not unit.is_heading_to_cemetery: return
		# The old unit is still physically occupied on its return leg. Wait.
		return
	incident.vehicle = null
	var targets: Array = incident.targets.filter(func(t): return _pending(t, incident.service) and (incident.service != "fire" or Time.get_ticks_msec() >= int(t.get_meta("fire_retry_after_ms", 0))))
	if targets.is_empty(): return
	if not is_instance_valid(director): return
	unit = director._dispatch_unbatched(incident.service, targets[0], false)
	if unit == null: return
	incident.vehicle = unit
	unit.set_meta("service_incident_key", incident.key)
	if incident.service == "fire":
		preload("res://audio/police_dispatch/EmergencyServiceRadio.gd").play_at(unit, "fire_dispatch")
	for target in targets:
		unit.add_service_target(target)
		if incident.service == "fire": target.set_meta("fire_response_assigned", true)

func _pending(target: Variant, service: String) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target.get_meta("service_complete", false): return false
	if service == "coroner": return target.get("is_dead") == true and not target.is_in_group("player")
	return service != "fire" or SUPPRESSION.is_active(target)
