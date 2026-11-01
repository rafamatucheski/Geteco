extends RefCounted
## Direção do trânsito: rota e projeção nela, sensores (obstacle_ahead, traffic_rear_clear), fila,
## impasse e empurrão, cruzamentos (TrafficJunctions: reserva, saída ocupada, retenção do casco) e
## desvio pela contramão/acostamento. Separado de scripts/Vehicle.gd em 01/11 (Onda 3) só para o dono
## caber na leitura. O dono mantém cada função antiga como delegação de uma linha com a mesma
## assinatura e os mesmos padrões (7 testes, ArrivalCar, Jessica, blindado, TrafficEscape, TrafficRails
## e TrafficJunctions chamam _drive_traffic, _junction_gate, _try_bypass, _lane_clear, _end_bypass,
## _traffic_route_offset... no veículo) e reexporta TRAFFIC_JAM_SECONDS, BYPASS_* e MERGE_PROBES.
## Estado: tudo o que alguém de fora lê ou escreve (blocked, blocker, stall_time, bypass_*, _held_junction,
## _clearing_junctions, _junction_list, _exit_blocked, _exit_wait, _sense_tick...) continua no Vehicle.
## Só a projeção na rota (_projection_*) e a âncora de travamento (_stuck_anchor), sem leitor fora do
## bloco, moram aqui. A inscrição em `route.changed` continua apontando para
## Vehicle._invalidate_route_projection, para a curva soltar a inscrição quando o veículo é liberado.
## `g` fica como CharacterBody3D, e não como o script do dono, para não criar preload cíclico.
## Sobrescritas fora do arquivo passam por `g.`: _try_bypass (ArrivalCar) e can_rotate (testes); as
## demais funções daqui não têm sobrescrita no repositório e são chamadas direto, sem ir e voltar pelo
## dono. Caminho quente (por carro de trânsito e por passo executado): _drive_traffic, _junction_gate,
## _traffic_route_offset e, a cada 0,1 s, obstacle_ahead. Rota, fuga e meio-comprimento são lidos do
## veículo uma vez por chamada; nada aqui aloca além do que o dono já alocava (as consultas de física
## de obstacle_ahead/_lane_clear/_exit_occupied/traffic_rear_clear continuam como eram).

const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host

var _projection_route: Curve3D
var _projection_position := Vector3.ZERO
var _projection_offset := 0.0
var _projection_valid := false
var _stuck_anchor := 0.0

const TRAFFIC_JAM_SECONDS := 2.5

func _traffic_jam_partner() -> Object:
	if not is_instance_valid(g.blocker) or not g.blocker is CharacterBody3D: return null
	if g.blocker.get("traffic") != true or g.blocker.get("blocked") != true: return null
	# Fila na mesma direção não é impasse: quem está atrás só espera.
	var mine := -g.global_basis.z
	var theirs: Vector3 = -(g.blocker as Node3D).global_basis.z
	if mine.dot(theirs) > 0.85: return null
	return g.blocker

func _pushable_obstacle(target) -> bool:
	if not is_instance_valid(target) or not target is Node: return false
	if target is CharacterBody3D:
		if target.get("traffic") == true: return false
		if target.has_method("driver_seat_anchor"):
			return target.get("controlled") != true and target.get("external_input") != true
		var down: bool = target.get("dead") == true or (target as Node).has_meta("street_down")
		return down and g.blocked_time > 8.0
	return true

func _route_ahead(offset: float, length: float, open: bool) -> float:
	if open: return offset-g.route_distance
	return fposmod(offset-g.route_distance+length*.5,length)-length*.5

func _release_current_junction() -> void:
	if g._held_junction != null: JUNCTIONS.release(g._held_junction,g.get_instance_id())
	g._held_junction = null

func _release_junction() -> void:
	_release_current_junction()
	for key in g._clearing_junctions: JUNCTIONS.release(key, g.get_instance_id())
	g._clearing_junctions.clear()

func _retain_current_junction() -> void:
	if g._held_junction == null: return
	if JUNCTIONS.has_reservation(g._held_junction, g.get_instance_id()) and JUNCTIONS.occupies(g._held_junction, g.get_instance_id()):
		if not g._clearing_junctions.has(g._held_junction): g._clearing_junctions.append(g._held_junction)
	else:
		JUNCTIONS.release(g._held_junction, g.get_instance_id())
	g._held_junction = null

func _clear_departed_junctions() -> void:
	for index in range(g._clearing_junctions.size() - 1, -1, -1):
		var key: Vector3i = g._clearing_junctions[index]
		if JUNCTIONS.has_reservation(key, g.get_instance_id()) and JUNCTIONS.occupies(key, g.get_instance_id()): continue
		JUNCTIONS.release(key, g.get_instance_id())
		g._clearing_junctions.remove_at(index)

