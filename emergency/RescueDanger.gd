extends RefCounted
## Before lifting: pause treatment, withdraw, then return to the exact work
## positions. With a patient already supported: keep evacuating as one team.
## Transfers never lose their phase, interpolation time, cot or patient owner.
var quiet_time := 0.0
var returning := false
var paused_positions: Array[Vector2] = []

func hear(sequence: Node, _origin: Vector2, _end: Vector2) -> void:
	if sequence.phase in ["transport", "parked"]: return
	quiet_time = 4.0
	returning = false
	sequence.ambulance.set_meta("medical_threat", true)

func update(sequence: Node, delta: float) -> bool:
	quiet_time = maxf(0.0, quiet_time - delta)
	var supported: bool = sequence.carrying or sequence.delivered or sequence.admitted
	# Finish a door/cot slide atomically. Retaining its clock is essential to
	# avoid a jump on resume; carrying a patient always has evacuation priority.
	var transfer: bool = sequence.phase in ["exit", "unload_stretcher", "crew_boarding", "load_patient", "lift_patient"]
	if supported or transfer:
		if quiet_time > 0:
			sequence.ambulance.set_meta("medical_threat_response", "evacuating" if supported else "completing_transfer")
		else: _clear(sequence)
		return false
	if quiet_time <= 0 and paused_positions.is_empty():
		_clear(sequence)
		return false
	if paused_positions.is_empty():
		for medic in sequence.crew: paused_positions.append(medic.global_position)
		# Do not resume half-completed treatment after staff leave the patient.
		if sequence.phase == "treat": sequence.phase_time = 0
	if quiet_time > 0:
		sequence.ambulance.set_meta("medical_threat_response", "sheltering")
		for medic in sequence.crew:
			var motion: Vector2 = medic.danger_response.movement(medic, delta, medic.speed * .85)
			sequence._move(medic, medic.global_position + motion * .25, delta, medic.speed * .85)
			medic._animate_danger(delta, false)
		return true
	returning = true
	sequence.ambulance.set_meta("medical_threat_response", "regrouping")
	var ready := true
	for i in sequence.crew.size():
		var medic: CharacterBody2D = sequence.crew[i]
		medic.torso_node.rotation.x = lerpf(medic.torso_node.rotation.x, 0, minf(1, delta*8))
		if not sequence._move(medic, paused_positions[i], delta, 90): ready = false
	if ready:
		paused_positions.clear()
		for medic in sequence.crew: medic.danger_response.threats.clear()
		_clear(sequence)
	return true

func _clear(sequence: Node) -> void:
	returning = false
	if not sequence.ambulance.has_meta("medical_threat"): return
	for medic in sequence.crew:
		if is_instance_valid(medic): medic.danger_response.threats.clear()
	sequence.ambulance.remove_meta("medical_threat")
	sequence.ambulance.remove_meta("medical_threat_response")

func finish_pose(sequence: Node) -> void:
	for medic in sequence.crew:
		if not is_instance_valid(medic) or not medic.visible: continue
		# Loaded crews visibly duck while keeping both hands at their handles.
		medic.head_node.rotation.x = -.18 if quiet_time > 0 else 0.0
		if quiet_time > 0: medic.torso_node.rotation.x = maxf(.18, medic.torso_node.rotation.x)
