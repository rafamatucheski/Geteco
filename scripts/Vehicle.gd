extends CharacterBody3D

const VISUAL := preload("res://scripts/VehicleVisual.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const MAX_SPEED := 15.0
const REVERSE_SPEED := 4.5
const WHEELBASE := 2.5
const WALL_DAMAGE_PER_SPEED := 0.65
const WALL_DAMAGE_MAX_RATIO := 0.12
const WALL_DAMAGE_COOLDOWN_SECONDS := 0.5
var _last_wall_damage_frame := -1000000
var paint_color := Color("d5a544"):
	set(value):
		if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b): return
		paint_color = Color(clampf(value.r,0,1),clampf(value.g,0,1),clampf(value.b,0,1),1)
		_paint_requested = true
		if _paint != null: _paint.apply(paint_color)
		if is_instance_valid(door_presentation): door_presentation.apply_paint(paint_color)
var _paint_requested := false
var _paint: RefCounted
var archetype := ""
var vehicle_id := ""
var health := 180.0
var horizontal_velocity := Vector3.ZERO
var damage_look: Node
var equipment: Node
var effects: Node
var equipment_state: Dictionary = {}
var max_health := 180.0
var max_forward_speed := MAX_SPEED
var drive_acceleration := 5.0
var half_width := 1.04
var half_length := 2.3
var body_height := 1.4
signal damaged(amount: float)
signal destroyed
var controlled := false
var traffic := false:
	set(value):
		traffic = value
		for part in _motorcycle_rider_parts:
			if is_instance_valid(part): part.visible = value
var _motorcycle_rider_parts: Array[MeshInstance3D] = []
var _motorcycle_seat := Vector3(0, -.05, .30)
var _motorcycle_grips: Dictionary = {}
var speed := 0.0
var steering := 0.0
var throttle_input := 0.0
var steer_input := 0.0
var brake_input := false
var external_input := false
var player_damage_attribution := true
var input_locked := false
var engine_disabled := false
## Dirigibilidade da V1 (gameplay/v1_handling/V1Handling.gd) com o jogador ao volante.
var handling = preload("res://gameplay/v1_handling/V1Handling.gd").new()
var _handling_frame := false
var distance_travelled := 0.0
var visual: Node3D
var door_presentation: Node3D
var shape: CollisionShape3D
var wheels: Array[Node3D] = []
## Peças presas ao eixo que esterçam sem rolar (garfo e para-lama de moto).
var steer_pivots: Dictionary = {}
var wheel_spin := 0.0
var tail_material: StandardMaterial3D
var route: Curve3D
var route_distance := 0.0
var route_laps := 0
var blocked := false
## Quem ocupa o sensor frontal (último teste). Usado para desfazer impasse em cruzamento.
var blocker: Object = null
var blocked_time := 0.0
var unjam_time := 0.0
var backoff_time := 0.0
var junction_wait := false
var junction_gap := INF
var _junction_route: Curve3D
var _junction_list: Array = []
var _held_junction: Variant = null
var _held_offset := 0.0
var sensor_clock := 0.0
## Tempo travado por obstáculo que não é sinal/PARE. A fila herda o do carro da frente,
## então fila de semáforo vermelho fica em zero e ninguém "ultrapassa no vermelho".
var stall_time := 0.0
## Tempo sem sair do lugar (fora de fila de sinal). A limpeza da população lê isso.
var stuck_time := 0.0
var _stuck_anchor := 0.0
## Desvio: -1 contramão (esquerda), +1 acostamento (direita), 0 na própria faixa.
var bypass_side := 0.0
var bypass_blend := 0.0
var bypass_start := 0.0
var bypass_retry := 0.0
var _merging_back := false
var _exit_blocked := false
var _sense_tick := false
var sensor_shape := BoxShape3D.new()
var rotation_shape := BoxShape3D.new()

## Diagnóstico de custo (só com world.benchmark_trace): etapas de _ready acima de 2 ms.
func _trace_ready(label: String, began: int) -> int:
	var now := Time.get_ticks_usec()
	if began == 0: return 0
	if now-began >= 2000:
		var world := get_parent()
		var costs: Array = world.get_meta("perf_costs",[])
		if costs.size() < 512: costs.append({"label":"vehicle_ready_"+label+":"+archetype,"start_usec":began,"duration_usec":now-began})
		world.set_meta("perf_costs",costs)
	return now

