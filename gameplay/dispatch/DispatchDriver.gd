extends RefCounted
## Piloto de uma viatura. Conduz o `Vehicle` original pelas entradas externas
## (throttle/steer/brake) do DispatchVehicle: a física, a colisão e o dano são
## os do próprio Vehicle.gd. Nunca reposiciona o veículo. O modo `traffic` do
## Vehicle limita a 5,5 m/s e não serve para resposta a ocorrências.

const OVERTAKE := preload("res://gameplay/dispatch/overtaking/OvertakeController.gd")
const OVERTAKE_RULES := preload("res://gameplay/dispatch/overtaking/OvertakeRules.gd")
const TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

signal replan_requested(reason: String)
signal gave_up(reason: String)
## Repasse dos sinais da ultrapassagem (o objeto é recriado por enable_overtaking).
signal overtake_state_changed(state: String, reason: String)
signal overtake_unresolved_changed(unresolved: bool, reason: String)

const WHEELBASE := 2.5
const MAX_STEER := 0.48
const BRAKE_DECELERATION := 7.0
const SENSOR_INTERVAL := 0.1
const REVERSE_SECONDS := 0.8
const REVERSE_CLEARANCE := 2.5
## Tentativas de ré sem progresso antes de desistir do trecho.
const MAX_FAILED_RECOVERIES := 4
const PROGRESS_RESET := 6.0
## Espera parado diante de obstáculo sentido (trânsito) antes de tratar como travamento.
const BLOCK_PATIENCE := 3.0

var vehicle: CharacterBody3D
var route: Curve3D
var speed_cap := 14.7
var stall_seconds := 2.0
var holding := false
var offset := 0.0
var remaining := INF
var blocked_ahead := false
var reversing := false
var failed_recoveries := 0
var stalled := 0.0
var blocked_wait := 0.0
var _sensor_clock := 0.0
var _reverse_clock := 0.0
var _reverse_steer := 0.0
var _attempts_since_replan := 0
var _progress_at_recovery := 0.0
## Ultrapassagem de carros ambiente que cederam passagem; nula até `enable_overtaking`.
var overtake: RefCounted
var _overtake_discovered := false
var _last_frame := -1
var _sensor := BoxShape3D.new()
var _rear_sensor := BoxShape3D.new()

func setup(p_vehicle: CharacterBody3D, p_speed_cap: float, p_stall_seconds: float) -> void:
	vehicle = p_vehicle
	speed_cap = p_speed_cap
	stall_seconds = p_stall_seconds
	vehicle.traffic = false
	vehicle.set_external_driver(true)
	_sensor.size = Vector3(vehicle.half_width * 2.0 + 0.1, 1.2, 1.0)
	_rear_sensor.size = Vector3(vehicle.half_width * 2.0, 1.0, REVERSE_CLEARANCE)

## Liga a ultrapassagem sobre o grafo real (o mesmo NativeTrafficRoutes do
## despacho). Sem chamada explícita, o primeiro tick tenta descobrir o grafo em
## `vehicle.get_parent().production.traffic_routes` (ProductionWorld); em cena
## sem essa referência a ultrapassagem fica desligada.
func enable_overtaking(routes: RefCounted, allow_oncoming: bool = true) -> void:
	_overtake_discovered = true
	overtake = OVERTAKE.new()
	overtake.setup(self, routes)
	overtake.allow_oncoming = allow_oncoming
	overtake.state_changed.connect(func(state: String, reason: String): overtake_state_changed.emit(state, reason))
	overtake.unresolved_changed.connect(func(unresolved: bool, reason: String): overtake_unresolved_changed.emit(unresolved, reason))

func disable_overtaking() -> void:
	_overtake_discovered = true
	if overtake != null: overtake.reset("disabled")
	overtake = null

func _discover_overtaking() -> void:
	if overtake != null or _overtake_discovered: return
	_overtake_discovered = true
	var parent := vehicle.get_parent()
	if parent == null: return
	var production: Variant = parent.get("production")
	if production == null: return
	var routes: Variant = production.get("traffic_routes")
	if routes != null: enable_overtaking(routes)