func _junction_gate(length: float, open: bool) -> bool:
	g.junction_gap = INF
	# Lidos uma vez do veículo: o laço abaixo passa por todo cruzamento da rota, por passo.
	var route: Curve3D = g.route
	var half_length: float = g.half_length
	if route != g._junction_route:
		_retain_current_junction()
		g._junction_route = route
		g._junction_list = JUNCTIONS.along(route)
	if g._held_junction != null:
		if not JUNCTIONS.has_reservation(g._held_junction, g.get_instance_id()):
			g._held_junction = null
		elif _route_ahead(g._held_offset,length,open) < -JUNCTIONS.EXIT and not JUNCTIONS.occupies(g._held_junction, g.get_instance_id()):
			_release_current_junction()
	for junction in g._junction_list:
		var offset := float(junction.offset)
		var ahead := _route_ahead(offset,length,open)
		if ahead <= -(JUNCTIONS.EXIT + half_length) or ahead > float(junction.get("approach_distance",JUNCTIONS.APPROACH)): continue
		# Um cruzamento ocupado anterior não pode substituir o token de aproximação mais novo.
		if g._clearing_junctions.has(junction.key): continue
		if g._held_junction == junction.key:
			if ahead <= 0.0: continue
			return false
		var gap: float
		if junction.has("stop_offset"):
			gap = _route_ahead(float(junction.stop_offset),length,open)-half_length
		else:
			gap = ahead-half_length-JUNCTIONS.stop_line(junction.key)
		# Usa o braço de chegada resolvido com a linha de parada. A tangente da curva
		# perto do centro pode já apontar para a rua transversal durante a curva.
		var heading: Vector3 = junction.get("heading",Vector3.ZERO)
		if heading.length_squared()<.0001:
			var before := route.sample_baked(offset-12.0 if open else fposmod(offset-12.0,length),true)
			var at := route.sample_baked(offset-8.0 if open else fposmod(offset-8.0,length),true)
			heading = at-before
		# Não bloquear o cruzamento: com a saída ocupada por carro parado, quem entra
		# fica no miolo e trava o eixo cruzado; era o nó que começava os engarrafamentos.
		if gap > -1.5 and g._sense_tick: g._exit_blocked = _exit_occupied(offset,length,open)
		if gap > -1.5 and g._exit_blocked:
			g._exit_wait += 1.0/Engine.physics_ticks_per_second
			g.junction_gap = gap
			return true
		g._exit_wait = 0.0
		if JUNCTIONS.request(junction.key,g.get_instance_id(),heading,gap,absf(g.speed)):
			_retain_current_junction()
			g._held_junction = junction.key
			g._held_offset = offset
			return false
		g.junction_gap = gap
		return true
	return false

func _invalidate_route_projection() -> void:
	_projection_valid = false

func _traffic_route_offset(point: Vector3) -> float:
	if g.route != _projection_route:
		if _projection_route != null:
			_projection_route.changed.disconnect(g._invalidate_route_projection)
		_projection_route = g.route
		_projection_route.changed.connect(g._invalidate_route_projection)
		_projection_valid = false
	if not _projection_valid or point != _projection_position:
		_projection_offset = g.route.get_closest_offset(point)
		_projection_position = point
		_projection_valid = true
	return _projection_offset

