extends RefCounted
## Máquina de estados da ultrapassagem, pertencente a um DispatchDriver.
##
##   idle -> waiting -> passing -> idle
##   passing -> holding_oncoming -> passing            (tráfego contrário: espera explícita)
##   passing -> returning -> idle                       (tráfego contrário antes/depois dos bloqueadores)
##   passing|returning -> recovering -> returning -> idle   (aborto, suspensão, pedido de parada)
##   holding_oncoming -> returning -> idle              (fora de "beside", com curva de retorno aprovada)
##
## Só age sobre carros ambiente em `traffic_yield_state` held/pulling. O carro
## continua sendo executado pelo Vehicle: aqui só se escolhe a curva que o
## DispatchDriver segue e o teto de velocidade. Nada de teletransporte, ré
## improvisada ou `controlled`: o DispatchVehicle/Vehicle já tratam a atribuição
## de dano (`is_player_damage_source`).
##
## Regra de recuperação: nunca se força uma manobra cuja varredura de casco
## falhe. Sem manobra livre, a viatura fica **parada e explícita**
## (`state`/`last_reason`/`unresolved`) e reavalia a cada 0,25 s.
##
## Dois relógios distintos, para não confundir "esperar" com "progredir":
##   - `_hold_age` / `_recover_age`: cada espera/tentativa (reiniciam entre tentativas);
##   - `episode_age`: o episódio inteiro fora do eixo, do primeiro aborto/espera até
##     voltar. NÃO reinicia com abortos repetidos, trocas de rota ou cancelamentos.
## `unresolved = true` (continua esperando) quando uma espera passa da paciência dela
## ou o episódio passa de EPISODE_PATIENCE. É o caso sem solução: o integrador vê e a
## unidade (DispatchUnit) usa `episode_age` para ENCERRAR O ATENDIMENTO, sem que isso
## mova, teleporte ou remova o veículo (remoção é outra chamada: `reset`).
##
## Eixo lembrado (`_axis`): a rota principal do início da manobra, congelada até a
## volta. Toda a geometria da recuperação (lateral, fase, retorno) é medida nela, não
## em `_driver.route`. Assim uma rota nula ou trocada no meio da manobra (perseguição
## replanejando, partida) não muda a referência, e o retorno continua com curva validada.

const RULES := preload("res://gameplay/dispatch/overtaking/OvertakeRules.gd")
const PLANNER := preload("res://gameplay/dispatch/overtaking/OvertakePlanner.gd")
const YIELD_MODEL := preload("res://gameplay/traffic_yield/YieldRoadModel.gd")

signal state_changed(state: String, reason: String)
signal unresolved_changed(unresolved: bool, reason: String)

var enabled := true
## Rua de mão dupla: permite ocupar a faixa contrária (só se estiver livre).
var allow_oncoming := true
var state := "idle"
var last_reason := ""
var bypass: Curve3D
var bypass_uses_oncoming := false
var speed_limit := INF
var wait_age := 0.0
## Esperando há tempo demais sem manobra livre (segue esperando; ver README).
var unresolved := false
var unresolved_reason := ""
## Segundos do episódio de recuperação em curso (0 fora de episódio). Só cresce em
## holding_oncoming / recovering / returning.
var episode_age := 0.0

var _driver: RefCounted
var _planner: RefCounted
var _eval := 0.0
var _passing_age := 0.0
var _stuck := 0.0
var _oncoming_clock := 0.0
var _cooldown := 0.0
var _hold_age := 0.0
var _recover_age := 0.0
var _in_episode := false
var _return_failures := 0
var _last_return_reason := ""
## Motivo que levou à recuperação (aborto, suspensão, parada pedida...).
var _cause := ""
## Rota principal congelada durante a manobra (ver cabeçalho). Nula fora dela.
var _axis: Curve3D
# Memória do desvio em curso (metros à frente da origem do eixo no início)
var _pass_origin := 0.0
var _first_start := 0.0
var _last_end := 0.0

