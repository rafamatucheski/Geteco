extends RefCounted
## Planeja o desvio à esquerda de carros que cederam passagem. Só produz uma
## `Curve3D`: quem anda, freia e colide é o `Vehicle` (pelo DispatchDriver).
##
## Um plano só existe se TODAS as amostras do caminho, do início da rampa até a
## volta à faixa mais uma cauda, passarem em:
##   - estar sobre pista do grafo real, sem cruzar o limite esquerdo/direito com o casco;
##   - não tocar zona de cruzamento;
##   - rota quase reta (variação de rumo por amostra ≤ MAX_TURN);
##   - casco completo (com folgas) livre de sólidos e de outros carros;
##   - em rua de mão dupla, o casco só cruza o eixo se `allow_oncoming` e a faixa
##     contrária estiver livre por todo o trecho mais ONCOMING_LOOKAHEAD m;
##   - em rua de mão única, o limite é a largura da própria pista (mesmo sentido).
## Sem isso devolve `{"ok": false, "reason": ...}` e o piloto espera.

const RULES := preload("res://gameplay/dispatch/overtaking/OvertakeRules.gd")

var model: RefCounted
var _pad := BoxShape3D.new()
var _zone := BoxShape3D.new()

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _wrap(route: Curve3D, offset: float) -> float:
	var length := route.get_baked_length()
	if route.get_meta("traffic_open", false): return clampf(offset, 0.0, length)
	return fposmod(offset, length)

func _point(route: Curve3D, offset: float) -> Vector3:
	return route.sample_baked(_wrap(route, offset), true)

func _tangent(route: Curve3D, offset: float) -> Vector3:
	var t := _point(route, offset + 0.6) - _point(route, offset - 0.6)
	t.y = 0.0
	return t.normalized() if t.length_squared() > 0.0001 else Vector3.FORWARD

## Distância à frente de `origin` (fechada: dá a volta).
func _ahead(route: Curve3D, origin: float, offset: float) -> float:
	if route.get_meta("traffic_open", false): return offset - origin
	return fposmod(offset - origin, route.get_baked_length())

