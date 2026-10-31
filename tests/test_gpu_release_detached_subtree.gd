extends SceneTree
## A full-map cache eviction must preserve gradual teardown after detachment.
const RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
const EVICTED_ROOTS := 72
const GPU_LEAVES_PER_ROOT := 2
var checks := 0
var failures := 0

class CostlyPlainLeaf extends Node:
	# Um destrutor real que passa do orçamento da fila torna isto independente
	# da velocidade da máquina: a fila precisa ceder em vez de destruir a próxima raiz.
	static var disposed := 0
	func _notification(what: int) -> void:
		if what != NOTIFICATION_PREDELETE: return
		var until := Time.get_ticks_usec() + 2000
		while Time.get_ticks_usec() < until: pass
		disposed += 1

func _initialize() -> void: run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if value: print("GPU_DETACHED PASS ", label)
	else:
		failures += 1
		push_error("GPU_DETACHED FAIL " + label)

func run() -> void:
	_check(RELEASE.enabled() and not RELEASE._hold_all, "normal gradual release mode is enabled")
	if failures > 0:
		quit(1)
		return
	RELEASE.flush()
	var root_ids: Array[int] = []
	var leaf_ids: Array[int] = []
	var began_msec := Time.get_ticks_msec()
	for index in EVICTED_ROOTS:
		var detached := Node3D.new()
		detached.name = "Evicted_%d" % index
		root_ids.append(detached.get_instance_id())
		var branch := Node3D.new()
		detached.add_child(branch)
		for gpu_index in GPU_LEAVES_PER_ROOT:
			var leaf := MeshInstance3D.new()
			leaf.mesh = BoxMesh.new()
			branch.add_child(leaf)
			leaf_ids.append(leaf.get_instance_id())
		# Este é visitado primeiro, antes dos dois donos de malha desta subárvore.
		branch.add_child(CostlyPlainLeaf.new())
		RELEASE.retire_detached_subtree(detached)
	var retained := true
	for id in root_ids:
		var node := instance_from_id(id) as Node3D
		retained = retained and is_instance_valid(node) and not node.is_inside_tree() and node.get_parent() == null and not node.is_queued_for_deletion() and not node.visible and node.process_mode == Node.PROCESS_MODE_DISABLED and RELEASE.is_retired(node)
	_check(retained, "all 72 detached subtrees are owned, inert and not queued for immediate free")
	_check(RELEASE.debug_snapshot().roots == EVICTED_ROOTS and RELEASE.pending() == EVICTED_ROOTS, "all 72 evictions enter the gradual queue")
	RELEASE.retire_detached_subtree(instance_from_id(root_ids[0]) as Node)
	_check(RELEASE.debug_snapshot().roots == EVICTED_ROOTS and RELEASE.pending() == EVICTED_ROOTS, "duplicate retirement cannot enqueue or free an owned subtree twice")
	RELEASE._tick()
	_check(CostlyPlainLeaf.disposed <= 1, "one tick cannot consume multiple costly subtree destructors")
	_check(RELEASE.debug_snapshot().roots == EVICTED_ROOTS, "first tick leaves the bulk of subtree work pending")
	_check(RELEASE.debug_snapshot().orphans == 0, "unvisited mesh owners remain in their queued subtree")
	# Aciona o consumidor real de forma síncrona para que o gancho automático de process-frame
	# dele não esconda quantas fatias de descarte foram necessárias.
	var slices := 1
	while RELEASE.debug_snapshot().roots > 0 and slices < EVICTED_ROOTS * 4:
		RELEASE._tick()
		slices += 1
	_check(RELEASE.debug_snapshot().roots == 0 and CostlyPlainLeaf.disposed == EVICTED_ROOTS, "finite CPU slices drain every detached subtree")
	_check(slices >= EVICTED_ROOTS, "72 costly subtree destructors require multiple budgeted slices")
	_check(RELEASE.debug_snapshot().orphans == EVICTED_ROOTS * GPU_LEAVES_PER_ROOT, "all unique GPU owners transfer to delayed release")
	var delay_preserved := true
	for entry in RELEASE._orphans:
		delay_preserved = delay_preserved and int(entry[1]) >= began_msec + RELEASE.DELAY_MSEC
	_check(delay_preserved, "GPU leaves retain the full release delay when adopted")
	var before_gpu: int = RELEASE.released_gpu
	RELEASE._release_orphans()
	_check(RELEASE.released_gpu == before_gpu and RELEASE.debug_snapshot().orphans == leaf_ids.size(), "GPU leaves cannot be freed before their deadline")
	# Avança só os prazos na fila para exercitar expiração/cota sem um
	# sleep de tempo de parede; as checagens de adoção e de antes do prazo acima usam tempo real.
	for entry in RELEASE._orphans: entry[1] = Time.get_ticks_msec() - 1
	RELEASE._release_orphans()
	var quota: int = RELEASE.debug_snapshot().gpu_per_frame
	_check(RELEASE.released_gpu - before_gpu == mini(quota, leaf_ids.size()), "one release pass respects the configured GPU leaf quota")
	_check(RELEASE.debug_snapshot().orphans == maxi(0, leaf_ids.size() - quota), "GPU work beyond the quota stays owned by the queue")
	RELEASE.flush()
	_check(RELEASE.pending() == 0 and RELEASE._stack.is_empty(), "flush clears CPU roots, traversal state and GPU owners")
	var gpu_freed := true
	for id in leaf_ids: gpu_freed = gpu_freed and not is_instance_id_valid(id)
	_check(gpu_freed, "flush frees every delayed GPU leaf")
	# Uma subárvore vazia pode ela mesma ser o último dono de GPU; terminar a raiz dela
	# precisa usar o mesmo atraso de terminar uma folha de malha dentro de um ramo maior.
	var gpu_root := MeshInstance3D.new()
	gpu_root.mesh = SphereMesh.new()
	var gpu_root_id := gpu_root.get_instance_id()
	RELEASE.retire_detached_subtree(gpu_root)
	RELEASE._tick()
	_check(RELEASE.debug_snapshot().roots == 0 and RELEASE.debug_snapshot().orphans == 1 and is_instance_id_valid(gpu_root_id), "an empty GPU root transfers intact to delayed release")
	RELEASE.flush()
	_check(not is_instance_id_valid(gpu_root_id) and RELEASE.pending() == 0, "flush also frees the delayed empty GPU root")
	# Raízes vazias podem usar destruição adiada durante o esvaziamento normal. Deixa esse
	# flush real do motor acontecer antes de afirmar que a posse foi liberada.
	await process_frame
	var roots_freed := true
	for id in root_ids: roots_freed = roots_freed and not is_instance_id_valid(id)
	_check(roots_freed, "all drained detached roots disappear after the deferred flush")
	print("GPU_DETACHED checks=", checks, " failures=", failures, " slices=", slices)
	quit(1 if failures else 0)
