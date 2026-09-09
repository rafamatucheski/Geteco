class_name AuthoredSidewalkPedestrian
extends AnimatedPedestrian3D

## Uses the articulated pedestrian with ambient life routines (entering restaurants/shops,
## window browsing, varied lateral lanes, anti-bunching and desynchronized strides).

@export var route_id: String = ""
@export var route_points: PackedVector2Array
@export_range(8.0, 48.0, 1.0) var sidewalk_half_width: float = 28.0
@export_range(12.0, 64.0, 1.0) var personal_space: float = 24.0
@export_range(-18.0, 18.0, 1.0) var lateral_offset: float = 0.0

var _route_segment := 0
var _route_direction := 1
var _route_target_ready := false
var _normal_walk_speed := 48.0
var _spawn_distance := 0.0
var route_loop := false

# --- Rotinas Ambientais de Vida (Restaurantes, Lojas, Vitrines) ---
var visit_cooldown: float = 20.0
var is_visiting: bool = false
var _visiting_timer: float = 0.0
var _visiting_door_pos: Vector2 = Vector2.ZERO
var _window_shop_pause: float = 0.0

# `_sidewalk_avoidance_offset()` and `_spacing_speed_factor()` each used to
# independently call get_tree().get_nodes_in_group() once per pedestrian per
# physics frame (2x redundant O(n) scans x every pedestrian). Cached once per
# frame instead; the candidate set considered is unchanged. The refresh itself
# is further throttled (every 3rd physics frame) since a couple of frames of
# staleness in a soft avoidance/spacing heuristic is imperceptible, and this
# is the single biggest per-pedestrian recurring cost besides its 3D viewport.
var _cached_neighbors: Array = []
var _neighbor_refresh_counter: int = 0
const NEIGHBOR_REFRESH_STRIDE := 3


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
	
	# Intervalo aleatório para decidir visitar restaurante ou loja
	visit_cooldown = randf_range(14.0, 36.0)
	
	_place_at_route_distance(_spawn_distance)
	ambient_running_enabled = false
	super._ready()
	add_to_group("authored_sidewalk_pedestrian")


func _physics_process(delta: float) -> void:
	_neighbor_refresh_counter += 1
	if _neighbor_refresh_counter >= NEIGHBOR_REFRESH_STRIDE or _cached_neighbors.is_empty():
		_neighbor_refresh_counter = 0
		_cached_neighbors = get_tree().get_nodes_in_group("authored_sidewalk_pedestrian")
	_update_ambient_life(delta)
	
	if _window_shop_pause > 0.0 or (is_visiting and _visiting_timer > 0.0):
		velocity = Vector2.ZERO
		super._physics_process(delta)
		return
		
	base_walk_speed = _normal_walk_speed * _spacing_speed_factor()
	super._physics_process(delta)
	_enforce_sidewalk_guardrail()


func _update_ambient_life(delta: float) -> void:
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
	var buildings := get_tree().get_nodes_in_group("procedural_building")
	var best_building: ProceduralBuilding = null
	var best_dist := 200.0
	for b in buildings:
		if not is_instance_valid(b) or not (b is ProceduralBuilding):
			continue
		var k := String(b.building_kind)
		if not ("shop" in k or "corner_shop" in k or "clothing" in k or "diner" in k or "restaurant" in k or "ammunation" in k):
			continue
		var d := global_position.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best_building = b as ProceduralBuilding
			
	if best_building:
		# Encontra o ponto da porta/entrada na fachada sul
		var door := Vector2(best_building.global_position.x, best_building.global_position.y + best_building.footprint.y * 0.5 - 12.0)
		if best_building.arcade_depth > 0.0:
			door.y -= best_building.arcade_depth * 0.45
			
		is_visiting = true
		_visiting_door_pos = door
		walk_target = door
		_visiting_timer = 0.0


