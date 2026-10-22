extends Node
## Low-priority resource I/O only. Never instantiate procedural worlds here:
## an indivisible _ready() cannot obey a main-thread time budget.
## Geometry/collision remain owned by the existing proximity streamer.
const MANIFEST := preload("res://runtime/RegionPreparationResources.gd")
const MAX_HELD := 128
var controller: Node
var pending: Array[Dictionary] = []
var held: Dictionary = {}
var seen: Dictionary = {}
var failed: Array[String] = []
var active_path := ""
var active_region := ""
var requested := 0
var loaded := 0
var cached := 0
var max_step_ms := 0.0
var start_delay := 120
var cooldown := 0

func _ready() -> void:
	process_priority = 1000

func enqueue(id: String) -> void:
	var paths: Array = MANIFEST.RESOURCES.get(id,[])
	for path in paths:
		request(str(path),id)

func request(path: String, id: String) -> void:
	if seen.has(path): return
	seen[path] = true
	pending.append({"path":path,"region":id})
	requested += 1
	set_process(true)

func take(id: String) -> void:
	# Prioritize newly needed resources; this never blocks a live mount waiting
	# for I/O. The normal loader/streamer remains authoritative at the destination.
	var urgent: Array[Dictionary] = []
	var other: Array[Dictionary] = []
	for task in pending:
		if task.region == id: urgent.append(task)
		else: other.append(task)
	urgent.append_array(other)
	pending = urgent

func status() -> Dictionary:
	return {"kind":"resources_only","pending":pending.size(),"active":active_path,"requested":requested,"loaded":loaded,"cached":cached,"held":held.size(),"failed":failed.duplicate(),"max_step_ms":max_step_ms}

func _process(delta: float) -> void:
	if not is_instance_valid(controller) or not controller.ready_for_play: return
	if controller.session == null or not controller.session.ready_for_play or controller.travel_busy or controller.session.has_position_transition(): return
	if start_delay > 0: start_delay -= 1; return
	if cooldown > 0: cooldown -= 1; return
	if delta > .020 or Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) > .006: return
	for resident in controller.regions.values():
		if not resident.is_streaming_idle(): return
	var began := Time.get_ticks_usec()
	_step()
	max_step_ms = maxf(max_step_ms,(Time.get_ticks_usec()-began)/1000.0)
	cooldown = 1
	controller.background_loading_status = status()

func _step() -> void:
	if not active_path.is_empty():
		var state := ResourceLoader.load_threaded_get_status(active_path)
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			# get() is permitted only after LOADED; otherwise it blocks the frame.
			var resource := ResourceLoader.load_threaded_get(active_path)
			if resource != null:
				if held.size() >= MAX_HELD: held.erase(held.keys()[0])
				held[active_path] = resource
				loaded += 1
		else:
			failed.append(active_path)
		active_path = ""
		active_region = ""
		return
	if pending.is_empty(): set_process(false); return
	var task: Dictionary = pending.pop_front()
	if ResourceLoader.has_cached(task.path) or _prefetched.has(task.path) or _prefetch_draining.has(task.path):
		# Existing consumers already hold this resource; don't inflate ownership.
		cached += 1
		return
	var error := ResourceLoader.load_threaded_request(task.path,"",false,ResourceLoader.CACHE_MODE_REUSE)
	if error != OK:
		failed.append(task.path)
		return
	active_path = task.path
	active_region = task.region

func _exit_tree() -> void:
	# Collect the engine's request without blocking teardown or keeping a world
	# alive. A static coroutine owns only the tree signal and resource path.
	if not active_path.is_empty():
		var script: GDScript = get_script()
		script.drain_request(get_tree(),active_path)
	pending.clear()
	held.clear()

## Busca antecipada sob a cortina (22/10). O manifesto é quase todo shader (46 de 59): carregado em
## thread, o shader_set_code e a compilação/leitura das variantes caem no thread principal no próximo
## RenderingServer.sync, já com o jogo rodando. No estresse de 22/10 apareciam quadros de 34–61 ms com
## 14 ms entre o último _process e o desenho, sem span e sem nó removido. Pedidos todos de uma vez no
## começo da carga, em paralelo com o resto, e recolhidos antes de a cortina sair; o que não chegar no
## prazo fica para a fila de sempre. GETECO_BG_PREFETCH=0 volta a carregar só depois de jogável.
static var _prefetched: Dictionary = {}
static var _prefetch_requested: Array[String] = []
static var _prefetch_draining: Dictionary = {}

static func prefetch_enabled() -> bool:
	return OS.get_environment("GETECO_BG_PREFETCH") != "0"

static func prefetch_start() -> void:
	if not prefetch_enabled() or not _prefetch_requested.is_empty(): return
	for id in MANIFEST.RESOURCES:
		for entry in MANIFEST.RESOURCES[id]:
			var path := str(entry)
			if _prefetched.has(path) or path in _prefetch_requested or ResourceLoader.has_cached(path): continue
			if ResourceLoader.load_threaded_request(path,"",false,ResourceLoader.CACHE_MODE_REUSE) == OK:
				_prefetch_requested.append(path)

## Espera os pedidos terminarem (até o prazo) e guarda os recursos pela sessão. Devolve quantos chegaram.
static func prefetch_collect(tree: SceneTree, deadline_msec: int) -> int:
	var collected := 0
	while not _prefetch_requested.is_empty():
		var still: Array[String] = []
		for path in _prefetch_requested:
			var state := ResourceLoader.load_threaded_get_status(path)
			if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				still.append(path)
			elif state == ResourceLoader.THREAD_LOAD_LOADED:
				var resource := ResourceLoader.load_threaded_get(path)
				if resource != null:
					_prefetched[path] = resource
					collected += 1
		_prefetch_requested = still
		if still.is_empty() or Time.get_ticks_msec() >= deadline_msec: break
		await tree.process_frame
	# Pedidos atrasados: drain_request recolhe sem travar e a fila do jogo não os pede de novo
	# (dois load_threaded_get do mesmo caminho dão erro).
	for path in _prefetch_requested:
		_prefetch_draining[path] = true
		_drain_prefetch(tree, path)
	_prefetch_requested.clear()
	return collected

static func _drain_prefetch(tree: SceneTree, path: String) -> void:
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		var resource := ResourceLoader.load_threaded_get(path)
		if resource != null: _prefetched[path] = resource
	_prefetch_draining.erase(path)

static func drain_request(tree: SceneTree, path: String) -> void:
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(path)
