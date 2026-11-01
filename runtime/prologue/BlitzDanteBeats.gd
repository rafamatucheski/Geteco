extends RefCounted
## A noite pelo lado de Dante (prólogo): sinalizar, o trânsito desviando, a caminhada até a cabine, a
## emboscada, Lima reagindo, a fuga de Vicente, a algema, a viatura, a prisão e o quarto de oito anos
## depois. Separado da BlitzScene em 01/11 só para ela caber na leitura; o estado (estágio, relógio,
## `_beats`, bonecos) continua lá, e cada função antiga ficou lá como delegação de uma linha.
## `g` sem tipo e sem preload do dono, como em BlitzSet. Chamadas entre funções passam por `g.`.
const TRUCK := preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd")

var g

func _init(host: CanvasLayer) -> void:
	g = host

func _dante_begin() -> void:
	g._set_stage("dante_open")
	g.truck.position = Vector3(g.LANE_X, 0, 900)
	g.truck_speed = 0.0
	g._face(g.dante, Vector3.BACK)
	g._dante_heading = g.dante.rotation.y
	g._police_audio.play()
	g._police_audio.volume_db = -26.0
	g.say("dante", "radio_open", func(): g.say("dante", "colleagues"))

func _dante_tick(step: float) -> void:
	g._fire_cooldown = maxf(0.0, g._fire_cooldown - step)
	g._shake = maxf(0.0, g._shake - step * 2.5)
	g._vicente_hands()
	if g.stage in ["dante_ambush", "dante_fight", "dante_flee", "dante_wounded", "dante_cuff", "dante_cuffed"]: g._lima_tick(step)
	match g.stage:
		"dante_open":
			g._traffic(step)
			g._dante_hands(g._swing)
			g._nape_camera(step)
			# O terceiro veículo é o caminhão: entra depois dos dois carros.
			if g.stage_time > 10.0 and g._beat("truck_enters"):
				g.truck.position = Vector3(g.LANE_X, 0, 230.0)
				g.truck_speed = 14.0
			if g.truck.position.z < 800.0 and not g.signaled:
				var distance: float = g.truck.position.z - g.TRUCK_STOP_Z
				# Sem sinal, ele se arrasta e espera perto dos cavaletes.
				if distance < 160.0: g._show_prompt("signal")
				if distance > 70.0: g._move_truck(step)
				else: g._brake_to(g.TRUCK_STOP_Z + 42.0, step, 3.0)
				if g.autoplay and distance < 140.0: g._signal()
			elif g.signaled:
				g._swing = minf(1.0, g._swing + step * 3.0) if g.stage_time < 2.0 else maxf(0.0, g._swing - step * 1.5)
				if g._brake_to(g.TRUCK_STOP_Z, step, 4.0):
					g._play("res://audio/vehicle_fx/air_brake.wav", -6.0)
					g._hide_prompt()
					g._set_stage("dante_walk")
					g.say("dante", "stopped", func(): g.say("dante", "approach"))
					g._objective_text("walk")
			g._engine(g.camera.global_position.distance_to(g.truck.global_position))
		"dante_walk":
			g._traffic(step)
			g._swing = maxf(0.0, g._swing - step * 1.5)
			g._walk_dante(step)
			g._dante_hands(g._swing)
			g._walk_bastos(step)
			g._nape_camera(step, 4.0)
			g._engine(g.camera.global_position.distance_to(g.truck.global_position))
			var beside: bool = Vector2(g.dante.global_position.x - g.DANTE_BESIDE.x, g.dante.global_position.z - g.DANTE_BESIDE.z).length() < .6
			if beside and g._bastos_leg >= g.BASTOS_PATH.size():
				g._objective.text = ""
				g._set_stage("dante_ask")
		"dante_ask": g._dante_ask(step)
		"dante_ambush": g._dante_ambush(step)
		"dante_fight":
			g._aim_tick(step)
			g._shooter_tick(step)
			g._vicente_crouch()
			if g.shooter_health <= 0 and g.stage_time > 1.4:
				g.say("dante", "flee")
				g._objective_text("flee")
				g._set_stage("dante_flee")
		"dante_flee":
			g._aim_tick(step)
			g._vicente_run(step)
		"dante_wounded": g._dante_wounded(step)
		"dante_cuff": g._dante_cuff(step)
		"dante_cuffed":
			g._high_camera(g._wrists(), 5.0, step)
			if g.stage_time > 1.4 and g._beat("to_car"): g._fade(true, .6, g._setup_escort)
		"dante_escort": g._dante_escort(step)
		"dante_drive": g._dante_drive(step)
		"dante_prison": g._dante_prison(step)
		"dante_black": g._dante_black()
		"dante_after": g._dante_after(step)
	if g.stage in ["dante_open", "dante_walk", "dante_ask", "dante_ambush", "dante_fight", "dante_flee", "dante_wounded", "dante_cuff", "dante_cuffed", "dante_escort"]: g._engine(g.camera.global_position.distance_to(g.truck.global_position) if g.stage == "dante_open" else 4.0)

