extends Node2D
## Rodoviária: covered coach bays, guarded yard and the canonical street service.
signal player_disembarked
const BUS := preload("res://world/harbor/HarborTransitBus.gd")
const PASSENGER := preload("res://world/harbor/HarborTransitPassenger.gd")
# Keep the passenger queue and its approach south of Dante's arrival/phone spot.
# Returning passengers must never walk through the player while controls lock.
const QUEUE_LOCAL_Y := 95.0
var network: Node2D
var bus: Node2D
var passengers: Array[Node2D] = []
var visits := 1
var boarded := 0
var alighted := 0
var departures := 0
var _phase := "hold"
var _elapsed := 0.0
var _actor: CharacterBody2D
var _actor_route := PackedVector2Array()
var _actor_clock := 0.0
var _first_arrival := true
var _saved_physics := true
var _passenger_routes: Dictionary = {}
var terminal_view: Node2D
var terminal_operations: Node2D

func _ready() -> void:
	# Register before the parent populates traffic: the service bus is created
	# deferred, so it cannot yet be discovered by the factory's vehicle scan.
	add_to_group("traffic_spawn_exclusion")
	# Reserve both the local stop and the regional departure berth before cars spawn.
	set_meta("traffic_spawn_exclusion_rect", Rect2(1580, 1160, 535, 120))
	terminal_view = preload("res://world/harbor/terminal/HarborTerminalView.gd").new()
	terminal_view.name = "TerminalArchitecture"
	add_child(terminal_view)
	terminal_operations = preload("res://world/harbor/terminal/HarborTerminalOperations.gd").new()
	terminal_operations.name = "TerminalOperations"
	terminal_operations.architecture = terminal_view
	add_child(terminal_operations)
	call_deferred("_setup_service")

func _setup_service() -> void:
	network = get_parent().get_node("RoadNetwork")
	var lane: Path2D
	for candidate in network.find_children("*", "Path2D", true, false):
		if String(candidate.get_meta("traffic_road_id", "")).get_file() == "market_street" and int(candidate.get_meta("traffic_direction", 0)) == 1 and not bool(candidate.get_meta("is_lane_connector", false)):
			lane = candidate
			break
	if lane == null:
		push_error("Terminal requires Market Street platform-side lane")
		return
	var follow := PathFollow2D.new()
	follow.name = "HarborBusFollow"
	follow.loop = false
	lane.add_child(follow)
	follow.progress = lane.curve.get_closest_offset(lane.to_local(Vector2(1700, 1250)))
	bus = preload("res://cars/traffic/TrafficVehicle.tscn").instantiate()
	bus.set_script(BUS)
	bus.name = "HarborLocalBus"
	bus.station = self
	bus.stop_lane = lane
	bus.stop_offset = follow.progress
	follow.add_child(bus)
	for i in 4:
		var person := PASSENGER.new()
		person.name = "TerminalPassenger%d" % i
		person.district_theme = 1
		person.archetype_override = [1, 2, 6, 7][i]
		person.ambient_running_enabled = false
		person.base_walk_speed = 40.0
		person.position = _queue_slot(i)
		add_child(person)
		person.add_collision_exception_with(bus)
		person.set_destination(person.global_position, "waiting" if i < 2 else "onboard")
		if i >= 2:
			person.hide()
			person.set_physics_process(false)
		passengers.append(person)
	var state := get_node("/root/CampaignState")
	var saves := get_node("/root/SaveManager")
	var travel := get_node_or_null("/root/RegionTravel")
	var is_save: bool = (saves != null and saves.has_pending_save()) \
		or (get_parent() != null and bool(get_parent().get("loaded_from_save"))) \
		or (travel != null and not travel.pending_world.is_empty())
	_first_arrival = not is_save and not state.has_campaign_flag(&"harbor_arrival_seen")
	if not _first_arrival:
		_phase = "unload"

func prepare_player(actor: CharacterBody2D) -> void:
	var travel := get_node_or_null("/root/RegionTravel")
	var is_save: bool = (get_parent() != null and bool(get_parent().get("loaded_from_save"))) \
		or (travel != null and not travel.pending_world.is_empty())
	if not _first_arrival or is_save:
		if is_instance_valid(actor):
			actor.show()
		return
	_actor = actor
	_actor.hide()

func begin_player_disembark(actor: CharacterBody2D) -> void:
	_actor = actor
	_saved_physics = actor.is_physics_processing()
	actor.set_physics_process(false)
	actor.global_position = bus.door_position()
	actor.velocity = Vector2.ZERO
	actor.hide()
	_actor_route = PackedVector2Array([Vector2(actor.global_position.x, 1130), get_parent().get_node("ArrivalSpawn").global_position])
	_phase = "player_exit"
	bus.dwelling = true