func _hull_clear(vehicle: CharacterBody3D, point: Vector3, heading: Vector3, ignore: Array[RID]) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _pad
	var yaw := atan2(-heading.x, -heading.z)
	query.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, vehicle.global_position.y + vehicle.shape.position.y, point.z))
	query.collision_mask = 7
	var exclude: Array[RID] = [vehicle.get_rid()]
	exclude.append_array(ignore)
	query.exclude = exclude
	return vehicle.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _oncoming_clear(vehicle: CharacterBody3D, start: Vector3, tangent: Vector3, width: float, span: float, ignore: Array[RID]) -> bool:
	var length := span + RULES.ONCOMING_LOOKAHEAD
	_zone.size = Vector3(width * 0.5, 2.4, length)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _zone
	var yaw := atan2(-tangent.x, -tangent.z)
	var center := start + tangent * (length * 0.5)
	query.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, vehicle.global_position.y + 1.2, center.z))
	query.collision_mask = 7
	var exclude: Array[RID] = [vehicle.get_rid()]
	exclude.append_array(ignore)
	query.exclude = exclude
	return vehicle.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Faixa contrária livre nos ONCOMING_LOOKAHEAD m à frente do veículo (rua de
## mão única: sempre livre; fora de pista: sem opinião, livre).
func oncoming_ahead_clear(vehicle: CharacterBody3D, ignore: Array[RID]) -> bool:
	var tangent := -vehicle.global_basis.z
	tangent.y = 0.0
	tangent = tangent.normalized()
	var info: Dictionary = model.lateral(vehicle.global_position, tangent, vehicle.half_width)
	if not info.valid or info.one_way: return true
	var right: Vector3 = info.right
	var start: Vector3 = vehicle.global_position - right * float(info.signed) - right * float(info.width) * 0.25
	return _oncoming_clear(vehicle, start, tangent, float(info.width), 0.0, ignore)

func oncoming_margin(vehicle: CharacterBody3D, ignore: Array[RID], exit_distance: float, our_speed: float) -> float:
	return float(oncoming_probe(vehicle, ignore, exit_distance, our_speed).margin)

## Menor folga prevista, na faixa contrária à frente, quando a viatura tiver
## percorrido `exit_distance` para sair dela. Para cada corpo: folga atual à
## frente − distância que ainda percorremos − quanto ele avança (se vem de frente
## e anda) no tempo que levamos. Parado ou sólido conta como fixo. INF = nada à vista
## (ou rua de mão única / fora de pista, onde não há faixa contrária).
## `stationary`: o corpo que define a menor folga está parado ou é sólido, ou seja,
## esperar não vai abrir a folga sozinha (um carro que anda acaba passando).
func oncoming_probe(vehicle: CharacterBody3D, ignore: Array[RID], exit_distance: float, our_speed: float) -> Dictionary:
	var tangent := -vehicle.global_basis.z
	tangent.y = 0.0
	tangent = tangent.normalized()
	var info: Dictionary = model.lateral(vehicle.global_position, tangent, vehicle.half_width)
	if not info.valid or info.one_way: return {"margin": INF, "stationary": false}
	var right: Vector3 = info.right
	var width := float(info.width)
	var start: Vector3 = vehicle.global_position - right * float(info.signed) - right * width * 0.25
	_zone.size = Vector3(width * 0.5, 2.4, RULES.ONCOMING_LOOKAHEAD)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _zone
	var center := start + tangent * (RULES.ONCOMING_LOOKAHEAD * 0.5)
	query.transform = Transform3D(Basis(Vector3.UP, atan2(-tangent.x, -tangent.z)), Vector3(center.x, vehicle.global_position.y + 1.2, center.z))
	query.collision_mask = 7
	var exclude: Array[RID] = [vehicle.get_rid()]
	exclude.append_array(ignore)
	query.exclude = exclude
	var exit_time := exit_distance / maxf(our_speed, RULES.MIN_EXIT_SPEED)
	var best := INF
	var stationary := false
	for hit in vehicle.get_world_3d().direct_space_state.intersect_shape(query, 8):
		var body: Object = hit.collider
		if not is_instance_valid(body) or not body is Node3D: continue
		var other: Node3D = body
		var their_half := float(other.get("half_length")) if "half_length" in other else 1.0
		var gap: float = (other.global_position - vehicle.global_position).dot(tangent) - float(vehicle.half_length) - their_half
		var closing := 0.0
		var their_speed := 0.0
		if "speed" in other:
			their_speed = float(other.get("speed"))
			var their_heading := -other.global_basis.z * signf(their_speed)
			if their_heading.dot(tangent) < -0.3: closing = absf(their_speed)
		var margin: float = gap - exit_distance - closing * exit_time
		if margin < best:
			best = margin
			stationary = absf(their_speed) < RULES.STATIONARY_SPEED
	return {"margin": best, "stationary": stationary}

## Casco livre ao longo do que falta de uma curva JÁ planejada (desvio preservado
## durante a espera pela faixa contrária). O plano original passou na varredura, mas
## o mundo muda enquanto a viatura espera ou depois de uma suspensão: retomar exige
## a mesma varredura de novo, senão a viatura seguiria uma curva obsoleta.
func curve_clear(vehicle: CharacterBody3D, curve: Curve3D, ignore: Array[RID]) -> bool:
	if curve == null or curve.get_baked_length() < 0.5: return false
	_size_pad(vehicle)
	var length := curve.get_baked_length()
	var s := curve.get_closest_offset(vehicle.global_position)
	var previous: Vector3 = vehicle.global_position
	var heading := -vehicle.global_basis.z
	heading.y = 0.0
	while s < length:
		s = minf(s + RULES.SAMPLE_STEP, length)
		var point := curve.sample_baked(s, true)
		if point.distance_to(previous) > 0.01: heading = (point - previous).normalized()
		if not _hull_clear(vehicle, point, heading, ignore): return false
		previous = point
	return true

func _size_pad(vehicle: CharacterBody3D) -> void:
	var hull := (vehicle.shape.shape as BoxShape3D).size
	_pad.size = Vector3(hull.x + 2.0 * RULES.PAD_SIDE, maxf(0.5, hull.y - 0.3), hull.z + 2.0 * RULES.PAD_END)

## Rumo da rota no ponto mais próximo do veículo.
func heading_at(route: Curve3D, vehicle: CharacterBody3D) -> Vector3:
	return _tangent(route, route.get_closest_offset(vehicle.global_position))

## Onde a viatura está ao longo da rota, em metros à frente de `origin`.
func progress(route: Curve3D, origin: float, vehicle: CharacterBody3D) -> float:
	return _ahead(route, origin, route.get_closest_offset(vehicle.global_position))

## Deslocamento à esquerda do veículo em relação ao eixo da rota (positivo = esquerda).
func lateral_left(vehicle: CharacterBody3D, route: Curve3D) -> float:
	var offset := route.get_closest_offset(vehicle.global_position)
	var base := _point(route, offset)
	var right := _tangent(route, offset).cross(Vector3.UP)
	return -Vector3(vehicle.global_position.x - base.x, 0.0, vehicle.global_position.z - base.z).dot(right)

## `blockers`: veículos em held/pulling na faixa à frente. `return_only`: só
## volta ao eixo da rota (aborto ou fim do bloqueio). `ramp_scale` (só no retorno,
## ≥ 1): alonga a rampa para uma volta mais suave; nunca encurta.
func plan(vehicle: CharacterBody3D, route: Curve3D, blockers: Array, allow_oncoming: bool, ignore: Array[RID], return_only: bool = false, ramp_scale: float = 1.0) -> Dictionary:
	model.refresh_if_changed()
	if not model.has_graph(): return _fail("no_graph")
	var half_width: float = vehicle.half_width
	_size_pad(vehicle)
	var open: bool = route.get_meta("traffic_open", false)
	var length := route.get_baked_length()
	var origin := route.get_closest_offset(vehicle.global_position)
	var speed: float = absf(vehicle.speed)
	var start_lat := maxf(0.0, lateral_left(vehicle, route))
	var target := 0.0
	var hold_until := 0.0
	var ramp_in := 0.0
	var ramp_out := 0.0
	var first_start := 0.0
	var pass_end := 0.0
	if return_only:
		if start_lat < 0.2: return _fail("already_in_lane")
		ramp_in = RULES.ramp_length(start_lat, speed) * maxf(1.0, ramp_scale)
	else:
		var nearest := INF
		var last_end := 0.0
		for blocker in blockers:
			if not is_instance_valid(blocker): continue
			var blocker_offset := route.get_closest_offset(blocker.global_position)
			var ahead := _ahead(route, origin, blocker_offset)
			var base := _point(route, blocker_offset)
			var right_of_route := Vector3(blocker.global_position.x - base.x, 0.0, blocker.global_position.z - base.z).dot(_tangent(route, blocker_offset).cross(Vector3.UP))
			target = maxf(target, RULES.needed_shift(right_of_route, blocker.half_width, half_width))
			nearest = minf(nearest, ahead - blocker.half_length)
			last_end = maxf(last_end, ahead + blocker.half_length)
		if target < RULES.MIN_SHIFT: return _fail("lane_clear")
		if target > RULES.MAX_SHIFT: return _fail("shift_too_large")
		ramp_in = RULES.ramp_length(target - start_lat, speed)
		ramp_out = RULES.ramp_length(target, RULES.RAMP_PER_M_FAST * 2.0)
		# A rampa de entrada inteira precisa caber antes do primeiro bloqueador.
		if nearest < ramp_in + 1.0: return _fail("no_room_to_swerve")
		hold_until = maxf(last_end + RULES.FRONT_CLEAR, ramp_in)
		first_start = nearest
		pass_end = last_end
	var total := ramp_in + RULES.TAIL if return_only else hold_until + ramp_out + RULES.TAIL
	total = maxf(total, ramp_in + RULES.TAIL)
	if open and origin + total > length - 1.0:
		if not return_only: return _fail("route_ends")
		# Só voltar ao eixo: se o eixo acaba perto, encurta a cauda de validação (a rampa
		# inteira, sim, precisa caber). O que falta continua varrido amostra a amostra.
		total = length - 1.0 - origin
		if total < ramp_in + RULES.RETURN_MIN_TAIL: return _fail("route_ends")
	var count := int(ceil(total / RULES.SAMPLE_STEP))
	var points: Array[Vector3] = [vehicle.global_position]
	var previous_tangent := _tangent(route, origin)
	var previous: Vector3 = vehicle.global_position
	var oncoming := false
	var zone_start := Vector3.ZERO
	var zone_tangent := Vector3.ZERO
	var zone_width := 0.0
	var zone_from := 0.0
	for index in range(1, count + 1):
		var s := minf(float(index) * RULES.SAMPLE_STEP, total)
		var offset := origin + s
		var base := _point(route, offset)
		var tangent := _tangent(route, offset)
		if previous_tangent.angle_to(tangent) > RULES.MAX_TURN: return _fail("curve_too_tight")
		previous_tangent = tangent
		var shift := RULES.profile(s, start_lat, target, ramp_in, hold_until, ramp_out)
		var point := base - tangent.cross(Vector3.UP) * shift
		point.y = base.y
		if model.in_junction(point, half_width): return _fail("junction")
		var info: Dictionary = model.lateral(point, tangent, half_width + RULES.PAD_SIDE)
		if not info.valid: return _fail("off_pavement")
		if info.room_raw < 0.0 or info.left_raw < 0.0: return _fail("narrow_road")
		if not info.one_way and info.signed - (half_width + RULES.PAD_SIDE) < RULES.CENTER_MARGIN:
			# Casco sobre o eixo da rua de mão dupla: só com contramão permitida e livre.
			if not allow_oncoming and not return_only: return _fail("oncoming_lane_forbidden")
			if not oncoming:
				zone_start = point - (info.right as Vector3) * float(info.signed) - (info.right as Vector3) * float(info.width) * 0.25
				zone_tangent = tangent
				zone_width = float(info.width)
				zone_from = s
			oncoming = true
		var heading := (point - previous).normalized() if point.distance_to(previous) > 0.01 else tangent
		if not _hull_clear(vehicle, point, heading, ignore): return _fail("obstructed")
		points.append(point)
		previous = point
	if oncoming and not return_only:
		if not _oncoming_clear(vehicle, zone_start, zone_tangent, zone_width, total - zone_from, ignore): return _fail("oncoming_traffic")
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	for point in points: curve.add_point(point)
	curve.set_meta("traffic_open", true)
	curve.set_meta("traffic_endpoint", points[points.size() - 1])
	return {"ok": true, "curve": curve, "oncoming": oncoming, "target": target, "length": curve.get_baked_length(), "start_left": start_lat, "origin": origin, "first_start": first_start, "last_end": pass_end}
