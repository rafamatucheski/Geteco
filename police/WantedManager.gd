extends Node

# Este script será ativado depois como um "AutoLoad" (Singleton).
# Ele rodará invisível durante o jogo todo gerenciando os crimes.

var current_stars: int = 0
var stars: int:
	get: return current_stars
var crime_points: int = 0
var time_hidden: float = 0.0

# Isolated minor incidents expire before they become a pursuit.
const STAR_THRESHOLDS := [0, 12, 30, 60, 100, 160, 240]
const MINOR_INCIDENT_MEMORY := 12.0
const INITIAL_DISPATCH_DELAY := [0.0, 6.0, 3.0, 1.0, 1.0, 1.0, 1.0]
const DISPATCH_INTERVAL := [0.0, 10.0, 8.0, 6.0, 5.0, 4.0, 4.0]
const MAX_ACTIVE_UNITS := [0, 2, 3, 4, 5, 5, 5]
const DEPLOYMENT_BUDGET := [0, 4, 6, 10, 14, 18, 22]
var deployed_this_pursuit := 0
const CONTACT_GRACE := 1.0
var _contact_age := CONTACT_GRACE + 1.0
var _sensor_timer := 0.0
var _dispatch_serial := 0
var _has_known_position := false
var _radio_player: AudioStreamPlayer
signal radio_message(event: StringName, level: int)

# Avisa o HUD e os carros da Polícia sempre que o nível de estrelas mudar
signal stars_changed(new_level)
signal crime_reported(severity: int)

var police_spawn_timer: float = 0.0
var _exterior_target: Node2D

func get_suspect_actor() -> Node2D:
	# Perception alone uses the real actor; navigation uses get_pursuit_target.
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(vehicle) and vehicle.get("is_driven_by_player") == true and vehicle.is_visible_in_tree():
			return vehicle
	return actor

func _remember_position(point: Vector2) -> void:
	if not is_instance_valid(_exterior_target):
		_exterior_target = Node2D.new()
		_exterior_target.name = "PoliceLastKnownPosition"
		_exterior_target.set_meta("police_search_position", true)
		add_child(_exterior_target)
	_exterior_target.global_position = point
	_has_known_position = true

func _remember_reported_crime() -> void:
	var suspect := get_suspect_actor()
	if is_instance_valid(suspect):
		_remember_position(suspect.get_meta("police_exterior_position", suspect.global_position))

func get_pursuit_target() -> Node2D:
	if current_stars <= 0: return null
	if not _has_known_position: _remember_reported_crime()
	var suspect := get_suspect_actor()
	if is_instance_valid(suspect) and not suspect.has_meta("police_exterior_position") and _contact_age <= CONTACT_GRACE:
		return suspect
	return _exterior_target if _has_known_position and is_instance_valid(_exterior_target) else null

func is_searching() -> bool:
	return current_stars > 0 and _contact_age > CONTACT_GRACE

func get_escape_duration() -> float:
	if current_stars == 6: return 120.0
	return 18.0 + 5.0 * current_stars

func get_max_active_units() -> int:
	return MAX_ACTIVE_UNITS[current_stars]

func can_request_reinforcements() -> bool:
	return current_stars > 0 and deployed_this_pursuit < DEPLOYMENT_BUDGET[current_stars]

func report_visual_contact(observer: Node2D) -> bool:
	if current_stars <= 0 or not is_instance_valid(observer) or not observer.is_visible_in_tree(): return false
	if observer.get("is_dead") == true or observer.get("is_broken") == true: return false
	if observer.get("is_driven_by_player") == true or observer.get("local_security") == true: return false
	if observer.has_method("has_police_response_crew") and not observer.has_police_response_crew(): return false
	var suspect := get_suspect_actor()
	if is_instance_valid(suspect) and observer.get_world_2d() != suspect.get_world_2d(): return false
	if not is_instance_valid(suspect) or suspect.has_meta("police_exterior_position") or not suspect.is_visible_in_tree(): return false
	var sight_range := 650.0 if observer.is_in_group("emergency_vehicle") else 430.0
	if observer.global_position.distance_to(suspect.global_position) > sight_range: return false
	var query := PhysicsRayQueryParameters2D.create(observer.global_position, suspect.global_position, 1 | 2)
	var excluded: Array[RID] = []
	if observer is CollisionObject2D: excluded.append(observer.get_rid())
	query.exclude = excluded
	var hit := observer.get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != suspect: return false
	_remember_position(suspect.global_position)
	_contact_age = 0.0
	time_hidden = 0.0
	return true

