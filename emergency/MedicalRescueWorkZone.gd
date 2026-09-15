extends StaticBody2D
## Local working clearance follows the real crew and cot, never their visual lift.
const GROUP := &"medical_rescue_work_zone"
const PROTECTED := &"medical_vehicle_protected"
var active := false
var sequence: Node
var ambulance: Node2D
var crew: Array = []
var _protected: Array[Node2D] = []
var _allowed: Array[PhysicsBody2D] = []
var _shields: Array[CollisionShape2D] = []
var _detached := false

func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 0
	process_physics_priority = -100
	for i in 6:
		var shield := CollisionShape2D.new()
		shield.shape = CircleShape2D.new()
		shield.disabled = true
		add_child(shield)
		_shields.append(shield)

func sync(source: Node) -> void:
	sequence = source
	ambulance = source.ambulance
	crew = source.crew.duplicate()
	_refresh()

func detach_sequence() -> void:
	sequence = null
	_detached = true
	_refresh()

func _physics_process(_delta: float) -> void:
	_refresh()

func _allow_actor(actor: Node2D) -> void:
	if actor is PhysicsBody2D and not _allowed.has(actor):
		add_collision_exception_with(actor)
		actor.add_collision_exception_with(self)
		_allowed.append(actor)

func _add_shield(index: int, point: Vector2, radius: float, actor: Node2D = null) -> int:
	var shield := _shields[index]
	shield.global_position = point
	shield.shape.radius = radius
	shield.disabled = false
	if is_instance_valid(actor):
		actor.set_meta(PROTECTED, true)
		_protected.append(actor)
		_allow_actor(actor)
	return index + 1

func _refresh() -> void:
	if not is_inside_tree(): return
	for actor in _protected:
		if is_instance_valid(actor): actor.remove_meta(PROTECTED)
	_protected.clear()
	for shield in _shields: shield.disabled = true
	active = false
	collision_layer = 0
	if _shields.is_empty(): return
	if is_instance_valid(sequence) and sequence.phase in ["transport", "parked"]: return
	var count := 0
	if is_instance_valid(ambulance): _allow_actor(ambulance)
	for medic in crew:
		if is_instance_valid(medic) and medic.is_visible_in_tree() and not medic.is_queued_for_deletion():
			count = _add_shield(count, medic.global_position, 27.0, medic)
	if is_instance_valid(sequence):
		var cot: Node2D = sequence.stretcher
		if is_instance_valid(cot):
			_allow_actor(cot)
			if cot.is_visible_in_tree(): count = _add_shield(count, cot.global_position, 37.0, cot)
		var patient: Node2D = sequence.patient
		if is_instance_valid(patient):
			_allow_actor(patient)
			if sequence.carrying or sequence.delivered:
				if is_instance_valid(cot) and cot.is_visible_in_tree():
					patient.set_meta(PROTECTED, true)
					_protected.append(patient)
			elif patient.is_visible_in_tree(): count = _add_shield(count, patient.global_position, 30.0, patient)
		if sequence.phase in ["exit", "fetch", "open_rear", "unload_stretcher"] and is_instance_valid(ambulance):
			count = _add_shield(count, sequence.rear_point(), 37.0)
		# Keep the validated door/cot working space reserved for the entire
		# roadside treatment. Following traffic must not occupy it while the
		# medics are away at the patient and block the return to the rear doors.
		if not sequence.hospital_delivery and ambulance.has_meta("ambulance_parking_goal"):
			var shield := _shields[5]
			if not shield.shape is RectangleShape2D: shield.shape = RectangleShape2D.new()
			var planner = ambulance.get("_ambulance_approach")
			var half: Vector2 = planner._half_size(ambulance)
			var rear: float = planner.rear_distance(ambulance)+34
			shield.shape.size = Vector2(half.x+10+rear,(half.y+32)*2)
			shield.global_transform = ambulance.global_transform * Transform2D(0,Vector2((half.x+10-rear)*.5,0))
			shield.disabled = false
			count += 1
	# The player on foot can reach the crew without hitting vehicle clearance.
	for player in get_tree().get_nodes_in_group("player"):
		if player is PhysicsBody2D and not player.is_in_group("vehicle"): _allow_actor(player)
	active = count > 0
	collision_layer = 2 if active else 0
	if _detached and not active: queue_free()

func _exit_tree() -> void:
	for actor in _allowed:
		if is_instance_valid(actor):
			actor.remove_collision_exception_with(self)
			remove_collision_exception_with(actor)
	_allowed.clear()
	for actor in _protected:
		if is_instance_valid(actor): actor.remove_meta(PROTECTED)

static func blocks_hull(vehicle: Node2D, shape: Shape2D, pose: Transform2D) -> bool:
	for zone in vehicle.get_tree().get_nodes_in_group(GROUP):
		if not zone.active or zone.ambulance == vehicle: continue
		for shield in zone._shields:
			if not shield.disabled and shape.collide(pose, shield.shape, shield.global_transform): return true
	return false

static func has_zones(vehicle: Node2D) -> bool:
	for zone in vehicle.get_tree().get_nodes_in_group(GROUP):
		if zone.active and zone.ambulance != vehicle: return true
	return false

static func lane_clearance(vehicle: Node2D, path: Path2D, follow: PathFollow2D, braking: float, speed: float) -> float:
	if not has_zones(vehicle): return INF
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision == null: collision = vehicle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null: return INF
	var horizon := maxf(60.0, speed * speed / (2.0 * braking) + 20.0)
	var distance := 0.0
	while distance <= horizon:
		var offset := follow.progress + distance
		if follow.loop: offset = fposmod(offset, path.curve.get_baked_length())
		else: offset = minf(offset, path.curve.get_baked_length())
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, follow.cubic_interp) * vehicle.transform * collision.transform
		if blocks_hull(vehicle, collision.shape, pose): return maxf(0.0, distance - 8.0)
		distance += 4.0
	return INF

static func limit_player_motion(vehicle: CharacterBody2D) -> void:
	if not vehicle.is_in_group("vehicle") and not vehicle.is_in_group("ambient_traffic"): return
	if not has_zones(vehicle): return
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision == null: collision = vehicle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null: return
	# Steering happens before move(). A blocked turn cannot swing the side of
	# a stopped car through the team. Restore only the last rotation at this
	# same position; activating clearance never relocates an existing vehicle.
	if blocks_hull(vehicle, collision.shape, collision.global_transform):
		var safe_pose: Transform2D = vehicle.get_meta("vehicle_safe_transform", vehicle.global_transform)
		if safe_pose.origin.distance_squared_to(vehicle.global_position) < 0.0001 and not blocks_hull(vehicle, collision.shape, safe_pose * collision.transform):
			vehicle.global_transform = safe_pose
		vehicle.velocity = Vector2.ZERO
		return
	if vehicle.velocity.is_zero_approx(): return
	var speed := vehicle.velocity.length()
	var direction := vehicle.velocity / speed
	var braking := 700.0
	var horizon := speed * speed / (2.0 * braking) + speed * vehicle.get_physics_process_delta_time() + 16.0
	var distance := 0.0
	while distance <= horizon:
		var pose := collision.global_transform
		pose.origin += direction * distance
		if blocks_hull(vehicle, collision.shape, pose):
			var clearance := maxf(0.0, distance - 8.0)
			vehicle.velocity = direction * minf(speed, minf(sqrt(2.0 * braking * clearance), clearance / maxf(0.001, vehicle.get_physics_process_delta_time())))
			return
		distance += 4.0
