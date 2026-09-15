class_name AuthoredSidewalkPedestrian
extends AnimatedPedestrian3D

## Uses the articulated pedestrian with ambient life routines (entering restaurants/shops,
## window browsing, varied lateral lanes, anti-bunching and desynchronized strides).

@export var route_id: String = ""
@export var route_points: PackedVector2Array
@export_range(8.0, 48.0, 1.0) var sidewalk_half_width: float = 28.0
@export_range(12.0, 64.0, 1.0) var personal_space: float = 24.0
@export_range(-18.0, 18.0, 1.0) var lateral_offset: float = 0.0
@export_range(0.0, 0.95, 0.01) var detour_bias := 0.28
@export_range(6.0, 36.0, 1.0) var detour_amplitude := 22.0
@export_range(1.0, 10.0, 0.1) var poi_search_radius := 420.0

var _route_segment := 0
var _route_direction := 1
var _route_target_ready := false
var _normal_walk_speed := 48.0
var _spawn_distance := 0.0
var route_loop := false
# Panic can leave the authored corridor. Rejoin a nearby accessible leg on foot.
var _rejoining_route := false
var _rejoin_point := Vector2.ZERO
const SOCIAL_LOOKAHEAD := 64.0

# --- Rotinas Ambientais de Vida (Restaurantes, Lojas, Vitrines) ---
var visit_cooldown: float = 20.0
var is_visiting: bool = false
var _visiting_timer: float = 0.0
var _visiting_door_pos: Vector2 = Vector2.ZERO
var _window_shop_pause: float = 0.0
var _visit_approach_elapsed := 0.0
var _visit_fade: Tween

# Compartilha a busca espacial; os filtros de distância/direção continuam locais.
const NEIGHBORHOOD := preload("res://world/shared/pedestrians/PedestrianNeighborhood.gd")
var _cached_neighbors: Array = []
var _neighbor_refresh_counter: int = 0
const NEIGHBOR_REFRESH_STRIDE := 3
var locomotion_state: StringName = &"walking"
var recovery_count := 0
var _recovery_cooldown := 0.0
var _recovery_attempt := 0
var _recovering_leg := false
var _corridor_segment := -1
var _corridor_direction := 0
var _corridor_start := Vector2.ZERO
var _corridor_end := Vector2.ZERO
var _corridor_width := 28.0
var walk_space: RefCounted
var _nearby_roads: Array[Dictionary] = []
var _passing_person: WeakRef
var _passing_side := 1.0
var _passing_axis := Vector2.ZERO
var _passing_until := 0.0
var _life_clock := 0.0
var _yield_peer: WeakRef
var _yield_deadline := 0.0
var _yield_cooldown := 0.0
var _yield_now := false
var _local_route_goal := Vector2.INF
var _local_target := Vector2.INF


func configure_authored_route(points: PackedVector2Array, id: String, spawn_distance: float = 0.0) -> void:
	route_points = points.duplicate()
	route_loop = points.size()>3 and points[0].is_equal_approx(points[points.size()-1])
	route_id = id
	_spawn_distance = maxf(0.0, spawn_distance)


func _ready() -> void:
	if route_points.size() < 2:
		push_error("AuthoredSidewalkPedestrian %s requires at least two route points" % name)
		set_physics_process(false)
		return
		
	# Offset lateral único para espalhar pedestres pela calçada (evita fila indiana)
	lateral_offset = randf_range(-12.0, 12.0)
	
	# Cadências e velocidades de caminhada naturais e distintas (38 a 56 px/s)
	_normal_walk_speed = clampf(randf_range(38.0, 56.0), 36.0, 58.0)
	base_walk_speed = _normal_walk_speed
	var profile_roll := randf()
	detour_bias *= 0.75 + profile_roll * 0.75
	detour_amplitude = clampf(detour_amplitude * (0.45 + profile_roll * 1.1), 10.0, 36.0)
	visit_cooldown = randf_range(14.0, 36.0) * (0.8 + randf() * 0.4)
	
	_place_at_route_distance(_spawn_distance)
	ambient_running_enabled = false
	super._ready()
	movement_navigation.grid_step = 12.0
	movement_navigation.point_filter = _navigation_point_allowed
	_configure_navigation_corridor()
	_validate_initial_spawn()
	add_to_group("authored_sidewalk_pedestrian")