func _scan_police_contact() -> void:
	for observer in get_tree().get_nodes_in_group("police_officer"):
		if report_visual_contact(observer): return
	for observer in get_tree().get_nodes_in_group("emergency_vehicle"):
		if observer.get("type") == 0 and report_visual_contact(observer): return

func _play_star_radio(stars: int) -> void:
	if stars <= 0:
		return
	var event: StringName = &"suspect_spotted" if stars <= 1 else &"reinforcements"
	radio_message.emit(event, stars)
	var chatter = preload("res://audio/police_dispatch/PoliceDispatchRadio.gd").stream_for(event)
	if not chatter:
		chatter = ProceduralAudio.get_police_radio_chatter_stream()
	if not chatter:
		return
	if not is_instance_valid(_radio_player):
		_radio_player = AudioStreamPlayer.new()
		_radio_player.name = "PoliceRadioPlayer"
		_radio_player.bus = "SFX"
		_radio_player.volume_db = -16.0
		add_child(_radio_player)
	_radio_player.stream = chatter
	_radio_player.play()

func _radio(_event: StringName) -> void:
	pass

func report_officer_killed() -> void:
	report_crime(maxi(30, STAR_THRESHOLDS[3] - crime_points))
	police_spawn_timer = minf(police_spawn_timer, 0.8)

func _is_active_pursuit_unit(unit: Node) -> bool:
	return is_instance_valid(unit) and unit.get("type") == 0 and unit.visible \
		and unit.get_meta("police_player_pursuit", false) \
		and unit.get("is_driven_by_player") != true and not unit.get("is_broken") \
		and (not unit.has_method("has_police_response_crew") or unit.has_police_response_crew()) \
		and not unit.get("is_returning_to_base")

func _has_active_elite(exclude: Node = null) -> bool:
	for unit in get_tree().get_nodes_in_group("emergency_vehicle"):
		if unit != exclude and _is_active_pursuit_unit(unit) and unit.get("police_variant") == "tactical":
			return true
	return false

func _configure_dispatch(unit: Node) -> void:
	_dispatch_serial += 1
	deployed_this_pursuit += 1
	unit.set_meta("police_player_pursuit", true)
	if unit.has_method("configure_police_response"):
		# Five vehicles are enough for the maximum response. Keep one elite
		# tactical crew in that formation and replace it only after it leaves.
		var elite := current_stars >= 4 and not _has_active_elite(unit)
		unit.configure_police_response(current_stars, _dispatch_serial, elite)

func _find_lane_spawn(target_node: Node2D) -> Dictionary:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(90, 42)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1 | 2 | 4
	var best_candidate: Dictionary = {}
	var best_score := INF
	var camera := target_node.get_viewport().get_camera_2d()
	var view_rect := Rect2()
	if camera:
		var size := target_node.get_viewport_rect().size / camera.zoom
		view_rect = Rect2(camera.get_screen_center_position() - size * 0.5, size).grow(90)
	for node in get_tree().get_nodes_in_group("unified_traffic_lane"):
		var lane := node as Path2D
		if lane == null or lane.curve == null or lane.curve.point_count < 2 or not lane.can_process(): continue
		var length := lane.curve.get_baked_length()
		var goal_offset := lane.curve.get_closest_offset(lane.to_local(target_node.global_position))
		var closed := bool(lane.get_meta("traffic_lane_loop", false))
		closed = closed or lane.curve.get_point_position(0).distance_to(lane.curve.get_point_position(lane.curve.point_count - 1)) < 5.0
		for index in range(1, int(length / 160.0)):
			var offset := float(index) * 160.0
			var ahead := goal_offset - offset
			if closed: ahead = fposmod(ahead, length)
			elif ahead < 60.0: continue
			var point := lane.to_global(lane.curve.sample_baked(offset, true))
			var distance := point.distance_to(target_node.global_position)
			if distance < 520.0 or distance > 1800.0 or view_rect.has_point(point): continue
			var score := distance + ahead * 0.4
			# A worse candidate cannot win, even if its footprint is clear.
			# Keep the first equal score, matching the lane traversal order.
			if score >= best_score: continue
			var forward := lane.to_global(lane.curve.sample_baked(minf(length, offset + 8.0), true)) - point
			query.transform = Transform2D(forward.angle(), point)
			if target_node.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				best_score = score
				best_candidate = {"position": point, "rotation": forward.angle(), "distance": distance, "route_score": score}
	return best_candidate


