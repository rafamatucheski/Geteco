extends Node
var actor: CharacterBody2D
var patient: CharacterBody2D
var phase := "approach"
var timer := 0.0
var elapsed := 0.0
const RING_RADIUS := 80.0
const RING_SLOTS := 12
const PERSONAL_SPACE := 32.0
const CALL_DURATION := 5.0
var ring_offset := Vector2.INF
var calls_for_help := true
var navigation := preload("res://emergency/ResponderNavigation.gd").new()
var _physics := true
var _phone: MeshInstance3D
var _arm: Node3D
var _arm_transform := Transform3D.IDENTITY
var _upper: Node3D
var _upper_transform := Transform3D.IDENTITY

func reserve_position() -> bool:
	if calls_for_help:
		ring_offset = actor.global_position - patient.global_position
		return true
	# Reservations prevent simultaneous arrivals choosing the same empty spot.
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 7
	query.exclude = [actor.get_rid()]
	var best := INF
	for slot in RING_SLOTS:
		var offset := Vector2.from_angle(TAU * float(slot) / RING_SLOTS) * RING_RADIUS
		var point := patient.global_position + offset
		var reserved := false
		for other in actor.get_tree().get_nodes_in_group("medical_observer"):
			if other == self or not is_instance_valid(other.patient): continue
			if point.distance_to(other.patient.global_position + other.ring_offset) < PERSONAL_SPACE:
				reserved = true
				break
		if reserved: continue
		query.transform = Transform2D(0.0, point)
		if not actor.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		if not navigation.clear_segment(actor, point, patient.global_position): continue
		var cost := actor.global_position.distance_squared_to(point)
		if cost < best:
			best = cost
			ring_offset = offset
	return ring_offset.is_finite()

func _ready() -> void:
	if not ring_offset.is_finite() and not reserve_position():
		queue_free()
		return
	add_to_group("medical_observer")
	actor.set_meta("medical_witness", true)
	_physics = actor.is_physics_processing()
	actor.set_physics_process(false)
	actor.velocity = Vector2.ZERO
	# The caller stops where they noticed the casualty; reaching a crowded
	# ring position must never delay or silently replace the visible call.
	if calls_for_help:
		phase = "check"
		timer = 0.6
	if actor.has_method("ensure_presentation"): actor.ensure_presentation()
	if "right_lower_arm" in actor: _arm = actor.right_lower_arm
	if "right_upper_arm" in actor: _upper = actor.right_upper_arm
	if _upper: _upper_transform = _upper.transform
	if _arm:
		_arm_transform = _arm.transform
		_phone = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.075,.14,.025)
		_phone.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("17232b")
		_phone.material_override = mat
		_phone.position = Vector3(0,-.19,0)
		_arm.add_child(_phone)
		_phone.hide()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(patient) or not is_instance_valid(actor) or actor.is_dead or actor.get("is_incapacitated") == true or actor.get("is_scared") == true:
		queue_free()
		return
	if not patient.is_visible_in_tree() or (patient.get("is_dead") != true and patient.get("is_incapacitated") != true):
		queue_free()
		return
	var care := get_node("/root/NPCMedicalCare")
	var identity: String = patient.get_meta("medical_identity", "")
	var incident: Dictionary = care.incidents.get(identity, {})
	var unit: Variant = incident.get("unit")
	if is_instance_valid(unit) and unit.global_position.distance_squared_to(patient.global_position) < 180.0 * 180.0:
		# Resume walking as help arrives, freeing the approach corridor before
		# the stretcher and its two handles need this space.
		queue_free()
		return
	elapsed += delta
	if elapsed > 18:
		queue_free()
		return
	var model: Node3D = get_node("/root/NPCMedicalCare").model_for(actor)
	var direction := actor.global_position.direction_to(patient.global_position)
	if model: model.rotation.y = -direction.angle()-PI*.5
	if phase == "approach":
		var goal := patient.global_position + ring_offset
		if actor.global_position.distance_to(goal) > 3.0:
			var next := goal
			var center := patient.global_position
			var radial := actor.global_position - center
			var turn := wrapf(ring_offset.angle() - radial.angle(), -PI, PI)
			# Approach along the outside so seated ring members do not block
			# later arrivals trying to reach the far side of the casualty.
			if absf(turn) > 0.18:
				next = center + Vector2.from_angle(radial.angle() + clampf(turn, -0.25, 0.25)) * (RING_RADIUS + PERSONAL_SPACE + 8.0)
			actor.velocity = navigation.movement(actor, next, 55, delta)
			preload("res://world/shared/pedestrians/PersonMotion.gd").move_actor(actor)
			for key in ["left_upper_leg", "right_upper_leg"]:
				if key in actor and is_instance_valid(actor.get(key)): actor.get(key).rotation.x = sin(elapsed*7)*.3*(1 if key.begins_with("left") else -1)
		else:
			actor.velocity = Vector2.ZERO
			phase = "check"
			timer = 1.5
	else:
		timer -= delta
		if phase == "check" and timer <= 0:
			phase = "call" if calls_for_help else "wait"
			timer = CALL_DURATION if calls_for_help else 8.0
			if calls_for_help:
				if _phone: _phone.show()
				if _arm: _arm.rotation.x = -2.3
				if _upper: _upper.rotation = Vector3(-1.15,0,.4)
		elif phase == "call" and timer <= 0:
			get_node("/root/NPCMedicalCare").witness_called(patient)
			if _phone: _phone.hide()
			if _arm: _arm.transform = _arm_transform
			if _upper: _upper.transform = _upper_transform
			phase = "wait"
			timer = 3
		elif phase == "wait" and timer <= 0: queue_free()
	var viewport: SubViewport = get_node("/root/NPCMedicalCare").viewport_for(actor)
	if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _exit_tree() -> void:
	if is_instance_valid(_phone): _phone.queue_free()
	if is_instance_valid(_arm): _arm.transform = _arm_transform
	if is_instance_valid(_upper): _upper.transform = _upper_transform
	if is_instance_valid(actor):
		actor.velocity = Vector2.ZERO
		actor.remove_meta("medical_witness")
		actor.set_physics_process(_physics)