func _ready() -> void:
	var traced := Time.get_ticks_usec() if get_parent() != null and get_parent().get_meta("benchmark_trace",false) else 0
	collision_layer = 4
	collision_mask = 7
	floor_snap_length = 0.4
	shape = CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.08,1.4,4.6)
	var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(archetype)
	if not specification.is_empty():
		var dimensions: Array = specification.bounds_size
		hull.size = Vector3(maxf(.65,dimensions[0]),clampf(dimensions[1],1.1,3.6),dimensions[2])
		max_health = float(specification.get("durability",180))
		health = max_health
		max_forward_speed = clampf(float(specification.max_speed)/16.0,5,45)
		drive_acceleration = clampf(float(specification.acceleration)/160.0,2.0,10.0)
		if handling != null: handling.configure(specification)
	half_width = hull.size.x*.5
	half_length = hull.size.z*.5
	body_height = hull.size.y
	shape.shape = hull
	shape.position.y = hull.size.y*.5
	add_child(shape)
	rotation_shape.size = hull.size-Vector3(0,.15,0)
	sensor_shape.size = Vector3(hull.size.x+.07,1.2,1)
	traced = _trace_ready("spec",traced)
	visual = preload("res://runtime/FleetCatalog.gd").create(archetype) if not specification.is_empty() else VISUAL.create(paint_color)
	traced = _trace_ready("visual",traced)
	visual.name = "Coupe"
	add_child(visual)
	_bind_motorcycle_rider()
	_paint = preload("res://runtime/VehiclePaint.gd").new()
	_paint.bind(visual,archetype)
	if not _paint_requested:
		paint_color = preload("res://runtime/FleetCatalog.gd").default_paint(archetype,_paint.original_color)
	else:
		_paint.apply(paint_color)
	traced = _trace_ready("paint",traced)
	add_to_group("drivable")
	set_meta("gameplay_role","vehicle")
	var pivots: Dictionary = {}
	for part in visual.get_children():
		if str(part.get_meta("coupe_damage_material_key","")) == "tail":
			if tail_material == null: tail_material = part.material_override.duplicate()
			part.material_override = tail_material
		if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true) == false:
			# Garfo, para-lama e guidão da moto também carregam wheel_center, mas só
			# esterçam: no pivô da roda eles giravam junto com o pneu na frente da moto.
			var axle: Vector3 = part.get_meta("wheel_center")
			if not steer_pivots.has(axle):
				var steer_pivot := Node3D.new()
				steer_pivot.position = axle
				steer_pivot.set_meta("front",axle.z < 0)
				visual.add_child(steer_pivot)
				steer_pivots[axle] = steer_pivot
			part.reparent(steer_pivots[axle],false)
			part.position -= axle
		elif part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			if not pivots.has(center):
				var pivot := Node3D.new()
				pivot.position = center
				pivot.set_meta("front",center.z < 0)
				visual.add_child(pivot)
				pivots[center] = pivot
				wheels.append(pivot)
			part.reparent(pivots[center],false)
			part.position -= center
	traced = _trace_ready("pivots",traced)
	effects = preload("res://gameplay/vehicle_effects/VehicleEffects.gd").new()
	effects.configure(self)
	add_child(effects)
	traced = _trace_ready("effects",traced)
	damage_look = preload("res://gameplay/vehicle_effects/VehicleDamage.gd").new()
	damage_look.name = "DamageLook"
	damage_look.configure(self)
	add_child(damage_look)
	_trace_ready("damage_look",traced)

func set_external_driver(active: bool) -> void:
	external_input = active
	controlled = active and health > 0
	if not active:
		throttle_input = 0
		steer_input = 0
		brake_input = true

func is_player_damage_source() -> bool:
	return player_damage_attribution and controlled and not external_input