## Um desvio em curso continua válido quando o piloto troca a rota principal
## (a perseguição replaneja a cada ~1 s): a ultrapassagem mede tudo no eixo lembrado
## do início da manobra e a rota nova só vale depois da volta à faixa. Rota nula com
## o veículo fora do eixo mantém o estado: o piloto segue só a curva de desvio/retorno
## já validada (ou fica parado se não há) e a rota nova, quando vier, assume ao voltar.
func set_route(curve: Curve3D) -> void:
	if curve != null and (curve.point_count < 2 or curve.get_baked_length() < 0.25):
		curve = null
	if overtake != null:
		if curve == null: overtake.on_route_cleared()
		else: overtake.rebase_route(curve)
	route = curve
	offset = 0.0
	remaining = curve.get_baked_length() if curve != null else INF
	stalled = 0.0
	blocked_wait = 0.0
	reversing = false
	_attempts_since_replan = 0
	_progress_at_recovery = 0.0

## Cancela qualquer ultrapassagem: se o veículo está fora do eixo, para e volta
## com curva validada; senão só descarta o plano. Chamar ao encerrar/redirecionar
## a unidade quando a integração quiser recolher a manobra antes de outra ação.
func cancel_overtaking(reason: String) -> void:
	if overtake != null: overtake.cancel(reason)

## REMOÇÃO IMEDIATA (troca de região, dismiss_all, veículo que vai ser liberado):
## descarta o estado sem recuperação física, porque não sobra veículo para recuperar.
## Para redirecionar/cancelar com o veículo em jogo use `cancel_overtaking`.
func discard_overtaking(reason: String) -> void:
	if overtake != null: overtake.reset(reason)

## Recuperação de ultrapassagem pendente (ou caso sem solução): não é parada concluída.
func pending_recovery() -> bool:
	return overtake != null and overtake.blocks_parking()

## Contrato de parada concluída: veículo parado **e** sem recuperação pendente.
## Velocidade baixa sozinha (`is_stopped`) não basta para estacionar/desembarcar.
func settled() -> bool:
	return is_stopped() and not pending_recovery()

## "settled" | "moving" | "recovery_pending" | "recovery_unresolved" (para logs)
func stop_status() -> String:
	if overtake != null and overtake.unresolved: return "recovery_unresolved"
	if pending_recovery(): return "recovery_pending"
	return "settled" if is_stopped() else "moving"

func hold(value: bool) -> void:
	holding = value

func is_stopped() -> bool:
	return is_instance_valid(vehicle) and absf(vehicle.speed) < 0.35

## Fim de rota alcançado e veículo parado.
func at_route_end() -> bool:
	return route != null and remaining <= 1.2 and settled()

func tick(delta: float) -> void:
	var traced := STALL_WORK.begin()
	_stall_tick(delta)
	STALL_WORK.finish_slow("dispatch.driver.tick", traced, 5000, vehicle)

