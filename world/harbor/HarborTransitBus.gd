extends "res://city_demo/scripts/TrafficVehicle.gd"
## A local midi-bus using the SAME spacing, junction reservations and connectors
## as civil traffic. Only route choice and the station stop differ.
var station: Node2D
var stop_lane: Path2D
var stop_offset := 0.0
var dwelling := true
var stop_armed := true
var doors := 0.0
var distance_travelled := 0.0
const TURNS := {"market_street": ["warehouse_way", -1], "warehouse_way": ["foundry_avenue", -1], "foundry_avenue": ["union_avenue", 1], "union_avenue": ["market_street", 1]}

func _ready() -> void:
	target_length = 120.0
	speed = 72.0
	super._ready()
	active_archetype_id = "route_city"
	vehicle_id = active_archetype_id
	vehicle_mass = 4.2
	max_health = 300
	health = max_health
	_setup_3d_model({
		"model_class": "res://world/harbor/HarborTransitBusModel.gd",
		"target_length": target_length,
		"target_width": 34.0,
	}, Color("d1cbb7"))
	# Match the authored midi-bus footprint, including bumpers and tires.
	var ppm := 74.0 / 4.46
	body_model.scale = Vector3(34.0 / (2.42 * ppm), 0.85, target_length / (9.78 * ppm))
	collision_layer = 2
	collision_mask = 7
	display_name = "Ônibus do Harbor"
	var body_shape := RectangleShape2D.new()
	body_shape.size = Vector2(120, 34)
	collision.shape = body_shape
	pedestrian_hitbox.get_node("Collision").shape = body_shape.duplicate()
	add_to_group("modern_traffic")
	add_to_group("harbor_transit_bus")
	_lane_motion_initialized = true
	_lane_motion_speed = 0.0

func enter_vehicle(_actor: CharacterBody2D) -> void:
	# Scheduled passenger service, not a stealable vehicle in this first slice.
	pass

func advance_on_lane(delta: float) -> void:
	var follow := get_parent() as PathFollow2D
	if follow == null:
		return
	var lane := follow.get_parent() as Path2D
	var previous := global_position
	var old_doors := doors
	doors = move_toward(doors, 1.0 if dwelling else 0.0, delta * 2.5)
	if old_doors != doors:
		body_model.set_platform_doors(doors)
		_body_render_visible = false
	if dwelling or doors > 0.0 or is_broken:
		_lane_motion_speed = 0.0
		velocity = Vector2.ZERO
		is_moving_on_lane = false
		return
	if lane != stop_lane:
		stop_armed = true
	_choose_scheduled_turn(lane, follow)
	super.advance_on_lane(delta)
	distance_travelled += previous.distance_to(global_position)
	if stop_armed and follow.get_parent() == stop_lane and absf(follow.progress - stop_offset) < 1.0:
		dwelling = true
		_lane_motion_speed = 0.0
		station.bus_arrived()

func _traffic_control_zone_motion(path: Path2D, follow: PathFollow2D) -> Dictionary:
	var motion := super._traffic_control_zone_motion(path, follow)
	if stop_armed and path == stop_lane:
		var remaining := stop_offset - follow.progress
		if remaining >= -0.5:
			motion.allowed_advance = minf(float(motion.allowed_advance), maxf(0.0, remaining))
			motion.target_speed = minf(float(motion.target_speed), sqrt(maxf(0.0, 2.0 * 90.0 * remaining)))
	return motion

func _choose_scheduled_turn(lane: Path2D, follow: PathFollow2D) -> void:
	if lane == null or bool(lane.get_meta("is_lane_connector", false)):
		return
	var controller := _get_junction_traffic_controller()
	if controller == null:
		return
	var road := String(lane.get_meta("traffic_road_id", "")).get_file()
	if not TURNS.has(road):
		return
	# Use the controller's already-cached next junction and connection index.
	# Never bypass an intervening junction by choosing a distant connection.
	var next: Dictionary = controller._next_lane_junction(lane, follow, int(lane.get_meta("traffic_road_index", -1)))
	if next.is_empty():
		return
	var options: Array = controller._connections_from_lane.get(String(lane.get_meta("traffic_lane_id", "")), [])
	var straight: Dictionary = {}
	for connection: Dictionary in options:
		if int(connection.get("junction_index", -2)) != int(next.junction_index):
			continue
		var destination: Path2D = station.network.get_lane_path(String(connection.to_lane_id))
		if destination == null:
			continue
		if String(connection.to_road_id).get_file() == String(TURNS[road][0]) and int(destination.get_meta("traffic_direction", 0)) == int(TURNS[road][1]):
			follow.set_meta("traffic_planned_connection_id", String(connection.connection_id))
			return
		if String(connection.get("movement", "")) == "straight":
			straight = connection
	if not straight.is_empty():
		follow.set_meta("traffic_planned_connection_id", String(straight.connection_id))

func depart() -> void:
	dwelling = false
	stop_armed = false

func door_position() -> Vector2:
	# Dual-side urban coach: use the door facing the north platform. The authored
	# Harbor graph's forward lane is north of Market Street's centreline.
	return to_global(Vector2(37, -30))



