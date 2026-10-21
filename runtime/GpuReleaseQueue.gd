extends RefCounted
## Liberação gradual de recursos de vídeo (16/10/2026).
##
## Na emenda da ponte o quadro isolado de 290-630 ms tem a thread principal presa numa trava do driver
## NVIDIA (RtlAcquireSRWLockExclusive dentro do nvoglv64) enquanto uma thread do driver, disparada pelo
## dxcore, executa NtGdiDdDDIDestroyAllocation2: o driver destrói memória de vídeo segurando a trava
## (pilhas em docs/perf-cross-20261015-phase2.md). Descartar de uma vez um trecho da ferrovia, um bloco de
## grama ou a conexão da ponte solta dezenas de buffers num quadro só.
##
## Quem descarta entrega o nó aqui. Ele some do jogo na hora (escondido, sem processo e sem física: o
## CollisionObject3D sai do espaço com o modo desligado) e é liberado aos poucos: folhas sem recurso de
## vídeo próprio num orçamento de CPU por quadro; folhas que seguram o último dono de uma malha ou
## MultiMesh esperam DELAY_MSEC e saem no máximo algumas por quadro.
##
## Interruptores (lidos uma vez), para A/B no jogo:
## - GETECO_GPU_RELEASE_QUEUE=0: volta ao queue_free imediato de antes.
## - GETECO_GPU_HOLD_ALL=1: diagnóstico, nunca libera as folhas com recurso de vídeo (a memória cresce);
##   se a travada da ponte sumir assim, a causa é a liberação.
## - GETECO_GPU_RELEASE_PER_FRAME=N: folhas com recurso de vídeo liberadas por quadro (padrão 4).

const CPU_BUDGET_USEC := 800
const DEFAULT_GPU_LEAVES_PER_FRAME := 4
## Espera antes de soltar a memória de vídeo: no instante da troca de trechos a placa já recebe o que
## entra; a liberação fica para depois, espalhada.
const DELAY_MSEC := 1500
## Subárvore entregue continua na árvore (escondida) enquanto é desmontada, e o NativeRegion faz o mesmo com
## os trechos dele: quem trabalha em fatias sobre um trecho (fusão por célula, casca de sombra) não pode
## confiar em is_inside_tree(). Esta marca diz que o trecho acabou (crash de 16/10 na ponte: a fusão seguia
## num trecho do deserto sendo desmontado).
const RETIRED_META := &"gpu_release_retired"

static func is_retired(node: Variant) -> bool:
	return not is_instance_valid(node) or (node as Node).is_queued_for_deletion() or (node as Node).has_meta(RETIRED_META)

static var _enabled := OS.get_environment("GETECO_GPU_RELEASE_QUEUE") != "0"
static var _hold_all := OS.get_environment("GETECO_GPU_HOLD_ALL") == "1"
static var _gpu_per_frame: int = maxi(1, OS.get_environment("GETECO_GPU_RELEASE_PER_FRAME").to_int()) if OS.get_environment("GETECO_GPU_RELEASE_PER_FRAME").is_valid_int() else DEFAULT_GPU_LEAVES_PER_FRAME
## Subárvores entregues inteiras, ainda na árvore (escondidas e desligadas), desmontadas folha por folha.
static var _roots: Array[Node] = []
static var _stack: Array[Node] = []
## Folhas que seguram recurso de vídeo, já fora da árvore: [nó, liberar_a_partir_de_msec].
static var _orphans: Array = []
static var _hooked := false
## Contadores para diagnóstico (ver debug_snapshot).
static var released_gpu := 0
static var released_plain := 0

static func enabled() -> bool:
	return _enabled