func _signal() -> void:
	if g.signaled or g.stage != "dante_open": return
	g.signaled = true
	g.stage_time = 0.0
	g._hide_prompt()

func _traffic_near() -> bool:
	for index in g.cars.size():
		if g._car_speed[index] > 0.0 and g.cars[index].position.z < 70.0 and g.cars[index].position.z > -20.0: return true
	return false

func _traffic(step: float) -> void:
	for index in g.cars.size():
		var car: Node3D = g.cars[index]
		var start_at: float = 1.5 + index * 4.5
		if g.stage == "dante_open" and g.stage_time > start_at and g._beat("car_%d" % index):
			car.position = Vector3(g.LANE_X, 0, 150.0)
			g._car_speed[index] = 15.0
		if g._car_speed[index] <= 0.0: continue
		# Reduzem na blitz, desviam dos cavaletes pela faixa da esquerda e seguem.
		var near := car.position.z < 45.0 and car.position.z > -30.0
		g._car_speed[index] = move_toward(g._car_speed[index], 5.5 if near else 15.0, step * 5.0)
		var z: float = car.position.z - g._car_speed[index] * step
		var x: float = g.detour_x(z)
		var ahead: Vector3 = Vector3(g.detour_x(z - 1.0) - x, 0, -1.0)
		car.position = Vector3(x, 0, z)
		car.rotation.y = atan2(-ahead.x, -ahead.z)
		if z < -320.0:
			g._car_speed[index] = 0.0
			car.hide()

func _walk_bastos(step: float) -> void:
	if g._bastos_leg >= g.BASTOS_PATH.size():
		g._face(g.bastos, g._door_point() - g.bastos.global_position)
		return
	var goal: Vector3 = g.BASTOS_PATH[g._bastos_leg]
	var offset: Vector3 = goal - g.bastos.global_position
	offset.y = 0.0
	if offset.length() < .08:
		g._bastos_leg += 1
		return
	g.bastos.global_position += offset.normalized() * minf(offset.length(), 1.45 * step)
	g._face(g.bastos, offset)
	g._hands(g.bastos, null, null)

func _walk_dante(step: float) -> void:
	var input := Vector2.ZERO
	if g.autoplay:
		var offset: Vector3 = g.DANTE_BESIDE - g.dante.global_position
		# Contorna a frente do caminhão pela esquerda, como Bastos.
		if g.dante.global_position.z < -10.3 and g.dante.global_position.x > -.6: offset = Vector3(-.9, 0, -10.6) - g.dante.global_position
		input = Vector2(offset.x, offset.z).normalized() if offset.length() > .05 else Vector2.ZERO
	else:
		var game_input: Node = g.get_node_or_null("/root/GameInput")
		var move: Vector2 = game_input.movement() if game_input != null else Input.get_vector("move_left", "move_right", "move_up", "move_down")
		# Para frente é para o caminhão (+z) do ponto de vista da nuca.
		input = Vector2(-move.x, -move.y)
	if input.length() < .1: return
	input = input.limit_length(1.0)
	var velocity := Vector3(input.x, 0, input.y) * 1.55
	var next: Vector3 = g.dante.position + velocity * step
	next.x = clampf(next.x, -5.5, 5.5)
	next.z = clampf(next.z, -24.0, 6.0)
	# A carroceria e a cabine são sólidas para quem anda.
	var local: Vector3 = g.truck.to_local(next)
	if absf(local.x) < 1.6 and local.z > -6.0 and local.z < 6.0:
		next = g.truck.to_global(Vector3(signf(local.x) * 1.6 if local.x != 0.0 else -1.6, 0, local.z))
	g.dante.position = next
	var heading := atan2(-velocity.x, -velocity.z)
	g._dante_heading = heading
	g._face(g.dante, velocity)

