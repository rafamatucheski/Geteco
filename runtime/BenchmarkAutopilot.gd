extends RefCounted
## Piloto automático do benchmark de release (`--benchmark-drive`, 15/10/2026).
##
## O benchmark normal teleporta o carro do jogador pela rota com a física dele desligada: mede
## streaming, desenho e população, mas não o custo de dirigir de verdade (V1Handling,
## move_and_slide, StreetPhysics antes/depois do movimento, pneus/fumaça/escape, colisão com
## trânsito e mobília). Aqui o carro anda com a própria física, pela mesma rota e na mesma
## velocidade-alvo, e a direção vem das ações de entrada que o jogador usaria (acelerar, frear,
## esquerda, direita), então o caminho de código é o mesmo do jogo.
##
## Opções: `--benchmark-drive-lane=<m>` desloca a linha seguida para a direita da rota
## (padrão 1,8 m, para não andar na contramão do trânsito em rua de mão dupla).
## Carro preso (batida, mobília, trânsito parado) por PATIENCE segundos volta para a rota
## alguns metros à frente; `recoveries` no relatório conta quantas vezes.
const LOOKAHEAD_MIN := 6.0
const CORNER_SLOWDOWN_DISTANCE := 14.0
const CORNER_SPEED := 6.0
const PATIENCE := 4.0
const STUCK_PROGRESS := 2.0
const RECOVERY_SKIP := 4.0
## A rota é desenhada no chão; 8 m abaixo dela já é queda, não rampa nem desnível de rua.
const FALL_TOLERANCE := 8.0

var bench: Node
var car: CharacterBody3D
var speed_target := 12.0
var lane := 1.8
var progress := 0.0
var recoveries := 0
var falls := 0
var _starts: Array[Vector3] = []
var _directions: Array[Vector3] = []
var _lengths: Array[float] = []
var _cumulative: Array[float] = []
var _total := 0.0
var _stuck_clock := 0.0
var _stuck_progress := 0.0
var _speed_sum := 0.0
var _speed_samples := 0
## Quadros com o 3D desligado ou o jogo pausado (filme, menu, transição). A primeira rodada de
## validação (editor, 15/10) teve draw calls p50 = 12: algo tirou o mundo da tela durante a
## direção. Contar aqui deixa a fase 2 separar isso do custo de dirigir.
var frames_3d_off := 0
var frames_paused := 0

func _init(benchmark: Node, vehicle: CharacterBody3D, route: Array, target_speed: float) -> void:
	bench = benchmark
	car = vehicle
	speed_target = target_speed
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--benchmark-drive-lane="): lane = float(argument.trim_prefix("--benchmark-drive-lane="))
	for index in route.size():
		var a: Vector3 = route[index]
		var b: Vector3 = route[(index + 1) % route.size()]
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		_starts.append(a)
		_directions.append(flat.normalized())
		_lengths.append(flat.length())
		_cumulative.append(_total)
		_total += flat.length()

static func requested() -> bool:
	return "--benchmark-drive" in OS.get_cmdline_user_args()

## Põe o carro no começo da rota, parado, com a física ligada e conduzido.
func begin() -> void:
	_place(0.0)
	car.controlled = true
	car.external_input = false
	car.input_locked = false
	car.set_physics_process(true)

