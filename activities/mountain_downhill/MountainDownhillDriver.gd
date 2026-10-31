extends RefCounted
## Bounded sensors, real throttle/steering/braking; recovery never moves bodies.
var car
var course
var cap := 31.0
var lane := 0.0
var desired_lane := 0.0
var sensor_clock := 0.0
var pass_cooldown := 0.0
var gap := INF
var leader_speed := 0.0
var reverse_left := 0.0
var stalled := 0.0
var anchor := Vector3.ZERO
var recoveries := 0
var reaction := 0.0
var lane_query := PhysicsShapeQueryParameters3D.new()
## Rivais da mesma prova (MountainDownhill preenche). Sem eles cada piloto só vê o próprio corredor, e o
## impasse de 07/10 ficava sem saída: preso na faixa da esquerda diante de um carro contrário, com o
## pelotão ocupando a direita e ninguém abrindo espaço.
var peers: Array = []
var course_offset := 0.0
## Pedido de vaga na direita: carro contrário à frente na faixa da esquerda.
var merge_request := false
var lane_rate := 1.8
var stop_gap := 2.4
## Piloto brigão (28/10, pedido do usuário: "ele só tem que chegar"): carro na frente é para empurrar,
## não para esperar. Só obstáculo fixo (guard-rail, muro) ainda faz parar. GETECO_DOWNHILL_PUSH=0 volta
## ao piloto educado, para o A/B no mesmo jogo.
static var push_enabled := OS.get_environment("GETECO_DOWNHILL_PUSH") != "0"
var leader_vehicle := false
var oncoming_wait := 0.0
## Tempo sem avançar 8 m no percurso: a prova usa para devolver à pista quem ficou engavetado
## (os carros são cinemáticos, encostar não empurra ninguém).
var best_offset := -INF
var stuck_time := 0.0

func setup(vehicle, authored_course, index: int) -> void:
	car = vehicle
	course = authored_course
	cap = minf(float(car.max_forward_speed),[33.0,32.4,31.8,33.5,32.0,31.6][index])
	lane = -1.8 if index%2 == 0 else 1.8
	desired_lane = lane
	sensor_clock = float(index)*.025
	reaction = [.12,.2,.16,.25,.22,.18][index]
	anchor = car.global_position
	var clearance := BoxShape3D.new()
	clearance.size = Vector3(car.half_width*2.0+.3,.65,car.half_length*2.0+.7)
	lane_query.shape = clearance
	lane_query.collision_mask = 7
	lane_query.exclude = [car.get_rid()]
	car.set_external_driver(true)
	car.player_damage_attribution = false