func _drive_traffic(delta: float) -> void:
	if g.route == null: return
	if g.traffic_escape==null: g.traffic_escape=preload("res://gameplay/TrafficEscape.gd").new()
	# Lidas uma vez do veículo, e não a cada uso (roda por carro de trânsito e por passo).
	var traffic_escape: RefCounted = g.traffic_escape
	traffic_escape.tick(g,delta)
	if g.is_queued_for_deletion() or traffic_escape.retiring: return
	# Só TrafficEscape.tick, acima, troca a rota neste passo.
	var route: Curve3D = g.route
	if g.backoff_time > 0.0:
		g.backoff_time -= delta
		var rear_gap := .8 if traffic_escape!=null and not traffic_escape.active and traffic_escape.wait>0 else 3.0
		g.speed = move_toward(g.speed,-1.5 if traffic_rear_clear(rear_gap) else 0.0,8.0*delta)
		return
	g.sensor_clock -= delta
	g._sense_tick = g.sensor_clock <= 0
	if g._sense_tick:
		g.sensor_clock = 0.1
		g.blocked = obstacle_ahead()
		if g.unjam_time > 0.0 and g.blocked and g.blocker == g.get_meta("unjam_partner",null): g.blocked = false
		if g.bypass_side != 0.0 and g.blocked and _body_speed(g.blocker) < 0.6 and _in_home_lane(g.blocker): g.blocked = false
	g.unjam_time = maxf(0.0,g.unjam_time-delta)
	g.bypass_retry = maxf(0.0,g.bypass_retry-delta)
	g.blocked_time = g.blocked_time+delta if g.blocked else 0.0
	g.stall_time = _stall_estimate()
	# Sem progresso fora de fila de sinal: a limpeza tira o carro quando ninguém vê.
	# Zera só com avanço real na rota; empurrar carcaça centímetro a centímetro não conta.
	if absf(g.route_distance-_stuck_anchor) > 8.0:
		g.stuck_time = 0.0
		_stuck_anchor = g.route_distance
	elif g.stall_time > 0.0 or g.unjam_time > 0.0 or g.bypass_side != 0.0: g.stuck_time += delta
	if g.bypass_side != 0.0 and g._sense_tick: _update_bypass()
	if g.blocked_time > TRAFFIC_JAM_SECONDS and not traffic_escape.active:
		var partner := _traffic_jam_partner()
		if partner != null:
			g.blocked_time = 0.0
			# Quem está desviando pela contramão é o intruso: recua e deixa passar.
			var i_yield: bool = g.bypass_side < 0.0 or (partner.get("bypass_side") == 0.0 and g.get_instance_id() > partner.get_instance_id())
			if not i_yield:
				g.unjam_time = 3.0
				g.set_meta("unjam_partner",partner)
			else:
				g.backoff_time = 1.2
		elif g.bypass_retry <= 0.0 and g.bypass_side == 0.0 and g.stall_time > BYPASS_AFTER_SECONDS and g._try_bypass():
			g.blocked_time = 0.0
		elif _pushable_obstacle(g.blocker) and (not _is_vehicle(g.blocker) or g.stall_time > BYPASS_AFTER_SECONDS*3.0):
			# Adereço derrubado, lixeira, carcaça sem motorista: o trânsito empurrava
			# nada e esperava para sempre. Segue devagar; a física de rua derruba o objeto.
			g.blocked_time = 0.0
			g.unjam_time = 3.0
			g.set_meta("unjam_partner",g.blocker)
	# O progresso usa a posição real, então uma colisão não avança a rota do carro.
	var previous_distance: float = g.route_distance
	if not g._traffic_rail_drive: g.route_distance = _traffic_route_offset(g.global_position)
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	if not open and previous_distance > length-5 and g.route_distance < 5: g.route_laps += 1
	g.junction_wait = _junction_gate(length,open)
	# Panic may disregard the signal; still update physical junction retention.
	if traffic_escape.active: g.junction_wait=false
	var near_point := route.sample_baked(minf(g.route_distance+2,length) if open else fposmod(g.route_distance+2,length),true)
	var far_point := route.sample_baked(minf(g.route_distance+5,length) if open else fposmod(g.route_distance+5,length),true)
	var bend := absf((near_point-g.global_position).normalized().signed_angle_to((far_point-near_point).normalized(),Vector3.UP))
	var desired_speed := lerpf(5.5,2.2,clampf(bend/1.0,0,1))
	if traffic_escape.active: desired_speed=lerpf(9.0,4.5,clampf(bend,0,1))
	if g.unjam_time > 0.0: desired_speed = minf(desired_speed,2.5)
	if g.bypass_side != 0.0: desired_speed = minf(desired_speed,BYPASS_SPEED)
	if open: desired_speed = minf(desired_speed,maxf(0,(length-g.route_distance-1)*1.5))
	# Sinal fechado: freia progressivamente até a faixa, em vez de travar a 12 m/s² a
	# qualquer distância (o carro parava longe do cruzamento ou em cima da faixa).
	if g.junction_wait: desired_speed = minf(desired_speed,sqrt(2.0*3.5*maxf(0.0,g.junction_gap-.4)))
	var target_speed := 0.0 if g.blocked else desired_speed * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
	var rate := 12.0 if g.blocked else (7.0 if target_speed < g.speed else 2.5)
	g.speed = move_toward(g.speed,target_speed,rate*delta)
	var lookahead := lerpf(3.5,1.7,clampf(bend,0,1))
	var target := route.sample_baked(minf(g.route_distance+lookahead,length) if open else fposmod(g.route_distance+lookahead,length),true)
	# Desvio: persegue a mesma rota deslocada para o lado, entrando e saindo aos poucos.
	var blend_goal := 0.0 if g._merging_back or g.bypass_side == 0.0 else 1.0
	g.bypass_blend = move_toward(g.bypass_blend,blend_goal,delta/1.2)
	if g._merging_back and g.bypass_blend <= 0.0: _end_bypass()
	if g.bypass_blend > 0.0: target += _route_right(g.route_distance+lookahead,length,open)*_bypass_shift()*g.bypass_blend
	var direction := target-g.global_position
	direction.y = 0
	var desired := atan2(-direction.x,-direction.z)
	var next_yaw := rotate_toward(g.rotation.y,desired,delta*(2.7 if traffic_escape.active else 1.7))
	g.steering = clampf(angle_difference(g.rotation.y,desired),-0.48,0.48)
	# Carro parado não esterça no lugar (e poupa a consulta de colisão por passo).
	if not g._traffic_rail_drive and absf(g.speed) > 0.2 and next_yaw != g.rotation.y and g.can_rotate(next_yaw): g.rotation.y = next_yaw

