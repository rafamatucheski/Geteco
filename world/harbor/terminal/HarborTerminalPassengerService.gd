extends Node
## Persistent passengers cross the steps, wait on their platform, and travel with their coach.
const TRAVELER := preload("res://world/harbor/terminal/HarborTerminalTraveler.gd")
const POOL_SIZE := 4
const INITIAL_ONBOARD := 2
var operations: Node2D
var people: Array[Node2D] = []
var history: Array[Dictionary] = []
var phase := "away"
var boarded := 0
var alighted := 0
var rng := RandomNumberGenerator.new()
var _slots: Dictionary = {}
var _routes: Dictionary = {}
var _board_queue: Array[Node2D] = []
var _exit_queue: Array[Node2D] = []
var _active_boarder: Node2D
var _gap := 0.0
var _clock := 0.0
var _manifest: Dictionary = {}

func doorway() -> Vector2:
	return Vector2(operations.bay_x() + 13, -123)

func interior() -> Vector2:
	return doorway() + Vector2(-10, 0)

func aisle() -> Vector2:
	return doorway() + Vector2(15, 0)

func _slot_point(slot: int) -> Vector2:
	return Vector2(operations.bay_x() + 70, [-146.0, -114.0, -74.0, -42.0][slot])

func _ready() -> void:
	rng.seed = 8300 + operations.platform_index * 173
	for index in POOL_SIZE:
		var person := TRAVELER.new()
		person.name = "Platform%dTraveler%d" % [operations.platform_index + 1, index]
		person.district_theme = 1
		person.archetype_override = (index + operations.platform_index) % 8
		person.appearance_seed = rng.randi_range(10000, 900000)
		person.ambient_running_enabled = false
		person.position = _slot_point(index) if index < 2 else interior()
		operations.add_child(person)
		person.base_walk_speed = rng.randf_range(24.0, 31.0)
		person.get_node("CollisionShape2D").shape.radius = 4.5
		person.add_collision_exception_with(operations.coach)
		if is_instance_valid(operations.architecture):
			person.attach_to_terminal(operations.architecture.model)
		people.append(person)
		if index < 2:
			_slots[person] = index
			person.set_destination(person.global_position, "waiting")
		else:
			_set_onboard(person)
	_sync_models()

func _healthy(person: Node2D) -> bool:
	return is_instance_valid(person) and not person.is_dead and not person.is_incapacitated

func onboard_count() -> int:
	var result := 0
	for person in people:
		result += int(person.transit_state == "onboard")
	return result

func begin_stop() -> void:
	_board_queue.clear()
	_exit_queue.clear()
	for person in people:
		if not _healthy(person):
			continue
		if person.transit_state == "onboard":
			_exit_queue.append(person)
		elif person.transit_state in ["waiting", "resting"]:
			_board_queue.append(person)
	_manifest = {"boarding": _board_queue.size(), "alighting": _exit_queue.size(), "boarded": 0, "alighted": 0}
	_clock = 0
	_gap = 0.6
	phase = "alighting"

func cancel_service() -> void:
	phase = "away"
	_board_queue.clear()
	_exit_queue.clear()
	_routes.clear()
	_active_boarder = null
	for person in people:
		if not _healthy(person): continue
		if person.transit_state == "onboard":
			person.global_position = operations.coach.to_global(Vector2(25,30))
		person.show()
		person.model_root.show()
		person.set_physics_process(true)
		person.set_destination(person.global_position,"waiting")

func update(delta: float) -> void:
	_update_routes()
	_sync_models()
	if phase in ["away", "complete"]:
		return
	_clock += delta
	if operations.door_amount < 0.95 or operations.current_speed > 0.01:
		return
	_gap -= delta
	if phase == "alighting":
		if not _exit_queue.is_empty() and _gap <= 0.0 and _door_clear():
			var person: Node2D = _exit_queue.pop_front()
			if _healthy(person):
				var slot := _free_slot()
				_slots[person] = slot
				# Reveal behind the coach's opaque shell, then walk through its steps.
				# The person only becomes visible outside the door by moving there.
				person.position = interior()
				_route(person, [doorway(), aisle(), Vector2(aisle().x, _slot_point(slot).y), _slot_point(slot)], "alighting")
				_sync_models()
				person.show()
				person.model_root.show()
				person.set_physics_process(true)
				_gap = 1.15
		elif _exit_queue.is_empty() and _routes.is_empty():
			phase = "boarding"
			_gap = 0.7
	elif phase == "boarding":
		if is_instance_valid(_active_boarder):
			if not _healthy(_active_boarder):
				_routes.erase(_active_boarder)
				_active_boarder = null
			elif _active_boarder.position.distance_to(interior()) <= 3.2:
				_set_onboard(_active_boarder)
				boarded += 1
				_manifest.boarded += 1
				_active_boarder = null
				_gap = 1.0
		elif not _board_queue.is_empty() and _gap <= 0.0:
			var person: Node2D = _board_queue.pop_front()
			if _healthy(person):
				_active_boarder = person
				_route(person, [Vector2(aisle().x, person.position.y), aisle(), doorway(), interior()], "boarding")
		elif _board_queue.is_empty() and _clock > 8.0 and _door_clear():
			phase = "complete"
			_manifest.seconds = snappedf(_clock, 0.1)
			history.append(_manifest.duplicate())
			if history.size() > 12:
				history.pop_front()

func _route(person: Node2D, points: Array, state: String) -> void:
	_routes[person] = points.duplicate()
	person.set_destination(operations.to_global(points[0]), state)

func _update_routes() -> void:
	for person in _routes.keys():
		if not _healthy(person):
			_routes.erase(person)
			continue
		if person.global_position.distance_to(person.destination) > 3.2:
			continue
		var reached: Vector2 = _routes[person].pop_front()
		if person.transit_state == "alighting" and reached == doorway():
			alighted += 1
			_manifest.alighted += 1
		if _routes[person].is_empty():
			_routes.erase(person)
			if person.transit_state == "alighting":
				person.set_destination(person.global_position, "waiting")
		else:
			person.set_destination(operations.to_global(_routes[person][0]), person.transit_state)

func _door_clear() -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	query.shape = shape
	query.transform = Transform2D(0.0, operations.to_global(doorway()))
	query.collision_mask = 4
	return operations.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _free_slot() -> int:
	for index in POOL_SIZE:
		if not _slots.values().has(index):
			return index
	return POOL_SIZE - 1

func _set_onboard(person: Node2D) -> void:
	_slots.erase(person)
	_routes.erase(person)
	person.set_destination(person.global_position, "onboard")
	person.velocity = Vector2.ZERO
	person.hide()
	if is_instance_valid(person.model_root):
		person.model_root.hide()
	person.set_physics_process(false)

func _sync_models() -> void:
	if not is_instance_valid(operations.architecture):
		return
	for person in people:
		if not is_instance_valid(person.model_root):
			continue
		if person.transit_state == "onboard":
			# Hidden passengers stay attached to the physical coach during the trip.
			person.position = operations.coach.position
		var step := clampf((doorway().x + 3.0 - person.position.x) / 13.0, 0.0, 1.0)
		var height := 0.04 + step * 0.30 if person.transit_state in ["boarding", "alighting"] else 0.04
		person.model_root.position = operations.architecture.floor_from_local(person.position) + Vector3.UP * height

func _exit_tree() -> void:
	for person in people:
		if is_instance_valid(person) and is_instance_valid(person.model_root):
			person.model_root.queue_free()