func _physics_process(delta: float) -> void:
	if bus == null or bus._detached_from_lane:
		return
	_elapsed += delta
	_update_passenger_routes()
	for person in passengers:
		if person.transit_state == "onboard":
			person.global_position = bus.door_position() + Vector2(0, 12)
		if person.is_dead:
			person.transit_state = "unavailable"
	if _phase == "hold" or _phase == "away":
		return
	if _phase == "player_exit":
		_walk_player_off(delta)
		return
	if bus.doors < 0.95:
		return
	if _phase == "unload":
		# Finish each person's steps and aisle before the next one leaves. This
		# keeps the shared door clear and never asks opposing queues to overlap.
		if not _passenger_routes.is_empty():
			return
		for person in passengers:
			if person.transit_state == "onboard":
				if _elapsed < 1.3: return
				var door: Vector2 = bus.door_position()
				var slot := to_global(_queue_slot(passengers.find(person)))
				person.global_position = door + Vector2(0, 12)
				_passenger_route(person, [door, Vector2(door.x, slot.y + 32), Vector2(slot.x, slot.y + 32), slot], "alighting")
				person.show()
				person.set_physics_process(true)
				alighted += 1
				_elapsed = 0.0
				return
		_phase = "board"
	if _phase == "board":
		if not _passenger_routes.is_empty(): return
		for person in passengers:
			if person.transit_state == "waiting":
				var door: Vector2 = bus.door_position()
				var aisle_y: float = to_global(Vector2(0, QUEUE_LOCAL_Y)).y + 32
				_passenger_route(person, [Vector2(person.global_position.x, aisle_y), Vector2(door.x, aisle_y), door, door + Vector2(0, 12)], "boarding")
				return
		if _elapsed > 2.0:
			bus.depart()
			departures += 1
			_phase = "away"

func _queue_slot(index: int) -> Vector2:
	return Vector2(-112 + index * 36, QUEUE_LOCAL_Y)

func _passenger_route(person: Node2D, points: Array, state: String) -> void:
	_passenger_routes[person] = points.duplicate()
	person.set_destination(points[0], state)

func _update_passenger_routes() -> void:
	for person in _passenger_routes.keys():
		if not is_instance_valid(person) or person.is_dead or person.is_incapacitated:
			_passenger_routes.erase(person)
			continue
		if person.global_position.distance_to(person.destination) > 3.2: continue
		_passenger_routes[person].pop_front()
		if not _passenger_routes[person].is_empty():
			person.set_destination(_passenger_routes[person][0], person.transit_state)
			continue
		_passenger_routes.erase(person)
		if person.transit_state == "boarding":
			person.set_destination(person.global_position, "onboard")
			person.velocity = Vector2.ZERO
			person.hide()
			person.set_physics_process(false)
			boarded += 1
		else:
			person.set_destination(person.global_position, "resting")
		_elapsed = 0.0

func _walk_player_off(delta: float) -> void:
	if bus.doors < 0.95:
		return
	_actor.show()
	if _actor_route.is_empty():
		_actor.velocity = Vector2.ZERO
		_actor.set_physics_process(_saved_physics)
		_phase = "unload"
		_elapsed = 0.0
		player_disembarked.emit()
		return
	var difference := _actor_route[0] - _actor.global_position
	if difference.length() < 2:
		_actor_route.remove_at(0)
		return
	var motion := difference.limit_length(58.0 * delta)
	_actor.move_and_collide(motion)
	_actor_clock += delta * 7.5
	if _actor.model_root != null:
		_actor.model_root.rotation.y = lerp_angle(_actor.model_root.rotation.y, -atan2(difference.y, difference.x) - PI * 0.5, 1.0 - exp(-12.0 * delta))
		_actor.left_upper_leg.rotation.x = sin(_actor_clock) * 0.36
		_actor.right_upper_leg.rotation.x = -sin(_actor_clock) * 0.36

func bus_arrived() -> void:
	visits += 1
	_elapsed = 0.0
	for person in passengers:
		if person.transit_state == "resting":
			person.transit_state = "waiting"
	_phase = "unload"

func get_service_status() -> Dictionary:
	return {"phase": _phase, "visits": visits, "boarded": boarded, "alighted": alighted, "departures": departures, "passengers": passengers.size(), "distance": bus.distance_travelled if bus else 0.0}

func _exit_tree() -> void:
	if is_instance_valid(_actor) and _phase == "player_exit":
		_actor.set_physics_process(_saved_physics)
	# The bus's parent belongs to RoadNetwork, not this station.
	if is_instance_valid(bus) and bus.get_parent() is PathFollow2D:
		bus.get_parent().queue_free()

func bus_stolen() -> void:
	_phase = "away"
	_passenger_routes.clear()
	for person in passengers:
		if not is_instance_valid(person) or person.is_dead: continue
		if person.transit_state == "onboard": person.global_position = bus.door_position()
		person.show()
		person.set_physics_process(true)
		person.set_destination(person.global_position + Vector2(0,-45),"waiting")

func _draw() -> void:
	# Tactile edging joins the 3D terminal promenade to the active street stop.
	for x in [-60, -20, 20, 60]:
		draw_line(Vector2(x, 108), Vector2(x + 20, 108), Color("e6c46a"), 3)
