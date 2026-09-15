@tool
class_name RoadCrossingArea2D
extends Area2D

## Runtime pedestrian crossing anchored to the canonical road graph by
## {road_id, t}. The owning safety system resolves that reference to a pose;
## this node never stores a second world-space authoring coordinate.

signal pedestrian_request(crossing_id: StringName, junction_id: StringName)
signal stop_requirement_changed(crossing_id: StringName, required: bool)

const SAFETY_AREA_LAYER := 8
const DEFAULT_BODY_MASK := 2 | 4
const MARKING_COLOR := Color("#eeeade")
const TACTILE_COLOR := Color("#d9ad34")
const STOP_LINE_COLOR := Color("#f4f1e8")

var crossing_id: StringName = &""
var junction_id: StringName = &""
var road_id: StringName = &""
var road_index := -1
var t := 0.0
var crossing_axis: StringName = &"AUTO"
var road_width := 96.0
var sidewalk_reach := 34.0
var crossing_depth := 30.0
var approach_depth := 150.0

var _has_signal_state := false
var _vehicle_permitted := true
var _pedestrian_permitted := false
var _pedestrians_inside: Dictionary = {}
var _vehicles_inside: Dictionary = {}
var _last_stop_required := false
var _signal_controller: Node = null
var _roadway_occupancy_shape := RectangleShape2D.new()


func _ready() -> void:
	add_to_group("road_pedestrian_crossing")
	add_to_group("road_crossing_area")
	add_to_group("road_crossing")
	add_to_group("traffic_crossing")
	add_to_group("traffic_control_zone")
	monitoring = not Engine.is_editor_hint()
	monitorable = true
	collision_layer = SAFETY_AREA_LAYER
	collision_mask = DEFAULT_BODY_MASK
	_ensure_shapes()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	queue_redraw()


func configure(reference: Dictionary) -> void:
	crossing_id = StringName(reference.get("id", "crossing"))
	junction_id = StringName(reference.get("junction_id", ""))
	road_id = StringName(reference.get("road_id", ""))
	road_index = int(reference.get("road_index", -1))
	t = clampf(float(reference.get("t", 0.0)), 0.0, 1.0)
	road_width = maxf(24.0, float(reference.get("road_width", 96.0)))
	sidewalk_reach = maxf(0.0, float(reference.get("sidewalk_reach", 34.0)))
	crossing_depth = maxf(12.0, float(reference.get("crossing_depth", 30.0)))
	approach_depth = maxf(crossing_depth, float(reference.get("approach_depth", 150.0)))
	var tangent: Vector2 = reference.get("road_tangent", Vector2.RIGHT)
	if tangent.is_zero_approx():
		tangent = Vector2.RIGHT
	rotation = tangent.angle()
	position = reference.get("position", Vector2.ZERO)
	var walk_direction := tangent.orthogonal()
	var requested_axis := String(reference.get("crossing_axis", "AUTO"))
	crossing_axis = StringName(
		"EW" if absf(walk_direction.x) >= absf(walk_direction.y) else "NS"
	) if requested_axis == "AUTO" or requested_axis.is_empty() else StringName(requested_axis)
	set_meta("crossing_id", crossing_id)
	set_meta("junction_id", junction_id)
	set_meta("road_id", road_id)
	set_meta("road_index", road_index)
	set_meta("t", t)
	set_meta("crossing_axis", crossing_axis)
	set_meta("stop_required", should_stop_vehicle())
	if is_inside_tree():
		_ensure_shapes()
		queue_redraw()


func set_signal_controller(controller: Node) -> void:
	_signal_controller = controller


func set_signal_state(vehicle_permitted: bool, pedestrian_permitted: bool) -> void:
	# A road-relative crossing with no nearby junction is intentionally
	# unsignalized and keeps pedestrian-on-crossing priority semantics.
	if junction_id == StringName():
		clear_signal_state()
		return
	_has_signal_state = true
	_vehicle_permitted = vehicle_permitted
	_pedestrian_permitted = pedestrian_permitted
	_refresh_stop_requirement()