func _validate_initial_spawn() -> void:
	# Only initial placement, before the first physics tick. Runtime recovery
	# never relocates actors. Authored spawn offsets must fit the physical body.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = get_node("CollisionShape2D").shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.margin = safe_margin
	var space := get_world_2d().direct_space_state
	if space.intersect_shape(query, 1).is_empty() and preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd").allows(global_position, _nearby_roads): return
	var axis := _corridor_start.direction_to(_corridor_end)
	var along := (global_position - _corridor_start).dot(axis)
	for shift in [0.0, 24.0, -24.0, 48.0, -48.0, 72.0, -72.0]:
		for lateral in [0.0, 8.0, -8.0]:
			var point: Vector2 = _corridor_start + axis * clampf(along + shift, 0.0, _corridor_start.distance_to(_corridor_end)) + axis.orthogonal() * lateral
			if not _navigation_point_allowed(point): continue
			if not preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd").allows(point, _nearby_roads): continue
			query.transform.origin = point
			if not space.intersect_shape(query, 1).is_empty(): continue
			global_position = point
			return


func _physics_process(delta: float) -> void:
	_life_clock += delta
	_recovery_cooldown = maxf(0.0, _recovery_cooldown - delta)
	_neighbor_refresh_counter += 1
	if _neighbor_refresh_counter >= NEIGHBOR_REFRESH_STRIDE or _cached_neighbors.is_empty():
		_neighbor_refresh_counter = 0
		_cached_neighbors = NEIGHBORHOOD.neighbors(self, maxf(personal_space, SOCIAL_LOOKAHEAD))
	_update_ambient_life(delta)
	
	if _ambient_walk_paused():
		locomotion_state = &"visiting" if is_visiting else &"paused"
		movement_navigation.reset_progress()
		stuck_timer = 0.0
		velocity = Vector2.ZERO
		super._physics_process(delta)
		return
		
	base_walk_speed = _normal_walk_speed * _spacing_speed_factor()
	super._physics_process(delta)
	if velocity.is_zero_approx() and locomotion_state in [&"walking", &"detour"]:
		locomotion_state = &"waiting_person"
	_enforce_sidewalk_guardrail()


func _update_walk_destination(_delta: float) -> void:
	if is_visiting: return
	if stuck_timer < 0.1 and not _recovering_leg: _recovery_attempt = 0
	if _rejoining_route:
		if stuck_timer > 5.0 and _recovery_cooldown <= 0.0:
			_recovery_cooldown = 5.0
			_resume_after_panic()
		return
	if global_position.distance_to(walk_target) <= 8.0:
		if _recovering_leg:
			_recovering_leg = false
			_route_target_ready = false
		_pick_new_sidewalk_target()
		movement_navigation.reset_progress()
		stuck_timer = 0.0
		_recovery_attempt = 0
	elif stuck_timer > 2.5 and _recovery_cooldown <= 0.0:
		_recover_blocked_route()


func _recover_blocked_route() -> void:
	_recovery_cooldown = 3.0
	_recovery_attempt += 1
	recovery_count += 1
	locomotion_state = &"recovering"
	if _recovery_attempt == 1:
		if not movement_navigation._search_pending: movement_navigation.repath()
		return
	# Retreat on the SAME leg. Never skip a blocked corner across the block.
	var next := _next_route_index()
	var start := route_points[_route_segment]
	var finish := route_points[next]
	var axis := start.direction_to(finish)
	var along := clampf((global_position - start).dot(axis), 0.0, start.distance_to(finish))
	for retreat in [64.0, 40.0, 24.0]:
		var point := start + axis * maxf(0.0, along - retreat)
		if global_position.distance_to(point) < 12.0: continue
		# The retreat may itself need to go around a pole already passed.
		# Validate its endpoint, then let the same constrained planner get there.
		if not movement_navigation.clear_segment(self, point, point): continue
		_route_segment = next
		_route_direction = -_route_direction
		walk_target = point
		_recovering_leg = true
		movement_navigation.repath()
		movement_navigation.reset_progress()
		stuck_timer = 0.0
		return
	# A truly enclosed person waits and retries at a bounded rate.
	locomotion_state = &"waiting_path"