func setup(p_driver: RefCounted, routes: RefCounted) -> void:
	_driver = p_driver
	var model := YIELD_MODEL.new()
	model.configure(routes)
	_planner = PLANNER.new()
	_planner.model = model

func is_waiting() -> bool:
	return state == "waiting"

func is_active() -> bool:
	return state in ["passing", "returning", "recovering", "holding_oncoming"]

func displaced() -> bool:
	return bypass != null or state == "recovering" or state == "holding_oncoming"

## Enquanto há manobra pendente (desvio em curso, espera pela faixa contrária,
## busca de retorno, retorno) ou caso sem solução, a viatura NÃO está
## estacionada, mesmo com velocidade zero: estacionar/desembarcar aí deixaria
## gente na faixa contrária ou ao lado do carro que cedeu.
func blocks_parking() -> bool:
	return is_active() or unresolved

## Voltando ao eixo com curva válida (o piloto pode andar mesmo com `hold`).
func is_moving_back() -> bool:
	return state == "returning" and bypass != null

## Recuperação FÍSICA em curso (espera na faixa contrária, busca de retorno ou retorno
## depois de aborto/tráfego). Passagem normal, espera pelo bloqueador e ociosidade não
## contam: é o que a unidade acumula em `recovery_total`.
func in_recovery() -> bool:
	return _in_episode and state in ["holding_oncoming", "recovering", "returning"]

## Fora do eixo, com o eixo lembrado: o piloto pode continuar a manobra (curva de
## desvio/retorno) mesmo sem rota principal. Sem isso ele só frearia no lugar.
func follows_without_route() -> bool:
	return _axis != null and displaced()

func _set_state(next: String, reason: String) -> void:
	last_reason = reason
	if state == next: return
	state = next
	state_changed.emit(next, reason)

func _set_unresolved(value: bool, reason: String = "") -> void:
	var new_reason := reason if value else ""
	if unresolved == value and unresolved_reason == new_reason: return
	unresolved = value
	unresolved_reason = new_reason
	unresolved_changed.emit(unresolved, unresolved_reason)

## Limpa "sem solução" só enquanto há progresso de verdade: com o episódio já além da
## paciência, ou com voltas que travaram demais, uma curva aprovada no momento não
## apaga o histórico (senão o sinal piscaria a cada tentativa).
func _clear_unresolved_on_progress() -> void:
	if episode_age > RULES.EPISODE_PATIENCE or _return_failures >= RULES.RETURN_MAX_FAILURES: return
	_set_unresolved(false)

func _begin_episode() -> void:
	if _in_episode: return
	_in_episode = true
	episode_age = 0.0
	_return_failures = 0

func _end_episode() -> void:
	_in_episode = false
	episode_age = 0.0
	_return_failures = 0

func _clear_pass() -> void:
	bypass = null
	_axis = null
	speed_limit = INF
	wait_age = 0.0
	_stuck = 0.0
	_passing_age = 0.0
	_hold_age = 0.0
	_recover_age = 0.0
	_eval = 0.0
	_end_episode()
	_set_unresolved(false)

## REMOÇÃO IMEDIATA (destruição, desligar, unidade liberada): descarta tudo. Não
## move nada: o piloto volta a seguir a rota principal com o que o Vehicle já faz.
## Para o veículo em jogo, a chamada é `cancel`, que recupera fisicamente.
func reset(reason: String) -> void:
	_clear_pass()
	if state != "idle": _set_state("idle", reason)
	else: last_reason = reason

## O piloto chegou ao fim do desvio: devolve o controle à rota principal.
func finish_bypass() -> void:
	_clear_pass()
	_cooldown = 1.0
	_set_state("idle", "returned_to_lane")

func on_stuck() -> void:
	if is_active() and state != "holding_oncoming": abort("stuck")

# --- Cancelamento / suspensão / rota -----------------------------------------------