func tick(delta: float, hold: bool, next_checkpoint: int) -> void:
	if not is_instance_valid(car) or car.health <= 0: return
	car.set_external_driver(true)
	car.throttle_input = 0.0
	car.steer_input = 0.0
	car.brake_input = hold
	if hold: return
	if reaction > 0:
		reaction -= delta
		car.brake_input = true
		return
	var offset: float = course.nearest_offset(car.global_position)
	course_offset = offset
	# Rastejar também é estar preso: menos de 8 m em 5 s (engavetamento lento da 28/10, rivais nos portões 8–11).
	if offset > best_offset+8.0:
		best_offset = offset
		stuck_time = 0.0
	else: stuck_time += delta
	var look := clampf(4.0+absf(float(car.speed))*.27,4.0,12.0)
	var target_at := minf(offset+look,float(course.length)-.5)
	# Um checkpoint perdido precisa ser abordado pelo lado de cima. Dirigir
	# rumo a grampos posteriores nunca conserta um portão pulado nem a classificação dele.
	if next_checkpoint < course.gate_offsets.size():
		var required: float = course.gate_offsets[next_checkpoint]
		if offset > required+3.0: target_at = maxf(0.0,required-6.0)
	var direction: Vector3 = course.direction(target_at)
	var right := direction.cross(Vector3.UP).normalized()
	sensor_clock -= delta
	pass_cooldown = maxf(0.0,pass_cooldown-delta)
	if sensor_clock <= 0:
		sensor_clock = .15
		_sense(offset,look)
	lane = move_toward(lane,desired_lane,delta*lane_rate)
	if is_equal_approx(lane,desired_lane): lane_rate = 1.8
	var target: Vector3 = course.point(target_at)+right*lane
	var toward: Vector3 = target-car.global_position
	toward.y = 0
	var forward: Vector3 = -car.global_basis.z
	var alpha := forward.signed_angle_to(toward.normalized(),Vector3.UP)
	if reverse_left > 0:
		reverse_left -= delta
		car.throttle_input = -.7
		car.steer_input = -signf(alpha) if absf(alpha) > .2 else (-1.0 if recoveries%2 == 0 else 1.0)
		return
	if absf(alpha)>1.9 and absf(float(car.speed))<3.5 and _rear_clear():
		reverse_left = 1.3
		recoveries += 1
		car.brake_input = true
		return
	var desired: float = course.speed_at(offset,cap)
	var bend := absf(toward.normalized().signed_angle_to(direction,Vector3.UP))
	desired = minf(desired,lerpf(cap,4.5,clampf(bend/.85,0.0,1.0)))
	if is_finite(gap): desired = minf(desired,leader_speed+maxf(0.0,(gap-stop_gap)*.9))
	if push_enabled and leader_vehicle and is_finite(gap):
		# Encosta e empurra a ~4 m/s a mais que o da frente. Diante de contrário, espera 1,5 s pelo desvio
		# e depois mete o carro também.
		oncoming_wait = oncoming_wait+delta if stop_gap > 2.4 else 0.0
		if stop_gap <= 2.4 or oncoming_wait > 1.5: desired = maxf(desired,minf(course.speed_at(offset,cap),leader_speed+4.0))
	else: oncoming_wait = 0.0
	# Desviando de um contrário parado a poucos metros: o limite pela distância daria zero e o carro não
	# andaria para o lado. Anda devagar enquanto a faixa muda.
	if lane_rate > 1.8 and absf(lane-desired_lane) > .4 and gap > 3.0: desired = maxf(desired,2.5)
	desired = minf(desired,_yield_speed(offset))
	car.steer_input = clampf(atan2(5.0*sin(alpha),look)/.48,-1.0,1.0)
	if absf(alpha)>1.4:
		car.steer_input = signf(alpha)
		desired = minf(desired,3.0)
	# Vehicle.brake_input é o freio de mão: usa contra-aceleração nas curvas.
	car.brake_input = desired<.2 and absf(float(car.speed))<1.0
	car.throttle_input = clampf((desired-float(car.speed))*.65,-1.0,1.0) if not car.brake_input else 0.0
	if car.global_position.distance_to(anchor)>2.0:
		anchor = car.global_position
		stalled = 0.0
	else: stalled += delta
	if stalled > 3.0 and offset < float(course.length)-8.0:
		# Brigão: preso, dá ré mesmo com carro atrás (empurra quem está lá) em vez de ficar parado.
		if _rear_clear() or push_enabled:
			reverse_left = 1.1
			recoveries += 1
		stalled = 0.0

func _sense(offset: float, look: float) -> void:
	gap = INF
	leader_speed = 0.0
	var leader_is_vehicle := false
	var leader_oncoming := false
	var leader_rid := RID()
	merge_request = false
	stop_gap = 2.4
	var reach := minf(55.0,5.0+float(car.speed)*float(car.speed)/10.0)
	var origin: Vector3 = car.global_position+Vector3.UP*.65-car.global_basis.z*(car.half_length+.2)
	for side in [-.8,0.0,.8]:
		var from: Vector3 = origin+car.global_basis.x*float(car.half_width)*side
		var ray := PhysicsRayQueryParameters3D.create(from,from-car.global_basis.z*reach,7,[car.get_rid()])
		var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and from.distance_to(hit.position)<gap:
			gap = from.distance_to(hit.position)
			leader_speed = maxf(0.0,hit.collider.velocity.dot(-car.global_basis.z)) if hit.collider is CharacterBody3D else 0.0
			leader_is_vehicle = hit.collider is Node and hit.collider.is_in_group("drivable")
			leader_oncoming = leader_is_vehicle and (-car.global_basis.z).dot(-hit.collider.global_basis.z)<-.4
			leader_rid = hit.rid
	leader_vehicle = leader_is_vehicle
	# Contrário na própria faixa: para mais longe (sobra espaço para desviar), pede vaga aos rivais da direita
	# e aceita um desvio curto, de baixa velocidade, em vez da troca de dois segundos que o próprio carro
	# contrário bloqueava (07/10: a van ocupava o primeiro volume do corredor).
	if leader_oncoming and lane < 0.0 and gap < 35.0:
		stop_gap = 6.5
		merge_request = true
		if reverse_left <= 0.0 and _lane_clear(offset,look,1.8,true):
			desired_lane = 1.8
			lane_rate = 3.2
			pass_cooldown = 2.0
			return
	# O grid de dois lado a lado não é permissão para ficar na contramão. Volta
	# para a direita assim que o corredor físico estiver livre depois da largada ou
	# de uma ultrapassagem, antes que um carro vindo feche essa oportunidade.
	if desired_lane<0.0 and pass_cooldown<=0.0 and reverse_left<=0.0 and _lane_clear(offset,look,1.8):
		desired_lane = 1.8
		pass_cooldown = 2.0
		return
	# Um guard-rail visto do outro lado de uma curva não é um carro a ultrapassar. Reserva estrada
	# reta suficiente para a troca de faixa inteira de dois segundos, não só para o ponto final.
	if leader_is_vehicle and not leader_oncoming and pass_cooldown<=0.0 and reverse_left<=0.0 and leader_speed<cap-2.0 and _passing_straight(offset):
		var alternative := -1.8 if desired_lane>=0 else 1.8
		# O carro ultrapassado fica fora do corredor: colado nele (2,4 m) o começo da troca sempre o tocava e
		# a fila inteira andava atrás de um caminhão do trânsito a 4 m/s (28/10).
		if _lane_clear(offset,look,alternative,false,leader_rid):
			desired_lane = alternative
			pass_cooldown = 2.0

