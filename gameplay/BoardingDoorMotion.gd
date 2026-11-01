extends RefCounted
## Movimento do corpo pela porta (carro baixo, picape/SUV/van/caminhão) com a mão no batente,
## separado do VehicleBoardingPresentation em 01/11 (Onda 2 do plano de divisão). Estado (phase,
## _yaw, _drop, _scale_now, _crouch...) continua na apresentação, que mantém cada função antiga
## como delegação de uma linha. `g` fica como Node, sem preload cíclico, e até as chamadas entre
## funções passam por `g.`.

var g: Node

func _init(host: Node) -> void:
	g = host

## Mão no batente traseiro do vão. O alvo sobe junto com o corpo no degrau (a mão desliza
## no montante) e nunca fica acima do alcance do braço.
func _grip_pose(weight: float, feet_y: float) -> void:
	if weight <= .02: return
	var grip: Vector3 = g.vehicle.to_global(g._layout.grip)
	grip.y = clampf(feet_y + 1.12, feet_y + .9, maxf(grip.y, feet_y + 1.0))
	var sign_side := -1.0 if g._grip_side == "Left" else 1.0
	var default_hand := Vector3(.23 * sign_side, .90, -.28)
	var target: Vector3 = default_hand.lerp(g.actor.visual.to_local(grip), clampf(weight, 0.0, 1.0))
	g.actor._solve_combat_arm(g._grip_side, target, Basis.IDENTITY, true, sign_side)
	g.actor._set_combat_grips(g._grip_side == "Right" and weight > .5, g._grip_side == "Left" and weight > .5)

func _apply_door(t: float) -> void:
	var yaws: Array = g._car_yaws()
	var hidden_after := .96
	var drop := 0.0
	var yaw := 0.0
	g._scale_now = 1.0
	if t < g._approach:
		g.phase = "approach"
		var k := clampf(t / maxf(g._approach, .001) * g._approach_seconds / maxf(g._walk_seconds, .001), 0.0, 1.0)
		g.actor.global_position = g._path_at(k)
		if not g.exiting and k >= 1.0: g._open_door()
		var cycles := maxf(g._path_length / 1.35, .5)
		if k >= 1.0 and not g.exiting: g._pose_idle()
		else: g._pose_cycle("Walking", (1.0 - k if g.exiting else k) * cycles)
		var heading: Vector3 = g._path_heading(k)
		var face: float = g._yaw_toward(g._gate_world - g.actor.global_position)
		yaw = g._yaw_toward(heading) if heading.length_squared() > .0004 else face
		if not g.exiting: yaw = lerp_angle(yaw, face, smoothstep(.8, 1.0, k))
		else: yaw = lerp_angle(yaw, face, 1.0 - smoothstep(.0, .2, k))
	else:
		var u := clampf((t - g._approach) / maxf(1.0 - g._approach, .001), 0.0, 1.0)
		g._open_door()
		if g._kind == "car": g._door_car(u, yaws)
		else: g._door_climb(u, yaws)
		yaw = g._yaw
		drop = g._drop
	g.actor.visual.position = g._visual_position + Vector3.UP * drop
	g.actor.visual.rotation.y = yaw
	g.actor.visual.scale = g._visual_scale * g._scale_now
	g.actor.visible = g._seated_driver or t < g._approach + (1.0 - g._approach) * hidden_after

## Carro baixo. Espera fora do arco, dá um passo até o vão olhando para o banco, segura o
## batente e desliza para dentro abaixado, virando para o volante já sentado.
func _door_car(u: float, yaws: Array) -> void:
	var face_gate: float = g._yaw_toward(g._gate_world - g._stand_world)
	var reach_k := smoothstep(0.0, .2, u)
	var gate_k := smoothstep(.2, .55, u)
	var seat_k := smoothstep(.55, .88, u)
	var point: Vector3 = g._stand_world.lerp(g._reach_world, reach_k).lerp(g._gate_world, gate_k).lerp(g._seat, seat_k)
	g.actor.global_position = point
	g.phase = "reach" if u < .2 else "step"
	g._pose_idle()
	g.actor.pose_vehicle(smoothstep(.35, .95, u), 0.0, g.side, 1.0)
	g._grip_pose(smoothstep(.02, .18, u) * (1.0 - smoothstep(.62, .82, u)), point.y)
	g._yaw = lerp_angle(face_gate, yaws[1], smoothstep(.6, .95, u))
	# O quadril desce até o banco antes de cruzar a lataria: a cabeça passa sob o teto do vão.
	g._drop = -g._crouch * smoothstep(.12, .5, u)
	g._scale_now = lerpf(1.0, g._body_scale, smoothstep(.12, .5, u))

## Picape, SUV, van e caminhão: espera fora do arco, sobe no estribo (ciclo de escada) com a
## mão no montante e só então cruza o vão até o banco.
func _door_climb(u: float, yaws: Array) -> void:
	var truck: bool = g._kind == "truck"
	var climb_end := .62 if truck else .50
	var floor_y: float = g._seat.y
	var face_gate: float = g._yaw_toward(g._gate_world - g._stand_world)
	var step_point: Vector3 = g._reach_world.lerp(g._gate_world, .35)
	var point: Vector3
	if u < climb_end:
		g.phase = "reach"
		var k := smoothstep(.06, climb_end, u)
		point = g._stand_world.lerp(g._reach_world, smoothstep(0.0, .12, u)).lerp(step_point, k)
		point.y = lerpf(g._stand_world.y, floor_y, k)
		g.actor.global_position = point
		g._pose_transition(.05 + k * (.55 if truck else .30))
		g._grip_pose(smoothstep(.0, .1, u), point.y)
		g._yaw = face_gate
		g._drop = 0.0
	else:
		g.phase = "step"
		var k := smoothstep(climb_end, .9, (u))
		var inside: Vector3 = g._gate_world
		point = step_point.lerp(inside, smoothstep(0.0, .5, k)).lerp(g._seat, smoothstep(.4, 1.0, k))
		point.y = floor_y
		g.actor.global_position = point
		g._pose_idle()
		g.actor.pose_vehicle(k, 0.0, g.side, 1.0)
		var seated: Array = g.actor._capture_pose()
		g._pose_transition(.60 if truck else .35)
		g.actor._apply_blend(g.actor._capture_pose(), seated, smoothstep(0.0, .35, k))
		g._grip_pose(1.0 - smoothstep(.1, .5, k), point.y)
		g._yaw = lerp_angle(face_gate, yaws[1], smoothstep(.3, 1.0, k))
		g._drop = -g._crouch * smoothstep(0.0, .35, k)
		g._scale_now = lerpf(1.0, g._body_scale, smoothstep(0.0, .35, k))