## Suspensão/retomada, cancelamento externo ou partida: se o veículo está fora do
## eixo, recupera fisicamente (para e volta só com curva validada); se não, só
## descarta o plano. Pedido repetido durante uma recuperação já em curso NÃO a
## reinicia: relógios e curva de retorno válida são preservados.
func recover_if_displaced(reason: String) -> void:
	# Sem manobra em curso não há o que recuperar (a viatura só está no ruído normal da faixa).
	if state == "idle": return
	if state == "waiting":
		reset(reason)
		return
	var vehicle: CharacterBody3D = _driver.vehicle
	if _axis == null or not is_instance_valid(vehicle) or _planner.lateral_left(vehicle, _axis) < 0.3:
		reset(reason)
		return
	match state:
		"passing":
			# Ao lado dos bloqueadores voltar é impossível (o carro ao lado ocupa a faixa):
			# abortar descartaria o desvio e prenderia a viatura na faixa contrária. Segue
			# a passagem já validada; depois de suspensão ela para e revalida antes.
			if _phase() != "beside": abort(reason)
			elif reason == "resumed": _hold("resumed_revalidating")
			else: _cause = reason
		"recovering":
			_cause = reason
		"holding_oncoming":
			# Já está parada e explícita; a reavaliação revalida o desvio preservado
			# (`curve_clear`). Abortar aqui perderia a curva e, com o bloqueador ao lado,
			# o retorno nunca passaria mesmo com a faixa contrária livre.
			_cause = reason
		"returning":
			# Curva de retorno em andamento continua valendo, exceto depois de suspensão:
			# o mundo mudou enquanto ela estava congelada, então replaneja.
			if reason == "resumed": abort(reason)
			else: _cause = reason

## API de cancelamento (unidade encerrando, região trocando, integração).
func cancel(reason: String) -> void:
	recover_if_displaced(reason)

## O piloto recebeu ordem de parar (estacionar): termina a manobra antes de frear.
## `holding_oncoming`, `recovering` e `returning` já estão parados ou voltando com
## curva válida; não há o que abortar. `passing` aborta (volta à faixa) só antes ou
## depois dos bloqueadores; ao lado deles a passagem validada continua até o fim e a
## unidade estaciona depois (senão o `settle` gerava um retorno impossível).
func settle() -> void:
	if state == "waiting":
		reset("hold_requested")
	elif state == "passing" and _axis != null and _phase() != "beside":
		abort("hold_requested")

## Condição para a espera atual sair sozinha (ver `OvertakeRules.exit_condition`).
func exit_condition() -> String:
	return RULES.exit_condition(unresolved_reason if unresolved else last_reason)

## `set_route(null)`: sem manobra, descarta. Fora do eixo, o eixo lembrado segue como
## referência: o piloto continua a curva de desvio/retorno que já tinha (ver
## `follows_without_route`) e, se não havia curva, a recuperação planeja sobre o eixo.
func on_route_cleared() -> void:
	if not displaced(): reset("route_cleared")

## O piloto vai trocar a rota principal (a perseguição replaneja ~1 s). Durante a
## manobra a referência é o eixo lembrado, não a rota nova: não há memória a
## reancorar nem motivo para abortar. A rota nova só passa a valer quando a viatura
## volta ao eixo (`finish_bypass`). Fica como ponto de contrato do piloto.
func rebase_route(_new_route: Curve3D) -> void:
	pass

# --- Corredor à frente ----------------------------------------------------------

## Veículos (camada 4) na faixa à frente. Devolve {"yielding": [], "others": []}.
func _corridor() -> Dictionary:
	var vehicle: CharacterBody3D = _driver.vehicle
	var box := BoxShape3D.new()
	box.size = Vector3(vehicle.half_width * 2.0 + 0.6, 1.4, RULES.DETECT_AHEAD)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(vehicle.global_basis, vehicle.global_position - vehicle.global_basis.z * (vehicle.half_length + RULES.DETECT_AHEAD * 0.5) + Vector3.UP * 0.8)
	query.collision_mask = 4
	query.exclude = _driver._excluded()
	var result := {"yielding": [], "others": []}
	for hit in vehicle.get_world_3d().direct_space_state.intersect_shape(query, 8):
		var body: Object = hit.collider
		if not is_instance_valid(body) or body == vehicle: continue
		if str(body.get_meta("traffic_yield_state", "")) in RULES.YIELD_STATES: result.yielding.append(body)
		else: result.others.append(body)
	return result