## Bastos bate no vidro e pede para descer; a câmera, da nuca de Dante, vira acompanhando ele.
func _dante_ask(step: float) -> void:
	g._face(g.dante, g._door_point() + Vector3(0, 0, -.6) - g.dante.global_position)
	# De frente para a chapa da porta.
	g._face(g.bastos, g.truck.global_basis.x)
	var glass: Vector3 = g.truck.to_global(Vector3(-1.2, 2.35, -3.25))
	if g._beat("ask_line"): g.say("dante", "ask")
	# Os nós dos dedos na porta, na altura do ombro dele, três batidas (o vidro fica alto demais).
	var knock: bool = g.stage_time < 1.4
	var tap: float = .05 * maxf(0.0, sin(g.stage_time * 14.0))
	g._hands(g.bastos, g.truck.to_global(Vector3(-1.25 - tap, 1.62, -3.8)) if knock else null, null)
	if g.stage_time < 3.2:
		g._nape_camera(step, 3.0, g._head(g.bastos).lerp(glass, smoothstep(.2, 1.4, g.stage_time) * .6))
		return
	if g._beat("door_opens"): g._open_door()
	if g.stage_time < 4.2:
		g._nape_camera(step, 3.0, glass)
		return
	# Sem close na cabine: a conversa pela porta aberta fica na câmera alta, como o resto da blitz.
	if not g._beats.has("step_down"): g._nape_camera(step, 3.0, glass)
	if g.stage_time > 4.8 and g._beat("vicente_line"): g.say("dante", "door", func(): g._clock = g.stage_time)
	if g._beats.has("vicente_line") and not g.speaking() and g.stage_time - g._clock > .8 and g._beat("step_down"):
		# Bastos olha de um para o outro; Vicente desce com as mãos à vista.
		g.vicente.reparent(g._set)
		g.vicente.stand_up()
		g.vicente.global_position = g._door_point() + Vector3(.3, 0, .15)
		g._face(g.vicente, Vector3.LEFT)
		# Ninguém ali tinha feito nada: ele desce, explica a carga, oferece abrir o baú.
		g.say("dante", "order_out", func(): g._ready_ambush = g.stage_time)
	if g._beats.has("step_down"):
		g._nape_camera(step, 3.0, g._eyes(g.vicente).lerp(g._eyes(g.bastos), .35))
		# Mãos ao alto, abertas acima da cabeça (com a junta do pescoço como cabeça, iam às orelhas).
		var neck: Vector3 = g._head(g.vicente)
		var side: Vector3 = g._forward(g.vicente).cross(Vector3.UP).normalized()
		var front: Vector3 = g._forward(g.vicente) * .06
		g.vicente.hand_targets = [neck + Vector3.UP * .4 + side * .27 + front, neck + Vector3.UP * .4 - side * .27 + front]
	if g._ready_ambush >= 0.0 and g.stage_time - g._ready_ambush > .6: g._set_stage("dante_ambush")

