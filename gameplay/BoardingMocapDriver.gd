extends RefCounted
## Embarque com mocap pela porta do motorista do carro baixo (entrada, saída, roubo com o "Pull Pilot
## From Seat" e a volta no meio da entrada), separado do VehicleBoardingPresentation em 01/11 (Onda 2
## do plano de divisão). Estado (_mocap, _pull, _segments, phase, progress, _motion...) e sinais
## continuam na apresentação, porque testes e o Driving leem esses campos lá; ela mantém cada função
## antiga como delegação de uma linha. `g` fica como Node, e não como o script da apresentação, para
## não criar preload cíclico e para as medições que trocam o fonte dela (--boarding-source) seguirem
## valendo. Até as chamadas entre funções passam por `g.`, como no GameplayCombatSound.

const MOCAP := preload("res://gameplay/VehicleBoardingMocap.gd")
const CARJACKING := preload("res://gameplay/VehicleCarjacking.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _begin_mocap_entry() -> void:
	g._visual_yaw = g.actor.visual.rotation.y
	g._visual_position = g.actor.visual.position
	g._visual_scale = g.actor.visual.scale
	g._mocap = MOCAP.new()
	g._mocap.prepare(g.actor, g.vehicle, g.side, true, MOCAP.seat_pelvis(g.vehicle))
	# A folha (dobradiça e ponta) entra no desvio do caminho; vazia, o caminho só contorna o casco.
	g._layout = g.vehicle.door_layout(g.side) if g.vehicle.has_method("door_layout") else {}
	var target: Vector3 = g._mocap.entry_start()
	var from_local: Vector3 = g.vehicle.to_local(g._start)
	var to_local: Vector3 = g.vehicle.to_local(target)
	g._planning_closed = true
	var route: Array[Vector2] = g._plan(Vector2(from_local.x, from_local.z), Vector2(to_local.x, to_local.z))
	g._path = [g._start]
	for index in range(1, route.size()):
		var point: Vector3 = g.vehicle.to_global(Vector3(route[index].x, 0.0, route[index].y))
		point.y = target.y if index == route.size() - 1 else lerpf(g._start.y, target.y, float(index) / float(route.size() - 1))
		g._path.append(point)
	g._path_length = 0.0
	for index in range(1, g._path.size()): g._path_length += g._path[index - 1].distance_to(g._path[index])
	g._walk_seconds = clampf(g._path_length / 2.3, .15, 3.2)
	# Chegou ao ponto: um instante parado, virado para a porta, antes de esticar a mão.
	g._approach_seconds = g._walk_seconds + .12
	var body: float = g._mocap.seconds()
	g.duration = g._approach_seconds + body
	g._approach = g._approach_seconds / g.duration
	g.active = true
	g.phase = "approach"
	g._motion = g.create_tween()
	g._motion.tween_property(g, "progress", 1.0, g.duration)
	g._motion.tween_callback(g._finish_entry)
	g._apply()

## Saída com o mocap, se o chão onde o clipe termina (~0,9 m fora da porta) estiver livre.
func _begin_mocap_exit() -> bool:
	var mocap := MOCAP.new()
	var seat: Vector3 = g._seat_from_pelvis if g._seat_from_pelvis.is_finite() else MOCAP.seat_pelvis(g.vehicle)
	mocap.prepare(g.actor, g.vehicle, g.side, false, seat)
	var landing: Vector3 = mocap.exit_landing()
	if not g._landing_clear(landing): return false
	g._mocap = mocap
	g._landing = landing
	g._visual_yaw = mocap.exit_yaw()
	# A mistura do banco para o clipe (pose, pelve e escala do motorista) é a de sempre:
	# `_apply_seat_blend` depois de cada pose do clipe, a partir do que `_leave_seat` guardou.
	g.progress = 0.0
	g.phase = "open"
	g.actor.show()
	g._motion = g.create_tween()
	g._motion.tween_property(g, "progress", 1.0, mocap.seconds())
	g._motion.tween_callback(g._finish_exit)
	g._apply()
	return true

func _landing_clear(point: Vector3) -> bool:
	if not is_instance_valid(g.vehicle) or not g.vehicle.is_inside_tree(): return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .92)
	query.collision_mask = 7
	query.exclude = [g.vehicle.get_rid(), g.actor.get_rid()]
	return g.vehicle.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _begin_mocap_carjack() -> void:
	g._begin_mocap_entry()
	g._mocap_carjack = true
	g._pull = MOCAP.new()
	g._pull.setup(g.actor, g.vehicle, g.side, g.PULL, g.PULL_MARKS, -g.vehicle.global_basis.x * float(g.side), MOCAP.seat_pelvis(g.vehicle), float(g.PULL_MARKS.sit_to))
	g._pull.obstacles = g.carjacking.door_obstacles()
	# Segmentos em s de jogo: caminhada, abrir a porta, puxar e sentar, fechar a porta e pegar o volante.
	g._segments = [g._approach_seconds, g.ENTER_DOOR_END / MOCAP.SPEED,
		(float(g.PULL_MARKS.end) - float(g.PULL_MARKS.start)) / float(g.PULL_MARKS.speed),
		(float(MOCAP.ENTER_MARKS.end) - g.ENTER_TAIL) / MOCAP.SPEED]
	g.duration = 0.0
	for seconds in g._segments: g.duration += seconds
	g._approach = g._approach_seconds / g.duration
	if is_instance_valid(g._motion): g._motion.kill()
	g._motion = g.create_tween()
	g._motion.tween_property(g, "progress", 1.0, g.duration)
	g._motion.tween_callback(g._finish_entry)
	g._apply()

