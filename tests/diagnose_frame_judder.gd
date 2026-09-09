extends SceneTree

## Diagnostica JUDDER ("o carro parece ir para frente e para tras"), nao FPS medio.
## O FPS pode estar em 60 e o movimento ainda ser irregular: o que o olho ve e o
## avanco APARENTE do mundo na tela por frame, e sem interpolacao de fisica esse
## avanco e quantizado pelos ticks de fisica, nao pelo tempo do frame. Um frame que
## nao pegou nenhum tick redesenha o mundo exatamente na mesma posicao; o proximo
## anda o dobro. Isso le como vibracao para frente e para tras.
##
## Roda com VSYNC LIGADO de proposito. measure_harbor_game_driving.gd desliga o
## vsync e libera o FPS: nessa condicao o batimento entre o relogio de fisica e o
## de apresentacao muda de carater e o defeito nao aparece do mesmo jeito.
##
## Variantes (passe depois de `--`): baseline | interp | nojitter | ticks120
const GAME := preload("res://world/harbor/HarborGame.tscn")
const SAMPLES := 600

func _initialize() -> void:
	call_deferred("_run")

func _stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += v
	var mean := total / float(values.size())
	var variance := 0.0
	for v in values:
		variance += (v - mean) * (v - mean)
	return {"mean": mean, "sd": sqrt(variance / float(values.size())),
		"min": sorted[0], "p50": sorted[sorted.size() / 2],
		"p99": sorted[int(sorted.size() * 0.99)], "max": sorted[sorted.size() - 1]}

