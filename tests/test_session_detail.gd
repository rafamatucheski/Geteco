extends SceneTree
const OPS := preload("res://runtime/SessionOperations.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sink := root.get_node("SessionDiagnostics")
	var probe := Node.new()
	root.add_child(probe)
	# Deixa a janela de incidentes do início terminar antes de provocar uma travada separada.
	await create_timer(2.5).timeout
	var token := OPS.begin(probe, "test_loader", "blocking_load", {"region":"fixture"})
	push_error("SESSION_DETAIL intentional error during load")
	# O watchdog do gravador precisa manter a etapa ativa mesmo com a thread principal bloqueada.
	OS.delay_msec(6200)
	OPS.finish(token)
	await process_frame
	# Força o consumo dentro de um intervalo rápido; os detalhes não podem depender de frame_spike.
	var profiler := sink.get_node("SystemProfile")
	profiler.call("_process", 0.0)
	# Este intervalo sintético começa DEPOIS do callback de preparação chamado à mão.
	# O agendamento real de quadros do motor é coberto pelo runner renderizado.
	profiler.set("_previous", Time.get_ticks_usec())
	var began := WORK.begin()
	OS.delay_msec(3)
	WORK.finish("fixture.small_work", began, {"region":"fixture", "queued_after":7})
	profiler.call("_process", 0.0)
	# Mais spans que o limite de detalhes: as chamadas agregadas sobrevivem, as omissões são explícitas.
	for i in 20:
		began = WORK.begin()
		OS.delay_msec(3)
		WORK.finish("fixture.bounded", began)
	profiler.call("_process", 0.0)
	began = WORK.begin()
	WORK.finish("retire.fixture", began, {"queued_after":7})
	profiler.call("_process", 0.0)
	sink.call("RecordProfile", "not valid json")
	await create_timer(1.2).timeout
	OPS.begin(probe, "test_loader", "unfinished", {})
	print("SESSION_DETAIL_PATH ", sink.get("LogPath"))
	probe.queue_free()
	quit()