## Um passo por quadro: lê onde o carro está, decide pedais e volante. Devolve a distância
## percorrida ao longo da rota (monotônica), que o benchmark usa no lugar do relógio.
func drive(delta: float) -> float:
	if bench.get_viewport().disable_3d: frames_3d_off += 1
	if bench.get_tree().paused: frames_paused += 1
	_advance_progress()
	var speed := absf(float(car.get("speed")))
	_speed_sum += speed
	_speed_samples += 1
	# Caiu pelo chão: o progresso projeta só x/z, então o carro em queda continuava "andando" a
	# rota no ar e nunca contava como preso (dirigindooeste_2 de 16/10 terminou em y≈-11400 com
	# 11 draw calls na mediana). Volta para a rota na hora e conta à parte.
	if car.global_position.y < _lane_point(progress).y - FALL_TOLERANCE:
		falls += 1
		recoveries += 1
		_place(progress)
		_stuck_progress = progress
		_stuck_clock = 0.0
		_release()
		return progress
	# Preso: pouco avanço na rota por PATIENCE segundos.
	_stuck_clock += delta
	if progress - _stuck_progress >= STUCK_PROGRESS:
		_stuck_progress = progress
		_stuck_clock = 0.0
	elif _stuck_clock >= PATIENCE:
		recoveries += 1
		progress += RECOVERY_SKIP
		_place(progress)
		_stuck_progress = progress
		_stuck_clock = 0.0
		_release()
		return progress
	var target := _lane_point(progress + maxf(LOOKAHEAD_MIN, speed * .8))
	var to_target := target - car.global_position
	to_target.y = 0
	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var error := wrapf(desired_yaw - car.rotation.y, -PI, PI)
	# Erro positivo = alvo à esquerda; no jogo, esquerda aumenta o yaw.
	var steer := clampf(error / .45, -1.0, 1.0)
	var wanted := speed_target
	if _distance_to_corner() < CORNER_SLOWDOWN_DISTANCE or absf(error) > .6: wanted = CORNER_SPEED
	var pedal := clampf((wanted - speed) * .35, -1.0, 1.0)
	_press("move_left", maxf(0.0, steer))
	_press("move_right", maxf(0.0, -steer))
	_press("accelerate", maxf(0.0, pedal))
	_press("brake", maxf(0.0, -pedal) if speed > .5 else 0.0)
	return progress

func finish() -> void:
	_release()

func summary() -> Dictionary:
	return {"recoveries": recoveries, "falls": falls,"mean_speed_mps": snappedf(_speed_sum / maxf(1, _speed_samples), .01),
		"lane_offset_m": lane, "distance_m": snappedf(progress, .1), "frames_3d_off": frames_3d_off, "frames_paused": frames_paused}

func _press(action: StringName, strength: float) -> void:
	if not InputMap.has_action(action): return
	if strength > .01: Input.action_press(action, strength)
	else: Input.action_release(action)

func _release() -> void:
	for action in [&"move_left", &"move_right", &"accelerate", &"brake"]:
		if InputMap.has_action(action): Input.action_release(action)

func _segment_at(distance: float) -> int:
	var along := fposmod(distance, _total)
	for index in _lengths.size():
		if along < _cumulative[index] + _lengths[index]: return index
	return _lengths.size() - 1

func _lane_point(distance: float) -> Vector3:
	var index := _segment_at(distance)
	var along := fposmod(distance, _total) - _cumulative[index]
	var direction := _directions[index]
	# Direita da direção de marcha (-Z é frente; direita = frente × cima).
	var right := direction.cross(Vector3.UP)
	return _starts[index] + direction * along + right * lane

## Projeta o carro no trecho atual e no seguinte; só avança (no máximo 20 m por quadro).
func _advance_progress() -> void:
	var loop_start := floorf(progress / _total) * _total
	var index := _segment_at(progress)
	var best := progress
	var best_gap := INF
	for step in 2:
		var segment := (index + step) % _lengths.size()
		var base := loop_start + _cumulative[segment] + (_total if index + step >= _lengths.size() else 0.0)
		var offset := (car.global_position - _starts[segment])
		offset.y = 0
		var t := clampf(offset.dot(_directions[segment]), 0.0, _lengths[segment])
		var gap := (offset - _directions[segment] * t).length()
		if gap < best_gap:
			best_gap = gap
			best = base + t
	if best > progress and best - progress < 20.0: progress = best

func _distance_to_corner() -> float:
	var index := _segment_at(progress)
	return _cumulative[index] + _lengths[index] - fposmod(progress, _total)

func _place(distance: float) -> void:
	var point := _lane_point(distance)
	var direction := _directions[_segment_at(distance)]
	# Pousa no chão de verdade: a rota é em y=0 e a calçada/asfalto da cidade fica a
	# ~0,12 m; com +0,1 o carro nascia dentro do piso e às vezes atravessava o mundo
	# (dirigindooeste_1 da fase 2 terminou em y=-3190).
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 30.0, point + Vector3.DOWN * 30.0, 1)
	query.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): point.y = float(hit.position.y)
	car.global_position = point + Vector3.UP * .35
	car.rotation = Vector3(0, atan2(-direction.x, -direction.z), 0)
	car.set("speed", 0.0)
	car.set("horizontal_velocity", Vector3.ZERO)
	car.velocity = Vector3.ZERO
	if car.get("handling") != null and car.handling.has_method("reset"): car.handling.reset()
	car.reset_physics_interpolation()
