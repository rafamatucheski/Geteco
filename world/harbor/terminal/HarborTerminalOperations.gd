extends Node2D
## Four scheduled coaches physically use their platforms and the Harbor street circuit.
const COACH_SERVICE := preload("res://world/harbor/terminal/HarborTerminalCoachService.gd")
var architecture: Node2D
var fleet: Array[Node2D] = []
var gates: Array[Dictionary] = []
var apron_owner: Node2D
var _native_nodes: Array[Node3D] = []
const GATE_CHECK_SECONDS := 2.2
var gate_requests := 0
var gate_authorizations := 0
var gate_passages := 0
# First-service aliases retained for scene inspection and the existing capture tools.
var coach: CharacterBody2D
var coach_model: Node3D
var passengers: Array[Node2D] = []
var passenger_service: Node
var exits: int:
	get:
		var count := 0
		for service in fleet: count += service.exits
		return count
var entries: int:
	get:
		var count := 0
		for service in fleet: count += service.entries
		return count

func _ready() -> void:
	add_to_group("harbor_terminal_operations")
	_create_gate("Entrada", Vector2(360, 125))
	_create_gate("Saida", Vector2(250, 125))
	for index in 4:
		var service := COACH_SERVICE.new()
		service.name = "PlatformService%02d" % (index + 1)
		service.operations = self
		service.architecture = architecture
		service.platform_index = index
		add_child(service)
		fleet.append(service)
	coach = fleet[0].coach
	coach_model = fleet[0].coach_model
	passenger_service = fleet[0].passenger_service
	for service in fleet:
		passengers.append_array(service.passenger_service.people)
	if is_instance_valid(architecture):
		architecture.set_animation_active(true)

