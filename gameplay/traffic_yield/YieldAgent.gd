extends RefCounted
## Um veículo ambiente cedendo passagem. Não move o veículo: só troca a
## `Curve3D` de `Vehicle.route` (contrato já usado pelo tráfego) e deixa
## `Vehicle._drive_traffic` conduzir, frear e colidir. Uma rota aberta faz o
## próprio Vehicle parar no fim; a rota original é devolvida por uma curva de
## retorno gradual, nunca por salto.
##
##   pulling -> held -> merging -> (rota original restaurada)
##   slow ----------------------> (sem espaço lateral: só reduz e espera)
##
## Espaço lateral: `YieldRoadModel` (largura da pista do próprio grafo) +
## varredura física do casco (`Vehicle.rotation_shape`, máscara 7) em cada
## amostra da curva. Sem pista ou com algo no caminho, não há manobra.

const RULES := preload("res://gameplay/traffic_yield/YieldRules.gd")

var vehicle: CharacterBody3D
var model: RefCounted
var original: Curve3D
var mode := "pulling"
var age := 0.0
var quiet := 0.0
var end_reason := ""
var finished := false
var _stalled := 0.0
var _last_progress := 0.0
var _merge_wait := 0.0
var _retry := 0.0

## Devolve verdadeiro se assumiu o veículo. `hazard` é o dicionário de
## Controller._emergencies() que motivou a cessão.
func begin(p_vehicle: CharacterBody3D, p_model: RefCounted) -> bool:
	vehicle = p_vehicle
	model = p_model
	original = vehicle.route
	if original == null or original.get_baked_length() < 8.0: return false
	var origin := original.get_closest_offset(vehicle.global_position)
	for length in RULES.PULL_LENGTHS:
		var curve := _pull_curve(origin, length)
		if curve != null:
			vehicle.route = curve
			vehicle.route_distance = 0.0
			mode = "pulling"
			_last_progress = 0.0
			_mark("pulling")
			return true
	mode = "slow"
	_mark("slow")
	return true

func _mark(state: String) -> void:
	if is_instance_valid(vehicle): vehicle.set_meta("traffic_yield_state", state)

# --- Geometria da rota original -----------------------------------------------

func _wrap(offset: float) -> float:
	var length := original.get_baked_length()
	if original.get_meta("traffic_open", false): return clampf(offset, 0.0, length)
	return fposmod(offset, length)

func _point(offset: float) -> Vector3:
	return original.sample_baked(_wrap(offset), true)

func _tangent(offset: float) -> Vector3:
	var t := _point(offset + 0.6) - _point(offset - 0.6)
	t.y = 0.0
	return t.normalized() if t.length_squared() > 0.0001 else -vehicle.global_basis.z

## Varredura do casco em `point` orientado por `heading`.
func _hull_clear(point: Vector3, heading: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = vehicle.rotation_shape
	var yaw := atan2(-heading.x, -heading.z)
	query.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(point.x, vehicle.global_position.y + vehicle.shape.position.y, point.z))
	query.collision_mask = 7
	var exclude: Array[RID] = [vehicle.get_rid()]
	query.exclude = exclude
	return vehicle.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Curva lateral: segue a rota original por `length` m e desloca para a direita
## até o menor espaço disponível. Nula se sair da pista, tocar num cruzamento,
## esbarrar em algo ou acabar a rota antes.
func _pull_curve(origin: float, length: float) -> Curve3D:
	if original.get_meta("traffic_open", false) and origin + length > original.get_baked_length() - 1.0: return null
	var count := int(ceil(length / RULES.SAMPLE_STEP))
	var base: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var rooms: Array[float] = []
	for index in range(1, count + 1):
		var offset := origin + float(index) * RULES.SAMPLE_STEP
		var point := _point(offset)
		var tangent := _tangent(offset)
		if model.in_junction(point): return null
		var info: Dictionary = model.lateral(point, tangent, vehicle.half_width)
		if not info.valid: return null
		base.append(point)
		rights.append(info.right)
		rooms.append(info.room)
	# O deslocamento final é o menor espaço da metade final da manobra.
	var final_shift := RULES.MAX_SHIFT
	# Whole-number grouping/index; preserve integer truncation and precision.
	@warning_ignore("integer_division")
	for index in range(count / 3, count): final_shift = minf(final_shift, rooms[index])
	if final_shift < RULES.MIN_SHIFT: return null
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	curve.add_point(vehicle.global_position)
	var previous: Vector3 = vehicle.global_position
	for index in count:
		var t := clampf(float(index + 1) / (float(count) * 0.6), 0.0, 1.0)
		var shift := minf(final_shift * t * t * (3.0 - 2.0 * t), rooms[index])
		var point: Vector3 = base[index] + rights[index] * shift
		point.y = base[index].y
		if not _hull_clear(point, (point - previous).normalized() if point.distance_to(previous) > 0.01 else _tangent(origin)): return null
		curve.add_point(point)
		previous = point
	curve.set_meta("traffic_open", true)
	curve.set_meta("traffic_endpoint", curve.get_point_position(curve.point_count - 1))
	return curve