func _physics_process(delta: float) -> void:
	if health <= 0:
		controlled = false
		traffic = false
		speed = move_toward(speed,0,20*delta)
	if traffic:
		_drive_traffic(delta)
	else:
		_drive_player(delta)
	# Trânsito parado em fila "dorme": sem move_and_slide nem consulta de giro. Em
	# engarrafamento, carros encostados custavam 60–98 ms por quadro somados (2026-09-23).
	if traffic and health > 0 and absf(speed) < 0.05 and horizontal_velocity.length_squared() < 0.0025 and is_on_floor():
		horizontal_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		return
	var previous := global_position
	var impact_speed := absf(speed)
	var forward := -global_basis.z
	if not _handling_frame:
		var traction := .9 if controlled and brake_input and absf(speed)>5 else 9.0
		horizontal_velocity = horizontal_velocity.lerp(forward*speed,1.0-exp(-traction*delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity.y = -1.0 if is_on_floor() else velocity.y-20.0*delta
	# Física de rua: atropelamento e mobília derrubável antes de mover (o carro
	# atravessa o que cedeu); batida carro x carro e deslize depois.
	STREET.vehicle_pre_move(self,delta)
	var incoming_velocity := Vector3(velocity.x,0,velocity.z)
	move_and_slide()
	var motion := global_position-previous
	motion.y = 0
	distance_travelled += motion.length()
	# Contact removes forward speed, instead of accumulating motion into a wall.
	if is_on_wall():
		speed = motion.dot(forward)/maxf(delta,0.001)
		horizontal_velocity = Vector3(velocity.x,0,velocity.z)
	var hit_vehicle := false
	for index in get_slide_collision_count():
		var target := get_slide_collision(index).get_collider()
		if target is Node and target.is_in_group("drivable"):
			hit_vehicle = true
			continue # StreetPhysics applies car-to-car damage once per actual impact.
		if impact_speed > 4 and target is Node and target.has_method("receive_damage") and target != self and not PROTECTION.is_protected(target):
			target.receive_damage(impact_speed*4,self)
	if is_on_wall() and not hit_vehicle and impact_speed > 6 and impact_speed-absf(speed) > 4:
		# O contato pode durar vários quadros; cobrar a batida apenas uma vez.
		# Tempo da simulação: uma pausa de compilação de shader não é outra batida.
		var now := Engine.get_physics_frames()
		if now-_last_wall_damage_frame >= ceili(WALL_DAMAGE_COOLDOWN_SECONDS * Engine.physics_ticks_per_second):
			_last_wall_damage_frame = now
			receive_damage(minf((impact_speed-absf(speed))*WALL_DAMAGE_PER_SPEED, max_health*WALL_DAMAGE_MAX_RATIO))
	STREET.vehicle_post_move(self,incoming_velocity,delta)
	wheel_spin += motion.dot(forward)/0.355
	for pivot in wheels:
		pivot.rotation = Vector3(wheel_spin,steering if pivot.get_meta("front") else 0.0,0)
	for pivot in steer_pivots.values():
		pivot.rotation.y = steering if pivot.get_meta("front") else 0.0
	if tail_material:
		tail_material.emission_energy_multiplier = 2.5 if brake_input or blocked else 0.65
	if is_instance_valid(effects): effects.physics_tick(delta,incoming_velocity)

func stop_boarding_motion() -> void:
	# The body animation uses fixed door/seat anchors. Speed alone left the
	# smoothed horizontal velocity dragging the vehicle out from under them.
	speed = 0.0
	horizontal_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	# StreetPhysics keeps impact momentum outside velocity. Retaining it let a
	# stopped car slide metres away from the fixed boarding anchors at 0 km/h.
	for key in ["crash_slide", "crash_spin", "crash_stun"]:
		if has_meta(key): remove_meta(key)
	if handling != null: handling.reset()

func _bind_motorcycle_rider() -> void:
	if not archetype.begins_with("bike_"): return
	# Prepared V1 bikes bake the pilot into sibling meshes. Separate only the
	# authored pilot palette/accessories once, before paint and wheel reparenting.
	for child in visual.get_children():
		if not child is MeshInstance3D: continue
		var part := child as MeshInstance3D
		var material: Material = part.material_override if part.material_override else part.mesh.surface_get_material(0)
		if not material is StandardMaterial3D: continue
		var color: String = material.albedo_color.to_html(false)
		var center: Vector3 = (part.transform * part.mesh.get_aabb()).get_center()
		if color == "161b20" and part.get_meta("wheel_spins", true) == false and center.y > .85 and absf(center.x) > .25:
			_motorcycle_grips["Left" if center.x < 0 else "Right"] = part
		if part.has_meta("wheel_center"): continue
		var body := color in ["41454d", "253043", "181b20", "cf5058", "101d29"]
		var helmet_z := -.23 if archetype == "bike_sport" else .01
		var helmet_stud := color == "b5c4ce" and absf(center.x) < .14 and center.y > 1.3 and absf(center.z - helmet_z) < .03
		var stripe_z := .212 if archetype == "bike_sport" else .332
		var jacket_stripe := color in ["d4dce0", "b5c4ce", "f1ede5"] and absf(center.x) < .02 and center.y > .95 and absf(center.z - stripe_z) < .02
		if not body and not helmet_stud and not jacket_stripe: continue
		_motorcycle_rider_parts.append(part)
		part.visible = traffic
		if color == "253043" and absf(center.x) < .01:
			_motorcycle_seat = center - Vector3(0, .95, 0)

func motorcycle_handholds() -> Dictionary:
	var holds := {}
	for side in _motorcycle_grips:
		var part: MeshInstance3D = _motorcycle_grips[side]
		if not is_instance_valid(part): continue
		# The mesh is already a child of the steering pivot. Follow its actual
		# presentation, including steer and vehicle yaw, without another scene scan.
		var sign_side := -1.0 if side == "Left" else 1.0
		var palm_basis: Basis = part.get_parent().global_basis.orthonormalized() * Basis(Vector3.BACK, -sign_side * PI * .5)
		holds[side] = Transform3D(palm_basis, part.to_global(part.mesh.get_aabb().get_center()))
	return holds

func _drive_player(delta: float) -> void:
	_handling_frame = false
	if handling != null and controlled and not external_input and not input_locked and not engine_disabled and health > 0:
		var axis: Vector2 = get_node("/root/GameInput").vehicle_input()
		var handbrake := Input.is_action_pressed("handbrake")
		handling.step(self, delta, axis.y, axis.x, handbrake, _wetness())
		throttle_input = axis.y
		steer_input = -axis.x
		brake_input = handling.service_brake(self, axis.y, handbrake)
		steering = move_toward(steering, steer_input * 0.48, delta * 2.0)
		_handling_frame = true
		return
	if handling != null: handling.reset()
	if not external_input:
		throttle_input = 0
		steer_input = 0
		brake_input = input_locked
		if controlled and not input_locked:
			var axis: Vector2 = get_node("/root/GameInput").vehicle_input()
			throttle_input = axis.y
			steer_input = -axis.x
			brake_input = Input.is_action_pressed("handbrake")
	if not controlled or engine_disabled: brake_input = true
	if brake_input:
		speed = move_toward(speed,0,14.0*delta)
	elif absf(throttle_input) > 0.01:
		var acceleration := 11.0 if speed*throttle_input < 0 else drive_acceleration
		speed = clampf(speed+throttle_input*acceleration*delta,-REVERSE_SPEED,max_forward_speed)
	else:
		speed = move_toward(speed,0,2.0*delta)
	steering = move_toward(steering,steer_input*0.48,delta*2.0)
	var turn := speed/WHEELBASE*tan(steering)*delta
	if absf(turn) > 0.0001 and can_rotate(rotation.y+turn): rotation.y += turn

func _wetness() -> float:
	var world := get_parent()
	var session = world.get("session") if world != null else null
	var weather = session.get("weather") if session != null else null
	return 1.0 if weather != null and int(weather.weather_state) in [1, 2] else 0.0

func can_rotate(yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.transform = Transform3D(Basis(Vector3.UP,yaw),global_position+Vector3.UP*shape.position.y)
	query.collision_mask = 7
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

## Impasse de cruzamento: sem prioridade de via, dois carros de direções cruzadas
## entravam no sensor um do outro e paravam para sempre (engarrafamento de 2026-09-23).
## Depois de TRAFFIC_JAM_SECONDS parados um diante do outro, o de menor id segue
## devagar ignorando só aquele carro; o outro dá uma ré curta para abrir espaço.
const TRAFFIC_JAM_SECONDS := 2.5

func _traffic_jam_partner() -> Object:
	if not is_instance_valid(blocker) or not blocker is CharacterBody3D: return null
	if blocker.get("traffic") != true or blocker.get("blocked") != true: return null
	# Fila na mesma direção não é impasse: quem está atrás só espera.
	var mine := -global_basis.z
	var theirs: Vector3 = -(blocker as Node3D).global_basis.z
	if mine.dot(theirs) > 0.85: return null
	return blocker

## Obstáculo que o trânsito pode empurrar depois de esperar: nunca gente viva, o
## carro do jogador ou outro carro de trânsito (esse tem desempate próprio). Pessoa
## caída só depois de 8 s. Se for parede de verdade, a física segura o carro.
func _pushable_obstacle(target) -> bool:
	if not is_instance_valid(target) or not target is Node: return false
	if target is CharacterBody3D:
		if target.get("traffic") == true: return false
		if target.has_method("driver_seat_anchor"):
			return target.get("controlled") != true and target.get("external_input") != true
		var down: bool = target.get("dead") == true or (target as Node).has_meta("street_down")
		return down and blocked_time > 8.0
	return true

## Distância ao longo da rota até `offset` (negativa depois de passar; rota fechada dá a volta).
func _route_ahead(offset: float, length: float, open: bool) -> float:
	if open: return offset-route_distance
	return fposmod(offset-route_distance+length*.5,length)-length*.5

func _release_junction() -> void:
	if _held_junction != null: JUNCTIONS.release(_held_junction,get_instance_id())
	_held_junction = null

## Cruzamento à frente (TrafficJunctions): true = parar na faixa. `junction_gap` fica
## com a distância da frente do carro até a faixa, para frear de forma progressiva.
func _junction_gate(length: float, open: bool) -> bool:
	junction_gap = INF
	if route != _junction_route:
		_release_junction()
		_junction_route = route
		_junction_list = JUNCTIONS.along(route)
	if _held_junction != null and _route_ahead(_held_offset,length,open) < -JUNCTIONS.EXIT: _release_junction()
	for junction in _junction_list:
		var offset := float(junction.offset)
		var ahead := _route_ahead(offset,length,open)
		if ahead <= -JUNCTIONS.EXIT or ahead > JUNCTIONS.APPROACH: continue
		if _held_junction == junction.key:
			if ahead <= 0.0: continue
			return false
		var gap := ahead-half_length-JUNCTIONS.stop_line(junction.key)
		# Rumo de chegada: trecho da rota logo antes do centro (a curva começa depois).
		var before := route.sample_baked(offset-6.0 if open else fposmod(offset-6.0,length),true)
		var at := route.sample_baked(offset-1.0 if open else fposmod(offset-1.0,length),true)
		# Não bloquear o cruzamento: com a saída ocupada por carro parado, quem entra
		# fica no miolo e trava o eixo cruzado; era o nó que começava os engarrafamentos.
		if gap > -1.5 and _sense_tick: _exit_blocked = _exit_occupied(offset,length,open)
		if gap > -1.5 and _exit_blocked and _exit_wait < EXIT_WAIT_LIMIT:
			_exit_wait += 1.0/Engine.physics_ticks_per_second
			junction_gap = gap
			return true
		_exit_wait = 0.0
		if JUNCTIONS.request(junction.key,get_instance_id(),at-before,gap,absf(speed)):
			_release_junction()
			_held_junction = junction.key
			_held_offset = offset
			return false
		junction_gap = gap
		return true
	return false

func _exit_tree() -> void:
	_release_junction()

func _drive_traffic(delta: float) -> void:
	if route == null: return
	if backoff_time > 0.0:
		backoff_time -= delta
		speed = move_toward(speed,-1.5,8.0*delta)
		return
	sensor_clock -= delta
	_sense_tick = sensor_clock <= 0
	if _sense_tick:
		sensor_clock = 0.1
		blocked = obstacle_ahead()
		if unjam_time > 0.0 and blocked and blocker == get_meta("unjam_partner",null): blocked = false
		if bypass_side != 0.0 and blocked and _body_speed(blocker) < 0.6 and _in_home_lane(blocker): blocked = false
	unjam_time = maxf(0.0,unjam_time-delta)
	bypass_retry = maxf(0.0,bypass_retry-delta)
	blocked_time = blocked_time+delta if blocked else 0.0
	stall_time = _stall_estimate()
	# Sem progresso fora de fila de sinal: a limpeza tira o carro quando ninguém vê.
	# Zera só com avanço real na rota; empurrar carcaça centímetro a centímetro não conta.
	if absf(route_distance-_stuck_anchor) > 8.0:
		stuck_time = 0.0
		_stuck_anchor = route_distance
	elif stall_time > 0.0 or unjam_time > 0.0 or bypass_side != 0.0: stuck_time += delta
	if bypass_side != 0.0 and _sense_tick: _update_bypass()
	if blocked_time > TRAFFIC_JAM_SECONDS:
		var partner := _traffic_jam_partner()
		if partner != null:
			blocked_time = 0.0
			# Quem está desviando pela contramão é o intruso: recua e deixa passar.
			var i_yield: bool = bypass_side < 0.0 or (partner.get("bypass_side") == 0.0 and get_instance_id() > partner.get_instance_id())
			if not i_yield:
				unjam_time = 3.0
				set_meta("unjam_partner",partner)
			else:
				backoff_time = 1.2
		elif bypass_retry <= 0.0 and bypass_side == 0.0 and stall_time > BYPASS_AFTER_SECONDS and _try_bypass():
			blocked_time = 0.0
		elif _pushable_obstacle(blocker) and (not _is_vehicle(blocker) or stall_time > BYPASS_AFTER_SECONDS*3.0):
			# Adereço derrubado, lixeira, carcaça sem motorista: o trânsito empurrava
			# nada e esperava para sempre. Segue devagar; a física de rua derruba o objeto.
			blocked_time = 0.0
			unjam_time = 3.0
			set_meta("unjam_partner",blocker)
	# Progress uses actual position, so a collision cannot advance the car's route.
	var previous_distance := route_distance
	route_distance = route.get_closest_offset(global_position)
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	if not open and previous_distance > length-5 and route_distance < 5: route_laps += 1
	junction_wait = _junction_gate(length,open)
	var near_point := route.sample_baked(minf(route_distance+2,length) if open else fposmod(route_distance+2,length),true)
	var far_point := route.sample_baked(minf(route_distance+5,length) if open else fposmod(route_distance+5,length),true)
	var bend := absf((near_point-global_position).normalized().signed_angle_to((far_point-near_point).normalized(),Vector3.UP))
	var desired_speed := lerpf(5.5,2.2,clampf(bend/1.0,0,1))
	if unjam_time > 0.0: desired_speed = minf(desired_speed,2.5)
	if bypass_side != 0.0: desired_speed = minf(desired_speed,BYPASS_SPEED)
	if open: desired_speed = minf(desired_speed,maxf(0,(length-route_distance-1)*1.5))
	# Sinal fechado: freia progressivamente até a faixa, em vez de travar a 12 m/s² a
	# qualquer distância (o carro parava longe do cruzamento ou em cima da faixa).
	if junction_wait: desired_speed = minf(desired_speed,sqrt(2.0*3.5*maxf(0.0,junction_gap-.4)))
	var target_speed := 0.0 if blocked else desired_speed
	var rate := 12.0 if blocked else (7.0 if target_speed < speed else 2.5)
	speed = move_toward(speed,target_speed,rate*delta)
	var lookahead := lerpf(3.5,1.7,clampf(bend,0,1))
	var target := route.sample_baked(minf(route_distance+lookahead,length) if open else fposmod(route_distance+lookahead,length),true)
	# Desvio: persegue a mesma rota deslocada para o lado, entrando e saindo aos poucos.
	var blend_goal := 0.0 if _merging_back or bypass_side == 0.0 else 1.0
	bypass_blend = move_toward(bypass_blend,blend_goal,delta/1.2)
	if _merging_back and bypass_blend <= 0.0: _end_bypass()
	if bypass_blend > 0.0: target += _route_right(route_distance+lookahead,length,open)*_bypass_shift()*bypass_blend
	var direction := target-global_position
	direction.y = 0
	var desired := atan2(-direction.x,-direction.z)
	var next_yaw := rotate_toward(rotation.y,desired,delta*1.7)
	steering = clampf(angle_difference(rotation.y,desired),-0.48,0.48)
	# Carro parado não esterça no lugar (e poupa a consulta de colisão por passo).
	if absf(speed) > 0.2 and can_rotate(next_yaw): rotation.y = next_yaw

## Desvio de obstáculo parado (viatura na faixa, carcaça, fila que não anda): antes o
## trânsito só esperava, e um carro parado virava engarrafamento sem fim (2026-09-25).
## Depois de BYPASS_AFTER_SECONDS travado, o carro procura a contramão (depois o
## acostamento) livre por uns 25 m, contorna devagar e volta quando a própria faixa
## está livre ao lado e à frente.
const BYPASS_AFTER_SECONDS := 3.5
const BYPASS_SPEED := 4.0
const BYPASS_MAX_DISTANCE := 45.0
const BYPASS_PROBES := [0.0, 5.0, 10.0, 16.0, 22.0]
const MERGE_PROBES := [0.0, 4.0, 8.0]
## Saída do cruzamento ocupada: espera isso no máximo. Carro estacionado perto da
## saída não pode fechar a aproximação para sempre.
const EXIT_WAIT_LIMIT := 8.0
var _exit_wait := 0.0

func _is_vehicle(target) -> bool:
	return is_instance_valid(target) and target is Node and (target as Node).has_method("driver_seat_anchor")

func _body_speed(target) -> float:
	if not is_instance_valid(target): return 0.0
	if _is_vehicle(target): return absf(float(target.get("speed")))
	if target is CharacterBody3D: return (target as CharacterBody3D).velocity.length()
	if target is RigidBody3D: return (target as RigidBody3D).linear_velocity.length()
	return 0.0

func _stall_estimate() -> float:
	if junction_wait or not blocked or not is_instance_valid(blocker): return 0.0
	if blocker is Node3D and blocker.get("traffic") == true:
		var same_way := (-global_basis.z).dot(-(blocker as Node3D).global_basis.z) > 0.85
		if same_way:
			# Fila: vale o travamento de quem está na frente. Na fila do sinal ele é zero.
			if blocker.get("junction_wait") == true or blocker.get("blocked") != true: return 0.0
			return float(blocker.get("stall_time"))
	if _body_speed(blocker) > 0.6: return 0.0
	return blocked_time

func _route_point(offset: float, length: float, open: bool) -> Vector3:
	return route.sample_baked(clampf(offset,0.0,length) if open else fposmod(offset,length),true)

func _route_right(offset: float, length: float, open: bool) -> Vector3:
	var tangent := _route_point(offset+1.0,length,open)-_route_point(offset-1.0,length,open)
	tangent.y = 0
	if tangent.length_squared() < .0001: return global_basis.x
	return tangent.normalized().cross(Vector3.UP)

## Deslocamento lateral do desvio: faixa contrária inteira à esquerda; à direita só o
## que cabe até o meio-fio.
func _bypass_shift() -> float:
	return -3.4 if bypass_side < 0.0 else 2.6

## Casco livre na rota deslocada `shift` metros para a direita, a `probes` metros à frente.
func _lane_clear(shift: float, probes: Array, mask := 7) -> bool:
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = mask
	query.exclude = [get_rid()]
	for distance in probes:
		var at := route_distance+float(distance)
		var right := _route_right(at,length,open)
		var point := _route_point(at,length,open)+right*shift
		query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),point+Vector3.UP*shape.position.y)
		if not space.intersect_shape(query,1).is_empty(): return false
	return true

func _try_bypass() -> bool:
	bypass_retry = 1.0
	if route == null or str(get_meta("traffic_yield_state","")) != "": return false
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	# Nunca desvia para dentro de um cruzamento: lá a contramão é a via cruzada.
	for junction in _junction_list:
		var ahead := _route_ahead(float(junction.offset),length,open)
		if ahead > -JUNCTIONS.EXIT and ahead < 14.0: return false
	for side in [-1.0, 1.0]:
		bypass_side = side
		if _lane_clear(_bypass_shift(),BYPASS_PROBES):
			bypass_start = route_distance
			_merging_back = false
			return true
	bypass_side = 0.0
	return false

## Corpo parado na faixa original (o que estamos contornando): o sensor frontal o
## enxerga em diagonal durante o desvio e não deve frear o carro por isso.
func _in_home_lane(target) -> bool:
	if not target is Node3D: return false
	var point: Vector3 = (target as Node3D).global_position
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	var offset := route.get_closest_offset(point)
	return absf((point-_route_point(offset,length,open)).dot(_route_right(offset,length,open))) < 1.7

func _update_bypass() -> void:
	if _merging_back: return
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	var travelled := route_distance-bypass_start if open else fposmod(route_distance-bypass_start,length)
	# Contramão fechada por quem vem de frente há muito tempo: desiste e volta.
	if travelled > 4.0 and _lane_clear(0.0,MERGE_PROBES): _merging_back = true
	elif travelled > BYPASS_MAX_DISTANCE or blocked_time > 6.0: _merging_back = true

func _end_bypass() -> void:
	bypass_side = 0.0
	bypass_blend = 0.0
	_merging_back = false
	bypass_retry = 2.0

## Carro parado logo depois do cruzamento, na nossa saída.
func _exit_occupied(offset: float, length: float, open: bool) -> bool:
	var at := offset+JUNCTIONS.EXIT+half_length+1.0
	if open and at > length: return false
	var right := _route_right(at,length,open)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = 4
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),_route_point(at,length,open)+Vector3.UP*shape.position.y)
	for hit in get_world_3d().direct_space_state.intersect_shape(query,4):
		if _is_vehicle(hit.collider) and _body_speed(hit.collider) < 1.0: return true
	return false