func _configure_navigation_corridor() -> void:
	if _corridor_segment == _route_segment and _corridor_direction == _route_direction: return
	_corridor_segment = _route_segment
	_corridor_direction = _route_direction
	_corridor_start = route_points[_route_segment]
	_corridor_end = route_points[_next_route_index()]
	var axis := _corridor_start.direction_to(_corridor_end)
	movement_navigation.grid_step = 12.0
	movement_navigation.preferred_side = Vector2(-axis.y, axis.x)
	_corridor_width = maxf(28.0, sidewalk_half_width)
	if walk_space != null:
		_nearby_roads = walk_space.near_leg(_corridor_start, _corridor_end, _corridor_width)
		for road in _nearby_roads:
			if road.get("crossing", false):
				# Leave room to pass a parked motorcycle with the full body.
				# Signal checks use this same bounded crossing envelope.
				_corridor_width = minf(preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd").CROSSING_HALF_WIDTH, sidewalk_half_width)


func _navigation_point_allowed(point: Vector2) -> bool:
	if is_scared or is_visiting or _rejoining_route or (is_gangster and is_instance_valid(combat_target)): return true
	var segment := _corridor_end - _corridor_start
	var length := segment.length()
	if length < 0.001: return true
	var axis := segment / length
	var offset := point - _corridor_start
	var origin := global_position - _corridor_start
	if offset.dot(axis) < minf(-3.0, origin.dot(axis)) - 0.001 or offset.dot(axis) > maxf(length + 3.0, origin.dot(axis)) + 0.001: return false
	if absf(offset.dot(axis.orthogonal())) > maxf(_corridor_width, absf(origin.dot(axis.orthogonal()))) + 0.001: return false
	return preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd").allows(point, _nearby_roads, global_position)

func _next_route_index() -> int:
	if route_loop: return posmod(_route_segment + _route_direction, route_points.size() - 1)
	return clampi(_route_segment + _route_direction, 0, route_points.size() - 1)


func _update_ambient_life(delta: float) -> void:
	if is_dead or is_incapacitated or is_flying: return
	if is_scared or (is_gangster and is_instance_valid(combat_target)):
		_window_shop_pause = 0.0
		if is_visiting:
			_abort_visit()
		return
		
	if _window_shop_pause > 0.0:
		_window_shop_pause -= delta
		velocity = Vector2.ZERO
		return

	if is_visiting:
		_process_visiting_state(delta)
		return
		
	visit_cooldown -= delta
	if visit_cooldown <= 0.0:
		visit_cooldown = randf_range(25.0, 50.0)
		_try_start_poi_visit()


func _try_start_poi_visit() -> void:
	var candidates: Array = []
	var buildings := get_tree().get_nodes_in_group("procedural_building")
	var best_dist := 260.0
	for b in buildings:
		if not is_instance_valid(b) or not (b is ProceduralBuilding):
			continue
		var k := String(b.building_kind)
		if not ("shop" in k or "corner_shop" in k or "clothing" in k or "diner" in k or "restaurant" in k or "ammunation" in k):
			continue
		var d := global_position.distance_to(b.global_position)
		if d <= best_dist:
			candidates.append({"building": b as ProceduralBuilding, "distance": d})
			best_dist = min(best_dist, d + poi_search_radius * 0.1)
			
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return float(a.distance) < float(b.distance))
	var choice_count := mini(candidates.size(), 4)
	var weighted_index := 0
	var acc := 0.0
	var weights: Array[float] = []
	for i in range(choice_count):
		var d := maxf(1.0, float(candidates[i]["distance"]))
		var weight := 1.0 / d
		weights.append(weight)
		acc += weight
	var roll := randf() * acc
	for i in range(weights.size()):
		roll -= weights[i]
		if roll <= 0.0:
			weighted_index = i
			break
	var best_building: ProceduralBuilding = candidates[weighted_index]["building"] as ProceduralBuilding
	if best_building:
		# Encontra o ponto da porta/entrada na fachada sul
		var door := Vector2(best_building.global_position.x, best_building.global_position.y + best_building.footprint.y * 0.5 + 14.0)
		_configure_navigation_corridor()
		# Approach from outside with full body clearance, never target the wall.
		if not movement_navigation.clear_segment(self, global_position, door): return
			
		is_visiting = true
		_visit_approach_elapsed = 0.0
		_visiting_door_pos = door
		walk_target = door
		_visiting_timer = 0.0