func _stall_tick(delta: float) -> void:
	if not is_instance_valid(vehicle) or vehicle.health <= 0:
		if overtake != null: overtake.reset("vehicle_unavailable")
		return
	# Suspensa (sem tick por vários quadros) e retomada: o plano lateral é do passado.
	var frames := Engine.get_physics_frames()
	if overtake != null and _last_frame >= 0 and frames - _last_frame > OVERTAKE_RULES.RESUME_GAP_FRAMES: overtake.recover_if_displaced("resumed")
	_last_frame = frames
	vehicle.set_external_driver(true)
	vehicle.brake_input = false
	# Ordem de parar no meio de um desvio: termina a manobra (volta à faixa) antes
	# de frear, em vez de estacionar na faixa contrária ou ao lado do carro que cedeu.
	var settling := false
	if holding and overtake != null and overtake.is_active():
		overtake.settle()
		settling = true
	# Sem rota principal, fora do eixo: a ultrapassagem lembra o eixo e pode seguir a
	# curva de retorno que ela mesma validou. Sem curva, a viatura só freia (abaixo).
	var detached: bool = route == null and overtake != null and overtake.follows_without_route()
	if (route == null and not detached) or (holding and not settling):
		_brake(delta)
		return
	_discover_overtaking()
	var length := route.get_baked_length() if route != null else 0.0
	var traced := TRACE.begin()
	offset = route.get_closest_offset(vehicle.global_position) if route != null else 0.0
	TRACE.end("driver.closest_offset", traced)
	remaining = length - offset if route != null else INF
	_sensor_clock -= delta
	if _sensor_clock <= 0.0:
		_sensor_clock = SENSOR_INTERVAL
		var sensing := TRACE.begin()
		blocked_ahead = _obstacle_ahead()
		TRACE.end("driver.obstacle_sensor", sensing)
	if reversing:
		_reverse(delta)
		return
	# Caminho seguido: a rota principal ou, durante uma ultrapassagem, o desvio.
	var path: Curve3D = route
	var path_offset := offset
	var path_length := length
	var speed_limit := INF
	if overtake != null:
		var overtaking := TRACE.begin()
		overtake.tick(delta)
		TRACE.end("overtake.tick", overtaking)
		speed_limit = overtake.speed_limit
		if overtake.bypass != null:
			path = overtake.bypass
			path_length = path.get_baked_length()
			path_offset = path.get_closest_offset(vehicle.global_position)
			if path_length - path_offset <= 1.0:
				overtake.finish_bypass()
				path = route
				path_offset = offset
				path_length = length
				speed_limit = INF
	if path == null:
		# Sem rota principal e sem curva de recuperação validada: parado, nada é inventado.
		_brake(delta)
		return
	if path.point_count < 2 or path_length < 0.25:
		_brake(delta)
		return
	var lookahead := clampf(2.5 + absf(vehicle.speed) * 0.45, 3.0, 9.0)
	var target := path.sample_baked(minf(path_offset + lookahead, path_length), true)
	var beyond := path.sample_baked(minf(path_offset + lookahead + 6.0, path_length), true)
	var position := vehicle.global_position
	var forward := -vehicle.global_basis.z
	var to_target := target - position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01: to_target = forward
	var alpha := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	var bend := 0.0
	var leg := beyond - target
	leg.y = 0.0
	if leg.length_squared() > 0.25:
		bend = absf(to_target.normalized().signed_angle_to(leg.normalized(), Vector3.UP))
	var desired := lerpf(speed_cap, 4.0, clampf(bend / 0.9, 0.0, 1.0))
	# Frenagem até o fim da rota: v² = 2·a·d, com folga de 0,8 m.
	desired = minf(desired, sqrt(maxf(0.0, 2.0 * BRAKE_DECELERATION * 0.7 * (remaining - 0.8))))
	if blocked_ahead: desired = 0.0
	desired = minf(desired, speed_limit)
	var steer_command := clampf(atan2(2.0 * WHEELBASE * sin(alpha), maxf(lookahead, 1.0)) / MAX_STEER, -1.0, 1.0)
	if absf(alpha) > 1.6:
		# Rota atrás do veículo (retorno): esterço máximo, devagar. Com o alvo
		# exatamente às costas o seno some e o controle perderia o sentido.
		steer_command = 1.0 if alpha >= 0.0 else -1.0
		desired = minf(desired, 3.0)
	vehicle.steer_input = steer_command
	if vehicle.speed < -0.2: vehicle.steer_input = -vehicle.steer_input
	if vehicle.speed > desired + 0.6:
		vehicle.throttle_input = 0.0
		vehicle.brake_input = true
	else:
		vehicle.throttle_input = clampf((desired - vehicle.speed) * 0.9, 0.0, 1.0)
	_track_stall(delta, desired, alpha)

func _brake(_delta: float) -> void:
	vehicle.throttle_input = 0.0
	vehicle.steer_input = 0.0
	vehicle.brake_input = true
	stalled = 0.0