func clear_signal_state() -> void:
	_has_signal_state = false
	_vehicle_permitted = true
	_pedestrian_permitted = false
	_refresh_stop_requirement()


func is_pedestrian_allowed() -> bool:
	if _has_signal_state:
		return _pedestrian_permitted
	return true


func should_stop_vehicle(vehicle: Node = null) -> bool:
	if _has_signal_state:
		if _pedestrian_permitted or has_pedestrian_on_roadway():
			return true
		if _vehicle_permitted:
			return false
		if is_instance_valid(_signal_controller) and _signal_controller.has_method("can_clear_crossing"):
			return not bool(_signal_controller.call("can_clear_crossing", vehicle, junction_id, self))
		return true
	return has_pedestrian_on_roadway()


func has_pedestrian_on_roadway() -> bool:
	# The monitoring area includes waiting space on both sidewalks. Preserve
	# that broad registry for signal demand, but stop traffic only for bodies
	# whose actual collision shapes overlap the zebra on the carriageway.
	_roadway_occupancy_shape.size = Vector2(crossing_depth+2.0,road_width+2.0)
	for reference in _pedestrians_inside.values():
		var body: Object = reference.get_ref() if reference is WeakRef else null
		if not is_instance_valid(body) or not body is Node2D:
			continue
		if body is CollisionObject2D:
			var collision_body := body as CollisionObject2D
			for owner_id in collision_body.get_shape_owners():
				if collision_body.is_shape_owner_disabled(owner_id):
					continue
				var shape_transform := collision_body.global_transform * collision_body.shape_owner_get_transform(owner_id)
				for shape_index in collision_body.shape_owner_get_shape_count(owner_id):
					var shape := collision_body.shape_owner_get_shape(owner_id,shape_index)
					if shape != null and shape.collide(shape_transform,_roadway_occupancy_shape,global_transform):
						return true
		else:
			var point := to_local((body as Node2D).global_position)
			if Rect2(-_roadway_occupancy_shape.size*0.5,_roadway_occupancy_shape.size).has_point(point):
				return true
	return false


func contains_world_point(world_point: Vector2, include_approach: bool = true) -> bool:
	var local_point := to_local(world_point)
	var half_x := approach_depth * 0.5 if include_approach else crossing_depth * 0.5
	var half_y := road_width * 0.5 + sidewalk_reach
	return Rect2(Vector2(-half_x, -half_y), Vector2(half_x * 2.0, half_y * 2.0)).has_point(local_point)


func get_traffic_geometry() -> Dictionary:
	# O tráfego consulta a permissão com o veículo; não montar telemetria nem
	# consultar uma segunda vez a permissão genérica sem dono da reserva.
	return {"id":crossing_id,"road_id":road_id,"position":global_position}

func get_crossing_data() -> Dictionary:
	return {
		"id": crossing_id,
		"crossing_id": crossing_id,
		"junction_id": junction_id,
		"road_id": road_id,
		"road_index": road_index,
		"t": t,
		"crossing_axis": crossing_axis,
		"position": global_position,
		"road_tangent": Vector2.RIGHT.rotated(global_rotation),
		"road_width": road_width,
		"has_signal_state": _has_signal_state,
		"vehicle_permitted": _vehicle_permitted,
		"pedestrian_permitted": _pedestrian_permitted,
		"pedestrians_inside": _pedestrians_inside.size(),
		"vehicles_inside": _vehicles_inside.size(),
		"stop_required": should_stop_vehicle(),
	}


