extends SceneTree
## RegressÃ£o do contrato: um quadro rÃ¡pido tambÃ©m avanÃ§a a referÃªncia dos deltas.
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

func verify_optional_span_metadata(logger: LoggerProbe) -> void:
	var owner := Node.new()
	root.add_child(owner)
	logger._world = owner
	check(not owner.has_meta("perf_costs"), "trace disabled starts without optional span metadata")
	check(logger._spans_in_frame(0, Time.get_ticks_usec()).is_empty(), "missing span metadata yields no records without engine errors")
	logger._prune_spans()
	check(not owner.has_meta("perf_costs"), "pruning absent metadata does not create a trace buffer")
	owner.set_meta("perf_costs", "invalid optional payload")
	check(logger._spans_in_frame(0, Time.get_ticks_usec()).is_empty(), "wrong metadata type is ignored")
	logger._prune_spans()
	check(owner.get_meta("perf_costs") == "invalid optional payload", "pruning leaves unrelated metadata untouched")
	owner.set_meta("perf_costs", [])
	check(logger._spans_in_frame(0, Time.get_ticks_usec()).is_empty(), "empty span array stays empty")
	logger._prune_spans()
	check(owner.get_meta("perf_costs").is_empty(), "empty buffer pruning stays empty")
	var now := Time.get_ticks_usec()
	var rows: Array = []
	for duration in range(1, 11):
		rows.append({"label":"span_%02d" % duration,"start_usec":now,"duration_usec":duration*1000})
	rows.append({"label":"expired","start_usec":now-logger.SPAN_KEEP_USEC-1000000,"duration_usec":90000})
	rows.append({"label":"future","start_usec":now+1000000,"duration_usec":80000})
	rows.append("not a span")
	owner.set_meta("perf_costs", rows)
	var selected: Array = logger._spans_in_frame(now, now)
	check(selected.size() == logger.SPANS_PER_RECORD, "present spans retain the existing record limit")
	check(selected[0].label == "span_10" and selected[-1].label == "span_03", "present spans retain descending duration order and inclusive boundaries")
	check(selected[0].ms == 10.0 and selected[-1].ms == 3.0, "span microseconds still report exact milliseconds")
	check(not selected.any(func(row): return row.label in ["expired","future"]), "out-of-frame spans remain excluded")
	logger._prune_spans()
	var kept: Array = owner.get_meta("perf_costs")
	check(kept.size() == 11 and not kept.any(func(row): return row.label == "expired"), "pruning removes expired and non-dictionary entries")
	check(kept[-1].label == "future", "pruning preserves the existing unexpired future-row contract")
	logger._world = null
	owner.free()

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
	check(logger.captured.is_empty(), "quadro rÃ¡pido nÃ£o gera registro lento")
	check(logger._last_nodes == baseline + 1, "quadro rÃ¡pido avanÃ§a a amostra de nÃ³s")
	check(logger._last_objects == int(Performance.get_monitor(Performance.OBJECT_COUNT)), "quadro rÃ¡pido avanÃ§a a amostra de objetos")
	var slow_node := Node.new()
	root.add_child(slow_node)
	logger._threshold_ms = 0.0
	logger._process(0.0)
	check(logger.captured.size() == 1, "quadro seguinte gera um registro lento")
	if logger.captured.is_empty():
		quit(1)
		return
	check(int(logger.captured[0].nodes_delta) == 1, "delta lento exclui criaÃ§Ã£o ocorrida antes da amostra rÃ¡pida")
	check(logger.captured[0].has("process_frame") and logger.captured[0].has("delta_interval_ms"), "registro identifica quadro e intervalo amostrado")
	WORK.enabled = true
	var began := WORK.begin()
	WORK.finish("fixture.work", began, {"region": "fixture"})
	logger._process(0.0)
	check(logger.captured[1].work.size() == 1 and logger.captured[1].work[0].label == "fixture.work", "trabalho medido acompanha o registro do intervalo")
	check(WORK.take().is_empty(), "evento consumido nÃ£o reaparece no quadro seguinte")
	for i in WORK.MAX_EVENTS:
		WORK.events.append({"label": "fixture.fast", "ms": 0.01})
	WORK.finish_slow("fixture.critical", Time.get_ticks_usec()-20000)
	var saturated := WORK.take()
	check(saturated.any(func(event): return event.label == "fixture.critical"), "pico Ã© preservado quando buffer estÃ¡ cheio de eventos rÃ¡pidos")
	check(saturated[-1].label == "trace.events_dropped" and saturated[-1].count == 1, "substituiÃ§Ã£o no buffer informa perda")
	WORK.enabled = false
	check(WORK.begin() == 0, "mediÃ§Ã£o desativada nÃ£o abre evento")
	WORK.finish("fixture.disabled", Time.get_ticks_usec())
	check(WORK.take().is_empty(), "mediÃ§Ã£o desativada nÃ£o acumula eventos")
	var observed: Array[Dictionary] = []
	logger._threshold_ms = 1000000.0
	logger.interval_observed.connect(func(now, work, removed, roots):
		observed.append({"now":now,"work":work,"removed":removed,"roots":roots.duplicate()}))
	logger._process(0.0)
	check(observed.is_empty(), "optional interval observer is disabled by default")
	logger.observe_intervals = true
	WORK.enabled = true
	WORK.finish("fixture.circular", WORK.begin())
	logger._process(0.0)
	check(observed.size() == 1 and observed[0].now > 0 and observed[0].work.size() == 1 and observed[0].work[0].label == "fixture.circular", "fast interval forwards work to circular observer")
	check(WORK.take().is_empty(), "circular observer does not consume or duplicate work a second time")
	logger.observe_intervals = false
	WORK.enabled = false
	logger._process(0.0)
	check(observed.size() == 1, "disabled observer stops retaining intervals")
	var census_nodes: Array[Node] = []
	for i in 300:
		var census_node := Node.new()
		root.add_child(census_node)
		census_nodes.append(census_node)
	logger._start_census()
	# Simula nÃ³ jÃ¡ descoberto numa fatia e excluÃ­do antes de ser visitado.
	logger._census_pending.append(census_nodes[0])
	census_nodes[0].free()
	logger._advance_census()
	check((logger._census_seen.has(root.get_instance_id()) or (logger._census_pending.is_empty() and int(logger._census_ready.get("nodes_visited", 0)) >= 299)), "nÃ³ excluÃ­do jÃ¡ enfileirado nÃ£o aborta a prÃ³xima fatia")
	for i in 100:
		logger._advance_census()
		if logger._census_pending.is_empty(): break
	check(logger._census_pending.is_empty() and not logger._census_ready.is_empty(), "censo fatiado conclui sem acessar o nÃ³ excluÃ­do")
	check(int(logger._census_ready.classes.get("Node", 0)) >= 299, "censo completo inclui os nÃ³s vivos da fixture")
	check(logger._census_ready.has("started_t") and logger._census_ready.has("finished_t") and logger._census_ready.has("sampling_ms"), "censo identifica intervalo da coleta")
	check(not logger._census_ready.scripts.has(""), "scripts embutidos tÃªm chave JSON nÃ£o vazia")
	for census_node in census_nodes:
		if is_instance_valid(census_node): census_node.free()
	verify_optional_span_metadata(logger)
	logger.free()
	fast_node.free()
	slow_node.free()
	print("STALL_LOG_INTERVALS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
