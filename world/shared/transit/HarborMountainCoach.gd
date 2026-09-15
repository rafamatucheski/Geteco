extends "res://world/harbor/HarborTransitBus.gd"
## A scheduled coach uses the same live junction, queue and hull rules as traffic.

func _ready() -> void:
	super._ready()
	name = "HarborMountainRegionalCoach"
	display_name = "Expresso Harbor · Vila da Neve"
	characteristic = "Linha regional · uma plataforma na serra"
	speed = 108.0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("regional_coach")
	remove_from_group("harbor_transit_bus")
	_setup_3d_model({"model_class": "res://world/shared/transit/RegionalIntercityCoachModel.gd", "target_length": 120.0, "target_width": 34.0}, Color("3f788b"))
	var ppm := 74.0 / 4.46
	body_model.scale = Vector3(34.0 / (3.23 * ppm), 0.85, 120.0 / (11.96 * ppm))
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120, 34)
	collision.shape = shape
	pedestrian_hitbox.get_node("Collision").shape = shape.duplicate()

func advance_on_lane(delta: float) -> void:
	body_model.mountain_platform = station != null and station.at_mountain_berth()
	super.advance_on_lane(delta)

func _choose_scheduled_turn(lane: Path2D, follow: PathFollow2D) -> void:
	if station == null:
		return
	var connection: String = station.planned_connection(lane, follow.progress)
	if not connection.is_empty():
		follow.set_meta("traffic_planned_connection_id", connection)

func _traffic_control_zone_motion(path: Path2D, follow: PathFollow2D) -> Dictionary:
	var motion := super._traffic_control_zone_motion(path, follow)
	if station != null:
		var limit: float = station.lane_stop_limit(path, follow.progress)
		if is_finite(limit):
			var distance := maxf(0.0, limit - follow.progress)
			motion.allowed_advance = minf(float(motion.allowed_advance), distance)
			motion.target_speed = minf(float(motion.target_speed), sqrt(2.0 * 85.0 * distance))
	return motion

func door_position() -> Vector2:
	# Mountain berth faces east and the passenger apron is on its south side.
	return to_global(Vector2(37, 30)) if station != null and station.at_mountain_berth() else to_global(Vector2(37, -30))