func reset_after_rescue(rescue_lane: float) -> void:
	lane = rescue_lane
	desired_lane = rescue_lane
	reverse_left = 0.0
	stalled = 0.0
	stuck_time = 0.0
	best_offset = course.nearest_offset(car.global_position)
	anchor = car.global_position
	pass_cooldown = 1.0
	oncoming_wait = 0.0

func _passing_straight(offset: float) -> bool:
	var ahead := maxf(18.0,absf(float(car.speed))*2.5)
	var direction: Vector3 = course.direction(offset)
	for i in range(1,7):
		if direction.dot(course.direction(offset+ahead*float(i)/6.0)) < .985: return false
	return true

func _lane_clear(offset: float, look: float, alternative: float, sidestep := false, overtaken := RID()) -> bool:
	lane_query.exclude = [car.get_rid(),overtaken] if overtaken.is_valid() else [car.get_rid()]
	var clear := _lane_corridor_clear(offset,look,alternative,sidestep)
	lane_query.exclude = [car.get_rid()]
	return clear

func _lane_corridor_clear(offset: float, look: float, alternative: float, sidestep: bool) -> bool:
	# Varre o corredor real da transição, além da faixa de destino.
	var start_forward: Vector3 = course.direction(offset)
	var displacement: Vector3 = car.global_position-course.point(offset)
	var actual_lane := displacement.dot(start_forward.cross(Vector3.UP).normalized())
	# Desvio curto: a faixa muda em poucos metros, então o corredor é curto e chega ao lado cedo.
	var span := maxf(3.0,absf(float(car.speed))) if sidestep else maxf(8.0,look)
	for fraction in [0.0,.5,1.0]:
		var at := minf(offset+span*fraction,float(course.length)-.5)
		var forward: Vector3 = course.direction(at)
		var lateral := lerpf(actual_lane,alternative,minf(1.0,fraction*1.5) if sidestep else fraction)
		var center: Vector3 = course.point(at)+forward.cross(Vector3.UP).normalized()*lateral+Vector3.UP*.65
		lane_query.transform = Transform3D(Basis(Vector3.UP,atan2(-forward.x,-forward.z)),center)
		if not car.get_world_3d().direct_space_state.intersect_shape(lane_query,1).is_empty(): return false
	# Um carro ao lado ou chegando por trás também é dono da faixa de destino.
	# No desvio curto o rival que cedeu a vaga para atrás (ver _yield_speed); basta o lado e logo atrás.
	for behind in ([3.0] if sidestep else [4.0,8.0,12.0]):
		var at := maxf(0.0,offset-behind)
		var forward: Vector3 = course.direction(at)
		var center: Vector3 = course.point(at)+forward.cross(Vector3.UP).normalized()*alternative+Vector3.UP*.65
		lane_query.transform = Transform3D(Basis(Vector3.UP,atan2(-forward.x,-forward.z)),center)
		if not car.get_world_3d().direct_space_state.intersect_shape(lane_query,1).is_empty(): return false
	return true

## Rival da direita cede a vaga a quem pediu: se quem pede está à frente, para atrás dele com folga para o
## desvio curto; se está ao lado ou atrás, segue (a vaga abre atrás deste carro).
func _yield_speed(offset: float) -> float:
	var limit := INF
	if lane <= 0.0: return limit
	for peer in peers:
		if peer == self or not peer.merge_request or not is_instance_valid(peer.car): continue
		var ahead: float = float(peer.course_offset)-offset
		if ahead < float(car.half_length)*2.0+1.0 or ahead > 25.0: continue
		limit = minf(limit,maxf(0.0,(ahead-9.0)*.8))
	return limit

func _rear_clear() -> bool:
	var origin: Vector3 = car.global_position+Vector3.UP*.65
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+car.global_basis.z*(car.half_length+3.0),7,[car.get_rid()])
	return car.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
