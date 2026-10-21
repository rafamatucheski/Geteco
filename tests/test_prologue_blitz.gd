extends SceneTree
## Prólogo jogável curto, sem Main.tscn: a chegada de um jogo novo abre a blitz antes do filme da
## balsa, a cena joga sozinha (autoplay, relógio x4) até a algema e devolve para o filme com a marca
## gravada; depois o ponto de vista "vicente" (flashback do ato 2) é chamado pela API e devolve o
## on_done. Não mede desempenho nem confere a imagem.
const ARRIVAL := preload("res://runtime/Arrival.gd")
const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
var failures: Array[String] = []
var checks := 0

## O mínimo que Arrival._lock e _set_phase leem da sessão.
class FakeSession extends Node:
	var modal := false
	var world := FakeWorld.new()
class FakeWorld extends RefCounted:
	var player := FakePlayer.new()
	var gameplay := FakeGameplay.new()
class FakePlayer extends RefCounted:
	var input_locked := false
class FakeGameplay extends RefCounted:
	var health := 100.0

func _initialize() -> void:
	# Este teste confere o prólogo: o runner pula a abertura por padrão (Arrival.skip_opening).
	OS.set_environment("GETECO_SKIP_OPENING", "0")
	OS.set_environment("GETECO_SKIP_PROLOGUE", "")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func wait_until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return condition.call()

func run() -> void:
	var previous_3d := root.disable_3d
	var session := FakeSession.new()
	root.add_child(session)
	var arrival := ARRIVAL.new()
	arrival.configure(session)
	session.add_child(arrival)
	var saves: Array[Dictionary] = []
	arrival.changed.connect(func(): saves.append(arrival.snapshot()))
	arrival._begin_opening()
	var blitz = arrival.presentation
	check(blitz != null and blitz.get_script() == BLITZ and blitz.pov == "dante", "jogo novo abre o prólogo (Dante) antes do filme da balsa")
	check(arrival.phase == "opening" and arrival.controls_locked, "a chegada fica travada na fase da abertura")
	check(not saves.is_empty() and saves[-1].prologue_seen == false, "checkpoint do começo grava o prólogo pendente")
	blitz.autoplay = true
	blitz.pace = 4.0
	await process_frame
	check(paused and root.disable_3d, "a blitz pausa o mundo e desliga o 3D do viewport principal")
	var reached_cuff: bool = await wait_until(func(): return blitz.stage == "dante_cuff", 60.0)
	check(reached_cuff, "o prólogo chega à algema (stage=%s)" % str(blitz.stage))
	check(blitz.signaled and blitz.truck_speed == 0.0, "o caminhão parou depois da lanterna")
	var cut: bool = await wait_until(func(): return blitz.stage == "dante_black", 20.0)
	check(cut and blitz.cuff_progress >= 1.0 and blitz.curtain.color.a >= 1.0, "segurar a algema fecha e corta seco para preto")
	var returned: bool = await wait_until(func(): return arrival.prologue_seen, 20.0)
	check(returned and is_instance_valid(arrival.presentation) and arrival.presentation.get("film") != null, "fim do prólogo segue para o filme da balsa")
	check(saves[-1].prologue_seen == true, "o prólogo visto é gravado antes do filme")
	await process_frame
	check(not is_instance_valid(blitz), "a cena da blitz sai da árvore")
	# Sem chegar ao desembarque: tirar a chegada encerra o filme e devolve pausa e 3D.
	arrival.queue_free()
	await process_frame
	await process_frame
	check(not paused and root.disable_3d == previous_3d, "pausa e 3D voltam ao que eram")
	# Ato 2: a missão chama o flashback de Vicente e recebe o retorno.
	var results: Array = []
	var flashback = BLITZ.start(session, "vicente", func(was_skipped: bool): results.append(was_skipped))
	flashback.autoplay = true
	flashback.pace = 4.0
	await process_frame
	check(paused and flashback.pov == "vicente", "o flashback pausa o mundo de quem chamou")
	var stopped: bool = await wait_until(func(): return not is_instance_valid(flashback) or flashback.stage in ["vicente_wait", "vicente_face", "vicente_black"], 60.0)
	check(stopped, "Vicente para o caminhão na blitz")
	var faced: bool = await wait_until(func(): return not is_instance_valid(flashback) or flashback.stage in ["vicente_face", "vicente_black"], 30.0)
	check(faced, "a porta abre no rosto de Dante")
	var done: bool = await wait_until(func(): return not results.is_empty(), 30.0)
	check(done and results == [false], "on_done chamado uma vez, sem pulo: %s" % str(results))
	await process_frame
	check(not paused and root.disable_3d == previous_3d, "flashback devolve pausa e 3D")
	# Pulo (Esc duas vezes) também devolve, com skipped = true.
	var skipped_results: Array = []
	var skipped_scene = BLITZ.start(null, "vicente", func(was_skipped: bool): skipped_results.append(was_skipped))
	await wait_until(func(): return skipped_scene.stage.begins_with("vicente_"), 20.0)
	skipped_scene.request_skip()
	skipped_scene.request_skip()
	await process_frame
	check(skipped_results == [true] and not paused, "pular devolve on_done(true) e solta o mundo")
	session.queue_free()
	await process_frame
	print("PROLOGUE BLITZ checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