func _track_stall(delta: float, desired: float, alpha: float) -> void:
	# Só conta parada quando o piloto manda andar: parar no fim da rota ou por
	# ordem de `hold` não é travamento.
	var should_move := desired > 1.0 and remaining > 2.0
	if should_move and absf(vehicle.speed) < 0.6:
		stalled += delta
	else:
		stalled = maxf(0.0, stalled - delta * 0.5)
	# Obstáculo à frente (trânsito que anda) espera; obstáculo que não sai é tratado como travamento.
	# Esperando a vez de ultrapassar um carro que cedeu: não é travamento, não recua nem replaneja.
	var overtaking_wait: bool = overtake != null and (overtake.is_waiting() or overtake.is_active())
	# Já colado na fila: esperar o plano de ultrapassagem não cria a rampa que falta.
	# Permite a recuperação normal, com sensor traseiro e tentativas limitadas.
	var needs_room: bool = overtake != null and overtake.is_waiting() and overtake.last_reason == "no_room_to_swerve" and vehicle.archetype == "rescue_pumper"
	if needs_room: overtaking_wait = false
	if (blocked_ahead or needs_room) and remaining > 2.0 and absf(vehicle.speed) < 0.6 and not overtaking_wait:
		blocked_wait += delta
	else:
		blocked_wait = maxf(0.0, blocked_wait - delta)
	if blocked_wait > BLOCK_PATIENCE:
		blocked_wait = 0.0
		stalled = 0.0
		_recover(alpha)
		return
	if stalled <= stall_seconds: return
	stalled = 0.0
	_recover(alpha)

func _recover(alpha: float) -> void:
	# Fora do eixo por causa de uma ultrapassagem: nada de ré nem novo plano por cima do carro ao lado.
	if overtake != null and overtake.is_active():
		overtake.on_stuck()
		return
	if offset - _progress_at_recovery > PROGRESS_RESET:
		failed_recoveries = 0
		_attempts_since_replan = 0
	_progress_at_recovery = offset
	failed_recoveries += 1
	_attempts_since_replan += 1
	if failed_recoveries >= MAX_FAILED_RECOVERIES:
		failed_recoveries = 0
		gave_up.emit("stuck")
		return
	if _attempts_since_replan >= 2:
		_attempts_since_replan = 0
		replan_requested.emit("stuck")
		# O novo plano pode pedir retorno; recuar por cima dele só atrapalha.
		return
	if _rear_clear():
		reversing = true
		_reverse_clock = REVERSE_SECONDS
		if vehicle.archetype == "rescue_pumper" and overtake != null and overtake.is_waiting() and overtake.last_reason == "no_room_to_swerve":
			_reverse_clock = 3.0
		_reverse_steer = -signf(alpha) * 0.8 if absf(alpha) > 0.05 else 0.0

func _reverse(delta: float) -> void:
	_reverse_clock -= delta
	vehicle.steer_input = _reverse_steer
	vehicle.throttle_input = -1.0
	if _reverse_clock <= 0.0 or not _rear_clear():
		reversing = false
		vehicle.throttle_input = 0.0
		vehicle.brake_input = true

func _obstacle_ahead() -> bool:
	var length: float = 2.2 + vehicle.speed * vehicle.speed / 16.0
	_sensor.size.z = length
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sensor
	query.transform = Transform3D(vehicle.global_basis, vehicle.global_position - vehicle.global_basis.z * (vehicle.half_length + length * 0.5) + Vector3.UP * 0.8)
	query.collision_mask = 7
	query.exclude = _excluded()
	return not vehicle.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _rear_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _rear_sensor
	query.transform = Transform3D(vehicle.global_basis, vehicle.global_position + vehicle.global_basis.z * (vehicle.half_length + REVERSE_CLEARANCE * 0.5) + Vector3.UP * 0.8)
	query.collision_mask = 7
	query.exclude = _excluded()
	return vehicle.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Corpos que não contam como obstáculo: o próprio carro e quem desembarcou dele.
var ignore: Array[RID] = []
func _excluded() -> Array[RID]:
	var result: Array[RID] = [vehicle.get_rid()]
	result.append_array(ignore)
	return result