func _process(delta):
	if current_stars == 0:
		if crime_points > 0:
			time_hidden += delta
			if time_hidden >= MINOR_INCIDENT_MEMORY:
				crime_points = 0
				time_hidden = 0.0
		return
	_contact_age += delta
	time_hidden += delta
	_sensor_timer -= delta
	if _sensor_timer <= 0.0:
		_sensor_timer = 0.25
		_scan_police_contact()
	if time_hidden >= get_escape_duration():
		reset_crime()
		return
	police_spawn_timer -= delta
	if police_spawn_timer <= 0.0:
		_dispatch_police()
		police_spawn_timer = DISPATCH_INTERVAL[current_stars]

func _dispatch_police():
	if not can_request_reinforcements(): return
	var target_node := get_pursuit_target()
	if not is_instance_valid(target_node): return

	# Conta viaturas policiais ativas no momento
	var active_police_count: int = 0
	for em in get_tree().get_nodes_in_group("emergency_vehicle"):
		if _is_active_pursuit_unit(em):
			active_police_count += 1
			
	var max_active_cruisers = get_max_active_units()
	if active_police_count >= max_active_cruisers:
		return

	# The first unit leaves its precinct. Higher-level reinforcements can be
	# regional patrols already on the road, so a distant precinct cannot delay
	# every wave. Both paths retain the finite pool and deployment budget.
	var lane_spawn: Dictionary = {}
	var prefer_regional := current_stars >= 2 and deployed_this_pursuit > 0
	if prefer_regional:
		lane_spawn = _find_lane_spawn(target_node)
	var depot_director = get_tree().get_first_node_in_group("emergency_depot_director")
	if lane_spawn.is_empty() and depot_director and depot_director.can_process() and depot_director.has_method("request_dispatch"):
		var dispatched = depot_director.request_dispatch("police", target_node, true)
		if dispatched != null:
			_configure_dispatch(dispatched)
			return

	if lane_spawn.is_empty(): lane_spawn = _find_lane_spawn(target_node)
	if lane_spawn.is_empty(): return

	# 2. Despacho dinâmico offscreen inteligente (Spawn na malha viária próxima ao jogador)
	var pool = get_node_or_null("/root/EmergencyPool")
	var police: Node = null
	if pool and pool.has_method("get_vehicle"):
		police = pool.get_vehicle("police")
		if police == null: return # The finite pool includes units returning from a search.
	if police == null:
		var em_scene = load("res://emergency/EmergencyVehicle.tscn") as PackedScene
		if em_scene:
			police = em_scene.instantiate()
			get_tree().current_scene.add_child(police)
			
	if is_instance_valid(police):
		_configure_dispatch(police)
		police.set("type", 0)
		police.set("target", target_node)
		police.set("is_acting", false)
		police.set("is_returning_to_base", false)
		
		police.global_position = lane_spawn.position
		police.rotation = lane_spawn.rotation
		police.configure_depot_assignment("regional_patrol", lane_spawn.position, lane_spawn.position)
		if police.has_method("show"):
			police.show()
		police.set_physics_process(true)

func report_police_car_theft() -> void:
	time_hidden = 0.0
	# Each newly stolen cruiser adds one star, preserving an existing pursuit.
	var gained := false
	if current_stars < STAR_THRESHOLDS.size() - 1:
		current_stars += 1
		crime_points = maxi(crime_points, STAR_THRESHOLDS[current_stars])
		stars_changed.emit(current_stars)
		gained = true
		
	_remember_reported_crime()
	if gained:
		_play_star_radio(current_stars)

	_dispatch_police()
	police_spawn_timer = DISPATCH_INTERVAL[current_stars]

