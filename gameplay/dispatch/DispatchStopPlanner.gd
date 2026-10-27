extends RefCounted
## The stopping point includes a swept approach and a usable exit. Failed plans
## keep driving/braking on the existing route instead of parking in a junction.
const MODEL := preload("res://gameplay/traffic_yield/YieldRoadModel.gd")
const JOURNEY := preload("res://gameplay/AmbientJourney.gd")
var curve: Curve3D
var goal := Vector3.INF
var _retry := 0.0
var _model: RefCounted
## GETECO_STOP_FIX=0 volta à parada de antes de 27/10 (avanço pela frente do carro; ao desistir da
## rota sem acostamento, fica tentando), para A/B no mesmo build. DispatchUnit.on_gave_up lê o mesmo.
static var stop_fix := OS.get_environment("GETECO_STOP_FIX") != "0"

func reset() -> void:
	curve = null
	goal = Vector3.INF
	_retry = 0

static func departure_curve(vehicle: CharacterBody3D, road_route: Curve3D) -> Curve3D:
	var begin := road_route.get_closest_offset(vehicle.global_position)
	var length := road_route.get_baked_length()
	var offset := vehicle.global_position-road_route.sample_baked(begin,true)
	if Vector2(offset.x,offset.z).length()<.5: return road_route
	if length-begin<16: return null
	var curve := Curve3D.new()
	curve.bake_interval=.25
	for i in 29:
		var t := float(i)/28
		curve.add_point(road_route.sample_baked(begin+14*t,true)+offset*(1-smoothstep(0.0,1.0,t)))
	if not JOURNEY.curve_clear(vehicle,curve): return null
	var cursor := begin+15
	while cursor<length:
		curve.add_point(road_route.sample_baked(cursor,true))
		cursor+=1
	curve.add_point(road_route.sample_baked(length,true))
	curve.set_meta("traffic_open",true)
	return curve

func tick(unit, anchor: Vector3, delta: float) -> bool:
	if unit.driver.pending_recovery(): return false
	if curve != null:
		if goal.distance_to(anchor)>12:
			reset()
		else:
			unit.driver.hold(false)
			return unit.driver.at_route_end()
	_retry -= delta
	if _retry>0: return false
	_retry = .8
	if _model==null:
		_model = MODEL.new()
		_model.configure(unit.controller.routes)
	_model.refresh_if_changed()
	var vehicle: CharacterBody3D = unit.vehicle
	var forward := -vehicle.global_basis.z
	var info: Dictionary = _model.lateral(vehicle.global_position,forward,vehicle.half_width)
	if not info.valid: return false
	var foot_reach: float = unit.RULES.SPAWN_MAX if unit.is_police() else unit.RULES.FOOT_RANGE
	# A folga lateral (`room`) é medida no eixo da rua; o avanço também tem de ser. Com o avanço na
	# frente do carro, a viatura que chegava inclinada (cortando para o lado do alvo) somava 16 m × seno
	# do ângulo ao desvio e parava inteira na calçada (z = 6,8 numa rua de 8 m, 27/10).
	var along: Vector3 = Vector3.UP.cross(info.right).normalized() if stop_fix else forward
	for distance in [16.0,10.0,22.0]:
		for shoulder in [2.2,1.1,0.0]:
			var shift: float = info.room+shoulder
			if shift<.4: continue
			var candidate := Curve3D.new()
			candidate.bake_interval = .25
			for i in 17:
				var t := float(i)/16
				var lateral := smoothstep(0.0,.8,t)*shift
				candidate.add_point(vehicle.global_position+along*distance*t+info.right*lateral)
			var finish := candidate.get_point_position(16)
			if finish.distance_to(anchor)>foot_reach: continue
			if _model.in_junction(finish,vehicle.half_length): continue
			if not JOURNEY.curve_clear(vehicle,candidate): continue
			# No stopping plan without a safe right-hand door location.
			if unit.controller.exit_point_at(vehicle,finish,vehicle.rotation.y).is_empty(): continue
			candidate.set_meta("traffic_open",true)
			curve = candidate
			goal = anchor
			vehicle.set_meta("dispatch_needs_room",true)
			unit.driver.set_route(curve)
			unit.driver.hold(false)
			unit.controller.emit_dispatch_event("stop_planned",{"unit":unit,"point":finish,"shift":shift})
			return false
	return false