func _apply_mocap_carjack(t: float) -> void:
	g.actor.visible = true
	var elapsed: float = t * g.duration
	var segment := 0
	while segment < g._segments.size() - 1 and elapsed >= g._segments[segment]:
		elapsed -= g._segments[segment]
		segment += 1
	match segment:
		0:
			g._mocap_walk(t)
			if not g.carjacking.released: g.carjacking.follow_seat()
		1:
			if g._segment != 1: g._mocap.begin_blend()
			g.phase = "reach"
			g._mocap.pose(elapsed * MOCAP.SPEED, elapsed)
			if not g.carjacking.released: g.carjacking.follow_seat()
		2:
			var pull_time := float(g.PULL_MARKS.start) + elapsed * float(g.PULL_MARKS.speed)
			var victim_time: float = pull_time - g.PULL_OFFSET
			if g._segment != 2:
				g._pull.begin_blend()
				if not g.carjacking.released:
					if g.carjacking.mocap_begin(victim_time): g._extracting = true
					# Sem o clipe da vítima (corpo sem juntas): ela vai direto ao pouso verificado.
					else: g.carjacking.release()
				g.phase = "pull_driver"
			g._pull.pose(pull_time, elapsed)
			if g.carjacking.mocap_active:
				g.carjacking.mocap_pose(g.actor, victim_time, g._frame_delta)
				g._extraction_progress = clampf((victim_time - .9) / (CARJACKING.MOCAP_THROW_AT - .9), 0.0, 1.0)
			elif g.carjacking.released:
				g._extracting = false
				g._extraction_progress = 1.0
		_:
			if g._segment != 3:
				g._mocap.begin_blend()
				g._extracting = false
				g.phase = "step"
			g._mocap.pose(g.ENTER_TAIL + elapsed * MOCAP.SPEED, elapsed)
	g._segment = segment

## Caminhada até o ponto em que o clipe de entrada começa, virando para a porta no fim.
func _mocap_walk(t: float) -> void:
	g.phase = "approach"
	g._mocap_blending = false
	var k := clampf(t / maxf(g._approach, .001) * g._approach_seconds / maxf(g._walk_seconds, .001), 0.0, 1.0)
	g.actor.global_position = g._path_at(k)
	g.actor.visual.position = g._visual_position
	g.actor.visual.scale = g._visual_scale
	var cycles := maxf(g._path_length / 1.35, .5)
	if k >= 1.0: g._pose_idle()
	else: g._pose_cycle("Walking", (1.0 - k if g.exiting else k) * cycles)
	var heading: Vector3 = g._path_heading(k)
	var yaw: float = g._yaw_toward(heading) if heading.length_squared() > .0004 else g._mocap.yaw
	if g.exiting: yaw = lerp_angle(yaw, g._mocap.yaw, 1.0 - smoothstep(0.0, .25, k))
	else: yaw = lerp_angle(yaw, g._mocap.yaw, smoothstep(.7, 1.0, k))
	g.actor.visual.rotation.y = yaw

func _apply_mocap(t: float) -> void:
	g.actor.visible = true
	if g._mocap.clip == MOCAP.EXIT:
		var exit_time: float = t * float(g._mocap.marks.end)
		# "close_outside" é da saída antiga (`_apply_body` prende o corpo no pouso): aqui o clipe segue.
		g.phase = "open" if exit_time < float(g._mocap.marks.door_opened) else ("closing" if exit_time > float(g._mocap.marks.door_close) else "step")
		g._mocap.pose(exit_time, exit_time / MOCAP.SPEED)
		return
	if t < g._approach:
		g._mocap_walk(t)
		return
	var clip_time := clampf((t - g._approach) / maxf(1.0 - g._approach, .001), 0.0, 1.0) * float(g._mocap.marks.end)
	g.phase = "reach" if clip_time < float(g._mocap.marks.door_opened) else "step"
	if g.exiting:
		g._mocap.pose_reverse(clip_time)
		return
	if not g._mocap_blending:
		g._mocap_blending = true
		g._mocap.begin_blend()
	g._mocap.pose(clip_time, clip_time / MOCAP.SPEED)

## Desistir no meio da entrada: o clipe volta de trás para frente (a porta fecha quando a mão volta
## para antes de abri-la) e o corpo refaz o caminho. Depois de sentar não há volta: a entrada termina.
func _reverse_mocap_entry() -> bool:
	if g._mocap.clip != MOCAP.ENTER: return false
	var clip_time := clampf((g.progress - g._approach) / maxf(1.0 - g._approach, .001), 0.0, 1.0) * float(g._mocap.marks.end)
	if g.progress > g._approach and clip_time >= float(g._mocap.marks.sit_from): return false
	g.exiting = true
	if is_instance_valid(g._motion): g._motion.kill()
	g._motion = g.create_tween()
	g._motion.tween_property(g, "progress", 0.0, maxf(.35, g.progress * g.duration))
	g._motion.tween_callback(g._begin_close_exit)
	g._motion.tween_interval(.3)
	g._motion.tween_callback(g._finish_exit)
	return true