func _ensure_shapes() -> void:
	var crossing_shape := get_node_or_null("CrossingShape") as CollisionShape2D
	if crossing_shape == null:
		crossing_shape = CollisionShape2D.new()
		crossing_shape.name = "CrossingShape"
		add_child(crossing_shape)
	var exact_shape := RectangleShape2D.new()
	exact_shape.size = Vector2(crossing_depth, road_width + sidewalk_reach * 2.0)
	crossing_shape.shape = exact_shape

	var approach := get_node_or_null("VehicleApproachZone") as Area2D
	if approach == null:
		approach = Area2D.new()
		approach.name = "VehicleApproachZone"
		approach.collision_layer = SAFETY_AREA_LAYER
		approach.collision_mask = 2
		approach.monitoring = not Engine.is_editor_hint()
		approach.monitorable = true
		add_child(approach)
		approach.body_entered.connect(_on_approach_body_entered)
		approach.body_exited.connect(_on_approach_body_exited)
	var approach_shape := approach.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if approach_shape == null:
		approach_shape = CollisionShape2D.new()
		approach_shape.name = "CollisionShape2D"
		approach.add_child(approach_shape)
	var braking_shape := RectangleShape2D.new()
	braking_shape.size = Vector2(approach_depth, road_width)
	approach_shape.shape = braking_shape


func _on_body_entered(body: Node2D) -> void:
	if _is_pedestrian(body):
		_pedestrians_inside[body.get_instance_id()] = weakref(body)
		pedestrian_request.emit(crossing_id, junction_id)
		_refresh_stop_requirement()
	elif _is_vehicle(body):
		_vehicles_inside[body.get_instance_id()] = weakref(body)


func _on_body_exited(body: Node2D) -> void:
	_pedestrians_inside.erase(body.get_instance_id())
	_vehicles_inside.erase(body.get_instance_id())
	_refresh_stop_requirement()


func _on_approach_body_entered(body: Node2D) -> void:
	if _is_vehicle(body):
		_vehicles_inside[body.get_instance_id()] = weakref(body)


func _on_approach_body_exited(body: Node2D) -> void:
	_vehicles_inside.erase(body.get_instance_id())


func _is_pedestrian(body: Node) -> bool:
	return body.is_in_group("pedestrian") or body.is_in_group("district_one_pedestrians") or body.is_in_group("authored_sidewalk_pedestrian")


func _is_vehicle(body: Node) -> bool:
	return body.is_in_group("vehicle") or body.is_in_group("modern_traffic") or body.is_in_group("district_one_traffic") or body.is_in_group("phase1_traffic")


func _refresh_stop_requirement() -> void:
	_cleanup_invalid_bodies(_pedestrians_inside)
	_cleanup_invalid_bodies(_vehicles_inside)
	var required := should_stop_vehicle()
	set_meta("stop_required", required)
	if required != _last_stop_required:
		_last_stop_required = required
		stop_requirement_changed.emit(crossing_id, required)
	if is_instance_valid(_signal_controller) and _signal_controller.has_method("notify_crossing_demand"):
		_signal_controller.call("notify_crossing_demand", junction_id, crossing_axis, not _pedestrians_inside.is_empty())


func _cleanup_invalid_bodies(registry: Dictionary) -> void:
	for key in registry.keys():
		var reference: WeakRef = registry[key]
		if reference.get_ref() == null:
			registry.erase(key)


func _draw() -> void:
	var half_road := road_width * 0.5
	var first := -half_road + 6.0
	var last := half_road - 6.0
	var stripe_spacing := 15.0
	var stripe_y := first
	while stripe_y <= last:
		draw_rect(
			Rect2(Vector2(-crossing_depth * 0.43, stripe_y - 4.0), Vector2(crossing_depth * 0.86, 8.0)),
			MARKING_COLOR
		)
		stripe_y += stripe_spacing
	# Tactile pads are derived from the road width, exactly where asphalt meets
	# each sidewalk. They therefore move whenever the canonical road moves.
	for side in [-1.0, 1.0]:
		var pad_center := Vector2(0.0, side * (half_road + minf(sidewalk_reach * 0.5, 12.0)))
		draw_rect(Rect2(pad_center - Vector2(crossing_depth * 0.5, 6.0), Vector2(crossing_depth, 12.0)), TACTILE_COLOR)
	# Stop lines sit before the crossing on both approaches.
	for side in [-1.0, 1.0]:
		var stop_x: float = float(side) * (crossing_depth * 0.5 + 16.0)
		draw_line(Vector2(stop_x, -half_road), Vector2(stop_x, half_road), STOP_LINE_COLOR, 3.0, true)
