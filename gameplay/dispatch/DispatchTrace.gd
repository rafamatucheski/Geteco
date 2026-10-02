extends RefCounted
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Diagnóstico TEMPORÁRIO do custo de despacho, polícia e emergência sob carga.
## Desligado por padrão: só liga quando o mundo tem o meta `benchmark_trace` (o mesmo
## que os medidores existentes já ligam). Desligado, cada gancho é uma chamada
## que lê uma variável estática e retorna.
##
## Grava em `world.perf_costs`, o mesmo destino e formato dos demais rastros:
##  - `{label, start_usec, duration_usec, ...}` para cada trecho >= SLOW_USEC;
##  - a cada SUMMARY_USEC, um `dispatch.summary` com contagem, soma e máximo por rótulo,
##    o censo de unidades por serviço/estado e os contadores de física 3D do motor.
## Trechos aninhados se sobrepõem (`controller.tick` contém o `unit.tick` de cada unidade).
## O conjunto de rótulos é fechado (serviço, estado, arquétipo): não cresce com o tempo.
## Identifica custos diretos do despacho por etapa. O monitor do motor tem outra
## janela temporal: não subtraí-lo dos trechos para calcular um custo residual.

const SLOW_USEC := 2000
const SUMMARY_USEC := 1000000
const MAX_RECORDS := 512
## O buffer é compartilhado com os outros rastros e tem teto de 512: os trechos lentos
## avulsos param antes, para que os resumos por segundo nunca fiquem sem lugar.
const SLOW_RECORD_LIMIT := 384

static var on := false
static var _world: Node
static var _spans: Dictionary = {}
static var _window_start := 0
static var _window_physics_frames := 0
static var _controller_ticks := 0

static func refresh(world: Node) -> void:
	var active := is_instance_valid(world) and bool(world.get_meta("benchmark_trace", false))
	# A new world or a trace toggle starts a fresh measurement window.
	if not is_instance_valid(_world) or _world != world or active != on:
		_spans.clear()
		_window_start = 0
		_window_physics_frames = 0
		_controller_ticks = 0
	_world = world
	on = active

## 0 quando desligado; os ganchos tratam 0 como "não medir".
static func begin() -> int:
	return Time.get_ticks_usec() if on else 0

static func end(label: String, began: int, detail: Dictionary = {}) -> void:
	if began == 0: return
	var elapsed := Time.get_ticks_usec() - began
	# O buffer perf_costs pode saturar antes da poda; manter picos no canal por quadro.
	if elapsed >= 20000: STALL_WORK.finish_slow("dispatch." + label, began, 20000)
	var span: Variant = _spans.get(label)
	if span == null:
		_spans[label] = [1, elapsed, elapsed]
	else:
		span[0] += 1
		span[1] += elapsed
		span[2] = maxi(span[2], elapsed)
	if elapsed < SLOW_USEC or not is_instance_valid(_world): return
	var costs: Array = _world.get_meta("perf_costs", [])
	if costs.size() >= SLOW_RECORD_LIMIT: return
	var entry := {"label": label, "start_usec": began, "duration_usec": elapsed}
	entry.merge(detail)
	costs.append(entry)
	_world.set_meta("perf_costs", costs)

## Uma vez por quadro físico, ao fim do laço do controlador.
static func flush(controller: Node) -> void:
	if not on: return
	_controller_ticks += 1
	var now := Time.get_ticks_usec()
	if _window_start == 0:
		_window_start = now
		_window_physics_frames = Engine.get_physics_frames()
		return
	if now - _window_start < SUMMARY_USEC: return
	var spans := {}
	for label in _spans:
		var span: Array = _spans[label]
		spans[label] = {"n": span[0], "sum_us": span[1], "max_us": span[2]}
	var census := {"units": controller.units.size(), "wrecks": controller.wrecks.size(), "foot_officers": controller.foot_officer_count()}
	for unit in controller.units:
		var key := "%s:%s%s" % [unit.service, unit.state, ":suspended" if unit.suspended else ""]
		census[key] = int(census.get(key, 0)) + 1
	var entry := {
		"label": "dispatch.summary", "start_usec": _window_start, "duration_usec": now - _window_start,
		# Keep the legacy key as an alias, with the exact number of controller calls.
		"physics_ticks": _controller_ticks, "controller_ticks": _controller_ticks,
		# Engine counter delta since the first flush (separate from callback count).
		"engine_physics_ticks": Engine.get_physics_frames() - _window_physics_frames,
		"spans": spans, "census": census,
		# Máximo do último segundo (o motor só atualiza este monitor uma vez por segundo).
		"physics_process_max_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"phys3d": {
			"active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			"collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			"islands": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		},
	}
	_spans = {}
	_window_start = now
	_window_physics_frames = Engine.get_physics_frames()
	_controller_ticks = 0
	if not is_instance_valid(_world): return
	var costs: Array = _world.get_meta("perf_costs", [])
	if costs.size() >= MAX_RECORDS: return
	costs.append(entry)
	_world.set_meta("perf_costs", costs)