## Tiros do lado do passageiro: Bastos cai, Dante saca e vai para o abrigo.
func _dante_ambush(step: float) -> void:
	if g._beat("shooter_out"):
		# A porta do passageiro abre: o Rato desce do banco, pistola na mão. Dante vê primeiro e grita.
		g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(g.passenger_door, "rotation:y", 1.5, .45 / g.pace)
		g._play("res://audio/vehicle_fx/door_open_1.wav", -3.0)
		# Os dois policiais congelam: Bastos na porta, Lima no cavalete. Quem reage é Dante.
		g._hands(g.bastos, null, null)
		g._hands(g.lima, null, null)
		g._face(g.bastos, g.SHOOTER_OUT - g.bastos.global_position)
		g._face(g.lima, g.SHOOTER_OUT - g.lima.global_position)
		g.say("dante", "ambush")
		g._play("res://audio/weapons_fire/gun_draw_0.wav", -4.0)
		g.dante.weapon.show()
		g.lantern.hide()
	# Ele desce do banco quando a porta já abriu; o primeiro tiro é em Bastos, na porta do motorista.
	if g.stage_time > .35 and g._beat("shooter_jump"):
		g.shooter.reparent(g._set)
		g.shooter.seated = false
		g.shooter.body.sit_amount = 0.0
		g.shooter.weapon.visible = true
		g.shooter.global_position = g.truck.to_global(Vector3(1.95, 0, -3.3))
		g.shooter.rotation = Vector3.ZERO
	# Contorna a frente do caminhão (por fora da carroceria) até ter linha.
	var legs := [g.SHOOTER_OUT, g.SHOOTER_EXPOSED]
	if g._beats.has("shooter_jump") and g._shooter_leg < legs.size():
		g.shooter.global_position = g.shooter.global_position.move_toward(legs[g._shooter_leg], 3.6 * step)
		if g.shooter.global_position.distance_to(legs[g._shooter_leg]) < .05: g._shooter_leg += 1
	var first_target: Vector3 = g.bastos.global_position if not g._beats.has("first_shot") else g.dante.global_position
	if g._beats.has("shooter_jump"): g._face(g.shooter, first_target - g.shooter.global_position)
	if g._beats.has("shooter_jump") and g.shooter.global_position.distance_to(g.SHOOTER_EXPOSED) < .3 and g._beat("first_shot"):
		g._enemy_shot()
		g._kill(g.bastos, (g.bastos.global_position - g.shooter.global_position).normalized())
		g._shake = .5
		g.say("dante", "man_down")
		g._shot_clock = g.stage_time
	if g._beats.has("shooter_jump"): g.shooter.update_pose(step, true, false, 0.0, 0.0)
	var cover: Vector3 = g.dante.global_position.move_toward(g.DANTE_COVER, 2.6 * step)
	g.dante.global_position = cover
	g._vicente_crouch()
	g._aim_point = g.SHOOTER_EXPOSED + Vector3.UP * 1.2
	var toward: Vector3 = g._aim_point - g.dante.global_position
	g.aim_yaw = atan2(-toward.x, -toward.z)
	g.dante.update_pose(step, true, false, 0.0, 0.0)
	g._aim_camera(step)
	if g._beats.has("first_shot") and g.stage_time - g._shot_clock > .7:
		g._shooter_exposed = true
		g._shooter_clock = 1.6
		g._objective_text("fight")
		g._show_fire_prompt()
		g._set_stage("dante_fight")

## Lima reage: um instante de susto, corre para trás da viatura, saca e atira por cima do capô enquanto o
## atirador está vivo (o acerto é do jogador). Depois guarda a arma, vai até Bastos e pede apoio no rádio.
func _lima_tick(step: float) -> void:
	if not g._beats.has("first_shot"): return
	g._lima_clock += step
	if g._lima_clock < .9: return
	var fighting: bool = is_instance_valid(g.shooter) and g.shooter_health > 0
	if fighting:
		if g._beat("lima_draw"):
			g.lima.weapon.show()
			g._play_at_volume("res://audio/weapons_fire/gun_draw_1.wav", -8.0)
		var offset: Vector3 = g.LIMA_COVER - g.lima.global_position
		offset.y = 0.0
		if offset.length() > .1:
			g.lima.global_position += offset.normalized() * minf(offset.length(), 3.6 * step)
			g._face(g.lima, offset)
			g.lima.update_pose(step, false, false, 0.0, 0.0)
			return
		if not g.speaking() and g._beat("lima_in_cover"): g.say("dante", "lima_cover")
		g._face(g.lima, g.shooter.global_position - g.lima.global_position)
		g.lima.update_pose(step, true, false, 0.0, 0.0)
		g._lima_fire -= step
		if g._lima_fire <= 0.0 and g._shooter_exposed:
			g._lima_fire = randf_range(.8, 1.3)
			g.lima.attack()
			g._play_at_volume("res://audio/weapons_fire/pistol_%d.wav" % randi_range(0, 3), -9.0)
		return
	# Atirador no chão: arma no coldre, ao lado de Bastos, rádio na boca.
	if g.lima.weapon.visible:
		g.lima.weapon.hide()
		g._play_at_volume("res://audio/weapons_fire/gun_holster_2.wav", -10.0)
	var beside: Vector3 = g.bastos.global_position + Vector3(-.9, 0, -.5)
	var walk: Vector3 = beside - g.lima.global_position
	walk.y = 0.0
	if walk.length() > .1:
		g.lima.global_position += walk.normalized() * minf(walk.length(), 2.4 * step)
		g._face(g.lima, walk)
		g._hands(g.lima, null, null)
		return
	g._face(g.lima, g.bastos.global_position - g.lima.global_position)
	var mouth: Vector3 = g._head(g.lima) + Vector3.UP * .14 + g._forward(g.lima) * .13 - g._forward(g.lima).cross(Vector3.UP).normalized() * .05
	g._hands(g.lima, null, mouth)
	if not g.speaking() and g._beat("lima_radio_call"): g.say("dante", "lima_radio")

