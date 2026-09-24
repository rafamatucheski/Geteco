extends Node3D
## Portaria física do Porto Sul: acesso autorizado, cancela segura e alarme
## quando alguém cruza o perímetro fora do corredor liberado.
const WORKER_MODEL := preload("res://gameplay/routines_v1/DockWorkerModel.gd")
const SCALE := 1.0 / 16.0
const GATE_POINT := Vector2(3310.0, 3380.0)
const GUARD_POINTS := [Vector2(3390,3340), Vector2(3430,3530), Vector2(3510,3540)]
const GATE_WIDTH := 104.0 * SCALE
const GATE_DEPTH := 0.16
const GATE_HEIGHT := 1.05
const GUARD_RANGE := 1.7

var session
var authorized_entry := false
var authorized_visit := false
var exiting_port := false
var alerted := false
var active := false
var _was_active := false
var gate_open := false
var was_inside := false
var initialized := false
var escape_clock := 0.0
var scan_clock := 0.0
var _gate_parts: Array[Dictionary] = []
var _staff: Array[Node3D] = []
var _gate_visuals: Node3D

func configure(owner_session) -> void:
	session = owner_session
	name = "HarborPortSecurity"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	_build_gate()
	_build_staff()
	active = session != null and session.state.region_id == "harbor"
	_was_active = active
	_gate_visuals.visible = active
	for staff in _staff: staff.visible = active
	for part in _gate_parts:
		(part.collision as CollisionShape3D).disabled = not active
	set_process(true)

func _build_gate() -> void:
	_gate_visuals = Node3D.new()
	_gate_visuals.name = "FreightGates"
	add_child(_gate_visuals)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e4ddc7")
	material.roughness = 0.82
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color("c3583f")
	stripe.roughness = 0.78
	for index in 2:
		var part := Node3D.new()
		part.name = "FreightGateWest" if index == 0 else "FreightGateEast"
		part.position = _world_point(GATE_POINT)
		_gate_visuals.add_child(part)
		var direction := 1.0 if index == 0 else -1.0
		var hinge := Node3D.new()
		hinge.name = "Boom"
		hinge.position = Vector3(direction * GATE_WIDTH * 0.5, 0.84, 0.0)
		var boom := MeshInstance3D.new()
		boom.name = "Barrier"
		var boom_mesh := BoxMesh.new()
		boom_mesh.size = Vector3(GATE_WIDTH * 0.5, 0.12, 0.10)
		boom.mesh = boom_mesh
		boom.position.x = -direction * GATE_WIDTH * 0.25
		boom.material_override = material
		hinge.add_child(boom)
		part.add_child(hinge)
		for stripe_index in 6:
			var mark := MeshInstance3D.new()
			var mark_mesh := BoxMesh.new()
			mark_mesh.size = Vector3(0.21, 0.125, 0.105)
			mark.mesh = mark_mesh
			mark.position = Vector3(-direction * (0.18 + stripe_index * 0.43), 0.0, -0.053)
			mark.material_override = stripe
			boom.add_child(mark)
		var body := StaticBody3D.new()
		body.name = "GateCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(GATE_WIDTH * 0.5 + 0.06, GATE_HEIGHT, GATE_DEPTH)
		collision.shape = shape
		collision.position = Vector3(direction * GATE_WIDTH * 0.25, GATE_HEIGHT * 0.5, 0.0)
		body.add_child(collision)
		part.add_child(body)
		_gate_parts.append({"root":part,"hinge":hinge,"body":body,"collision":collision,"direction":direction})
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = Color("46514d")
	for x_offset in [-GATE_WIDTH * 0.5, GATE_WIDTH * 0.5]:
		var post := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.12
		mesh.bottom_radius = 0.16
		mesh.height = 0.95
		post.mesh = mesh
		post.material_override = post_material
		post.position = _world_point(GATE_POINT) + Vector3(x_offset, 0.48, 0.0)
		_gate_visuals.add_child(post)

func _build_staff() -> void:
	for index in GUARD_POINTS.size():
		var guard := Node3D.new()
		guard.name = "PortSecurityStaff%d" % index
		guard.position = _world_point(GUARD_POINTS[index])
		guard.add_to_group("port_staff")
		guard.add_to_group("v1_routine_actor")
		guard.set_meta("gameplay_role", "ambient_worker")
		guard.set_meta("port_security_staff", true)
		add_child(guard)
		var model = WORKER_MODEL.new()
		model.worker_index = 36 + index
		guard.add_child(model)
		model.set_process(false)
		model.set_physics_process(false)
		_staff.append(guard)

func nearest_action() -> Dictionary:
	if not _available() or session.world.driving.occupied: return {}
	var actor: Node3D = session.world.player
	for guard in _staff:
		if is_instance_valid(guard) and actor.global_position.distance_to(guard.global_position) <= GUARD_RANGE:
			return {"id":"port_security","target":"south_port_checkpoint","label":"Conversar"}
	return {}

