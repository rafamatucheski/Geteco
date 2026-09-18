extends SceneTree
## Sem cap, um massacre contínuo mais rápido que o pool de coroner/ambulância
## empilha corpos vivos (AnimatedPedestrian3D + SubViewport) indefinidamente --
## o vídeo do usuário mostrou RAM de ~15,5GB pra ~27GB e FPS de ~40 pra ~15
## numa perseguição a pé de 140s. Este teste força mais corpos que
## MAX_SIMULTANEOUS_INCIDENTS de uma vez e confirma que o excesso é
## forçado a "unrecovered" (mesmo caminho que o CoronerCare já usa),
## sem tocar corpos já em resgate ativo.

class DeadCivilian extends CharacterBody2D:
	var is_dead := true
	var health := 0
	var is_incapacitated := false

class FakeCoronerUnit extends Node2D:
	var is_broken := false
	var is_returning_to_base := false
	var target: Node = null
	var type := 3
	var service_targets: Array = []

var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(30).timeout.connect(func(): printerr("MEDICAL_CAP TIMEOUT"); quit(2))
	var world := Node2D.new()
	world.name = "MedicalCapFixture"
	root.add_child(world)
	current_scene = world
	var care := root.get_node("NPCMedicalCare")
	care._reset()
	await physics_frame

	var total: int = int(care.MAX_SIMULTANEOUS_INCIDENTS) + 10
	var bodies: Array[DeadCivilian] = []
	for i in total:
		var body := DeadCivilian.new()
		body.position = Vector2(i * 40, 0)
		world.add_child(body)
		bodies.append(body)
	await physics_frame
	await physics_frame # NPCMedicalCare._register runs via node_added, deferred

	for body in bodies:
		care.report_injury(body)
	check(care.incidents.size() == total, "todos os %d corpos entram na fila" % total)

	# Um ciclo de _scan_clock (>=0.5s) basta pro pré-corte de excesso marcar
	# force_fade nos mais antigos/sem resgate; FADE_SECONDS (5s) pra sumir de vez.
	for i in 20:
		care._process(0.5)
		await physics_frame

	check(care.incidents.size() <= care.MAX_SIMULTANEOUS_INCIDENTS, "fila nunca passa do teto (%d), ficou em %d" % [care.MAX_SIMULTANEOUS_INCIDENTS, care.incidents.size()])
	var coroner := root.get_node("CoronerCare")
	var unrecovered := 0
	for record in coroner.records().values():
		if record.get("phase","") == "unrecovered": unrecovered += 1
	check(unrecovered >= total - care.MAX_SIMULTANEOUS_INCIDENTS, "excedente foi despachado como 'unrecovered' (%d)" % unrecovered)
	for body in bodies:
		check(is_instance_valid(body), "nenhum corpo foi liberado/destruído, só escondido")

	# Um corpo em resgate ativo (dispatched) nunca é forçado, mesmo em excesso.
	care._reset()
	for body in bodies:
		if is_instance_valid(body): body.queue_free()
	await physics_frame
	var protected_body := DeadCivilian.new()
	world.add_child(protected_body)
	await physics_frame
	await physics_frame
	care.report_injury(protected_body)
	var key: String = protected_body.get_meta("medical_identity", "")
	var fake_unit := FakeCoronerUnit.new()
	fake_unit.target = protected_body
	world.add_child(fake_unit)
	care.incidents[key].phase = "dispatched"
	care.incidents[key].unit = fake_unit
	for i in (care.MAX_SIMULTANEOUS_INCIDENTS + 5):
		var filler := DeadCivilian.new()
		filler.position = Vector2(1000 + i * 40, 0)
		world.add_child(filler)
	await physics_frame
	await physics_frame
	for child in world.get_children():
		if child is DeadCivilian and child != protected_body:
			care.report_injury(child)
	for i in 5: care._process(0.5)
	check(care.incidents.has(key) and care.incidents[key].phase == "dispatched", "corpo já em resgate ativo não é interrompido pelo teto")

	print("NPC_MEDICAL_INCIDENT_CAP failures=", failures)
	quit(0 if failures.is_empty() else 1)