func report_crime(severity: int):
	var actor := get_tree().get_first_node_in_group("player")
	if is_instance_valid(actor) and actor.get_meta("isolated_interior", false): return
	if severity < 0: return
	# Reseta o tempo de fuga, já que foi visto cometendo crime
	time_hidden = 0.0
	crime_points += severity
	_remember_reported_crime()
	
	var calc_stars = current_stars
	
	for level in range(1, STAR_THRESHOLDS.size()):
		if crime_points >= STAR_THRESHOLDS[level]:
			calc_stars = maxi(calc_stars, level)
	
	if calc_stars != current_stars:
		var stars_gained: bool = calc_stars > current_stars
		if current_stars == 0:
			police_spawn_timer = INITIAL_DISPATCH_DELAY[calc_stars]
		else:
			police_spawn_timer = minf(police_spawn_timer, INITIAL_DISPATCH_DELAY[calc_stars])
		current_stars = calc_stars
		stars_changed.emit(current_stars)
		if stars_gained:
			_play_star_radio(current_stars)

	crime_reported.emit(severity)

func ensure_minimum_wanted_level(level: int) -> void:
	level = clampi(level, 0, 6)
	report_crime(maxi(0, STAR_THRESHOLDS[level] - crime_points))

func decrease_stars(amount: int):
	current_stars = maxi(0, current_stars - maxi(0, amount))
	# Lost stars must also lower the underlying score, or one minor incident
	# restores the entire old pursuit on the next report.
	if amount > 0:
		crime_points = mini(crime_points, STAR_THRESHOLDS[current_stars])
	if current_stars == 0:
		crime_points = 0 # Ficha limpa
		police_spawn_timer = 0.0
		deployed_this_pursuit = 0
	
	stars_changed.emit(current_stars)

func reset_crime():
	crime_points = 0
	deployed_this_pursuit = 0
	current_stars = 0
	time_hidden = 0.0
	police_spawn_timer = 0.0
	_contact_age = CONTACT_GRACE + 1.0
	_has_known_position = false
	stars_changed.emit(0)

func stand_down_police() -> void:
	reset_crime()
	# Policiais a pé cessam fogo e iniciam retorno à viatura
	for officer in get_tree().get_nodes_in_group("police_officer"):
		if is_instance_valid(officer) and not officer.is_dead:
			if officer.has_method("stand_down"):
				officer.stand_down()
			else:
				officer.target = null
				officer.velocity = Vector2.ZERO

	# Viaturas de polícia desligam sirenes e iniciam retorno
	for em in get_tree().get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(em) and em.get("type") == 0:
			if em.has_method("stand_down"):
				em.stand_down()
			else:
				em.target = null
				em.set("is_returning_to_base", true)


func dismiss_all_police():
	reset_crime()
	# Remove policiais a pé
	for officer in get_tree().get_nodes_in_group("police_officer"):
		if is_instance_valid(officer):
			officer.queue_free()
			
	# Desativa viaturas de polícia ativas
	for em in get_tree().get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(em) and em.get("type") == 0:
			if em.has_method("_deactivate"):
				em._deactivate()
			else:
				em.queue_free()

# Atalho para cheats ou eventos de missão ("Leavemealone")
func clear_wanted_level():
	dismiss_all_police()

func reset():
	dismiss_all_police()

func serialize() -> Dictionary:
	return {
		"current_stars": current_stars,
		"crime_points": crime_points,
		"time_hidden": time_hidden,
		"deployed_this_pursuit": deployed_this_pursuit
	}

func restore(data: Dictionary) -> void:
	if not (data is Dictionary) or data.is_empty():
		return
	current_stars = clampi(int(data.get("current_stars", 0)), 0, 6)
	deployed_this_pursuit = clampi(int(data.get("deployed_this_pursuit", 0)), 0, DEPLOYMENT_BUDGET[6]) if current_stars > 0 else 0
	crime_points = maxi(0, int(data.get("crime_points", 0)))
	# Preserve the saved stars, but normalize points from older balance values.
	crime_points = maxi(crime_points, STAR_THRESHOLDS[current_stars])
	if current_stars < 6:
		crime_points = mini(crime_points, STAR_THRESHOLDS[current_stars + 1] - 1)
	time_hidden = maxf(0.0, float(data.get("time_hidden", 0.0)))
	police_spawn_timer = INITIAL_DISPATCH_DELAY[current_stars]
	_remember_reported_crime()
	stars_changed.emit(current_stars)