## Curva de retorno: a partir da posição atual, volta ao eixo da faixa original
## ao longo de MERGE_LENGTH m. Nula se algo bloquear o caminho.
func _merge_curve() -> Curve3D:
	var origin := original.get_closest_offset(vehicle.global_position)
	var lane_point := _point(origin)
	var right := _tangent(origin).cross(Vector3.UP)
	var lateral := Vector3(vehicle.global_position.x - lane_point.x, 0.0, vehicle.global_position.z - lane_point.z).dot(right)
	var count := int(ceil(RULES.MERGE_LENGTH / RULES.SAMPLE_STEP))
	if original.get_meta("traffic_open", false) and origin + RULES.MERGE_LENGTH > original.get_baked_length() - 1.0: return null
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	curve.add_point(vehicle.global_position)
	var previous: Vector3 = vehicle.global_position
	for index in range(1, count + 1):
		var offset := origin + 2.0 + float(index) * RULES.SAMPLE_STEP
		var t := float(index) / float(count)
		var point := _point(offset) + _tangent(offset).cross(Vector3.UP) * lateral * (1.0 - t * t * (3.0 - 2.0 * t))
		point.y = _point(offset).y
		if model.lateral(point, _tangent(offset), vehicle.half_width).valid == false: return null
		if not _hull_clear(point, (point - previous).normalized() if point.distance_to(previous) > 0.01 else _tangent(origin)): return null
		curve.add_point(point)
		previous = point
	curve.set_meta("traffic_open", true)
	curve.set_meta("traffic_endpoint", curve.get_point_position(curve.point_count - 1))
	return curve

# --- Laço ---------------------------------------------------------------------

## `hazards`: [{"position", "forward", "speed"}] das viaturas com sirene.
func tick(delta: float, hazards: Array) -> void:
	if finished: return
	if not is_instance_valid(vehicle) or vehicle.health <= 0.0 or vehicle.controlled or not vehicle.traffic:
		# Destruído, assumido pelo jogador ou tirado do tráfego: não há mais o que devolver.
		_finish("vehicle_unavailable", false)
		return
	age += delta
	var threat := false
	var behind := false
	for hazard in hazards:
		var e_position: Vector3 = hazard.position
		var e_forward: Vector3 = hazard.forward
		var e_speed: float = hazard.speed
		if RULES.threatens(e_position, e_forward, e_speed, vehicle.global_position, -vehicle.global_basis.z, vehicle.half_width): threat = true
		if RULES.close_behind(e_position, e_forward, e_speed, vehicle.global_position, vehicle.half_width): behind = true
	match mode:
		"pulling": _tick_pulling(delta)
		"slow": _tick_slow(delta)
		"held": pass
		"merging": _tick_merging(delta)
	if mode == "pulling" or mode == "slow" or mode == "held":
		quiet = 0.0 if threat else quiet + delta
		var may_leave := quiet >= RULES.RESUME_DELAY or age >= RULES.HOLD_MAX
		if may_leave and not behind and mode != "pulling": _start_resume(delta)

func _cap_speed(cap: float) -> void:
	if vehicle.speed > cap: vehicle.speed = cap

func _tick_pulling(delta: float) -> void:
	_cap_speed(RULES.YIELD_SPEED)
	var progress: float = vehicle.route_distance
	if progress > _last_progress + 0.3:
		_last_progress = progress
		_stalled = 0.0
	else:
		_stalled += delta
	var remaining: float = vehicle.route.get_baked_length() - progress
	if remaining <= 1.8 and absf(vehicle.speed) < 0.4:
		mode = "held"
		_mark("held")
	elif _stalled > RULES.PROGRESS_TIMEOUT:
		# Preso a meio caminho (algo entrou na frente): desiste da manobra.
		_stalled = 0.0
		mode = "held"
		_mark("held")

func _tick_slow(_delta: float) -> void:
	_cap_speed(RULES.SLOW_ONLY_SPEED)

func _start_resume(delta: float) -> void:
	# A varredura da volta custa até 7 consultas físicas: 4 vezes por segundo, não por quadro.
	_retry -= delta
	if _retry > 0.0: return
	_retry = 0.25
	if vehicle.obstacle_ahead():
		_merge_wait += delta
		return
	if vehicle.route == original or mode == "slow":
		# Sem desvio lateral: basta devolver a rota.
		_restore("resumed")
		return
	var curve := _merge_curve()
	if curve == null:
		_merge_wait += delta
		return
	vehicle.route = curve
	vehicle.route_distance = 0.0
	mode = "merging"
	_mark("merging")

func _tick_merging(_delta: float) -> void:
	_cap_speed(RULES.YIELD_SPEED)
	var remaining: float = vehicle.route.get_baked_length() - vehicle.route_distance
	# Antes de o Vehicle parar no fim da curva aberta, a rota original volta.
	if remaining <= 3.0: _restore("resumed")

func _restore(reason: String) -> void:
	if is_instance_valid(vehicle):
		vehicle.route = original
		vehicle.route_distance = original.get_closest_offset(vehicle.global_position)
	_finish(reason, true)

func _finish(reason: String, restored: bool) -> void:
	finished = true
	end_reason = reason
	if not is_instance_valid(vehicle): return
	# Veículo ainda no tráfego com rota de desvio: devolve a original sem salto.
	if not restored and original != null and vehicle.route != original and vehicle.traffic and vehicle.health > 0.0 and not vehicle.controlled:
		vehicle.route = original
	if vehicle.has_meta("traffic_yield_state"): vehicle.remove_meta("traffic_yield_state")

## Devolve a rota original imediatamente (troca de região, desligar o módulo).
func release() -> void:
	if finished: return
	if is_instance_valid(vehicle) and original != null and not vehicle.controlled: vehicle.route = original
	finished = true
	end_reason = "released"
	if is_instance_valid(vehicle) and vehicle.has_meta("traffic_yield_state"): vehicle.remove_meta("traffic_yield_state")