func _vicente_crouch() -> void:
	# Agachado atrás da porta aberta, mãos na cabeça.
	g.vicente.global_position = g.vicente.global_position.move_toward(g._door_point() + Vector3(.35, 0, .55), .05)
	g.vicente.sit_amount = move_toward(g.vicente.sit_amount, .55, .05)
	var neck: Vector3 = g._head(g.vicente)
	var side: Vector3 = g._forward(g.vicente).cross(Vector3.UP).normalized()
	var back: Vector3 = g._forward(g.vicente) * .02
	g.vicente.hand_targets = [neck + Vector3.UP * .27 + side * .07 - back, neck + Vector3.UP * .27 - side * .07 - back]

## Vicente corre pela pista escura; se chega ao fim, para e olha para trás (ainda dá para alcançar).
func _vicente_run(step: float) -> void:
	g.vicente.sit_amount = move_toward(g.vicente.sit_amount, 0.0, step * 3.0)
	g.vicente.hand_targets = [null, null]
	if g._flee_leg >= g.VICENTE_FLEE.size():
		g._face(g.vicente, g.dante.global_position - g.vicente.global_position)
		return
	var goal: Vector3 = g.VICENTE_FLEE[g._flee_leg]
	var offset: Vector3 = goal - g.vicente.global_position
	offset.y = 0.0
	if offset.length() < .1:
		g._flee_leg += 1
		return
	g.vicente.global_position += offset.normalized() * minf(offset.length(), 4.6 * step)
	g._face(g.vicente, offset)

## Vicente cai sentado segurando a coxa; Prado no rádio; Dante vai até ele, guarda a arma e se agacha.
func _dante_wounded(step: float) -> void:
	var forward: Vector3 = g._forward(g.vicente)
	var side := forward.cross(Vector3.UP).normalized()
	if g._beat("sit_down"):
		# As pernas falham e ele senta no asfalto, pernas à frente, as mãos na coxa baleada.
		g.vicente.sit_amount = 0.0
		g.vicente.hand_targets = [null, null]
		g._ground_seat = g.vicente.global_position + forward * .05 + Vector3.UP * .16
		var thigh: Vector3 = g._ground_seat + forward * .3 + Vector3.UP * .02 - side * .1
		var grip := Basis.looking_at(forward, Vector3.UP)
		# `side` é a direita dele: o pé e a mão esquerdos vão para -side (trocados, as pernas se cruzavam).
		g.vicente.sit_on_ground(g._ground_seat, {"Left": g._ground_seat + forward * .62 - side * .16 - Vector3.UP * .1, "Right": g._ground_seat + forward * .5 + side * .16 - Vector3.UP * .1},
			{"Left": Transform3D(grip, thigh - side * .07), "Right": Transform3D(grip, thigh + side * .05)}, .8)
	if g._beat("procedure"): g.say("dante", "wounded", func(): g.say("dante", "order"))
	# A 0,85 m: de 1 m, agachado, as mãos dele paravam 30 cm antes dos pulsos.
	var stand: Vector3 = g._ground_seat + forward * .85 - Vector3.UP * .16
	var offset: Vector3 = stand - g.dante.global_position
	offset.y = 0.0
	if offset.length() > .05:
		g.dante.global_position += offset.normalized() * minf(offset.length(), 1.3 * step)
	g._face(g.dante, g.vicente.global_position - g.dante.global_position)
	g.dante.update_pose(step, offset.length() > .4, false, 0.0, 0.0)
	# De cima, os dois no quadro, aproximando.
	g._high_camera((g.dante.global_position + g.vicente.global_position) * .5, 9.0, step)
	if offset.length() <= .05 and g.stage_time > 4.5 and not g.speaking():
		g._play("res://audio/weapons_fire/gun_holster_1.wav", -6.0)
		g.dante.weapon.hide()
		g._set_stage("dante_cuff")
		g._objective_text("cuff")
		g._show_prompt("cuff")
		g._progress.value = 0.0
		g._progress.show()