func _process_visiting_state(delta: float) -> void:
	var dist_to_door := global_position.distance_to(_visiting_door_pos)
	if dist_to_door > 22.0 and _visiting_timer == 0.0:
		_visit_approach_elapsed += delta
		if _visit_approach_elapsed > 12.0:
			_abort_visit()
			return
		walk_target = _visiting_door_pos
		return
		
	# Chegou na porta do restaurante/loja!
	if _visiting_timer == 0.0:
		_visiting_timer = randf_range(4.5, 8.5)
		var phrases := [
			"Almoçar algo gostoso! 🍽️",
			"Um café quentinho ☕",
			"Fazer um lanche 🥪",
			"Comprar comida 🍔",
			"Entrando na loja 🛍️"
		]
		_show_custom_bubble(phrases[randi() % phrases.size()], Color(0.3, 0.85, 0.45))
		
		# Entra no restaurante/loja: fade out suave e desativa colisão física
		if _visit_fade: _visit_fade.kill()
		_visit_fade = create_tween()
		_visit_fade.tween_property(self, "modulate:a", 0.0, 0.40)
		collision_layer = 0
		velocity = Vector2.ZERO
		return
		
	_visiting_timer -= delta
	velocity = Vector2.ZERO
	
	if _visiting_timer <= 0.0:
		# Sai do estabelecimento após comer/comprar!
		is_visiting = false
		collision_layer = 4
		if _visit_fade: _visit_fade.kill()
		_visit_fade = create_tween()
		_visit_fade.tween_property(self, "modulate:a", 1.0, 0.40)
		
		var exit_phrases := ["Muito bom! 👍", "Revigorado! ✨", "Satisfeito! 😊", "Bora continuar 🚶"]
		_show_custom_bubble(exit_phrases[randi() % exit_phrases.size()], Color(0.2, 0.7, 0.95))
		
		if randf() > 0.5:
			_route_direction = -_route_direction
		_resume_after_panic()
		visit_cooldown = randf_range(30.0, 60.0)


func _abort_visit() -> void:
	if _visit_fade: _visit_fade.kill()
	visit_cooldown = randf_range(25.0, 50.0)
	is_visiting = false
	_visiting_timer = 0.0
	collision_layer = 4
	modulate.a = 1.0
	if not is_scared: _resume_after_panic()


func _pick_new_sidewalk_target() -> void:
	if _rejoining_route: return
	if route_points.size() < 2:
		walk_target = global_position
		return
	if not _route_target_ready:
		_route_target_ready = true
	else:
		_route_segment += _route_direction
		if route_loop:
			_route_segment = posmod(_route_segment,route_points.size()-1)
			walk_target = route_points[posmod(_route_segment + _route_direction, route_points.size()-1)]
			return
		if _route_segment <= 0:
			_route_segment = 0
			_route_direction = 1
		elif _route_segment >= route_points.size() - 1:
			_route_segment = route_points.size() - 1
			_route_direction = -1
	var next_index := _next_route_index()
	var target_pt := route_points[next_index]
	var seg_start := route_points[_route_segment]
	var seg_dir := (target_pt - seg_start).normalized()
	if seg_dir.length_squared() > 0.001:
		var normal := Vector2(-seg_dir.y, seg_dir.x)
		var max_detour := minf(sidewalk_half_width * 0.7, detour_amplitude)
		if route_points.size() == 2 and randf() < detour_bias:
			var along_bias := randf_range(-0.5, 0.5) * (target_pt - seg_start).length()
			var along_offset := seg_dir * along_bias * 0.35
			var side_offset := normal * randf_range(-max_detour, max_detour)
			var rhythm_offset := normal.rotated(randf_range(-0.32, 0.32)) * 1.1
			walk_target = target_pt + seg_dir * minf(0.0, along_offset.dot(seg_dir)) + side_offset + rhythm_offset * randf_range(-0.45, 0.45)
		else:
			walk_target = target_pt + normal * lateral_offset
	else:
		walk_target = target_pt


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
			var seg_dir := (finish - start).normalized()
			var normal := Vector2(-seg_dir.y, seg_dir.x)
			position = start.lerp(finish, remaining / length) + normal * lateral_offset
			return
		remaining -= length
		index = next_index
	_route_segment = end_index
	position = route_points[end_index]


func _enforce_sidewalk_guardrail() -> void:
	# Arrival is handled once, before navigation. Search and social motion use
	# the same corridor rather than clipping an already validated direction.
	pass