func _process_visiting_state(delta: float) -> void:
	var dist_to_door := global_position.distance_to(_visiting_door_pos)
	if dist_to_door > 22.0 and _visiting_timer == 0.0:
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
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.40)
		collision_layer = 0
		velocity = Vector2.ZERO
		return
		
	_visiting_timer -= delta
	velocity = Vector2.ZERO
	
	if _visiting_timer <= 0.0:
		# Sai do estabelecimento após comer/comprar!
		is_visiting = false
		collision_layer = 4
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.40)
		
		var exit_phrases := ["Muito bom! 👍", "Revigorado! ✨", "Satisfeito! 😊", "Bora continuar 🚶"]
		_show_custom_bubble(exit_phrases[randi() % exit_phrases.size()], Color(0.2, 0.7, 0.95))
		
		if randf() > 0.5:
			_route_direction = -_route_direction
		_pick_new_sidewalk_target()
		visit_cooldown = randf_range(30.0, 60.0)


func _abort_visit() -> void:
	is_visiting = false
	_visiting_timer = 0.0
	collision_layer = 4
	modulate.a = 1.0
	_pick_new_sidewalk_target()


func _pick_new_sidewalk_target() -> void:
	if route_points.size() < 2:
		walk_target = global_position
		return
	if not _route_target_ready:
		_route_target_ready = true
	else:
		_route_segment += _route_direction
		if route_loop:
			_route_segment = posmod(_route_segment,route_points.size()-1)
			_route_direction = 1
			walk_target = route_points[_route_segment+1]
			return
		if _route_segment <= 0:
			_route_segment = 0
			_route_direction = 1
		elif _route_segment >= route_points.size() - 1:
			_route_segment = route_points.size() - 1
			_route_direction = -1
	var next_index := clampi(_route_segment + _route_direction, 0, route_points.size() - 1)
	var target_pt := route_points[next_index]
	var seg_start := route_points[_route_segment]
	var seg_dir := (target_pt - seg_start).normalized()
	if seg_dir.length_squared() > 0.001:
		var normal := Vector2(-seg_dir.y, seg_dir.x)
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
	if route_points.size() < 2 or is_visiting or is_scared:
		return
	if global_position.distance_to(walk_target) < 16.0:
		_pick_new_sidewalk_target()


func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	var base_dir := global_position.direction_to(dest)
	var avoidance := _sidewalk_avoidance_offset(base_dir)
	var combined := base_dir + avoidance
	var steered := combined.normalized() if combined.length_squared() > 0.0001 else base_dir
	
	# Anti-stuck inteligente: evita congelar em postes de luz, árvores ou esquinas
	if velocity.length_squared() < 4.0 and not is_visiting:
		stuck_timer += delta
		if stuck_timer > 1.2:
			# Nudge lateral para contornar o obstáculo e avançar
			lateral_offset = -lateral_offset + randf_range(-6.0, 6.0)
			_pick_new_sidewalk_target()
			stuck_timer = 0.0
	else:
		stuck_timer = maxf(0.0, stuck_timer - delta * 2.0)
		
	return steered * move_speed


func _sidewalk_avoidance_offset(travel_dir: Vector2) -> Vector2:
	var push := Vector2.ZERO
	if travel_dir.length_squared() < 0.0001:
		return push
	for candidate in _cached_neighbors:
		if candidate == self or not is_instance_valid(candidate):
			continue
		var to_other: Vector2 = candidate.global_position - global_position
		var distance: float = to_other.length()
		if distance <= 0.01 or distance >= personal_space:
			continue
		if travel_dir.dot(to_other / distance) < 0.2:
			continue
		var side := travel_dir.orthogonal()
		if side.dot(to_other) > 0.0:
			side = -side
		var strength := clampf((personal_space - distance) / personal_space, 0.0, 1.0)
		push += side * strength
	return push


func _spacing_speed_factor() -> float:
	if is_scared or (is_gangster and is_instance_valid(combat_target)):
		return 1.0
	var direction := global_position.direction_to(walk_target)
	for candidate in _cached_neighbors:
		if candidate == self or not is_instance_valid(candidate):
			continue
		if String(candidate.get("route_id")) != route_id:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance >= personal_space or distance <= 0.01:
			continue
		if direction.dot(global_position.direction_to(candidate.global_position)) > 0.35:
			# Nunca trava completamente a 0.0 para não causar congestionamento permanente
			return clampf((distance - 8.0) / maxf(1.0, personal_space - 8.0), 0.25, 1.0)
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