## Pulsos de Vicente juntos à frente do peito, oferecidos (sentado no asfalto).
func _wrists() -> Vector3:
	return g._ground_seat + g._forward(g.vicente) * .36 + Vector3.UP * .34

func _dante_cuff(step: float) -> void:
	var holding: bool = g.autoplay or Input.is_action_pressed("interact")
	# Segurar demora; soltar devolve devagar. Não existe outro comando.
	g.cuff_progress = clampf(g.cuff_progress + (step / g.HOLD_SECONDS if holding else -step * .4), 0.0, 1.0)
	g._progress.value = g.cuff_progress
	var wrists: Vector3 = g._wrists()
	var across: Vector3 = g._forward(g.vicente).cross(Vector3.UP).normalized()
	var offer: Basis = Basis.looking_at(g._forward(g.vicente), Vector3.UP)
	g.vicente.update_seat_hands({"Left": Transform3D(offer, wrists - across * .05), "Right": Transform3D(offer, wrists + across * .05)})
	# Dante agacha na frente dele; as mãos vão aos pulsos (direita por cima, esquerda segurando).
	var body = g._body(g.dante)
	if is_instance_valid(body):
		body.sit_amount = move_toward(body.sit_amount, .8, step * 2.0)
		body.seat_height = .25
	var reach: float = smoothstep(0.0, .5, g.cuff_progress)
	if reach > .01:
		var rest: Vector3 = g.dante.global_position + Vector3.UP * .55 + g._forward(g.dante) * .25
		var grip: Vector3 = rest.lerp(wrists, reach)
		g._hands(g.dante, grip + Vector3.UP * .05 - across * .04, grip - Vector3.UP * .02 + across * .05)
	else:
		g._hands(g.dante, null, null)
	# De cima, fechando nas mãos conforme o botão é segurado.
	g._high_camera(wrists, lerpf(9.0, 5.0, smoothstep(0.0, 1.0, g.cuff_progress)), step)
	if g.cuff_progress >= 1.0:
		g._play("res://audio/weapons_fire/gun_holster_0.wav", -2.0)
		g._hide_prompt()
		g._progress.hide()
		g._objective.text = ""
		g._set_stage("dante_cuffed")

func _cut_to_black() -> void:
	# Corte seco: sem fade, a chuva e o motor somem junto com a imagem.
	g.curtain.color.a = 1.0
	if is_instance_valid(g._crosshair): g._crosshair.hide()
	g._hide_prompt()
	g._progress.hide()
	g._objective.text = ""
	g._subtitle.text = ""
	g._queue.clear()
	g._line_left = 0.0
	for player in [g._rain_audio, g._engine_audio, g._police_audio, g._radio_click]:
		if is_instance_valid(player): player.stop()

func _dante_black() -> void:
	if g.stage_time > 1.4 and g._beat("title"):
		g._title.text = g.text(g.lines().get("title"))
		var tween: Tween = g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(g._title, "modulate:a", 1.0, .8 / g.pace)
		tween.tween_interval(2.2 / g.pace)
		tween.tween_property(g._title, "modulate:a", 0.0, .8 / g.pace)
	if g.stage_time > 5.4 and g._beat("after"): g._setup_room()

func _fade(to_black: bool, seconds: float, then := Callable()) -> void:
	var tween: Tween = g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(g.curtain, "color:a", 1.0 if to_black else 0.0, seconds / g.pace)
	if then.is_valid(): tween.tween_callback(then)

## Corte para a viatura: Vicente de pé, algemado, Dante segurando o braço dele; Lima atrás do baú.
func _setup_escort() -> void:
	g.vicente.stand_up()
	var door: Vector3 = g.police.to_global(g.CAR_DOOR_LOCAL)
	var out: Vector3 = (door - g.police.global_position)
	out.y = 0.0
	out = out.normalized()
	g.vicente.global_position = door + out * .35
	g._face(g.vicente, -out)
	g.dante.global_position = door + out * 1.05 + out.cross(Vector3.UP) * .35
	g._face(g.dante, g.vicente.global_position - g.dante.global_position)
	g.dante.sit_amount = 0.0
	g.lima.global_position = g.LIMA_CARGO
	g._face(g.lima, Vector3.FORWARD)
	g._hands(g.lima, null, null)
	g._high_focus = Vector3.INF
	g._clock = 0.0
	g._set_stage("dante_escort")
	g._fade(false, .6)
	g.say("dante", "escort", g._open_cargo)

