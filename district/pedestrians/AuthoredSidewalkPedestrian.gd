class_name AuthoredSidewalkPedestrian
extends AnimatedPedestrian3D

## Uses the current articulated Antigravity pedestrian while constraining all
## autonomous locomotion to an authored sidewalk polyline. Panic and combat may
## increase speed, but never replace the route with a random world-space target.

@export var route_id: String = ""
@export var route_points: PackedVector2Array
@export_range(8.0, 48.0, 1.0) var sidewalk_half_width: float = 28.0
@export_range(12.0, 64.0, 1.0) var personal_space: float = 22.0

var _route_segment := 0
var _route_direction := 1
var _route_target_ready := false
var _normal_walk_speed := 48.0
var _spawn_distance := 0.0


func configure_authored_route(points: PackedVector2Array, id: String, spawn_distance: float = 0.0) -> void:
	route_points = points.duplicate()
	route_id = id
	_spawn_distance = maxf(0.0, spawn_distance)


func _ready() -> void:
	if route_points.size() < 2:
		push_error("AuthoredSidewalkPedestrian %s requires at least two route points" % name)
		set_physics_process(false)
		return
	_place_at_route_distance(_spawn_distance)
	ambient_running_enabled = false
	super._ready()
	# Athletic clothes remain a visual archetype. Normal ambient movement is a
	# walk; sprinting is reserved for panic or active combat/crime.
	_normal_walk_speed = clampf(base_walk_speed, 34.0, 58.0)
	base_walk_speed = _normal_walk_speed
	add_to_group("authored_sidewalk_pedestrian")


func _physics_process(delta: float) -> void:
	base_walk_speed = _normal_walk_speed * _spacing_speed_factor()
	super._physics_process(delta)
	_enforce_sidewalk_guardrail()


func _pick_new_sidewalk_target() -> void:
	if route_points.size() < 2:
		walk_target = global_position
		return
	# A pedestrian reaches an end and turns back.  It never wraps the last
	# sidewalk point to the first one, which was the visible circle around blocks.
	if not _route_target_ready:
		_route_target_ready = true
	else:
		_route_segment += _route_direction
		if _route_segment <= 0:
			_route_segment = 0
			_route_direction = 1
		elif _route_segment >= route_points.size() - 1:
			_route_segment = route_points.size() - 1
			_route_direction = -1
	var next_index := clampi(_route_segment + _route_direction, 0, route_points.size() - 1)
	walk_target = route_points[next_index]


func _place_at_route_distance(distance: float) -> void:
	var total := 0.0
	for index in range(route_points.size() - 1):
		total += route_points[index].distance_to(route_points[index + 1])
	if total <= 0.001:
		position = route_points[0]
		return
	var phase := fposmod(distance, total * 2.0)
	_route_direction = 1 if phase <= total else -1
	var remaining := phase if _route_direction == 1 else total * 2.0 - phase
	var start_index := 0 if _route_direction == 1 else route_points.size() - 1
	var end_index := route_points.size() - 1 if _route_direction == 1 else 0
	var index := start_index
	while index != end_index:
		var next_index := index + _route_direction
		var start := route_points[index]
		var finish := route_points[next_index]
		var length := start.distance_to(finish)
		if length <= 0.001:
			index = next_index
			continue
		if remaining <= length:
			_route_segment = index
			position = start.lerp(finish, remaining / length)
			return
		remaining -= length
		index = next_index
	_route_segment = end_index
	position = route_points[end_index]


func _enforce_sidewalk_guardrail() -> void:
	if route_points.size() < 2:
		return
	if global_position.distance_to(walk_target) < 14.0:
		_pick_new_sidewalk_target()


func _navigate_towards(dest: Vector2, move_speed: float, _delta: float) -> Vector2:
	# Authored walkers do not use the base class' random anti-stuck sidestep.
	# That manoeuvre is useful for combat NPCs but made civilians orbit a kerb
	# or abruptly switch targets.  A blocked walker pauses on its own sidewalk.
	stuck_timer = 0.0
	return global_position.direction_to(dest) * move_speed


func _spacing_speed_factor() -> float:
	if is_scared or (is_gangster and is_instance_valid(combat_target)):
		return 1.0
	var direction := global_position.direction_to(walk_target)
	for candidate in get_tree().get_nodes_in_group("authored_sidewalk_pedestrian"):
		if candidate == self or not is_instance_valid(candidate):
			continue
		if String(candidate.get("route_id")) != route_id:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance >= personal_space or distance <= 0.01:
			continue
		if direction.dot(global_position.direction_to(candidate.global_position)) > 0.35:
			return clampf((distance - 10.0) / maxf(1.0, personal_space - 10.0), 0.0, 1.0)
	return 1.0


func validation_state() -> Dictionary:
	var deviation := 0.0
	if route_points.size() >= 2:
		var next_index := clampi(_route_segment + _route_direction, 0, route_points.size() - 1)
		deviation = global_position.distance_to(Geometry2D.get_closest_point_to_segment(
			global_position,
			route_points[_route_segment],
			route_points[next_index]
		))
	return {
		"route": route_id,
		"route_points": route_points.size(),
		"current_segment": _route_segment,
		"sidewalk_only": true,
		"random_world_targets": false,
		"route_deviation": deviation,
		"within_sidewalk": deviation <= sidewalk_half_width + 0.1,
	}