func _nearest_gap(blockers: Array) -> float:
	var vehicle: CharacterBody3D = _driver.vehicle
	var forward := -vehicle.global_basis.z
	var best := INF
	for blocker in blockers:
		var separation: Vector3 = blocker.global_position - vehicle.global_position
		best = minf(best, separation.dot(forward) - blocker.half_length - vehicle.half_length)
	return best

# --- Laço -----------------------------------------------------------------------

func tick(delta: float) -> void:
	if not enabled: return
	# Sem rota principal só há o que fazer se a viatura está fora do eixo (eixo lembrado).
	if _driver.route == null and _axis == null: return
	if is_active() and _axis == null:
		# Não deveria acontecer (o eixo nasce com a manobra); sem eixo não há referência.
		reset("axis_lost")
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_eval -= delta
	_tick_episode(delta)
	match state:
		"idle":
			if _driver.route != null and _eval <= 0.0 and _cooldown <= 0.0 and not _driver.reversing and not _driver.holding:
				_eval = RULES.EVAL_INTERVAL
				_try_start()
		"waiting":
			wait_age += delta
			if wait_age > RULES.WAIT_MAX:
				# Chega de esperar: o piloto volta à recuperação normal (ré/novo plano).
				wait_age = 0.0
				_cooldown = RULES.WAIT_MAX
				_set_state("idle", "wait_timeout")
			elif _driver.route != null and _eval <= 0.0:
				_eval = RULES.EVAL_INTERVAL
				_try_start()
		"passing", "returning":
			_monitor(delta)
		"holding_oncoming":
			_tick_holding(delta)
		"recovering":
			speed_limit = 0.0
			_recover_age += delta
			if _eval <= 0.0:
				_eval = RULES.EVAL_INTERVAL
				_try_return()

## Relógio do episódio: corre em espera/recuperação/retorno; passa da paciência sem ter
## voltado ao eixo = sem solução (mesmo que cada tentativa individual ainda pareça viva).
func _tick_episode(delta: float) -> void:
	if not _in_episode or state not in ["holding_oncoming", "recovering", "returning"]: return
	episode_age += delta
	if episode_age > RULES.EPISODE_PATIENCE and not unresolved:
		_set_unresolved(true, "recovery_no_progress")

func _try_start() -> void:
	var vehicle: CharacterBody3D = _driver.vehicle
	if vehicle.engine_disabled: return
	var corridor := _corridor()
	var yielding: Array = corridor.yielding
	if yielding.is_empty():
		if state == "waiting": _set_state("idle", "blockers_gone")
		wait_age = 0.0
		return
	var trigger := maxf(RULES.TRIGGER_MIN, absf(vehicle.speed) * RULES.TRIGGER_SECONDS + 8.0)
	if _nearest_gap(yielding) > trigger and not _driver.blocked_ahead:
		# Ainda longe: nada a fazer, e o tempo de espera não corre.
		if state == "waiting": _set_state("idle", "not_yet")
		wait_age = 0.0
		return
	if not corridor.others.is_empty():
		_wait("non_yielding_vehicle_ahead")
		return
	for blocker in yielding:
		if absf(blocker.speed) > RULES.BLOCKER_MAX_SPEED:
			_wait("blocker_moving")
			return
	# A faixa contrária só com a sirene ligada: é o que torna a passagem legítima.
	var oncoming_ok := allow_oncoming and _siren_on()
	var plan: Dictionary = _planner.plan(vehicle, _driver.route, yielding, oncoming_ok, _driver.ignore)
	if not plan.ok:
		_wait(str(plan.reason))
		return
	_axis = _driver.route
	bypass = plan.curve
	bypass_uses_oncoming = plan.oncoming
	_pass_origin = plan.origin
	_first_start = plan.first_start
	_last_end = plan.last_end
	speed_limit = RULES.ONCOMING_SPEED if plan.oncoming else RULES.PASS_SPEED
	_passing_age = 0.0
	_stuck = 0.0
	_oncoming_clock = 0.0
	wait_age = 0.0
	_set_state("passing", "oncoming_lane" if plan.oncoming else "own_side")

