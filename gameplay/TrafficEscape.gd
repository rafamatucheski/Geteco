extends RefCounted
const PLANNER := preload("res://gameplay/TrafficEscapePlanner.gd")
const WAIT := 4.5
const RETIRE := 24.0
const MAX_OBSTRUCTION_EPISODE := 40.0
var wait := 0.0
var active := false
var retiring := false
var _fade := 0.0
var _scan := 0.0
var _retry := 0.0
var _anchor := Vector3.INF
var _cause: Object
var _episode := 0.0
var _backoff_used := false
var _best_offset := 0.0
var _abandon_clock := -1.0
var _obstruction_origin := Vector3.INF
var _sensor_query: PhysicsShapeQueryParameters3D

func obstacle_ahead(car: CharacterBody3D) -> bool:
	# A caixa reta enxergava a viatura fora da curva aprovada e freava antes de
	# esterçar. Examine o casco ao longo da fuga, mantendo sólidos e veículos.
	if _sensor_query==null: _sensor_query=PhysicsShapeQueryParameters3D.new()
	var query := _sensor_query
	query.shape=car.rotation_shape
	query.exclude=[car.get_rid()]
	var space:=car.get_world_3d().direct_space_state
	var at: float=car.route.get_closest_offset(car.global_position)
	var horizon:=clampf(1.5+car.speed*car.speed/18.0,1.5,6.0)
	var previous:=car.global_position
	car.blocker=null
	for step in range(1,ceili(horizon)+1):
		var next: Vector3=car.route.sample_baked(minf(at+minf(float(step),horizon),car.route.get_baked_length()),true)
		var direction:=next-previous
		if direction.length_squared()<.001: continue
		query.transform=Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),previous+Vector3.UP*car.shape.position.y)
		query.motion=direction
		query.collision_mask=5
		if space.cast_motion(query)[0]<.99:
			var contact:=space.get_rest_info(query)
			car.blocker=contact.get("collider")
			return true
		query.motion=Vector3.ZERO
		query.transform.origin=next+Vector3.UP*car.shape.position.y
		query.collision_mask=2
		var people:=space.intersect_shape(query,16)
		if people.size()>=16: return true # Não esconder protegido numa consulta saturada.
		for hit in people:
			if preload("res://gameplay/DamageProtection.gd").is_protected(hit.collider):
				car.blocker=hit.collider
				return true
		previous=next
	return false

