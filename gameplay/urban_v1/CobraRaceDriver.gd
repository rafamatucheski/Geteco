extends RefCounted
## Acelera, freia e esterça o Vehicle real. Colisão nunca vira teleporte/progresso.
const COURSE := preload("res://gameplay/urban_v1/CobraRaceCourse.gd")
var car
var cap := 18.0
var lane := 0.0
var desired_lane := 0.0
var sensor := 0.0
var stalled := 0.0
var reverse := 0.0
var anchor := Vector3.ZERO
var recoveries := 0
var blocked := false
var gap := INF
var leader_speed := 0.0
var pass_cooldown := 0.0
var turns: Array[float] = []
var lane_query := PhysicsShapeQueryParameters3D.new()
var reaction := 0.0

func setup(vehicle, speed_cap: float, left_lane: bool) -> void:
	car=vehicle
	cap=speed_cap
	lane=-2.35 if left_lane else 0.0
	desired_lane=lane
	anchor=car.global_position
	var curve:=COURSE.curve()
	for i in range(1,COURSE.POINTS.size()-1):
		var incoming: Vector3=COURSE.POINTS[i-1].direction_to(COURSE.POINTS[i])
		var outgoing: Vector3=COURSE.POINTS[i].direction_to(COURSE.POINTS[i+1])
		if incoming.angle_to(outgoing)>.22: turns.append(curve.get_closest_offset(COURSE.POINTS[i]))
	var clearance:=BoxShape3D.new()
	clearance.size=Vector3(car.half_width*2+.25,.7,car.half_length*2+.5)
	lane_query.shape=clearance
	lane_query.collision_mask=7
	lane_query.exclude=[car.get_rid()]
	car.player_damage_attribution=false
	car.set_external_driver(true)

func tick(delta: float, hold: bool) -> void:
	if not is_instance_valid(car) or car.health<=0: return
	car.set_external_driver(true)
	car.brake_input=hold
	car.throttle_input=0.0
	if hold: return
	if reaction>0:
		reaction-=delta
		car.brake_input=true
		return
	var curve:=COURSE.curve()
	var offset:=curve.get_closest_offset(car.global_position)
	var length:=curve.get_baked_length()
	var passing_lanes:=COURSE.passing_lanes(offset)
	if desired_lane< -1: desired_lane=-absf(passing_lanes[0])
	if desired_lane>1 and offset<190: desired_lane=0
	var look:=clampf(5.0+absf(car.speed)*.35,5.0,10.0)
	var target:=curve.sample_baked(minf(offset+look,length),true)
	var beyond:=curve.sample_baked(minf(offset+look+1.0,length),true)
	var direction:=target.direction_to(beyond)
	if direction.length_squared()<.1: direction=COURSE.forward(3)
	var right:=direction.cross(Vector3.UP).normalized()
	sensor-=delta
	pass_cooldown=maxf(0,pass_cooldown-delta)
	if sensor<=0:
		sensor=.16
		var from: Vector3=car.global_position+Vector3.UP*.65-car.global_basis.z*(car.half_length+.15)
		gap=INF
		leader_speed=0
		var reach: float=4.0+car.speed*car.speed/12.0
		for side in [-.8,0.0,.8]:
			var origin: Vector3=from+car.global_basis.x*car.half_width*side
			var ray:=PhysicsRayQueryParameters3D.create(origin,origin-car.global_basis.z*reach,7,[car.get_rid()])
			var hit: Dictionary=car.get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty() and origin.distance_to(hit.position)<gap:
				gap=origin.distance_to(hit.position)
				if hit.collider is CharacterBody3D:
					leader_speed=maxf(0,hit.collider.velocity.dot(-car.global_basis.z))
		blocked=is_finite(gap)
		if blocked and pass_cooldown<=0:
			for alternative in passing_lanes:
				if absf(alternative-desired_lane)<.5: continue
				if _lane_clear(curve,offset,look,alternative):
					desired_lane=alternative
					pass_cooldown=2.0
					break
	lane=move_toward(lane,desired_lane,delta*2.5)
	target+=right*lane
	var toward: Vector3=target-car.global_position
	toward.y=0
	var forward: Vector3=-car.global_basis.z
	var alpha:=forward.signed_angle_to(toward.normalized(),Vector3.UP)
	if reverse>0:
		reverse-=delta
		car.throttle_input=-.75
		# Na ré, o esterço deve girar a frente em direção ao percurso.
		car.steer_input=-signf(alpha) if absf(alpha)>.25 else (-1.0 if recoveries%2==0 else 1.0)
		return
	# Depois de uma batida, andar em círculos longe da pista ainda deslocava
	# o carro e zerava o detector de impasse. Corrige também a orientação.
	if absf(alpha)>1.9 and absf(car.speed)<4.0 and _rear_clear():
		reverse=1.6
		recoveries+=1
		car.brake_input=true
		return
	var bend:=absf(toward.normalized().signed_angle_to(direction,Vector3.UP))
	var desired:=lerpf(cap,4.0,clampf(bend/.95,0,1))
	# Freia antes da curva: chegar rápido e só então virar arrastava o carro à calçada.
	for turn in turns:
		if turn>=offset-2 and turn<offset+40:
			desired=minf(desired,sqrt(36.0+10.0*maxf(0,turn-offset-6.0)))
	if blocked: desired=minf(desired,leader_speed+maxf(0,(gap-2.0)*1.1))
	desired=minf(desired,sqrt(maxf(0,10.0*(length-offset-.5))))
	car.steer_input=clampf(atan2(5.0*sin(alpha),look)/.48,-1,1)
	if absf(alpha)>1.5:
		car.steer_input=signf(alpha)
		desired=minf(desired,3.0)
	# O freio booleano do Vehicle é freio de mão (reduz aderência lateral).
	# Contra-aceleração desacelera sem fazer os seis pilotos derraparem na curva.
	car.brake_input=desired<.2 and absf(car.speed)<1.5
	car.throttle_input=clampf((desired-car.speed)*.65,-1.0,1.0) if not car.brake_input else 0.0
	if car.global_position.distance_to(anchor)>2:
		anchor=car.global_position
		stalled=0
	else: stalled+=delta
	if stalled>3.0 and offset<length-5:
		if _rear_clear():
			reverse=1.1
			recoveries+=1
		stalled=0

func _rear_clear() -> bool:
	var rear:=PhysicsRayQueryParameters3D.create(car.global_position+Vector3.UP*.65,car.global_position+Vector3.UP*.65+car.global_basis.z*(car.half_length+2.0),7,[car.get_rid()])
	return car.get_world_3d().direct_space_state.intersect_ray(rear).is_empty()

func _lane_clear(curve: Curve3D, offset: float, look: float, alternative: float) -> bool:
	# Verifica o volume do carro durante a troca e adiante, não só um raio central.
	for distance in [0.0,3.0,maxf(6.0,look)]:
		var at:=minf(offset+distance,curve.get_baked_length()-.2)
		var point:=curve.sample_baked(at,true)
		var direction:=point.direction_to(curve.sample_baked(at+.2,true))
		var right:=direction.cross(Vector3.UP).normalized()
		var yaw:=atan2(-direction.x,-direction.z)
		lane_query.transform=Transform3D(Basis(Vector3.UP,yaw),point+right*alternative+Vector3.UP*.65)
		if not car.get_world_3d().direct_space_state.intersect_shape(lane_query,1).is_empty(): return false
	return true
