extends Node2D
## One-platform urban terminal. Service uses the canonical street network.
signal player_disembarked
const BUS := preload("res://district/harbor_preview/HarborTransitBus.gd")
const PASSENGER := preload("res://district/harbor_preview/HarborTransitPassenger.gd")
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

func _ready() -> void:
	# Register before the parent populates traffic: the service bus is created
	# deferred, so it cannot yet be discovered by the factory's vehicle scan.
	add_to_group("traffic_spawn_exclusion")
	set_meta("traffic_spawn_exclusion_rect", Rect2(1580, 1160, 240, 120))
	for rect in [Rect2(-82, -27, 164, 8), Rect2(-82, -19, 7, 46), Rect2(75, -19, 7, 46)]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		collider.position = rect.get_center()
		body.add_child(collider)
		add_child(body)
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
	bus = preload("res://city_demo/scenes/TrafficVehicle.tscn").instantiate()
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
		person.position = Vector2(-90 + i * 23, QUEUE_LOCAL_Y)
		add_child(person)
		person.set_destination(person.global_position, "waiting" if i < 2 else "onboard")
		if i >= 2:
			person.hide()
			person.set_physics_process(false)
		passengers.append(person)
	var state := get_node("/root/CampaignState")
	var saves := get_node("/root/SaveManager")
	_first_arrival = not saves.has_pending_save() and not state.has_campaign_flag(&"harbor_arrival_seen")
	if not _first_arrival:
		_phase = "unload"

func prepare_player(actor: CharacterBody2D) -> void:
	if not _first_arrival:
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
	if bus == null:
		return
	_elapsed += delta
	for person in passengers:
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
		for person in passengers:
			if person.transit_state == "onboard":
				if _elapsed < 1.3:
					return
				person.global_position = bus.door_position()
				person.show()
				person.set_physics_process(true)
				person.set_destination(Vector2(person.global_position.x, to_global(Vector2(0, QUEUE_LOCAL_Y)).y), "alighting")
				alighted += 1
				_elapsed = 0.0
				return
		_phase = "board"
	if _phase == "board":
		for person in passengers:
			if person.transit_state == "alighting" and person.global_position.distance_to(person.destination) < 8:
				person.set_destination(to_global(Vector2(-90 + passengers.find(person) * 23, QUEUE_LOCAL_Y)), "resting")
		for person in passengers:
			if person.transit_state == "boarding":
				if person.global_position.distance_to(bus.door_position()) < 8:
					person.set_destination(person.global_position, "onboard")
					person.hide()
					person.set_physics_process(false)
					boarded += 1
				return
		for person in passengers:
			if person.transit_state == "waiting":
				person.set_destination(bus.door_position(), "boarding")
				return
		for person in passengers:
			if person.transit_state == "alighting":
				return
		if _elapsed > 2.0:
			bus.depart()
			departures += 1
			_phase = "away"

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
	if is_instance_valid(bus) and is_instance_valid(bus.get_parent()):
		bus.get_parent().queue_free()

func _draw() -> void:
	draw_style_box(_platform_style(), Rect2(-115, -55, 230, 112))
	# Shelter roof and slender supports leave a genuine walk-through frontage.
	draw_rect(Rect2(-86, -31, 172, 48), Color("344f54"))
	draw_rect(Rect2(-82, -27, 164, 37), Color("618183"))
	for x in [-78, 78]:
		draw_circle(Vector2(x, 24), 4, Color("394348"))
	for x in [-48, 23]:
		draw_rect(Rect2(x, 25, 29, 8), Color("725b47"))
	# A telephone pictogram rather than a building name painted on the street.
	draw_rect(Rect2(96, -20, 10, 30), Color("38494f"))
	draw_rect(Rect2(97, -18, 8, 10), Color("78b8af"))
	# Bay furniture and luggage lockers keep the pedestrian frontage open.
	draw_rect(Rect2(-114, -31, 21, 49), Color("465356"))
	for y in [-26, -11, 4]:
		draw_rect(Rect2(-111, y, 15, 11), Color("8c9b99"), false, 1)
	for x in [-60, -20, 20, 60]:
		draw_line(Vector2(x, 108), Vector2(x + 20, 108), Color("e6c46a"), 3)

func _platform_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("b5aa94")
	style.border_color = Color("ddd0af")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	return style