## Entrega uma subárvore inteira (trecho da ferrovia, bloco, conexão). Some do jogo neste quadro.
static func retire(node: Node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return
	node.set_meta(RETIRED_META, true)
	if not _enabled or not node.is_inside_tree():
		node.queue_free()
		return
	if node is Node3D: (node as Node3D).hide()
	elif node is CanvasItem: (node as CanvasItem).hide()
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_roots.append(node)
	_hook()

## Para quem já desmonta folha por folha (NativeRegion): entrega uma folha recém-tirada da árvore.
## Devolve true se a fila ficou com ela (quem chamou não deve liberar); false se é para liberar já.
static func adopt_detached_leaf(node: Node) -> bool:
	if not _enabled or not is_instance_valid(node) or not _holds_gpu(node): return false
	_orphans.append([node, Time.get_ticks_msec() + DELAY_MSEC])
	_hook()
	return true

## Libera tudo agora (fim de sessão, testes).
static func flush() -> void:
	# Variant: a raiz pode já ter sido liberada por fora (ver _drain_roots).
	for node: Variant in _roots:
		if is_instance_valid(node): (node as Node).queue_free()
	_roots.clear()
	_stack.clear()
	for entry in _orphans:
		if is_instance_valid(entry[0]): (entry[0] as Node).free()
	_orphans.clear()

static func pending() -> int:
	return _roots.size() + _orphans.size()

static func debug_snapshot() -> Dictionary:
	return {"enabled": _enabled, "hold_all": _hold_all, "gpu_per_frame": _gpu_per_frame, "roots": _roots.size(),
		"orphans": _orphans.size(), "released_gpu": released_gpu, "released_plain": released_plain}

## Folha cuja liberação solta memória de vídeo: dona única da malha/MultiMesh (a contagem inclui a
## referência do nó e a temporária desta leitura), ou partícula de GPU.
static func _holds_gpu(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		return mesh != null and mesh.get_reference_count() <= 2
	if node is MultiMeshInstance3D:
		var multimesh: MultiMesh = (node as MultiMeshInstance3D).multimesh
		return multimesh != null and multimesh.get_reference_count() <= 2
	return node is GPUParticles3D

static func _hook() -> void:
	if _hooked: return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	tree.process_frame.connect(Callable(load("res://runtime/GpuReleaseQueue.gd"), "_tick"))
	# Detached GPU leaves have no SceneTree owner. Drain them before the
	# renderer shuts down, even if the last retirement is younger than DELAY_MSEC.
	tree.root.tree_exiting.connect(Callable(load("res://runtime/GpuReleaseQueue.gd"), "_shutdown"), CONNECT_ONE_SHOT)
	_hooked = true

static func _shutdown() -> void:
	flush()
	_hooked = false

static func _tick() -> void:
	var began := Time.get_ticks_usec()
	_drain_roots(began)
	_release_orphans()

## Os nós entregues podem ser liberados por fora no meio da desmontagem (troca do Main na recarga, parte
## da cena antiga liberada antes do galho). Lê como Variant e só tipa depois de is_instance_valid: atribuir
## uma instância já liberada a uma variável Node é erro de execução, que abortava esta função no mesmo
## ponto a cada quadro; a fila travava para sempre e nada mais era liberado (milhares de "previously freed
## instance" no teste do ato 2, 20/10; tests/test_gpu_release_scene_swap.gd).
static func _drain_roots(began: int) -> void:
	while not _roots.is_empty():
		var root_value: Variant = _roots[0]
		if not is_instance_valid(root_value):
			_roots.pop_front()
			_stack.clear()
			continue
		var root: Node = root_value
		if _stack.is_empty(): _stack.append(root)
		while not _stack.is_empty():
			var top_value: Variant = _stack.back()
			if not is_instance_valid(top_value):
				_stack.pop_back()
				continue
			var top: Node = top_value
			var count := top.get_child_count()
			if count == 0:
				_stack.pop_back()
				if top != root: _dispose_leaf(top)
			else:
				var last := top.get_child(count - 1)
				if last.get_child_count() > 0: _stack.append(last)
				else: _dispose_leaf(last)
			if Time.get_ticks_usec() - began >= CPU_BUDGET_USEC: return
		root.queue_free()
		released_plain += 1
		_roots.pop_front()

static func _dispose_leaf(node: Node) -> void:
	node.get_parent().remove_child(node)
	if adopt_detached_leaf(node): return
	node.free()
	released_plain += 1

static func _release_orphans() -> void:
	if _hold_all or _orphans.is_empty(): return
	var now := Time.get_ticks_msec()
	var freed := 0
	while not _orphans.is_empty() and freed < _gpu_per_frame:
		var entry: Array = _orphans[0]
		if int(entry[1]) > now: return
		_orphans.pop_front()
		if is_instance_valid(entry[0]):
			(entry[0] as Node).free()
			released_gpu += 1
			freed += 1