## Jerk relativo: media de |passo[i] - passo[i-1]| dividida pela media do passo.
## Aceleracao suave mantem isso perto de 0 mesmo com a velocidade mudando; um
## movimento que alterna "parado, dobro, parado" vai para perto de 2. E a metrica
## que corresponde ao que o olho percebe, e e imune a variacao lenta de velocidade.
## Só compara frames ADJACENTES e ambos livres de colisão: juntar trechos separados
## por uma colisão injetaria um degrau falso na costura.
func _relative_jerk(steps: Array[float], clean: Array[bool]) -> float:
	var total := 0.0
	var counted := 0
	var jerk := 0.0
	var pairs := 0
	for i in steps.size():
		if not clean[i]:
			continue
		total += steps[i]
		counted += 1
		if i > 0 and clean[i - 1]:
			jerk += absf(steps[i] - steps[i - 1])
			pairs += 1
	if counted == 0 or pairs == 0:
		return 0.0
	var mean := total / float(counted)
	if mean <= 0.0:
		return 0.0
	return (jerk / float(pairs)) / mean

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var variant := "baseline"
	for candidate in ["interp", "nojitter", "ticks120", "interp_cadence", "cadence"]:
		if args.has(candidate) or args.has("--" + candidate):
			variant = candidate
	if variant == "interp":
		physics_interpolation = true
		Engine.physics_jitter_fix = 0.0  # a doc do Godot pede 0 junto com interpolacao
	elif variant == "nojitter":
		Engine.physics_jitter_fix = 0.0
	elif variant == "ticks120":
		Engine.physics_ticks_per_second = 120

	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0
	if variant == "interp_cadence" or variant == "cadence":
		if variant == "interp_cadence":
			physics_interpolation = true
			Engine.physics_jitter_fix = 0.0
		# Casa o FPS com um divisor inteiro do refresh do monitor. Num display de
		# 160Hz um jogo a 64 FPS cai entre 2 e 3 refreshes por frame e alterna
		# 12.5ms / 18.75ms de tempo de apresentacao -- judder mesmo com o custo de
		# CPU/GPU perfeitamente constante. Travando num divisor, cada frame fica
		# exatamente o mesmo numero de refreshes na tela.
		var refresh := DisplayServer.screen_get_refresh_rate()
		if refresh > 0.0:
			Engine.max_fps = int(round(refresh / 3.0))
	print("SETUP variant=%s vsync=%d refresh=%.1fHz physics_ticks=%d jitter_fix=%.2f interpolation=%s" % [
		variant, DisplayServer.window_get_vsync_mode(),
		DisplayServer.screen_get_refresh_rate(),
		Engine.physics_ticks_per_second, Engine.physics_jitter_fix, str(physics_interpolation)])

	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world := GAME.instantiate()
	root.add_child(world)
	current_scene = world
	for i in 90:
		await process_frame
	if not world.gameplay_ready or paused:
		push_error("Checkpoint nao ficou jogavel")
		quit(1)
		return

	var player: Node2D = world.get_node("Player")
	var car: CharacterBody2D = world.get_node("PlayerCar")
	car.global_position = Vector2(700, 425)
	car.rotation = 0.0
	player.global_position = car.global_position
	car.enter_vehicle(player)
	# A animacao de embarque zera a velocidade, e o acelerador so arma depois de um
	# frame com input solto (_drive_input_armed) -- entrar segurando a tecla nao sai
	# acelerando. Espera o embarque terminar ANTES de pressionar.
	for i in 150:
		await process_frame
	Input.action_press("ui_up")
	for i in 240:
		await process_frame
	if car.velocity.length() < 50.0:
		push_error("Carro nao acelerou (vel=%.1f): mediria um carro parado" % car.velocity.length())
		quit(1)
		return

	var camera := car.get_node_or_null("Camera2D") as Camera2D
	var viewport := root.get_viewport()
	var frame_ms: Array[float] = []
	var steps: Array[float] = []
	var clean_flags: Array[bool] = []
	var clean_steps: Array[float] = []
	var ticks_hist := {0: 0, 1: 0, 2: 0, 3: 0}
	var collided := 0
	var previous_screen: Vector2 = viewport.get_canvas_transform() * Vector2.ZERO
	var previous_ticks := Engine.get_physics_frames()

	for i in SAMPLES:
		# O screen shake move a camera aleatoriamente em +-30px e mascara o efeito
		# que estamos medindo. Zerado durante a amostragem para isolar o judder.
		if camera:
			camera._shake_amount = 0.0
		var start := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)

		var ticks := Engine.get_physics_frames()
		var used := clampi(int(ticks - previous_ticks), 0, 3)
		previous_ticks = ticks
		ticks_hist[used] = ticks_hist.get(used, 0) + 1

		var screen: Vector2 = viewport.get_canvas_transform() * Vector2.ZERO
		var moved := screen.distance_to(previous_screen)
		previous_screen = screen
		steps.append(moved)
		# Colisao muda a velocidade de verdade: nao serve para medir suavidade.
		var is_clean := car.get_slide_collision_count() == 0
		clean_flags.append(is_clean)
		if is_clean:
			clean_steps.append(moved)
		else:
			collided += 1

	Input.action_release("ui_up")

	var f := _stats(frame_ms)
	var c := _stats(clean_steps)
	var zero_ratio := 100.0 * float(ticks_hist[0]) / float(SAMPLES)
	var over := {17: 0, 25: 0, 50: 0}
	for ms in frame_ms:
		if ms > 16.67: over[17] += 1
		if ms > 25.0: over[25] += 1
		if ms > 50.0: over[50] += 1
	print("JUDDER variant=%s frame_ms mean=%.2f p50=%.2f p99=%.2f max=%.2f  acima_de 16.7ms=%d 25ms=%d 50ms=%d /%d" % [
		variant, f.mean, f.p50, f.p99, f.max, over[17], over[25], over[50], SAMPLES])
	print("JUDDER variant=%s ticks_por_frame 0=%d(%.1f%%) 1=%d 2=%d 3+=%d  colisoes=%d" % [
		variant, ticks_hist[0], zero_ratio, ticks_hist[1], ticks_hist[2], ticks_hist[3], collided])
	print("JUDDER variant=%s screen_step n=%d mean=%.2f sd=%.2f cv=%.3f JERK_RELATIVO=%.3f" % [
		variant, clean_steps.size(), c.mean, c.sd, c.sd / maxf(c.mean, 0.001), _relative_jerk(steps, clean_flags)])
	world.queue_free()
	await process_frame
	quit(0)