const BYPASS_AFTER_SECONDS := 3.5
const BYPASS_SPEED := 4.0
const BYPASS_MAX_DISTANCE := 45.0
const BYPASS_PROBES := [0.0, 5.0, 10.0, 16.0, 22.0]
const MERGE_PROBES := [0.0, 4.0, 8.0]

func traffic_rear_clear(distance := 3.0) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = g.rotation_shape
	query.collision_mask = 7
	query.exclude = [g.get_rid()]
	query.transform = Transform3D(g.global_basis,g.global_position+Vector3.UP*g.shape.position.y)
	query.motion = g.global_basis.z*distance
	var space := g.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return false
	return space.cast_motion(query)[0]>=1.0

func _is_vehicle(target) -> bool:
	return is_instance_valid(target) and target is Node and (target as Node).has_method("driver_seat_anchor")

func _body_speed(target) -> float:
	if not is_instance_valid(target): return 0.0
	if _is_vehicle(target): return absf(float(target.get("speed")))
	if target is CharacterBody3D: return (target as CharacterBody3D).velocity.length()
	if target is RigidBody3D: return (target as RigidBody3D).linear_velocity.length()
	return 0.0

func _stall_estimate() -> float:
	if g.junction_wait or not g.blocked or not is_instance_valid(g.blocker): return 0.0
	if g.blocker.has_method("is_servicing_stop") and g.blocker.is_servicing_stop(): return g.blocked_time
	if g.blocker is Node3D and g.blocker.get("traffic") == true:
		var same_way := (-g.global_basis.z).dot(-(g.blocker as Node3D).global_basis.z) > 0.85
		if same_way:
			# Fila: vale o travamento de quem está na frente. Na fila do sinal ele é zero.
			if g.blocker.get("junction_wait") == true or g.blocker.get("blocked") != true: return 0.0
			return float(g.blocker.get("stall_time"))
	if _body_speed(g.blocker) > 0.6: return 0.0
	return g.blocked_time

func _route_point(offset: float, length: float, open: bool) -> Vector3:
	return g.route.sample_baked(clampf(offset,0.0,length) if open else fposmod(offset,length),true)

func _route_right(offset: float, length: float, open: bool) -> Vector3:
	var tangent := _route_point(offset+1.0,length,open)-_route_point(offset-1.0,length,open)
	tangent.y = 0
	if tangent.length_squared() < .0001: return g.global_basis.x
	return tangent.normalized().cross(Vector3.UP)

func _bypass_shift() -> float:
	if not is_nan(g.bypass_lane_shift): return g.bypass_lane_shift
	return -3.4 if g.bypass_side < 0.0 else 2.6

func _lane_clear(shift: float, probes: Array, mask := 7) -> bool:
	var length: float = g.route.get_baked_length()
	var open: bool = g.route.get_meta("traffic_open",false)
	var space := g.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = g.rotation_shape
	query.collision_mask = mask
	query.exclude = [g.get_rid()]
	for distance in probes:
		var at: float = g.route_distance+float(distance)
		var right := _route_right(at,length,open)
		var point := _route_point(at,length,open)+right*shift
		query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),point+Vector3.UP*g.shape.position.y)
		if not space.intersect_shape(query,1).is_empty(): return false
	return true