func obstacle_ahead() -> bool:
	var length := 2.2+speed*speed/20.0
	sensor_shape.size.z = length
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sensor_shape
	query.transform = Transform3D(global_basis,global_position-global_basis.z*(half_length+length/2)+Vector3.UP*0.8)
	query.collision_mask = 7
	query.exclude = [get_rid()]
	var hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(query,1)
	blocker = hits[0].collider if not hits.is_empty() else null
	return not hits.is_empty()

func place(point: Vector3, yaw: float) -> void:
	global_position = point
	rotation.y = yaw
	speed = 0
	velocity = Vector3.ZERO
	horizontal_velocity = Vector3.ZERO
	reset_physics_interpolation()

## Porte para embarque/desembarque. Antes toda carroceria usava a porta e o banco do
## carro pequeno: o motorista de ônibus e de caminhão entrava abaixado pelo meio da
## lataria. `open`: moto, buggy e empilhadeira (sem porta); `car`: senta baixo;
## `tall`: caminhonete, SUV e van (um degrau); `truck`: cabine alta, sobe pelo estribo;
## `bus`: porta dianteira direita com escada.
func boarding_class() -> String:
	if archetype.begins_with("bike_") or archetype in ["port_forklift", "beach_buggy", "dune_buggy"]: return "open"
	if archetype == "route_city": return "bus"
	if body_height >= 2.35: return "truck"
	if body_height >= 1.75: return "tall"
	return "car"