func _siren_on() -> bool:
	var equipment: Variant = _driver.vehicle.equipment
	return is_instance_valid(equipment) and equipment.siren_on == true

func _wait(reason: String) -> void:
	if state != "waiting": wait_age = 0.0
	_set_state("waiting", reason)

# --- Durante o desvio -------------------------------------------------------------

## "before": ainda atrás do primeiro bloqueador; "beside": ao lado; "after": já passou.
func _phase() -> String:
	var vehicle: CharacterBody3D = _driver.vehicle
	var here: float = _planner.progress(_axis, _pass_origin, vehicle)
	if here + vehicle.half_length < _first_start - 0.3: return "before"
	if here - vehicle.half_length > _last_end + 0.3: return "after"
	return "beside"

## Faixa contrária à frente: {"margin": folga prevista ao terminar de sair dela
## (INF = nada à vista), "stationary": quem define essa folga está parado}.
func _oncoming_probe() -> Dictionary:
	var vehicle: CharacterBody3D = _driver.vehicle
	var here: float = _planner.progress(_axis, _pass_origin, vehicle)
	var to_exit := maxf(0.0, _last_end + vehicle.half_length - here) + RULES.RETURN_ALLOWANCE
	return _planner.oncoming_probe(vehicle, _driver.ignore, to_exit, absf(vehicle.speed))

func _monitor(delta: float) -> void:
	var vehicle: CharacterBody3D = _driver.vehicle
	_passing_age += delta
	if _passing_age > RULES.PASSING_MAX:
		abort("passing_timeout")
		return
	if vehicle.engine_disabled:
		abort("engine_disabled")
		return
	if _driver.blocked_ahead and absf(vehicle.speed) < 0.6: _stuck += delta
	else: _stuck = maxf(0.0, _stuck - delta)
	if _stuck > RULES.STUCK_ABORT:
		abort("blocked_while_passing")
		return
	_oncoming_clock -= delta
	if state == "passing" and bypass_uses_oncoming and _oncoming_clock <= 0.0:
		_oncoming_clock = RULES.EVAL_INTERVAL
		_react_to_oncoming()

## Tráfego contrário surgiu com a viatura na faixa contrária. Antes dos
## bloqueadores ou depois deles, sair para a direita é livre de bloqueador: tenta
## a curva de retorno validada. Ao lado deles, voltar é impossível: se a folga
## prevista ao sair não basta, para e espera, sem forçar.
func _react_to_oncoming() -> void:
	if float(_oncoming_probe().margin) >= RULES.SAFE_GAP: return
	var phase := _phase()
	if phase == "beside":
		_hold("oncoming_traffic")
		return
	if not _retreat("oncoming_traffic_" + phase):
		_hold("oncoming_traffic_return_blocked")

func _hold(reason: String) -> void:
	_begin_episode()
	speed_limit = 0.0
	_hold_age = 0.0
	_oncoming_clock = 0.0
	_eval = 0.0
	_set_state("holding_oncoming", reason)

## Curva de retorno ao eixo lembrado. Só existe se (1) o rumo da viatura ainda é
## compatível com o do eixo (sem meia-volta) e (2) alguma rampa (a normal ou uma mais
## suave) passa na varredura de casco completa. Senão devolve o motivo; nada é forçado.
func _plan_return() -> Dictionary:
	var vehicle: CharacterBody3D = _driver.vehicle
	var forward := -vehicle.global_basis.z
	forward.y = 0.0
	if _planner.heading_at(_axis, vehicle).dot(forward.normalized()) < RULES.RETURN_MIN_ALIGNMENT:
		return {"ok": false, "reason": "heading_mismatch"}
	var last := {"ok": false, "reason": "no_plan"}
	for scale in RULES.RETURN_RAMP_SCALES:
		var plan: Dictionary = _planner.plan(vehicle, _axis, [], true, _driver.ignore, true, scale)
		if plan.ok: return plan
		last = plan
		# Rampa mais longa não ajuda: sem grafo, ou já no eixo.
		if str(plan.reason) in ["no_graph", "already_in_lane"]: break
	return last

