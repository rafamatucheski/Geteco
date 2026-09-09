extends SceneTree

## Mede o MECANISMO do judder isolado da rota do jogo, porque medir na rota real
## nao e reprodutivel: colisoes e trafego fazem cada execucao seguir um caminho
## diferente, e a variancia entre execucoes fica maior que a diferenca entre as
## configuracoes que se quer comparar.
##
## Aqui um corpo anda em linha reta a velocidade CONSTANTE, sem nada para colidir,
## com a Camera2D filha dele -- igual ao PlayerCar. O avanco do corpo no mundo por
## tick e exatamente constante, entao toda variacao no avanco APARENTE na tela e
## judder, e nada mais.
##
## Uso: --script res://tests/measure_motion_judder_isolated.gd -- [no_interp]
const SPEED := 240.0
const FRAMES := 300

var _use_interpolation := false

class Mover extends CharacterBody2D:
	func _physics_process(_delta: float) -> void:
		move_and_slide()

func _initialize() -> void:
	call_deferred("_run")

func _relative_jerk(steps: Array[float]) -> float:
	if steps.size() < 3:
		return 0.0
	var total := 0.0
	var jerk := 0.0
	for i in steps.size():
		total += steps[i]
		if i > 0:
			jerk += absf(steps[i] - steps[i - 1])
	var mean := total / float(steps.size())
	if mean <= 0.0:
		return 0.0
	return (jerk / float(steps.size() - 1)) / mean

func _measure(fps_cap: int) -> void:
	Engine.max_fps = fps_cap
	var world := Node2D.new()
	# Marcos estaticos: dao conteudo para a camera atravessar, como a cidade faz.
	for i in 400:
		var block := ColorRect.new()
		block.size = Vector2(48, 48)
		block.position = Vector2((i % 20) * 220, (i / 20) * 180)
		block.color = Color(0.2 + 0.6 * float(i % 3) / 2.0, 0.3, 0.5)
		world.add_child(block)
	var mover := Mover.new()
	mover.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	mover.global_position = Vector2(0, 400)
	mover.velocity = Vector2(SPEED, 0.0)
	world.add_child(mover)
	var camera := Camera2D.new()
	mover.add_child(camera)
	root.add_child(world)
	camera.make_current()
	camera.reset_smoothing()
	for i in 40:
		await process_frame

	var viewport := root.get_viewport()
	var steps: Array[float] = []
	var frame_ms: Array[float] = []
	var zero_tick := 0
	var previous_screen: Vector2 = viewport.get_canvas_transform() * Vector2.ZERO
	var previous_ticks := Engine.get_physics_frames()
	for i in FRAMES:
		var start := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
		if Engine.get_physics_frames() == previous_ticks:
			zero_tick += 1
		previous_ticks = Engine.get_physics_frames()
		var screen: Vector2 = viewport.get_canvas_transform() * Vector2.ZERO
		steps.append(screen.distance_to(previous_screen))
		previous_screen = screen

	var total_ms := 0.0
	for ms in frame_ms:
		total_ms += ms
	var mean_ms := total_ms / float(FRAMES)
	var mean_step := 0.0
	for s in steps:
		mean_step += s
	mean_step /= float(FRAMES)
	var sd := 0.0
	for s in steps:
		sd += (s - mean_step) * (s - mean_step)
	sd = sqrt(sd / float(FRAMES))
	# Alvo teorico: velocidade constante repartida igualmente entre os frames.
	print("ISOLATED interp=%-5s max_fps=%-4d fps_real=%5.1f  step mean=%5.2f sd=%5.2f cv=%.3f  JERK=%.3f  frames_sem_tick=%d/%d" % [
		str(_use_interpolation), fps_cap, 1000.0 / maxf(mean_ms, 0.001),
		mean_step, sd, sd / maxf(mean_step, 0.001), _relative_jerk(steps), zero_tick, FRAMES])
	world.queue_free()
	await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	# O projeto agora liga physics_interpolation por padrao. O argumento serve para
	# DESLIGAR e reproduzir o baseline de antes da correcao.
	if args.has("no_interp") or args.has("--no_interp"):
		physics_interpolation = false
		Engine.physics_jitter_fix = 0.5
	_use_interpolation = physics_interpolation
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	print("SETUP interp=%s refresh=%.1fHz physics_ticks=%d jitter=%.2f" % [
		str(physics_interpolation), DisplayServer.screen_get_refresh_rate(),
		Engine.physics_ticks_per_second, Engine.physics_jitter_fix])
	# 0 = sem teto (vsync do monitor manda); 64 reproduz o FPS medido no jogo;
	# 60 casa exatamente com o tick de fisica; 53 e 160/3, divisor inteiro do refresh.
	for cap in [0, 64, 60, 53]:
		await _measure(cap)
	quit(0)