## O baú aberto: geladeira e fogão encaixotados, nada além disso.
func _open_cargo() -> void:
	TRUCK.set_loot_visible(g.truck, true)
	TRUCK.set_cargo_open(g.truck, true)
	g._play("res://audio/vehicle_fx/door_open_2.wav", -4.0)
	g._clock = g.stage_time

func _cuffed_hands() -> void:
	var forward: Vector3 = g._forward(g.vicente)
	var side := forward.cross(Vector3.UP).normalized()
	var waist: Vector3 = g.vicente.global_position + forward * .22 + Vector3.UP * .95
	g.vicente.hand_targets = [waist + side * .04, waist - side * .04]
	# Dante conduz pelo braço: a mão esquerda dele no braço direito de Vicente.
	g._hands(g.dante, null, g._head(g.vicente) - Vector3.UP * .3 - side * .2)

func _dante_escort(step: float) -> void:
	# Na viatura enquanto ele pede; no baú aberto (as caixas de eletrodoméstico à vista); de volta a ele.
	var at_cargo: bool = g._clock > 0.0 or (g._clock < 0.0 and g.stage_time + g._clock < .4)
	if at_cargo:
		# De trás do caminhão, por cima do ombro de Lima, para dentro do baú: de cima o teto escondia as caixas.
		if g.camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
			g._close_camera()
			g.camera.fov = 50.0
		g.camera.global_position = g.truck.to_global(Vector3(.9, 2.3, 10.8))
		g.camera.look_at(g.truck.to_global(Vector3(0, 1.6, 3.0)), Vector3.UP)
	else: g._high_camera(g.police.global_position.lerp(g.vicente.global_position, .5), 10.0, step)
	g._cuffed_hands()
	if g._beats.has("cargo_line") == false and g._clock > 0.0 and g.stage_time - g._clock > 1.4 and not g.speaking() and g._beat("cargo_line"):
		g.say("dante", "cargo", func(): g._clock = -g.stage_time)
	# Depois do "Viu?!": Dante põe Vicente na viatura sem responder e vai para o volante.
	if g._clock < 0.0 and g.stage_time + g._clock > 1.2 and g._beat("into_car"):
		g.vicente.hide()
		g._play("res://audio/vehicle_fx/door_close_0.wav", -4.0)
	if g._beats.has("into_car"):
		g._hands(g.dante, null, null)
		var driver: Vector3 = g.police.to_global(g.CAR_DRIVER_LOCAL)
		var offset: Vector3 = driver - g.dante.global_position
		offset.y = 0.0
		if offset.length() > .05:
			g.dante.global_position += offset.normalized() * minf(offset.length(), 1.4 * step)
			g._face(g.dante, offset)
		elif g._beat("driver_in"):
			g.dante.hide()
			g._play("res://audio/vehicle_fx/door_close_1.wav", -4.0)
			g._police_audio.volume_db = -14.0
			g._set_stage("dante_drive")

## A viatura sai com ele no banco de trás, giroflex ligado, e some na pista.
func _dante_drive(step: float) -> void:
	g._police_speed = minf(13.0, g._police_speed + 3.2 * step)
	g.police.rotation.y = move_toward(g.police.rotation.y, 0.0, step * .25)
	g.police.position.x = move_toward(g.police.position.x, g.LANE_X, step * .9)
	g.police.position.z -= g._police_speed * step
	g._high_camera(g.police.global_position + Vector3(0, 0, 4.0), 19.0, step)
	if g.stage_time > 4.0 and g._beat("leave"): g._fade(true, 1.0, g._setup_prison)

## A prisão à noite: muralha, guaritas, holofote; a viatura chega e o portão abre.
func _setup_prison() -> void:
	g._prison.show()
	g.police.global_position = g.PRISON + Vector3(1.8, 0, 46.0)
	g.police.rotation = Vector3.ZERO
	g._police_speed = 9.0
	g._close_camera()
	g.camera.fov = 52.0
	g.camera.global_position = g.PRISON + Vector3(17.0, 6.5, 31.0)
	g.camera.look_at(g.PRISON + Vector3(0, 3.5, -7.0), Vector3.UP)
	# Mais longe da câmera que a blitz: a névoa recua para a muralha aparecer.
	g._environment.fog_depth_begin = 45.0
	g._environment.fog_depth_end = 260.0
	g._set_stage("dante_prison")
	g._fade(false, 1.0)

