extends SceneTree
## Regressão funcional de agendamento com paredes 3D reais e o planejador de fuga real.
## Esta fixture não certifica FPS nem a cadeia completa de sinais de jogo.
const DIRECTOR := preload("res://gameplay/civilian_reactions/CivilianReactionDirector.gd")

class Witness extends CharacterBody3D:
	var speed := 1.5
	var controlled_automatically := false
	var automatic_direction := Vector3.ZERO

class CountingDanger extends "res://gameplay/civilian_reactions/CivilianDanger.gd":
	var attempts := 0
	func begin_escape(body: Node3D, blocked: Array[Vector3] = []) -> Dictionary:
		attempts += 1
		return super.begin_escape(body, blocked)

class SilentPresenter extends Node:
	var screams := 0
	func scream(_actor: Node3D) -> bool:
		screams += 1
		return true
	func clear_actor(_actor_id: int) -> void: pass
	func clear_all() -> void: pass

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	print("CIVILIAN_BLOCKED_RETRY ", "PASS " if ok else "FAIL ", label, " ", detail)
	if not ok:
		failures += 1
		push_error(label + " " + detail)

func wall(parent: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	body.position = point
	return body

## A busca produtiva é incremental: aguarda o orçamento dos frames reais sem
## avançar o cooldown manual do fixture. Física/obstáculos continuam reais.
func finish_search(director: Node, state: Dictionary) -> void:
	for _frame in 90:
		director._process_escape_queue()
		# Reentrada no mesmo frame simula catch-up da física e compartilha o teto.
		director._process_escape_queue()
		check("escape rays respect shared frame cap", director.escape_rays_used <= DIRECTOR.ESCAPE_RAYS_PER_FRAME)
		if state.escape_search.is_empty(): return
		await process_frame
	check("pending escape completes within fixture bound", false)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("CIVILIAN_BLOCKED_RETRY requires --no-save")
		quit(2)
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var witness := Witness.new()
	scene.add_child(witness)
	witness.position = Vector3(50, 0, 50)
	var exit_wall := wall(scene, Vector3(49, 1.5, 50), Vector3(.2, 3, 2.4))
	wall(scene, Vector3(51, 1.5, 50), Vector3(.2, 3, 2.4))
	wall(scene, Vector3(50, 1.5, 49), Vector3(2.4, 3, .2))
	wall(scene, Vector3(50, 1.5, 51), Vector3(2.4, 3, .2))
	var director := DIRECTOR.new()
	scene.add_child(director)
	director.set_physics_process(false)
	var presentation := SilentPresenter.new()
	director.add_child(presentation)
	director.presenter = presentation
	for _frame in 3:
		await physics_frame
	var state: Dictionary = director._begin(witness, "panic")
	var danger := CountingDanger.new()
	state.danger = danger
	var threat := Vector3(55, 0, 50)
	danger.remember(threat, threat + Vector3.LEFT * 30)
	director._steer_panic(witness, state, 1.0 / 60.0)
	check("first reaction schedules immediately", danger.attempts == 1 and not state.escape_search.is_empty())
	await finish_search(director, state)
	check("real enclosure has no escape", state.target == Vector3.ZERO)
	check("trapped witness stays still", witness.automatic_direction == Vector3.ZERO)
	for _tick in 30:
		director._steer_panic(witness, state, 1.0 / 60.0)
	check("failed search respects retry interval", danger.attempts == 1, "attempts=" + str(danger.attempts))
	# Renova o mesmo perigo real como uma rajada faria. A percepção não pode reiniciar
	# o relógio da busca falha a cada alerta, senão a correção por quadro é contornada.
	for _tick in 30:
		director._alert(witness, threat, threat + Vector3.LEFT * 30, null)
		director._steer_panic(witness, state, 1.0 / 60.0)
	check("repeated alerts preserve retry interval", danger.attempts == 1, "attempts=" + str(danger.attempts))
	check("burst still renews danger", danger.threats.size() == 1 and float(danger.threats[0].age) == 0.0)
	# Uma ameaça diferente é lembrada na hora mesmo enquanto a busca falha
	# continua na cadência limitada. Ela precisa ser usada pela próxima busca devida.
	director._alert(witness, threat + Vector3.RIGHT * 2, threat + Vector3.LEFT * 28, null)
	check("distinct threat is retained during cooldown", danger.threats.size() == 2 and danger.attempts == 1)
	# Uma obstrução real desaparece. A nova tentativa precisa retomar, em vez de suprimir
	# a fuga para sempre ou permitir movimento através das paredes ainda fechadas.
	exit_wall.queue_free()
	for _frame in 3:
		await physics_frame
	# Para na primeira nova tentativa devida: esta fixture parada não pode também
	# disparar o replanejamento legítimo de travado depois que uma fuga foi achada.
	for _tick in 8:
		director._steer_panic(witness, state, .25)
		if danger.attempts > 1: break
	check("retry happens when cadence expires", danger.attempts == 2, "attempts=" + str(danger.attempts))
	await finish_search(director, state)
	check("opened physical exit produces escape", state.target != Vector3.ZERO and witness.automatic_direction != Vector3.ZERO)
	var before := danger.attempts
	state.target = witness.global_position
	state.replan = DIRECTOR.REPLAN_INTERVAL
	director._steer_panic(witness, state, 1.0 / 60.0)
	check("actual arrival replans immediately", danger.attempts == before + 1)
	await finish_search(director, state)
	# A recuperação descarta o alvo antigo. Um tiro novo precisa retomar o pânico na hora,
	# mesmo que a contagem regressiva da busca falha anterior não tenha expirado.
	state.phase = "recover"
	state.target = Vector3.ZERO
	state.replan = DIRECTOR.REPLAN_INTERVAL
	before = danger.attempts
	director._alert(witness, threat, threat + Vector3.LEFT * 30, null)
	director._steer_panic(witness, state, 1.0 / 60.0)
	check("new threat resumes panic immediately", state.phase == "panic" and danger.attempts == before + 1)
	await finish_search(director, state)
	# O desvio por buzina também é uma fase de reação distinta, não um pânico ativo.
	state.phase = "horn"
	state.target = Vector3.ZERO
	state.replan = DIRECTOR.REPLAN_INTERVAL
	before = danger.attempts
	director._alert(witness, threat, threat + Vector3.LEFT * 30, null)
	director._steer_panic(witness, state, 1.0 / 60.0)
	check("shot interrupts horn immediately", state.phase == "panic" and danger.attempts == before + 1 and presentation.screams == 1)
	await finish_search(director, state)
	director.reset_population()
	scene.queue_free()
	state.clear()
	for _frame in 3:
		await physics_frame
	print("CIVILIAN_BLOCKED_RETRY checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