func _try_bypass() -> bool:
	g.bypass_retry = 1.0
	if g.route == null or str(g.get_meta("traffic_yield_state","")) != "": return false
	var length: float = g.route.get_baked_length()
	var open: bool = g.route.get_meta("traffic_open",false)
	# Nunca desvia para dentro de um cruzamento: lá a contramão é a via cruzada.
	for junction in g._junction_list:
		var ahead := _route_ahead(float(junction.offset),length,open)
		if ahead > -JUNCTIONS.EXIT and ahead < 14.0: return false
	# Numa avenida de quatro faixas, usa só a faixa vizinha no mesmo
	# sentido. Olha para trás e para frente antes de desviar de um ônibus parado.
	var nearest := INF
	var profile := {}
	for section in g.route.get_meta("lane_sections",[]):
		var a: Vector3 = section.a
		var b: Vector3 = section.b
		if a.direction_to(b).dot(-g.global_basis.z)<.7: continue
		var separation := Geometry3D.get_closest_point_to_segment(g.global_position,a,b).distance_squared_to(g.global_position)
		if separation<nearest: nearest=separation; profile=section
	if int(profile.get("lanes",1))==2:
		g.bypass_side = 1.0 if int(g.route.get_meta("lane_index",0))==0 else -1.0
		g.bypass_lane_shift = g.bypass_side*float(profile.width)*.25
		if _lane_clear(g.bypass_lane_shift,[-8.0,-4.0,0.0,5.0,10.0,16.0,22.0]):
			g.bypass_start=g.route_distance; g._merging_back=false
			return true
		g.bypass_side=0; g.bypass_lane_shift=NAN
		return false
	for side in [-1.0, 1.0]:
		g.bypass_side = side
		if _lane_clear(_bypass_shift(),BYPASS_PROBES):
			g.bypass_start = g.route_distance
			g._merging_back = false
			return true
	g.bypass_side = 0.0
	return false

func _in_home_lane(target) -> bool:
	if not target is Node3D: return false
	var point: Vector3 = (target as Node3D).global_position
	var length: float = g.route.get_baked_length()
	var open: bool = g.route.get_meta("traffic_open",false)
	var offset: float = g.route.get_closest_offset(point)
	return absf((point-_route_point(offset,length,open)).dot(_route_right(offset,length,open))) < 1.7

func _update_bypass() -> void:
	if g._merging_back: return
	var length: float = g.route.get_baked_length()
	var open: bool = g.route.get_meta("traffic_open",false)
	var travelled: float = g.route_distance-g.bypass_start if open else fposmod(g.route_distance-g.bypass_start,length)
	# Contramão fechada por quem vem de frente há muito tempo: desiste e volta.
	if travelled > 4.0 and _lane_clear(0.0,MERGE_PROBES): g._merging_back = true
	elif travelled > BYPASS_MAX_DISTANCE or g.blocked_time > 6.0: g._merging_back = true

func _end_bypass() -> void:
	g.bypass_lane_shift = NAN
	g.bypass_side = 0.0
	g.bypass_blend = 0.0
	g._merging_back = false
	g.bypass_retry = 2.0

func _exit_occupied(offset: float, length: float, open: bool) -> bool:
	var at: float = offset+JUNCTIONS.EXIT+g.half_length+1.0
	if open and at > length: return false
	var right := _route_right(at,length,open)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = g.rotation_shape
	query.collision_mask = 4
	query.exclude = [g.get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),_route_point(at,length,open)+Vector3.UP*g.shape.position.y)
	for hit in g.get_world_3d().direct_space_state.intersect_shape(query,4):
		if _is_vehicle(hit.collider) and _body_speed(hit.collider) < 1.0: return true
	return false

func obstacle_ahead() -> bool:
	if g.traffic_escape!=null and g.traffic_escape.active: return g.traffic_escape.obstacle_ahead(g)
	var length: float = 2.2+g.speed*g.speed/20.0
	g.sensor_shape.size.z = length
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = g.sensor_shape
	query.transform = Transform3D(g.global_basis,g.global_position-g.global_basis.z*(g.half_length+length/2)+Vector3.UP*0.8)
	query.collision_mask = 7
	query.exclude = [g.get_rid()]
	# Estrutura de rampa marcada `vehicle_ramp_structure` (túnel do canal): numa
	# rampa de 12,5 % a caixa horizontal a 0,8 m entra no próprio piso e o carro
	# freava sem nada à frente. Carros, pessoas e o resto do mundo continuam valendo.
	g.blocker = null
	for hit in g.get_world_3d().direct_space_state.intersect_shape(query,4):
		if is_instance_valid(hit.collider) and hit.collider.has_meta("vehicle_ramp_structure"): continue
		if g.traffic_escape!=null and g.traffic_escape.active and hit.collider is CharacterBody3D and not _is_vehicle(hit.collider) and not PROTECTION.is_protected(hit.collider): continue
		g.blocker = hit.collider
		break
	return g.blocker != null
