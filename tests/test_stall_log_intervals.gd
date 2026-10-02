extends SceneTree
## Regressão do contrato: um quadro rápido também avança a referência dos deltas.
const WORK := preload("res://runtime/StallWorkTrace.gd")

class LoggerProbe extends "res://runtime/StallLog.gd":
	var captured: Array[Dictionary] = []
	func _ready() -> void: pass
	func _playing() -> bool: return true
	func _ensure_world() -> void: pass
	func _write(record: Dictionary) -> void: captured.append(record.duplicate(true))

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	create_timer(10.0).timeout.connect(func(): push_error("STALL_LOG_INTERVALS timeout"); quit(2))
	var logger := LoggerProbe.new()
	root.add_child(logger)
	logger.set_process(false)
	logger._enabled = true
	logger._started_usec = Time.get_ticks_usec()
	logger._last_prune_usec = logger._started_usec
	logger._threshold_ms = 1000000.0
	logger._process(0.0)
	var baseline := logger._last_nodes
	var fast_node := Node.new()
	root.add_child(fast_node)
	logger._process(0.0)
	check(logger.captured.is_empty(), "quadro rápido não gera registro lento")
	check(logger._last_nodes == baseline + 1, "quadro rápido avança a amostra de nós")
	check(logger._last_objects == int(Performance.get_monitor(Performance.OBJECT_COUNT)), "quadro rápido avança a amostra de objetos")
	var slow_node := Node.new()
	root.add_child(slow_node)
	logger._threshold_ms = 0.0
	logger._process(0.0)
	check(logger.captured.size() == 1, "quadro seguinte gera um registro lento")
	if logger.captured.is_empty():
		quit(1)
		return
	check(int(logger.captured[0].nodes_delta) == 1, "delta lento exclui criação ocorrida antes da amostra rápida")
	check(logger.captured[0].has("process_frame") and logger.captured[0].has("delta_interval_ms"), "registro identifica quadro e intervalo amostrado")
	WORK.enabled = true
	var began := WORK.begin()
	WORK.finish("fixture.work", began, {"region": "fixture"})
	logger._process(0.0)
	check(logger.captured[1].work.size() == 1 and logger.captured[1].work[0].label == "fixture.work", "trabalho medido acompanha o registro do intervalo")
	check(WORK.take().is_empty(), "evento consumido não reaparece no quadro seguinte")
	for i in WORK.MAX_EVENTS:
		WORK.events.append({"label": "fixture.fast", "ms": 0.01})
	WORK.finish_slow("fixture.critical", Time.get_ticks_usec()-20000)
	var saturated := WORK.take()
	check(saturated.any(func(event): return event.label == "fixture.critical"), "pico é preservado quando buffer está cheio de eventos rápidos")
	check(saturated[-1].label == "trace.events_dropped" and saturated[-1].count == 1, "substituição no buffer informa perda")
	WORK.enabled = false
	check(WORK.begin() == 0, "medição desativada não abre evento")
	WORK.finish("fixture.disabled", Time.get_ticks_usec())
	check(WORK.take().is_empty(), "medição desativada não acumula eventos")
	var census_nodes: Array[Node] = []
	for i in 300:
		var census_node := Node.new()
		root.add_child(census_node)
		census_nodes.append(census_node)
	logger._start_census()
	# Simula nó já descoberto numa fatia e excluído antes de ser visitado.
	logger._census_pending.append(census_nodes[0])
	census_nodes[0].free()
	logger._advance_census()
	check(logger._census_seen.has(root.get_instance_id()), "nó excluído já enfileirado não aborta a próxima fatia")
	for i in 100:
		logger._advance_census()
		if logger._census_pending.is_empty(): break
	check(logger._census_pending.is_empty() and not logger._census_ready.is_empty(), "censo fatiado conclui sem acessar o nó excluído")
	check(int(logger._census_ready.classes.get("Node", 0)) >= 299, "censo completo inclui os nós vivos da fixture")
	check(logger._census_ready.has("started_t") and logger._census_ready.has("finished_t") and logger._census_ready.has("sampling_ms"), "censo identifica intervalo da coleta")
	check(not logger._census_ready.scripts.has(""), "scripts embutidos têm chave JSON não vazia")
	for census_node in census_nodes:
		if is_instance_valid(census_node): census_node.free()
	logger.free()
	fast_node.free()
	slow_node.free()
	print("STALL_LOG_INTERVALS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