func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	_configure_navigation_corridor()
	if _rejoining_route:
		if global_position.distance_to(_rejoin_point) <= 5.0:
			_rejoining_route = false
			_route_target_ready = false
			_pick_new_sidewalk_target()
			dest = walk_target
		else:
			dest = _rejoin_point
	var local_goal := _local_navigation_goal(dest)
	var planned := super._navigate_towards(local_goal, move_speed, delta)
	locomotion_state = &"recovering" if _recovering_leg or _rejoining_route else (&"detour" if not movement_navigation.path.is_empty() else &"walking")
	if planned.is_zero_approx():
		locomotion_state = &"waiting_path"
		return Vector2.ZERO
	var base_dir := planned.normalized()
	var avoidance := _sidewalk_avoidance_offset(base_dir)
	if _yield_now:
		locomotion_state = &"waiting_person"
		movement_navigation.reset_progress()
		stuck_timer = 0.0
		return Vector2.ZERO
	# A navegação já validou esse segmento. Só testar outra vez quando o
	# desvio social realmente altera a direção; move_and_slide mantém a colisão.
	if avoidance.is_zero_approx(): return planned
	var combined := base_dir + avoidance
	var steered := combined.normalized() if combined.length_squared() > 0.0001 else base_dir
	
	# Espaçamento social não pode empurrar o pedestre para dentro de um poste.
	if not movement_navigation.clear_segment(self, global_position, global_position + steered * 20.0):
		return planned
	return steered * minf(move_speed, planned.length())

func _local_navigation_goal(dest: Vector2) -> Vector2:
	if is_visiting or _rejoining_route or is_scared or (is_gangster and is_instance_valid(combat_target)):
		return dest
	if _local_route_goal == dest and _local_target.is_finite() and global_position.distance_to(_local_target) > 8.0:
		return _local_target
	_local_route_goal = dest
	_local_target = dest
	if global_position.distance_to(dest) <= 112.0: return dest
	# Long sidewalks contain several independent obstacles. A local search
	# must reach the next stretch, not require sight of the far end of the block.
	var axis := _corridor_start.direction_to(_corridor_end)
	var along := (global_position - _corridor_start).dot(axis)
	for advance in [96.0, 112.0, 80.0, 64.0]:
		var point := _corridor_start + axis * clampf(along + advance, 0.0, _corridor_start.distance_to(_corridor_end))
		if movement_navigation.clear_segment(self, point, point):
			_local_target = point
			break
	return _local_target

func _ambient_walk_paused() -> bool:
	return _window_shop_pause > 0.0 or (is_visiting and _visiting_timer > 0.0)


func _social_neighbor(candidate: Variant) -> bool:
	return is_instance_valid(candidate) and candidate != self and candidate.is_inside_tree() and candidate.is_visible_in_tree() and candidate.modulate.a >= 0.1 and candidate.get_world_2d() == get_world_2d()


func _sidewalk_avoidance_offset(travel_dir: Vector2) -> Vector2:
	var push := Vector2.ZERO
	_yield_now = false
	if travel_dir.length_squared() < 0.0001: return push
	var yielding_to: Node2D = _yield_peer.get_ref() if _yield_peer != null else null
	if yielding_to != null and _social_neighbor(yielding_to) and _life_clock < _yield_deadline:
		var gap := yielding_to.global_position - global_position
		if gap.dot(travel_dir) > -4.0 and absf(gap.dot(travel_dir.orthogonal())) < personal_space + 2.0:
			_yield_now = true
			return push
	_yield_peer = null
	var committed: Node2D = _passing_person.get_ref() if _passing_person != null else null
	if committed != null and (not _social_neighbor(committed) or (committed.global_position - global_position).dot(_passing_axis) < -personal_space or _life_clock > _passing_until):
		committed = null
		_passing_person = null
	for candidate in _cached_neighbors:
		if not _social_neighbor(candidate): continue
		var relative: Vector2 = candidate.global_position - global_position
		var along := relative.dot(travel_dir)
		if along < -4.0 or along > SOCIAL_LOOKAHEAD: continue
		var other_velocity := Vector2.ZERO
		if candidate is CharacterBody2D: other_velocity = candidate.velocity
		var closing := travel_dir * _normal_walk_speed - other_velocity
		var prediction := clampf(relative.dot(closing) / maxf(1.0, closing.length_squared()), 0.0, 0.8)
		var clearance := (relative - closing * prediction).length()
		if clearance >= personal_space: continue
		# Both approaching walkers keep to their own right. Choosing a fresh side
		# from tiny position changes made pairs dance left/right indefinitely.
		var route_axis := _corridor_start.direction_to(_corridor_end)
		if is_scared or _rejoining_route or route_axis.is_zero_approx(): route_axis = travel_dir
		var right := Vector2(-route_axis.y, route_axis.x)
		var side_distance := relative.dot(right)
		# At a kerb only one walker may have room on its own right. The other
		# yields briefly instead of following it sideways and blocking it again.
		if _life_clock >= _yield_cooldown and absf(side_distance) < personal_space and along < 56.0:
			var facing_us := other_velocity.dot(travel_dir) < -4.0
			if candidate.has_method("_person_detour_direction"): facing_us = candidate.walk_dir.dot(travel_dir) < -0.2
			var passing_point: Vector2 = candidate.global_position + right * (personal_space + 1.0)
			var peer_yields_to_us := false
			if candidate.has_method("_person_detour_direction") and candidate._yield_peer != null:
				peer_yields_to_us = candidate._yield_peer.get_ref() == self and candidate._yield_deadline > candidate._life_clock
			if facing_us and not peer_yields_to_us and not _navigation_point_allowed(passing_point):
				_yield_peer = weakref(candidate)
				_yield_deadline = _life_clock + 3.5
				_yield_cooldown = _life_clock + 6.0
				_yield_now = true
				return Vector2.ZERO
		if committed == null:
			_passing_side = 1.0 if absf(side_distance) < 9.0 else -signf(side_distance)
			# Commit to the free side for the whole encounter, including near poles.
			var probe := (travel_dir + right * _passing_side).normalized() * 24.0
			if not _navigation_point_allowed(global_position + probe): _passing_side = -_passing_side
			_passing_axis = route_axis
			_passing_person = weakref(candidate)
			_passing_until = _life_clock + 3.0
			committed = candidate
		var side := Vector2(-_passing_axis.y, _passing_axis.x) * _passing_side
		var strength := clampf((personal_space - clearance) / personal_space, 0.0, 1.0)
		push += side * strength * (1.0 - along / (SOCIAL_LOOKAHEAD * 1.5))
	return push.limit_length(1.15)

