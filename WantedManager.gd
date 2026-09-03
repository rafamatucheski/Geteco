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

var police_spawn_timer: float = 0.0

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
	var target_node = null
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.get("is_driven_by_player") == true and is_instance_valid(v) and v.visible:
			target_node = v
			break
			
	if not target_node:
		target_node = get_tree().get_first_node_in_group("player")
		
	if not target_node or not is_instance_valid(target_node):
		return

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
	if depot_director and depot_director.has_method("request_dispatch"):
		var dispatched = depot_director.request_dispatch("police", target_node, true)
		if dispatched != null:
			return

	# 2. Despacho dinâmico offscreen inteligente (Spawn na malha viária próxima ao jogador)
	var pool = get_node_or_null("/root/EmergencyPool")
	var police: Node = null
	if pool and pool.has_method("get_vehicle"):
		police = pool.get_vehicle("police")
	if police == null:
		var em_scene = load("res://EmergencyVehicle.tscn") as PackedScene
		if em_scene:
			police = em_scene.instantiate()
			get_tree().current_scene.add_child(police)
			
	if is_instance_valid(police):
		police.set("type", 0)
		police.set("target", target_node)
		police.set("is_acting", false)
		police.set("is_returning_to_base", false)
		
		# Posição de interceptação dinâmica nas vias principais (550px a 750px de distância)
		var spawn_angles := [0.0, PI * 0.5, PI, PI * 1.5, PI * 0.25, -PI * 0.25]
		var pick_ang = spawn_angles[randi() % spawn_angles.size()]
		var offset_vec = Vector2.RIGHT.rotated(pick_ang) * randf_range(520.0, 720.0)
		var spawn_pos = target_node.global_position + offset_vec
		
		police.global_position = spawn_pos
		police.rotation = (target_node.global_position - spawn_pos).angle()
		if police.has_method("show"):
			police.show()
		police.set_physics_process(true)

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
