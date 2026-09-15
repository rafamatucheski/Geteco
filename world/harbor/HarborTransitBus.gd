extends "res://cars/traffic/TrafficVehicle.gd"
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

func enter_vehicle(actor: CharacterBody2D) -> void:
	var was_detached := _detached_from_lane
	super.enter_vehicle(actor)
	if not is_driven_by_player or was_detached: return
	dwelling = false
	stop_armed = false
	doors = 0.0
	body_model.set_platform_doors(0.0)
	_body_render_visible = false
	if is_instance_valid(station) and station.has_method("bus_stolen"):
		station.bus_stolen()

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


func _lane_pedestrian_blocks(follow: PathFollow2D, pedestrian: Node, _must_clear_rail_crossing: bool) -> bool:
	# Side rays extend beyond the bus in a turn and can hit a stationary resident
	# on the sidewalk. Stop for the actual swept lane hull and a crossing person's
	# predicted movement, including their collision radius, instead of the ray alone.
	var path := follow.get_parent() as Path2D
	if path != null and bool(path.get_meta("curved_pedestrian_corridor", false)):
		return super._lane_pedestrian_blocks(follow, pedestrian, _must_clear_rail_crossing)
	if path == null or path.curve == null or not pedestrian is Node2D:
		return true
	var radius := 11.0
	for part in pedestrian.get_children():
		if part is CollisionShape2D and part.shape != null and not part.disabled:
			var extent: Vector2 = part.shape.get_rect().size * part.global_scale.abs() * 0.5
			radius = maxf(radius, maxf(extent.x, extent.y))
	var half: Vector2 = collision.shape.size * 0.5 + Vector2.ONE * (radius + 2.0)
	var future: Vector2 = pedestrian.global_position
	if pedestrian is CharacterBody2D:
		future += pedestrian.velocity * 0.65
	var end := minf(path.curve.get_baked_length(), follow.progress + maxf(95.0, target_length * 1.1))
	var samples := maxi(1, ceili((end - follow.progress) / 6.0))
	for index in range(samples + 1):
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(lerpf(follow.progress, end, float(index) / samples), true) * collision.transform
		var here: Vector2 = pose.affine_inverse() * pedestrian.global_position
		var predicted := pose.affine_inverse() * future
		var swept := Rect2(here, Vector2.ZERO).expand(predicted).grow(0.01)
		if Rect2(-half, half * 2.0).intersects(swept):
			return true
	return false