## Lados por onde se entra ao volante. Ônibus só pela porta de serviço da direita.
func boarding_sides() -> Array:
	return [1] if boarding_class() == "bus" else [-1, 1]

## Altura do piso da cabine sobre o chão, que o corpo precisa vencer para entrar.
func boarding_step_height() -> float:
	match boarding_class():
		"truck": return clampf(body_height * .36, .85, 1.15)
		"bus": return .42
		"tall": return .32
	return 0.0

func _cab_z() -> float:
	match boarding_class():
		"bus": return -(half_length - .8)
		"truck": return -(half_length - 1.3)
	return -clampf(half_length * .18, .30, .62)

func driver_door_anchor(side: int) -> Vector3:
	return to_global(Vector3(float(side) * (half_width + .54), .04, _cab_z()))

func driver_seat_anchor() -> Vector3:
	if archetype.begins_with("bike_"): return to_global(_motorcycle_seat)
	if boarding_class() == "bus":
		return to_global(Vector3(-minf(.55, half_width * .4), .08 + boarding_step_height(), _cab_z() - .15))
	if boarding_class() in ["truck", "tall"]:
		return to_global(Vector3(-minf(.45, half_width * .3), .08 + boarding_step_height(), _cab_z() + .15))
	var seat_z := -clampf(half_length * .16, .26, .55)
	return to_global(Vector3(-minf(.28, half_width * .24), .08, seat_z))