func _person_detour_direction(direction: Vector2) -> Vector2:
	if _passing_person != null and _passing_person.get_ref() != null:
		return Vector2(-_passing_axis.y, _passing_axis.x) * _passing_side
	return Vector2(-direction.y, direction.x)


func _spacing_speed_factor() -> float:
	if is_scared or (is_gangster and is_instance_valid(combat_target)): return 1.0
	var direction := global_position.direction_to(walk_target)
	var result := 1.0
	for candidate in _cached_neighbors:
		if not _social_neighbor(candidate): continue
		var relative: Vector2 = candidate.global_position - global_position
		var along := relative.dot(direction)
		var lateral := absf(relative.dot(direction.orthogonal()))
		if along <= 0.0 or along >= personal_space * 1.8 or lateral > 17.0: continue
		var other_velocity := Vector2.ZERO
		if candidate is CharacterBody2D: other_velocity = candidate.velocity
		# Head-on traffic needs room to pass; a slower leader needs following space.
		var opposing := other_velocity.dot(direction) < -4.0
		if candidate.has_method("_person_detour_direction"): opposing = opposing or candidate.walk_dir.dot(direction) < -0.2
		var floor_speed := 0.65 if opposing else 0.25
		result = minf(result, clampf((along - 12.0) / maxf(1.0, personal_space), floor_speed, 1.0))
	return result


func _resume_after_panic() -> void:
	danger_response.threats.clear()
	if route_points.size() < 2:
		super._resume_after_panic()
		return
	var best := INF
	var selected := 0
	for index in range(route_points.size() - 1):
		var point := Geometry2D.get_closest_point_to_segment(global_position, route_points[index], route_points[index + 1])
		var distance := global_position.distance_to(point)
		# Prefer a visible sidewalk, so returning cannot cut through the block.
		var cost := distance
		if not movement_navigation.clear_segment(self, global_position, point): cost += 1600.0
		if cost < best:
			best = cost
			selected = index
			_rejoin_point = point
	_route_segment = selected if _route_direction > 0 else selected + 1
	_rejoining_route = true
	walk_target = _rejoin_point
	stuck_timer = 0.0
	movement_navigation.path.clear()
	movement_navigation.destination = Vector2.INF
	movement_navigation.reset_progress()


func validation_state() -> Dictionary:
	var deviation := 0.0
	if route_points.size() >= 2:
		var next_index := _next_route_index()
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
		"within_sidewalk": deviation <= _corridor_width + 0.1 and preload("res://world/shared/pedestrians/PedestrianWalkSpace.gd").allows(global_position, _nearby_roads),
		"locomotion_state": String(locomotion_state),
		"recovery_count": recovery_count,
		"no_progress_seconds": stuck_timer,
	}