func _dante_prison(step: float) -> void:
	var stop_z: float = g.PRISON.z + 1.0
	var distance: float = g.police.global_position.z - stop_z
	g._police_speed = minf(g._police_speed, sqrt(maxf(0.0, 2.0 * 2.6 * distance)))
	g.police.global_position.z -= minf(g._police_speed * step, maxf(0.0, distance))
	if g.stage_time > 2.4 and g._beat("gate"): g._play("res://audio/vehicle_fx/air_brake.wav", -12.0)
	if g._beats.has("gate"):
		for index in g._gate.size():
			var leaf: Node3D = g._gate[index]
			leaf.position.x = move_toward(leaf.position.x, (-6.2 if index == 0 else 6.2), step * 1.3)
	if is_instance_valid(g._flood): g._flood.rotation.y = -.35 + sin(g.stage_time * .5) * .25
	if g.stage_time > 7.0 and g._beat("prison_out"): g._fade(true, 1.2, func(): g._cut_to_black(); g._set_stage("dante_black"))

## Oito anos depois: Dante, sem farda, sentado na beira da cama com a carta, a cabeça baixa. Sem fala.
func _setup_room() -> void:
	g._prison.hide()
	g._room.show()
	g.police.hide()
	g.rain.emitting = false
	g.rain.hide()
	g._environment.fog_depth_begin = 32.0
	g._environment.fog_depth_end = 150.0
	g.dante.show()
	g.dante.civilian()
	g.dante.combat_facing = NAN
	g.dante.global_position = g.ROOM
	# O corpo inteiro vira para +z, não só o visual: a pose sentada do jogo lê as mãos no espaço do Actor, e
	# com só o visual girado as palmas ficavam de trás para a frente (braços torcidos).
	g.dante.rotation.y = PI
	g.dante.visual.rotation.y = 0.0
	# Curvado para a frente, cotovelos perto dos joelhos, a carta entre as mãos e a cabeça baixa sobre ela.
	g.dante.head_bow = .5
	# Mãos nas bordas da folha como no volante (Y ao longo do que segura, Z para o corpo), a folha inclinada
	# com o topo longe dele.
	var hold: Basis = g.dante.global_basis * Basis(Vector3.RIGHT, -.6)
	# De frente para +z, a esquerda dele é +x (trocado, uma perna atravessava a outra).
	g.dante.seat(g.ROOM + Vector3(0, .64, -.42), {"Left": g.ROOM + Vector3(.18, .08, .14), "Right": g.ROOM + Vector3(-.18, .08, .14)},
		{"Left": Transform3D(hold, g.ROOM + Vector3(.12, .8, .1)), "Right": Transform3D(hold, g.ROOM + Vector3(-.12, .8, .1))}, -.32)
	g.letter.show()
	# Três-quartos pela esquerda dele, na altura do rosto curvado: a luz do abajur no rosto e na carta, a
	# janela de chuva e a cama ao fundo.
	g._close_camera()
	g.camera.fov = 40.0
	g.camera.global_position = g.ROOM + Vector3(1.2, .98, 1.1)
	g.camera.look_at(g.ROOM + Vector3(0, .9, -.18), Vector3.UP)
	if is_instance_valid(g._rain_audio):
		g._rain_audio.volume_db = -18.0
		g._rain_audio.play()
	g._title.modulate.a = 0.0
	g._set_stage("dante_after")
	g._fade(false, 1.2)

func _dante_after(step: float) -> void:
	# A carta entre as mãos, com a face voltada para o rosto dele; a câmera se aproxima devagar.
	var left: Vector3 = g.dante.combat_palm_position("Left")
	var right: Vector3 = g.dante.combat_palm_position("Right")
	var middle: Vector3 = (left + right) * .5
	var facing: Vector3 = (g._eyes(g.dante) - middle).normalized()
	var across := (left - right).normalized()
	across = (across - facing * across.dot(facing)).normalized()
	g.letter.global_transform = Transform3D(Basis(across, facing, across.cross(facing)), middle)
	g.camera.global_position = g.camera.global_position.move_toward(g.ROOM + Vector3(.95, .95, .82), step * .05)
	g.camera.look_at(g.ROOM + Vector3(0, .9, -.18), Vector3.UP)
	if g.stage_time > 7.0 and g._beat("end"): g._fade(true, 1.4, func(): g._finish(false))
