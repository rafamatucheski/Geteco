extends SceneTree

## Diagnóstico do simulador de ossos do Meshy: com o log de sessão ativo, liberar o simulador registra "exiting"
## e a poda registra "pruned" (com o ator); sem a lista segurar referência morta. Não mede desempenho.
const MECHANIC := preload("res://assets/maciota/MechanicModel.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	STALL_WORK.session_enabled = true
	var walker := Node3D.new()
	root.add_child(walker)
	var mechanic := MECHANIC.new() as Node3D
	walker.add_child(mechanic)
	for i in 10: await process_frame
	var rig = mechanic.body.get("_meshy")
	check(rig != null and rig._physical_simulators.size() > 0, "o corpo tem simulador de ossos para testar")
	if rig == null or rig._physical_simulators.is_empty():
		print("MESHY_SIMULATOR_LOG failures=", failures)
		quit(1)
		return
	# O registrador da sessão esvazia essa fila a cada quadro; lê-se antes de esperar quadros.
	STALL_WORK.take_session()
	var simulator: Node = rig._physical_simulators[0]
	check(simulator.tree_exiting.get_connections().size() > 0, "o simulador foi ligado ao diagnóstico (rig montado com o log ativo)")
	simulator.free()
	rig.update_physical_simulators()
	var events: Array = STALL_WORK.session_lifecycle.duplicate()
	var kinds: Array[String] = []
	for event in events:
		if str(event.label) == "retire.meshy_simulator": kinds.append(str(event.details.kind))
	check("exiting" in kinds, "liberar o simulador registra 'exiting' (%s)" % str(kinds))
	check("pruned" in kinds, "a poda registra 'pruned' (%s)" % str(kinds))
	check(rig._physical_simulators.size() == 0 or is_instance_valid(rig._physical_simulators[0]), "a lista não guarda referência morta")
	STALL_WORK.session_enabled = false
	walker.free()
	await process_frame
	print("MESHY_SIMULATOR_LOG failures=", failures)
	quit(0 if failures.is_empty() else 1)
