extends Node

# Este script será ativado depois como um "AutoLoad" (Singleton).
# Ele rodará invisível durante o jogo todo gerenciando os crimes.

var current_stars: int = 0
var stars: int:
	get: return current_stars
var crime_points: int = 0
var time_hidden: float = 0.0

# Avisa o HUD e os carros da Polícia sempre que o nível de estrelas mudar
signal stars_changed(new_level)
signal crime_reported(severity: int)

var police_spawn_timer: float = 0.0
var _exterior_target: Node2D

func get_pursuit_target() -> Node2D:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if actor and actor.has_meta("police_exterior_position"):
		if not is_instance_valid(_exterior_target):
			_exterior_target = Node2D.new()
			_exterior_target.name = "PoliceLastKnownExterior"
			add_child(_exterior_target)
		_exterior_target.global_position = actor.get_meta("police_exterior_position")
		_exterior_target.set_meta("police_search_position", true)
		return _exterior_target
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(vehicle) and vehicle.get("is_driven_by_player") == true and vehicle.is_visible_in_tree():
			return vehicle
	return actor

func _find_lane_spawn(target_node: Node2D) -> Dictionary:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(90, 42)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1 | 2 | 4
	var candidates: Array[Dictionary] = []
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
			var forward := lane.to_global(lane.curve.sample_baked(minf(length, offset + 8.0), true)) - point
			query.transform = Transform2D(forward.angle(), point)
			if target_node.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				candidates.append({"position": point, "rotation": forward.angle(), "distance": distance, "route_score": distance + ahead * 0.4})
	if candidates.is_empty(): return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.route_score < b.route_score)
	return candidates[0]


func _process(delta):
	# Lógica de fugir da polícia
	if current_stars > 0:
		time_hidden += delta
		
		if time_hidden >= 30.0:
			time_hidden = 0.0
			decrease_stars(1)
			
		police_spawn_timer -= delta
		if police_spawn_timer <= 0:
			_dispatch_police()
			police_spawn_timer = maxf(3.0, 15.0 - (current_stars * 2.5))

func _dispatch_police():
	if current_stars <= 0: return
	var target_node := get_pursuit_target()
	if not is_instance_valid(target_node): return

	# Conta viaturas policiais ativas no momento
	var active_police_count: int = 0
	for em in get_tree().get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(em) and em.get("type") == 0 and em.visible and not em.get("is_broken") and not em.get("is_returning_to_base"):
			active_police_count += 1
			
	var max_active_cruisers = mini(current_stars, 4)
	if active_police_count >= max_active_cruisers:
		return

	# 1. Tenta despacho oficial da Delegacia de Bairro / Central
	var depot_director = get_tree().get_first_node_in_group("emergency_depot_director")
	if depot_director and depot_director.can_process() and depot_director.has_method("request_dispatch"):
		var dispatched = depot_director.request_dispatch("police", target_node, true)
		if dispatched != null:
			dispatched.set_meta("police_player_pursuit", true)
			return

	var lane_spawn := _find_lane_spawn(target_node)
	if lane_spawn.is_empty(): return

	# 2. Despacho dinâmico offscreen inteligente (Spawn na malha viária próxima ao jogador)
	var pool = get_node_or_null("/root/EmergencyPool")
	var police: Node = null
	if pool and pool.has_method("get_vehicle"):
		police = pool.get_vehicle("police")
		if police == null: return # The finite pool includes units returning from a search.
	if police == null:
		var em_scene = load("res://EmergencyVehicle.tscn") as PackedScene
		if em_scene:
			police = em_scene.instantiate()
			get_tree().current_scene.add_child(police)
			
	if is_instance_valid(police):
		police.set_meta("police_player_pursuit", true)
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
	# Furto de viatura oficial da PM eleva procurado para pelo menos 2 estrelas
	if current_stars < 2:
		current_stars = 2
		crime_points = maxi(crime_points, 18)
		stars_changed.emit(current_stars)
	else:
		report_crime(20)
		
	# Toca rádio policial alertando o furto
	var chatter = ProceduralAudio.get_police_radio_chatter_stream()
	if chatter:
		var p = AudioStreamPlayer.new()
		p.stream = chatter
		p.volume_db = 2.0
		p.bus = "SFX"
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	
	# Despacho urgente imediato de viaturas da PM
	police_spawn_timer = 0.2
	_dispatch_police()

func report_crime(severity: int):
	# Reseta o tempo de fuga, já que foi visto cometendo crime
	time_hidden = 0.0
	crime_points += severity
	
	var calc_stars = current_stars
	
	# Matemática de progressão de estrelas do GTA
	if crime_points >= 200: calc_stars = 6
	elif crime_points >= 120: calc_stars = 5
	elif crime_points >= 70: calc_stars = 4
	elif crime_points >= 35: calc_stars = 3
	elif crime_points >= 15: calc_stars = 2
	elif crime_points >= 1: calc_stars = 1
	
	if calc_stars != current_stars:
		current_stars = calc_stars
		stars_changed.emit(current_stars)

	crime_reported.emit(severity)

func decrease_stars(amount: int):
	current_stars = maxi(0, current_stars - amount)
	if current_stars == 0:
		crime_points = 0 # Ficha limpa
	
	stars_changed.emit(current_stars)

func reset_crime():
	crime_points = 0
	current_stars = 0
	time_hidden = 0.0
	stars_changed.emit(0)

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
		"time_hidden": time_hidden
	}

func restore(data: Dictionary) -> void:
	if not (data is Dictionary) or data.is_empty():
		return
	current_stars = clampi(int(data.get("current_stars", 0)), 0, 6)
	crime_points = maxi(0, int(data.get("crime_points", 0)))
	time_hidden = maxf(0.0, float(data.get("time_hidden", 0.0)))
	stars_changed.emit(current_stars)
