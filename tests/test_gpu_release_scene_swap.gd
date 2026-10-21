extends SceneTree
## GpuReleaseQueue quando a cena dona é liberada no meio da desmontagem (troca do Main: recarga fria,
## load_game). A fila é estática; antes, os nós já liberados que ela ainda guardava eram atribuídos a
## variáveis tipadas (Node) antes da checagem de validade e cada quadro imprimia "Trying to assign
## invalid previously freed instance" em _drain_roots (milhares de linhas no teste do ato 2, 20/10).
## Sem mundo, segundos: conta os erros com um Logger e confere que a fila esvazia.
const RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
var checks := 0
var failures: Array[String] = []

class ErrorCounter extends Logger:
	var errors := 0
	var first := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors += 1
		if first.is_empty(): first = "%s:%d %s %s %s" % [file, line, function, code, rationale]
	func _log_message(_message: String, _error: bool) -> void:
		pass

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): failures.append("watchdog 60 s"); finish())
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("GPU_SCENE_SWAP ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

## Uma subárvore grande o bastante para a desmontagem levar vários quadros (orçamento de 0,8 ms).
## Folhas com malha própria vão para a espera de vídeo (4 por quadro): só no caso pequeno.
func build(parent: Node, breadth: int, depth: int, mesh_leaves: bool) -> void:
	for i in breadth:
		var child := Node3D.new() if depth > 0 or not mesh_leaves else MeshInstance3D.new()
		if child is MeshInstance3D: (child as MeshInstance3D).mesh = BoxMesh.new()
		parent.add_child(child)
		if depth > 0: build(child, breadth, depth - 1, mesh_leaves)

func scene_with_retired_branch(breadth := 14, depth := 3, mesh_leaves := false) -> Node3D:
	var scene := Node3D.new()
	scene.name = "OldMain"
	root.add_child(scene)
	var branch := Node3D.new()
	scene.add_child(branch)
	build(branch, breadth, depth, mesh_leaves)
	return scene

func run() -> void:
	if not check(RELEASE.enabled(), "fila ligada (sem GETECO_GPU_RELEASE_QUEUE=0)"): finish(); return
	var counter := ErrorCounter.new()
	var deadline := 0
	OS.add_logger(counter)
	# Caso 1: a cena dona é liberada com a desmontagem pela metade (pilha com nós da cena antiga).
	var scene := scene_with_retired_branch()
	RELEASE.retire(scene.get_child(0))
	await process_frame
	await process_frame
	check(RELEASE.pending() > 0, "desmontagem ainda em andamento quando a cena sai")
	scene.free()
	for i in 10: await process_frame
	check(counter.errors == 0, "cena liberada no meio da desmontagem não gera erro (%d; primeiro: %s)" % [counter.errors, counter.first])
	check(RELEASE.pending() == 0, "fila esvazia depois da troca de cena (%d)" % RELEASE.pending())
	# Caso 2: a cena sai antes do primeiro quadro de desmontagem (raiz já liberada no topo da fila).
	scene = scene_with_retired_branch()
	RELEASE.retire(scene.get_child(0))
	scene.free()
	for i in 5: await process_frame
	check(counter.errors == 0, "raiz liberada antes de começar não gera erro (%d; primeiro: %s)" % [counter.errors, counter.first])
	check(RELEASE.pending() == 0, "fila vazia com a raiz liberada (%d)" % RELEASE.pending())
	# Caso 4 (o do log, linha 128): a raiz continua válida, mas um nó que está na pilha da desmontagem
	# foi liberado por fora (parte da cena antiga liberada antes do galho). Antes o erro abortava a
	# função no mesmo ponto a cada quadro, para sempre.
	scene = scene_with_retired_branch()
	RELEASE.retire(scene.get_child(0))
	await process_frame
	await process_frame
	var stacked: Array = RELEASE._stack.duplicate()
	if check(stacked.size() >= 2, "pilha da desmontagem com nós (%d)" % stacked.size()):
		(stacked[stacked.size() - 1] as Node).free()
	for i in 10: await process_frame
	check(counter.errors == 0, "nó da pilha liberado por fora não gera erro (%d; primeiro: %s)" % [counter.errors, counter.first])
	deadline = Time.get_ticks_msec() + 15000
	while RELEASE.pending() > 0 and Time.get_ticks_msec() < deadline: await process_frame
	check(RELEASE.pending() == 0, "fila esvazia mesmo assim (%d)" % RELEASE.pending())
	scene.free()
	# Caso 3: o caminho normal continua liberando tudo, folhas com malha inclusive.
	scene = scene_with_retired_branch(4, 2, true)
	var before := RELEASE.debug_snapshot()
	RELEASE.retire(scene.get_child(0))
	deadline = Time.get_ticks_msec() + 15000
	while RELEASE.pending() > 0 and Time.get_ticks_msec() < deadline: await process_frame
	var after := RELEASE.debug_snapshot()
	check(RELEASE.pending() == 0 and scene.get_child_count() == 0, "desmontagem normal termina e tira o galho da cena")
	check(int(after.released_gpu) > int(before.released_gpu), "folhas com malha passam pela espera de vídeo (%d)" % (int(after.released_gpu) - int(before.released_gpu)))
	check(counter.errors == 0, "nenhum erro no caminho normal (%d)" % counter.errors)
	scene.free()
	OS.remove_logger(counter)
	finish()

func finish() -> void:
	print("GPU_SCENE_SWAP checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