## Só a curva de retorno; falso se a varredura do casco não a aprovar.
func _retreat(reason: String) -> bool:
	var plan := _plan_return()
	if not plan.ok:
		_last_return_reason = str(plan.reason)
		return false
	_begin_episode()
	bypass = plan.curve
	bypass_uses_oncoming = false
	speed_limit = RULES.RETURN_SPEED
	_hold_age = 0.0
	_passing_age = 0.0
	_set_state("returning", reason)
	return true

## Parada explícita na faixa contrária: reavalia; volta a passar quando a folga
## prevista permite E o desvio preservado ainda passa na varredura, ou sai pela
## direita se já não há bloqueador ao lado.
func _tick_holding(delta: float) -> void:
	_hold_age += delta
	if _eval > 0.0: return
	_eval = RULES.EVAL_INTERVAL
	var vehicle: CharacterBody3D = _driver.vehicle
	if vehicle.engine_disabled:
		last_reason = "engine_disabled_waiting"
		_set_unresolved(true, "engine_disabled_while_displaced")
		return
	var probe := _oncoming_probe()
	var margin_ok: bool = float(probe.margin) >= RULES.SAFE_GAP
	if margin_ok:
		if _planner.curve_clear(vehicle, bypass, _driver.ignore):
			speed_limit = RULES.ONCOMING_SPEED
			_end_episode()
			_set_unresolved(false)
			_set_state("passing", "oncoming_cleared")
			return
		last_reason = "bypass_obstructed"
	var phase := _phase()
	if phase != "beside" and _retreat("oncoming_traffic_" + phase):
		_clear_unresolved_on_progress()
		return
	# Sem manobra livre: fica parado, reavalia, e declara o caso sem solução.
	if _hold_age > RULES.OPPOSING_PATIENCE:
		var why := "return_blocked_by_oncoming"
		if margin_ok: why = "bypass_obstructed"
		elif phase == "beside": why = "oncoming_stopped_ahead" if bool(probe.stationary) else "oncoming_deadlock"
		_set_unresolved(true, why)

## Algo mudou no meio do desvio: para e volta à faixa só quando o caminho estiver livre.
## Pedido repetido com a recuperação já em curso não reinicia nada (só atualiza a causa).
func abort(reason: String) -> void:
	if state == "recovering":
		_cause = reason
		return
	if not is_active() or _axis == null: return
	_begin_episode()
	if state == "returning":
		# Uma volta que travou: conta, para o episódio poder declarar "sem solução".
		_return_failures += 1
		if _return_failures >= RULES.RETURN_MAX_FAILURES: _set_unresolved(true, "return_failed_repeatedly")
	bypass = null
	speed_limit = 0.0
	_eval = 0.0
	_stuck = 0.0
	_recover_age = 0.0
	_cause = reason
	_set_state("recovering", reason)

func _try_return() -> void:
	var vehicle: CharacterBody3D = _driver.vehicle
	if vehicle.engine_disabled:
		last_reason = "engine_disabled_waiting"
		_set_unresolved(true, "engine_disabled_while_displaced")
		return
	var lateral: float = _planner.lateral_left(vehicle, _axis)
	if lateral < 0.2:
		_clear_pass()
		_set_state("idle", "already_in_lane")
		return
	var plan := _plan_return()
	if not plan.ok:
		# Sem caminho livre de volta: espera explícita, sem forçar nada.
		_last_return_reason = str(plan.reason)
		last_reason = "return_blocked:" + _last_return_reason
		if _recover_age > RULES.RECOVER_PATIENCE: _set_unresolved(true, "return_blocked:" + _last_return_reason)
		return
	bypass = plan.curve
	bypass_uses_oncoming = false
	speed_limit = RULES.RETURN_SPEED
	_passing_age = 0.0
	_recover_age = 0.0
	_clear_unresolved_on_progress()
	_set_state("returning", "returning_after_" + _cause)