func animate_driver_door(side: int, opened: bool, duration := .28) -> void:
	_ensure_door_presentation()
	if is_instance_valid(door_presentation): door_presentation.set_open(side, opened, duration)

func _ensure_door_presentation() -> void:
	if is_instance_valid(door_presentation) or boarding_class() in ["open", "bus"]: return
	door_presentation = preload("res://gameplay/VehicleDoorPresentation.gd").new()
	visual.add_child(door_presentation)
	door_presentation.configure(self)

func camera_lookahead() -> Vector3:
	return -global_basis.z*clampf(speed*0.4,-2.0,6.0)

func ensure_equipment(world: Node) -> Node:
	if is_instance_valid(equipment): return equipment
	equipment = preload("res://gameplay/VehicleEquipment.gd").new()
	equipment.configure(self,world)
	add_child(equipment)
	if not equipment_state.is_empty(): equipment.restore_state(equipment_state)
	return equipment

func receive_damage(amount: float, _source: Node = null) -> void:
	if amount <= 0 or health <= 0: return
	health = maxf(0,health-amount)
	damaged.emit(amount)
	# Aparência (desgaste, fogo no motor, carcaça) vive em VehicleDamage; a vida continua aqui.
	var look := damage_look if is_instance_valid(damage_look) else null
	if look: look.note_source(_source)
	if health <= 0:
		destroyed.emit()
		if look: look.wreck()
	elif look: look.refresh()

func repair() -> void:
	health = max_health
	if is_instance_valid(damage_look): damage_look.restore()
