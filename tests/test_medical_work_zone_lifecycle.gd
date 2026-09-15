extends "res://tests/test_medical_choreography_continuity.gd"
## Observe the real rescue/admission fixture, including the hidden transport gap.
var zone_saw_roadside := false
var zone_saw_transport := false
var zone_saw_hospital_exit := false
var zone_saw_empty_return := false
var zone_lifecycle_errors: Dictionary = {}
var zone_refs: Array[WeakRef] = []
var zone_actor_refs: Array[WeakRef] = []

func run() -> void:
	physics_frame.connect(_observe_work_zones)
	await super.run()

func _observe_work_zones() -> void:
	for unit in get_nodes_in_group("emergency_vehicle"):
		if not unit.has_meta("medical_sequence"): continue
		var sequence: Node = unit.get_meta("medical_sequence")
		if not is_instance_valid(sequence): continue
		# Observe settled physics state, allowing deferred shape updates one tick.
		if sequence.phase_time < .15: continue
		var zone: Node = sequence.get("work_zone")
		if not is_instance_valid(zone):
			zone_lifecycle_errors["An active rescue owns its traffic protection"] = true
			continue
		var known := false
		for reference in zone_refs:
			if reference.get_ref() == zone: known = true
		if not known:
			zone_refs.append(weakref(zone))
			for actor in [unit, sequence.patient] + sequence.crew:
				if is_instance_valid(actor): zone_actor_refs.append(weakref(actor))
		var moving_outside: bool = sequence.phase != "transport"
		if zone.active != moving_outside:
			zone_lifecycle_errors["Protection active state follows external work: " + sequence.phase] = true
		if sequence.phase == "transport":
			zone_saw_transport = true
			if _has_enabled_collision(zone):
				zone_lifecycle_errors["No invisible traffic barrier stays at the former rescue site"] = true
			for medic in sequence.crew:
				if medic.get_meta("medical_vehicle_protected", false):
					zone_lifecycle_errors["Boarded medics no longer reserve street space"] = true
		elif not sequence.hospital_delivery:
			zone_saw_roadside = true
		elif sequence.phase in ["exit", "fetch", "unload_stretcher"]:
			zone_saw_hospital_exit = true
		elif sequence.phase == "hospital_return_cot":
			zone_saw_empty_return = true
			if not zone.active:
				zone_lifecycle_errors["Admission does not remove protection from the empty cot return"] = true

func _has_enabled_collision(zone: Node) -> bool:
	if zone.collision_layer == 0: return false
	for shape in zone.get_children():
		if shape is CollisionShape2D and not shape.disabled: return true
	return false

func check(ok: bool, label: String) -> void:
	if label.begins_with("Parked ambulance survives"):
		super.check(zone_saw_roadside, "Traffic protection followed the real roadside rescue")
		super.check(zone_saw_transport, "Transport disabled the old roadside work zone")
		super.check(zone_saw_hospital_exit, "Hospital exit reactivated protection before the hospital_* phases")
		super.check(zone_saw_empty_return, "The admitted patient's empty cot return remained protected")
		for issue in zone_lifecycle_errors:
			super.check(false, str(issue))
		for reference in zone_refs:
			super.check(not is_instance_valid(reference.get_ref()), "Completed hospital delivery removes the work zone")
		for reference in zone_actor_refs:
			var actor: PhysicsBody2D = reference.get_ref()
			if not is_instance_valid(actor): continue
			for exception in actor.get_collision_exceptions():
				super.check(is_instance_valid(exception), "Zone cleanup leaves no freed collision exceptions on surviving actors")
		print("MEDICAL_WORK_ZONE lifecycle_errors=", zone_lifecycle_errors.size(), " observed_zones=", zone_refs.size())
	super.check(ok, label)