func perform(target: String) -> bool:
	if target != "south_port_checkpoint" or nearest_action().is_empty(): return false
	if authorized_entry or authorized_visit:
		session.show_message("GUARDA: Sua passagem já está autorizada.")
		return true
	session._menu("Portaria")
	var speech := Label.new()
	speech.text = "GUARDA: Por que você quer entrar no porto?\nSem autorização, a segurança será avisada."
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.custom_minimum_size.x = 560
	session.column.add_child(speech)
	session._button("Pagar propina · R$ 100", _pay_bribe)
	session._button("Dar meia-volta", Callable(session, "close_menu"))
	return true

func _pay_bribe() -> void:
	if not _available() or authorized_entry or authorized_visit: return
	if not session.state.spend(100, "south_port_bribe:" + session._transaction()):
		session.show_message("GUARDA: São R$ 100. Saldo insuficiente.")
		return
	authorized_entry = true
	_alerted_reset()
	session.close_menu()
	session.show_message("GUARDA: Pode entrar. A cancela está liberada.")

func _process(delta: float) -> void:
	if session == null or not is_instance_valid(session.world.player): return
	# Entering a building must not revoke an open visit or close a gate on its user.
	if not session.state.place_id.is_empty(): return
	scan_clock -= delta
	if scan_clock > 0.0: return
	var step := maxf(0.05, 0.1 - scan_clock)
	scan_clock = 0.1
	var point := _actor_position_now()
	active = session.state.region_id == "harbor"
	if active != _was_active:
		_gate_visuals.visible = active
		for staff in _staff: staff.visible = active
		for part in _gate_parts:
			(part.collision as CollisionShape3D).set_deferred("disabled", not active or gate_open)
		_was_active = active
	if not active:
		gate_open = false
		for part in _gate_parts:
			(part.collision as CollisionShape3D).set_deferred("disabled", true)
			(part.hinge as Node3D).rotation.y = 0.0
		return
	var inside := _inside_security_zone(point)
	if not initialized:
		was_inside = inside # A save que já deixou o jogador no porto não vira invasão.
		initialized = true
	elif inside and not was_inside:
		if authorized_entry:
			authorized_visit = true
			authorized_entry = false
			_alerted_reset()
			session.save_game()
		else:
			_raise_alarm(point)
	elif was_inside and not inside:
		exiting_port = true
		if authorized_visit: _alerted_reset()
	was_inside = inside
	if exiting_port and point.z < GATE_POINT.y * SCALE - 1.0:
		exiting_port = false
		authorized_visit = false
		authorized_entry = false
		_alerted_reset()
	if authorized_entry and not inside and point.distance_to(_world_point(GATE_POINT)) > 24.0:
		authorized_entry = false
	var should_open := authorized_entry or authorized_visit or exiting_port or _emergency_near_gate()
	if gate_open and _gate_occupied(): should_open = true
	_set_gate(should_open)
	if alerted:
		if inside: escape_clock = 0.0
		else: escape_clock += step
		if escape_clock >= 10.0: _alerted_reset()

func _raise_alarm(point: Vector3) -> void:
	if alerted: return
	alerted = true
	escape_clock = 0.0
	session.show_message("GUARDA: Invasor no porto! Segurança avisada.")
	if is_instance_valid(session.world.gameplay): session.world.gameplay.register_crime(30, point)

func _alerted_reset() -> void:
	alerted = false
	escape_clock = 0.0

func _actor_position_now() -> Vector3:
	if session.world.driving.occupied and is_instance_valid(session.world.driving.car): return session.world.driving.car.global_position
	return session.world.player.global_position

func _gate_occupied() -> bool:
	if not active or _gate_parts.is_empty(): return false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(GATE_WIDTH, 2.8, 1.25)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _world_point(GATE_POINT) + Vector3(0, 1.25, 0))
	query.collision_mask = 7
	for part in _gate_parts: query.exclude.append((part.body as StaticBody3D).get_rid())
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var collider: Variant = hit.get("collider")
		if collider is CharacterBody3D: return true
	return false

func _emergency_near_gate() -> bool:
	for vehicle in get_tree().get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(vehicle) and vehicle is Node3D and vehicle.global_position.distance_to(_world_point(GATE_POINT)) <= 14.0: return true
	return false

func _set_gate(open: bool) -> void:
	if gate_open == open: return
	gate_open = open
	for part in _gate_parts:
		var collision := part.collision as CollisionShape3D
		collision.set_deferred("disabled", not active or open)
		var hinge := part.hinge as Node3D
		var direction: float = float(part.direction)
		hinge.rotation.y = -direction * PI * 0.48 if open else 0.0

func _inside_security_zone(point: Vector3) -> bool:
	var authored := Vector2(point.x / SCALE, point.z / SCALE)
	return (authored.x >= 3200.0 and authored.x <= 6100.0 and authored.y > 3400.0 and authored.y < 6000.0) \
		or (authored.x > 3620.0 and authored.x < 6100.0 and authored.y >= 3200.0 and authored.y <= 3400.0)

func _available() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "harbor" and session.state.place_id.is_empty() and session.world.gameplay.health > 0 and not session.is_transition_blocked()

func _world_point(source: Vector2) -> Vector3:
	return Vector3(source.x * SCALE, 0.0, source.y * SCALE)