func _create_gate(label: String, point: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = label + "Barrier"
	body.position = point
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(76, 4)
	collision.shape = rectangle
	body.add_child(collision)
	add_child(body)
	var gate := {"name": label, "point": point, "collision": collision, "opening": 0.0, "arm": null,
		"state": "closed", "owner": null, "queue": [], "timer": 0.0, "entered": false,
		"signals": [], "request_lamp": null, "requests": 0, "authorizations": 0, "passages": 0}
	if is_instance_valid(architecture):
		var stand := Node3D.new()
		stand.position = architecture.floor_from_local(point - Vector2(38, 0))
		architecture.model.add_child(stand)
		_native_nodes.append(stand)
		_box(stand, Vector3(0, 0.60, 0), Vector3(0.38, 1.20, 0.40), Color("e7bc4b"))
		var arm := Node3D.new()
		arm.position.y = 1.22
		stand.add_child(arm)
		_box(arm, Vector3(2.11, 0, 0), Vector3(4.22, 0.12, 0.14), Color("f8ebce"))
		for stripe in 8:
			_box(arm, Vector3(0.28 + stripe * 0.51, 0, 0), Vector3(0.20, 0.125, 0.15), Color("bf4537"))
		gate.arm = arm
		# A driver calls the staffed booth; amber means checking, green means
		# permission. The physical arm still has to finish opening afterward.
		_box(stand, Vector3(0, 1.99, 0), Vector3(0.42, 1.02, 0.38), Color("29363c"))
		for index in 3:
			var lamp := _box(stand, Vector3(0, 2.31 - index * .30, .21), Vector3(.25, .22, .07), Color("283430"))
			gate.signals.append(lamp.material_override)
		var intercom := Node3D.new()
		intercom.position = architecture.floor_from_local(point + Vector2(-38 if label == "Entrada" else 38, 16 if label == "Entrada" else -16))
		architecture.model.add_child(intercom)
		_native_nodes.append(intercom)
		_box(intercom, Vector3(0, .8, 0), Vector3(.18, 1.6, .18), Color("53666b"))
		_box(intercom, Vector3(0, 1.63, 0), Vector3(.42, .56, .26), Color("25343b"))
		for line in 3: _box(intercom, Vector3(0, 1.73 + line * .06, .14), Vector3(.26, .018, .03), Color("a5bab7"))
		gate.request_lamp = _box(intercom, Vector3(0, 1.51, .15), Vector3(.12, .12, .04), Color("34433e")).material_override
	gates.append(gate)

func request_apron(service: Node2D) -> bool:
	if not is_instance_valid(apron_owner):
		apron_owner = service
	return apron_owner == service

func release_apron(service: Node2D) -> void:
	if apron_owner == service:
		apron_owner = null

func _physics_process(delta: float) -> void:
	var guard_active := false
	for gate in gates:
		_tick_gate(gate, delta)
		guard_active = guard_active or gate.state in ["checking", "opening", "passing"]
	if is_instance_valid(architecture) and architecture.model.has_method("set_guard_authorization"):
		architecture.model.set_guard_authorization(guard_active)

func configure_gate_route(service: Node2D) -> float:
	var index := 0 if service.state == "arriving" else (1 if service.state == "departing" else -1)
	if index < 0: return INF
	var gate: Dictionary = gates[index]
	var distance := 0.0
	# Find the first *swept hull* contact, including the entrance's curved
	# approach. Stopping the vehicle centre at a marker would put its nose
	# through the arm before the driver ever requested permission.
	while distance <= service.route.get_baked_length():
		var shape: Shape2D = service._shape_for_heading(service._route_heading(distance))
		var pose := Transform2D(0.0, service.to_global(service.route.sample_baked(distance)))
		if shape.collide(pose, gate.collision.shape, gate.collision.global_transform): return maxf(0.0, distance - 9.0)
		distance += 1.0
	return INF

func gate_clearance(service: Node2D) -> float:
	if service.gate_passed: return INF
	var index := 0 if service.state == "arriving" else (1 if service.state == "departing" else -1)
	if index < 0: return INF
	var gate: Dictionary = gates[index]
	if gate.owner == service and gate.state == "passing" and float(gate.opening) >= .99: return INF
	var distance := maxf(0.0, service.gate_stop_progress - service.route_progress)
	if distance <= .25 and service.current_speed <= 1.0:
		if gate.owner != service and not gate.queue.has(service):
			gate.queue.append(service)
			gate.requests += 1
			gate_requests += 1
	return distance

func _gate_occupied(gate: Dictionary) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var zone := RectangleShape2D.new()
	zone.size = Vector2(76, 16)
	query.shape = zone
	query.transform = gate.collision.global_transform
	query.collision_mask = 1 | 2 | 4
	query.exclude = [gate.collision.get_parent().get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _owner_cleared(gate: Dictionary) -> bool:
	if not is_instance_valid(gate.owner) or not is_instance_valid(gate.owner.coach): return true
	var service: Node2D = gate.owner
	var direction := -1.0 if gate.name == "Entrada" else 1.0
	for corner in service.coach_shape.shape.points:
		var point := to_local(service.coach_shape.to_global(corner))
		if (point.y - float(gate.point.y)) * direction < 9.0: return false
	return true

func _tick_gate(gate: Dictionary, delta: float) -> void:
	for service in fleet:
		if service.state != "stolen" or not is_instance_valid(service.coach) or not service.coach.is_driven_by_player: continue
		if service.coach.global_position.distance_to(to_global(gate.point)) < 100.0 and gate.owner != service and not gate.queue.has(service):
			gate.queue.append(service)
	gate.timer += delta
	if gate.state == "closed":
		while not gate.queue.is_empty() and not is_instance_valid(gate.queue[0]): gate.queue.pop_front()
		if not gate.queue.is_empty():
			gate.owner = gate.queue.pop_front()
			gate.state = "checking"
			gate.timer = 0.0
	elif gate.state == "checking":
		if not is_instance_valid(gate.owner):
			gate.state = "closed"
		elif float(gate.timer) >= GATE_CHECK_SECONDS and not _gate_occupied(gate):
			gate.state = "opening"
			gate.authorizations += 1
			gate_authorizations += 1
	elif gate.state == "opening":
		gate.opening = move_toward(float(gate.opening), 1.0, delta * .85)
		if float(gate.opening) >= 1.0:
			gate.state = "passing"
			gate.entered = false
	elif gate.state == "passing":
		if _gate_occupied(gate): gate.entered = true
		if _owner_cleared(gate) and not _gate_occupied(gate):
			if is_instance_valid(gate.owner): gate.owner.gate_passed = true
			gate.passages += 1
			gate_passages += 1
			gate.owner = null
			gate.state = "closing"
	elif gate.state == "closing":
		# A person stepping onto the threshold keeps the arm raised. Never
		# lower a collider onto a pedestrian or the back of a long coach.
		if _gate_occupied(gate):
			gate.opening = move_toward(float(gate.opening), 1.0, delta * .85)
		else:
			gate.opening = move_toward(float(gate.opening), 0.0, delta * .85)
			if float(gate.opening) <= 0.0: gate.state = "closed"
	gate.collision.set_deferred("disabled", float(gate.opening) > .05 or _gate_occupied(gate))
	var signal_index := 2 if gate.state in ["opening", "passing"] else (1 if gate.state == "checking" else 0)
	var colors := [Color("ed5344"), Color("ffd365"), Color("64eaa5")]
	for index in gate.signals.size():
		var material: StandardMaterial3D = gate.signals[index]
		material.albedo_color = colors[index] if index == signal_index else Color("253331")
		material.emission_enabled = index == signal_index
		material.emission = colors[index] if index == signal_index else Color.BLACK
	if gate.request_lamp != null:
		var pulse: bool = gate.state == "checking" and fmod(float(gate.timer), .5) < .3
		gate.request_lamp.albedo_color = Color("84e4ec") if pulse else Color("34433e")
		gate.request_lamp.emission_enabled = pulse
		gate.request_lamp.emission = Color("63dce8")
	if is_instance_valid(gate.arm):
		gate.arm.rotation.z = float(gate.opening) * PI * 0.49

func get_operation_status() -> Dictionary:
	var status := {"entries": 0, "exits": 0, "bay_visits": 0, "distance": 0.0, "boarded": 0, "alighted": 0, "people": passengers.size(), "fleet": [], "gate_requests": gate_requests, "gate_authorizations": gate_authorizations, "gate_passages": gate_passages}
	for service in fleet:
		status.entries += service.entries
		status.exits += service.exits
		status.bay_visits += service.bay_visits
		status.distance += service.distance_travelled
		status.boarded += service.passenger_service.boarded
		status.alighted += service.passenger_service.alighted
		status.fleet.append({"platform": service.platform_index + 1, "state": service.state, "position": service.coach.position, "speed": service.current_speed, "blocked": service.blocked, "blocked_by": service.blocked_by, "passengers": service.passenger_service.phase, "trips": service.completed_laps})
	return status

func _exit_tree() -> void:
	for node in _native_nodes:
		if is_instance_valid(node):
			node.queue_free()

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.layers = 128
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	mesh.material_override = material
	mesh.position = point
	parent.add_child(mesh)
	return mesh