func tick(car: CharacterBody3D, delta: float) -> void:
	if car.controlled or not car.traffic or car.health<=0 or car.get_meta("armored_transport",false) or car.get_meta("race_owned",false):
		if retiring: car.fade_traffic_retirement(0)
		active=false; retiring=false; wait=0
		_episode=0; _cause=null; _backoff_used=false; _abandon_clock=-1; _obstruction_origin=Vector3.INF
		car.remove_meta("traffic_escape_state")
		return
	if retiring:
		_fade+=delta
		car.speed=move_toward(car.speed,0,12*delta)
		car.fade_traffic_retirement(minf(1,_fade))
		if _fade>=1: car.queue_free()
		return
	if _abandon_clock>=0: _abandon_clock+=delta
	# Movimento em círculos/manobras perto da viatura não equivale a liberação.
	# O limite de progresso continua útil, mas o episódio tem um prazo absoluto.
	if car.get_meta("ambient_traffic",false) and _abandon_clock>=MAX_OBSTRUCTION_EPISODE and (active or (_obstruction_origin!=Vector3.INF and car.global_position.distance_to(_obstruction_origin)<25)):
		_retire(car)
		return
	if _anchor==Vector3.INF: _anchor=car.global_position
	if not active and _anchor.distance_to(car.global_position)>3:
		wait=0; _anchor=car.global_position
	if active:
		var offset: float = car.route.get_closest_offset(car.global_position)
		if offset>_best_offset+3: _best_offset=offset; wait=0
		else: wait+=delta
		if offset>=float(car.route.get_meta("traffic_escape_until",0)):
			active=false
			car.route.remove_meta("traffic_escape_until")
			car.set_meta("traffic_escape_state","resumed")
			wait=0
			_cause=null; _episode=0; _backoff_used=false
			_abandon_clock=-1
			_obstruction_origin=Vector3.INF
			var world:=car.get_parent()
			var production: Variant=world.get("production") if is_instance_valid(world) else null
			if is_instance_valid(production):
				var restored: Curve3D=production.ambient_traffic_routes.route_near(car.global_position,0,-car.global_basis.z)
				if restored!=null and restored.sample_baked(restored.get_closest_offset(car.global_position),true).distance_to(car.global_position)<3:
					car.route=restored
					car.route_distance=restored.get_closest_offset(car.global_position)
				elif car.route.get_meta("traffic_escape_free",false): _retire(car)
		if wait>=RETIRE: _retire(car)
		return
	_scan-=delta
	if _scan<=0:
		_scan=.5
		var detected: Object=_root(car)
		if is_instance_valid(detected): _cause=detected
		elif is_instance_valid(_cause) and _cause is Node3D:
			var relative: Vector3=(_cause as Node3D).global_position-car.global_position
			var forward: Vector3=-car.global_basis.z
			if relative.dot(forward)<-3 or relative.length()>45 or car._body_speed(_cause)>.6: _cause=null
		else: _cause=null
	if not is_instance_valid(_cause):
		if car.get_meta("traffic_escape_state","")=="waiting": car.remove_meta("traffic_escape_state")
		var at_end: bool=car.route!=null and car.route.get_meta("traffic_open",false) and car.route.get_baked_length()-car.route_distance<2
		if _abandon_clock>=32 and absf(car.speed)<.6 and (at_end or car._stall_estimate()>0): _retire(car)
		if _obstruction_origin!=Vector3.INF and car.global_position.distance_to(_obstruction_origin)>25:
			_abandon_clock=-1
			_obstruction_origin=Vector3.INF
		wait=0; _episode=0; _backoff_used=false
		return
	if _abandon_clock<0:
		_abandon_clock=0
		_obstruction_origin=_cause.global_position if _cause is Node3D else car.global_position
	_episode+=delta
	if absf(car.speed)<.6: wait+=delta
	if _episode>=RETIRE and absf(car.speed)<.6:
		_retire(car)
		return
	if wait<WAIT: return
	car.set_meta("traffic_escape_state","waiting")
	car.stuck_time=maxf(car.stuck_time,wait)
	_retry-=delta
	if _retry>0: return
	_retry=1.2+float(car.get_instance_id()%5)*.1
	var world := car.get_parent()
	var yield_controller: Variant=world.get("traffic_yield") if is_instance_valid(world) else null
	if is_instance_valid(yield_controller): yield_controller.release_vehicle(car,"escape")
	var curve := PLANNER.plan(car,car.route)
	if curve==null:
		if car.get_meta("traffic_escape_plan_failure","")=="deferred": _retry=.05
		elif not _backoff_used and car.traffic_rear_clear(.8):
			# A tight queue has no entry ramp. Open longitudinal room from its tail
			# first; each reverse step still checks the actual rear clearance.
			_backoff_used=true
			car.backoff_time=maxf(car.backoff_time,2.4)
		return
	car.route=curve
	if car.has_meta("ambient_next_route"): car.remove_meta("ambient_next_route")
	car.route_distance=0
	car._end_bypass()
	car.backoff_time=0
	car.unjam_time=0
	active=true
	_best_offset=0
	wait=0
	car.set_meta("traffic_escape_state","escaping")
	car.set_meta("traffic_escape_shift",curve.get_meta("traffic_escape_shift"))

func _retire(car: CharacterBody3D) -> void:
	# Only ambient vehicles may be removed; never a mission car or player property.
	if not car.get_meta("ambient_traffic",false): return
	retiring=true
	_fade=0
	car.set_meta("traffic_escape_state","retiring")

func _root(car: CharacterBody3D) -> Object:
	var seen := {}
	var target: Object=car.blocker if is_instance_valid(car.blocker) else null
	for step in 8:
		if not is_instance_valid(target) or not target is Node: break
		if seen.has(target.get_instance_id()): break
		seen[target.get_instance_id()]=true
		if target.get_meta("dispatch_unit",false) and car._body_speed(target)<.6: return target
		if target.has_method("driver_seat_anchor") and target.get("health")!=null and float(target.get("health"))<=0: return target
		if target.get("traffic")!=true: break
		# A normal red-light queue without a service obstruction is not panic.
		if not is_instance_valid(target.get("blocker")): break
		target=target.get("blocker")
	if not car.junction_wait and not car.blocked: return null
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(car.half_width*2+1,1.4,24)
	query.shape=box
	query.transform=Transform3D(car.global_basis,car.global_position-car.global_basis.z*(car.half_length+12)+Vector3.UP*.8)
	query.exclude=[car.get_rid()]
	query.collision_mask=4
	for hit in car.get_world_3d().direct_space_state.intersect_shape(query,12):
		if hit.collider.get_meta("dispatch_unit",false) and car._body_speed(hit.collider)<.6: return hit.collider
	return null
