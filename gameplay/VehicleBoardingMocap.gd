extends RefCounted
## Entrar e sair do carro pela porta do motorista com o mocap do Mixamo ("Entering Car" / "Exiting Car",
## biblioteca "mixveh" do Actor). Antes (até 28/10) o corpo deslizava em linha reta até o banco com a
## pose de pé dobrada por IK, e a porta abria e fechava sozinha. No clipe a pessoa puxa a maçaneta, dá
## um passo para trás enquanto a folha abre, entra com a perna direita, senta, recolhe a esquerda, fecha
## a porta com a mão esquerda e só então pega o volante; na saída abre a porta, põe o pé no chão,
## levanta apoiada, sai, vira e empurra a porta.
##
## O clipe é tocado no espaço do esqueleto, com o deslocamento do quadril: o Actor fica parado em
## `origin` e o visual girado para que o +Z do clipe aponte para dentro do carro (entrada) ou para a
## frente dele (saída). O alinhamento é MEDIDO no jogo: pose no instante sentado → pelve sobre o banco
## (`INTERIOR.pelvis_world`), pose no instante da maçaneta → mão sobre a maçaneta da folha real.
## Só carro baixo pela porta esquerda; o resto segue o embarque antigo. GETECO_MOCAP_BOARDING=0 desliga.
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const ENTER := "mixveh/enter_car"
const EXIT := "mixveh/exit_car"
static var enabled := OS.get_environment("GETECO_MOCAP_BOARDING") != "0"
## Marcos dos clipes (s do clipe), lidos nas medidas de evidence/mocap-vehicle-20261028/clips.json:
## mão esquerda na maçaneta, folha abrindo, quadril descendo ao banco, mão puxando a porta, fim.
const ENTER_MARKS := {"reach": 0.8, "door_open": 0.85, "door_opened": 1.8, "shift_out": 2.9,
	"sit_from": 2.3, "sit_to": 3.3, "door_close": 3.75, "door_closed": 4.35, "end": 4.9}
## Saída: mão empurra a porta, pé no chão, levanta (2,0–2,8 s), sai, vira e empurra a porta (3,95–4,5 s).
const EXIT_MARKS := {"door_open": 0.55, "door_opened": 1.5, "stand_from": 2.0, "stand_to": 2.8,
	"door_close": 3.95, "door_closed": 4.5, "end": 4.65}
## 1,3× o tempo do mocap: o clipe é de quem entra sem pressa (5,5 s); no jogo fica ~3,8 s.
const SPEED := 1.3
## Mistura da pose de antes (caminhada/banco) para o primeiro quadro do clipe.
const BLEND_IN := 0.2

var actor: CharacterBody3D
var vehicle: CharacterBody3D
var side := -1
var clip := ""
var marks: Dictionary = {}
## Origem do Actor e guinada do visual enquanto o clipe toca.
var origin := Vector3.ZERO
var yaw := 0.0
## Diferença de altura entre o banco do clipe e o deste carro, aplicada só com o corpo sentado.
var drop := 0.0
## Deslocamento no plano para a mão cair na maçaneta desta porta (some antes de sentar).
var reach_shift := Vector3.ZERO
var base_position := Vector3.ZERO
var base_scale := Vector3.ONE
var speed := SPEED
var _from_pose: Array = []
## Curva do tronco e encolhimento correntes para a cabeça passar no vão (ver `_duck`).
var _bend := 0.0
var _shrink := 1.0
var _duck_clock := -1.0
const DUCK_STEP := .12
const DUCK_MAX := .84
## Da junta da cabeça ao topo do cabelo (o mesmo de VehicleBoardingPresentation).
const HEAD_TOP := .26
var _from_origin := Vector3.ZERO
var _from_visual := Vector3.ZERO
var _door_opened := false
var _door_closed := false
## Instante do clipe no último ajuste da porta (para a velocidade máxima da folha).
var _door_clock := -1.0
## Porta inteira no mocap (~69°): a de tabela (60°) deixava o vão estreito para o corpo do clipe.
const DOOR_LIMIT := 1.2
## Batente da folha (~75°): até aqui o corpo no vão pode empurrá-la além da abertura normal.
const DOOR_HARD_LIMIT := 1.32
const DOOR_SPEED := 3.5
## Raio do corpo em volta de cada ponto conferido contra a folha (tronco, cabeça, joelhos e pés).
const BODY_RADIUS := .17
## Altura (no veículo) da borda de baixo da folha de carro baixo.
const DOOR_BOTTOM := .28
## Sentado o forro da porta fecha colado na coxa: o quadril sentado conta só este raio contra a folha
## (com o raio de pé, no conversível o banco colado à porta segurava a folha aberta e o recuo tirava
## o corpo do banco).
const SEATED_RADIUS := .08
## Recuo de quem está no caminho da folha (m/s) e volta dele quando a folha passou.
## Recuo planejado (mundo) para o tronco ficar fora do arco da folha (ver `_plan_clearance`).
var clearance := Vector3.ZERO
const DOOR_POINTS := ["Hips", "Spine02", "Head", "LeftLeg", "RightLeg", "LeftUpLeg", "RightUpLeg"]
## Outros corpos que passam pelo vão (o motorista arrancado no roubo): juntas conferidas como as do Dante.
var obstacles: Array[Node3D] = []

static func available(p_actor: Node, p_vehicle: Node, p_side: int, kind: String) -> bool:
	if not enabled or kind != "car" or p_side != -1: return false
	if not is_instance_valid(p_actor) or p_actor.get("animation") == null or p_actor.get("skeleton") == null: return false
	var player: AnimationPlayer = p_actor.animation
	return player.has_animation(ENTER) and player.has_animation(EXIT) and p_vehicle.has_method("animate_driver_door")

## Pelve do motorista sentado neste carro, em coordenadas do mundo.
static func seat_pelvis(p_vehicle: Node3D) -> Vector3:
	var s := INTERIOR.spec(p_vehicle) if INTERIOR.shows_driver(p_vehicle) else {}
	if s.is_empty(): return p_vehicle.driver_seat_anchor() + Vector3.UP * .1
	return p_vehicle.to_global(Vector3(float(s.sx), float(s.floor) + float(s.hip), float(s.sz)))

func seconds() -> float:
	return (float(marks.end) - float(marks.get("start", 0.0))) / speed

## `seat`: pelve no banco (mundo). Entrada: +Z do clipe para dentro do carro; saída: para a frente dele.
func prepare(p_actor: CharacterBody3D, p_vehicle: CharacterBody3D, p_side: int, entering: bool, seat: Vector3) -> void:
	var facing: Vector3 = -p_vehicle.global_basis.x * float(p_side) if entering else -p_vehicle.global_basis.z
	# Entrada: o quadril ainda anda ~10 cm depois de sentar (recolhe a perna, pega o volante); alinhar no
	# fim deixa a pelve no banco quando o motorista assume (test_vehicle_doors, beach_cabriolet a 0,22 m).
	setup(p_actor, p_vehicle, p_side, ENTER if entering else EXIT, ENTER_MARKS if entering else EXIT_MARKS, facing,
		seat, float(ENTER_MARKS.end) if entering else 0.0, entering)

## Qualquer clipe da "mixveh" no referencial do carro: `facing` é para onde aponta o +Z do clipe e
## `seat_time` o instante do clipe em que a pelve deve estar sobre `seat`. `marks` dá os instantes de
## sentar (sit_from/sit_to) ou levantar (stand_from/stand_to), das portas e o fim.
func setup(p_actor: CharacterBody3D, p_vehicle: CharacterBody3D, p_side: int, p_clip: String, p_marks: Dictionary,
		facing: Vector3, seat: Vector3, seat_time: float, measure_reach := false) -> void:
	actor = p_actor
	vehicle = p_vehicle
	side = p_side
	clip = p_clip
	marks = p_marks
	speed = float(marks.get("speed", SPEED))
	base_position = actor.visual.position
	base_scale = actor.visual.scale
	facing.y = 0.0
	facing = facing.normalized()
	# O visual olha para -Z; o modelo do Dante é girado 180° dentro dele, então o +Z do clipe é o -Z do visual.
	yaw = atan2(-facing.x, -facing.z)
	var saved_position := actor.global_position
	var saved_rotation: Vector3 = actor.visual.rotation
	var saved_pose: Array = actor._capture_pose()
	origin = Vector3(seat.x, vehicle.global_position.y + .04, seat.z)
	reach_shift = Vector3.ZERO
	drop = 0.0
	_place(seat_time)
	actor._pose_clip(clip, seat_time)
	var pelvis: Vector3 = INTERIOR.pelvis_world(actor)
	origin += Vector3(seat.x - pelvis.x, 0.0, seat.z - pelvis.z)
	drop = seat.y - pelvis.y
	var ground := _ground(origin)
	drop += origin.y - ground
	origin.y = ground
	if measure_reach: reach_shift = _measure_reach()
	clearance = Vector3.ZERO
	if clip == ENTER: clearance = _plan_clearance(float(marks.door_open), float(marks.door_opened))
	elif clip == EXIT: clearance = _plan_clearance(float(marks.door_close), float(marks.end))
	actor._apply_pose(saved_pose)
	actor.global_position = saved_position
	actor.visual.rotation = saved_rotation
	actor.visual.position = base_position
	actor.visual.scale = base_scale

## Onde o Actor começa o clipe de entrada (o corpo anda até aqui e vira para a porta).
func entry_start() -> Vector3:
	return origin + reach_shift

## Onde o corpo termina a saída, no chão (para conferir espaço livre antes de escolher o mocap).
func exit_landing() -> Vector3:
	var saved_pose: Array = actor._capture_pose()
	var saved_position := actor.global_position
	var saved_rotation: Vector3 = actor.visual.rotation
	# No fim, com o recuo planejado: é ali que o corpo fica (e que precisa estar livre).
	_place(float(marks.end))
	actor._pose_clip(clip, float(marks.end))
	var pelvis: Vector3 = INTERIOR.pelvis_world(actor)
	actor._apply_pose(saved_pose)
	actor.global_position = saved_position
	actor.visual.rotation = saved_rotation
	actor.visual.position = base_position
	actor.visual.scale = base_scale
	return Vector3(pelvis.x, origin.y, pelvis.z)

## Guinada (`visual.rotation.y`) do corpo no fim da saída.
func exit_yaw() -> float:
	var saved_pose: Array = actor._capture_pose()
	var saved_rotation: Vector3 = actor.visual.rotation
	_place(float(marks.end))
	actor._pose_clip(clip, float(marks.end))
	# Frente do quadril: +Z do esqueleto no repouso, girado pela pose do clipe.
	var hips: Basis = actor.skeleton.get_bone_global_pose(actor.hips).basis * actor.skeleton.get_bone_global_rest(actor.hips).basis.inverse()
	var front: Vector3 = actor.skeleton.global_basis.orthonormalized() * hips.orthonormalized() * Vector3(0, 0, 1)
	actor._apply_pose(saved_pose)
	actor.visual.rotation = saved_rotation
	front.y = 0.0
	if front.length_squared() < .0001: return yaw
	return atan2(-front.x, -front.z)

func _place(clip_time: float) -> void:
	var shift := reach_shift * _reach_weight(clip_time)
	actor.global_position = origin + shift + clearance * _clearance_weight(clip_time)
	actor.visual.rotation = Vector3(0.0, yaw - actor.global_rotation.y, 0.0)
	actor.visual.scale = base_scale
	actor.visual.position = base_position + Vector3.UP * drop * _seat_weight(clip_time)

## Recuo planejado: entra antes de a folha andar e, na entrada, sai enquanto o corpo vai para o vão
## (a porta já está aberta inteira); na saída fica até o fim (o corpo termina fora do arco).
func _clearance_weight(clip_time: float) -> float:
	if clearance == Vector3.ZERO: return 0.0
	if clip == ENTER:
		return smoothstep(float(marks.door_open) - .4, float(marks.door_open), clip_time) 			* (1.0 - smoothstep(float(marks.door_opened), float(marks.shift_out), clip_time))
	if clip == EXIT: return smoothstep(float(marks.stand_to), float(marks.door_close), clip_time)
	return 0.0

## Menor recuo (radial à dobradiça, como quem dá passos para trás) que tira o tronco do arco que a folha
## varre na janela [from, to] do clipe, medido nas poses do próprio clipe. Calculado uma vez: um recuo
## reativo, refeito a cada quadro, não tinha alvo estável e chegou a tirar o corpo ~1 m do banco.
func _plan_clearance(from: float, to: float) -> Vector3:
	var door = vehicle.get("door_presentation")
	var layout: Dictionary = vehicle.door_layout(side) if vehicle.has_method("door_layout") else {}
	if door == null or layout.is_empty(): return Vector3.ZERO
	var hinge: Vector3 = layout.hinge
	var reach := float(layout.length) + BODY_RADIUS + .05
	var sweep := maxf(float(door.angle), DOOR_LIMIT)
	var samples: Array = []
	var time := from
	while time <= to + .001:
		_place(time)
		actor._pose_clip(clip, time)
		var points: Array[Vector3] = []
		for bone_name in ["Hips", "Spine02", "Head"]:
			var bone: int = actor._combat_bones.get(bone_name, -1)
			if bone >= 0: points.append(vehicle.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone).origin)))
		samples.append(points)
		time += .05
	var offset := Vector3.ZERO
	for attempt in 6:
		var worst := Vector3.ZERO
		for points in samples:
			for raw in points:
				var point: Vector3 = raw + offset
				if point.y < DOOR_BOTTOM: continue
				var relative := Vector2(float(side) * (point.x - hinge.x), point.z - hinge.z)
				var distance := relative.length()
				if distance < .12 or distance >= reach: continue
				var margin := asin(clampf(BODY_RADIUS / distance, 0.0, 1.0))
				var at := atan2(relative.x, relative.y)
				if at + margin < 0.0 or at - margin > sweep: continue
				var push := Vector3(float(side) * relative.x, 0.0, relative.y).normalized() * (reach - distance + .01)
				if push.length() > worst.length(): worst = push
		if worst == Vector3.ZERO: break
		offset += worst
	return vehicle.global_basis * offset.limit_length(.9)

## Peso do banco: 0 de pé, 1 sentado (a correção de altura só vale com o corpo no banco).
func _seat_weight(clip_time: float) -> float:
	if marks.has("sit_from"): return smoothstep(float(marks.sit_from), float(marks.sit_to), clip_time)
	if marks.has("stand_from"): return 1.0 - smoothstep(float(marks.stand_from), float(marks.stand_to), clip_time)
	return 0.0

## A mão vai à maçaneta real enquanto abre a porta; o desvio some quando o corpo cruza o vão.
func _reach_weight(clip_time: float) -> float:
	if reach_shift == Vector3.ZERO or not marks.has("shift_out"): return 0.0
	return 1.0 - smoothstep(float(marks.door_opened), float(marks.shift_out), clip_time)

## Mão esquerda do clipe no instante da maçaneta contra a maçaneta da folha fechada (perto da borda
## traseira, na altura da cintura). Limitado: a porta de cada carro é diferente, o banco manda.
func _measure_reach() -> Vector3:
	if not vehicle.has_method("door_layout"): return Vector3.ZERO
	var layout: Dictionary = vehicle.door_layout(side)
	if layout.is_empty(): return Vector3.ZERO
	var hinge: Vector3 = layout.hinge
	var length := float(layout.length)
	var handle: Vector3 = vehicle.to_global(Vector3(hinge.x, 0.0, hinge.z + length * .82))
	_place(float(marks.reach))
	actor._pose_clip(clip, float(marks.reach))
	var hand_bone: int = actor._combat_bones.get("LeftHand", -1)
	if hand_bone < 0: return Vector3.ZERO
	var hand: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(hand_bone).origin)
	var shift := handle - hand
	shift.y = 0.0
	return shift.limit_length(.45)

func _ground(point: Vector3) -> float:
	var fallback := vehicle.global_position.y + .04
	if not vehicle.is_inside_tree(): return fallback
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.5, point + Vector3.DOWN * 2.0, 1, [vehicle.get_rid()])
	var hit := vehicle.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or absf(float(hit.position.y) - fallback) > .35: return fallback
	return float(hit.position.y)

## Começa a mistura a partir da pose atual (último quadro da caminhada) ou de `from` (motorista no banco).
## Ao trocar de clipe, a origem e a altura do visual também saem de onde o clipe anterior deixou o corpo.
func begin_blend(from: Array = []) -> void:
	_from_pose = from if not from.is_empty() else actor._capture_pose()
	_door_clock = -1.0
	_duck_clock = -1.0
	_from_origin = actor.global_position
	_from_visual = actor.visual.position

## Pose do instante `clip_time` (s do clipe) e eventos da porta.
func pose(clip_time: float, blend_seconds_done: float) -> void:
	_place(clip_time)
	actor._pose_clip(clip, clip_time)
	if not _from_pose.is_empty() and blend_seconds_done < BLEND_IN:
		var target: Array = actor._capture_pose()
		var k := smoothstep(0.0, BLEND_IN, blend_seconds_done)
		actor._apply_blend(_from_pose, target, k)
		actor.global_position = _from_origin.lerp(actor.global_position, k)
		actor.visual.position = _from_visual.lerp(actor.visual.position, k)
	elif blend_seconds_done >= BLEND_IN:
		_from_pose = []
	# Posição no vão antes e depois de abaixar a cabeça: a curva do tronco leva a cabeça para a dobradiça,
	# e o funil pode trazer o corpo para baixo do teto depois de a cabeça ter sido conferida. Só `_duck`
	# guarda estado; funil e vão são refeitos a partir da pose atual.
	_funnel(clip_time)
	_keep_in_gap(clip_time)
	_duck(clip_time)
	_funnel(clip_time)
	_keep_in_gap(clip_time)
	_head_floor()
	_doors(clip_time)

## Última conferência da cabeça, depois do funil e do vão (que podem trazer o corpo alguns centímetros
## para baixo do teto do vão depois de `_duck`): se ainda passar, só abaixa o corpo. Sem estado: `_place`
## repõe o visual a cada quadro (imperador_64_conv, 28/10: 3–6 cm em 1–2 quadros).
func _head_floor() -> void:
	var door = vehicle.get("door_presentation")
	var layout: Dictionary = vehicle.door_layout(side) if vehicle.has_method("door_layout") else {}
	var head_bone: int = actor._combat_bones.get("Head", -1)
	if door == null or layout.is_empty() or head_bone < 0: return
	var roof: float = float(door.spec.top) * vehicle.visual.scale.y - .04
	var over := _head_over(head_bone, roof, layout, door.spec)
	if over > 0.0: actor.visual.position.y -= minf(over, .12)

## Porta aberta até o batente e corpo no vão: o tronco não passa da folha. Sentando (e levantando, na
## saída) o clipe curva o tronco para a frente, para o lado da dobradiça, onde a folha aberta fica nos
## nossos carros (no do mocap havia espaço); o corpo gira em volta da dobradiça de volta para o vão.
## Refeito a cada quadro a partir da pose do clipe, sem acumular.
func _keep_in_gap(_clip_time: float) -> void:
	var door = vehicle.get("door_presentation")
	var layout: Dictionary = vehicle.door_layout(side) if vehicle.has_method("door_layout") else {}
	if door == null or layout.is_empty(): return
	var current: float = door.current_angle(side)
	if current < DOOR_LIMIT - .05: return
	var hinge: Vector3 = layout.hinge
	var reach := float(layout.length) + BODY_RADIUS
	# Uma parte corrigida pode deixar outra encostada: até três passes.
	for attempt in 3:
		var worst := 0.0
		var worst_at := 0.0
		for bone_name in ["Hips", "Spine02", "Head"]:
			var bone: int = actor._combat_bones.get(bone_name, -1)
			if bone < 0: continue
			var point: Vector3 = vehicle.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone).origin))
			if point.y < DOOR_BOTTOM: continue
			var relative := Vector2(float(side) * (point.x - hinge.x), point.z - hinge.z)
			var distance := relative.length()
			if distance < .12 or distance >= reach: continue
			var at := atan2(relative.x, relative.y)
			var over := (at - (current - asin(clampf(BODY_RADIUS / distance, 0.0, 1.0)))) * distance
			if at < -.1 or over <= worst: continue
			worst = over
			worst_at = at
		if worst <= 0.0: return
		# Arco em volta da dobradiça, para ângulos menores (para dentro do vão).
		actor.global_position += vehicle.global_basis * (Vector3(-float(side) * cos(worst_at), 0.0, sin(worst_at)) * (worst + .005))

## Cruzando a lateral do carro, quadril, peito e cabeça ficam dentro do vão da porta (entre a coluna da
## dobradiça e a de trás): o caminho do clipe, feito para outro carro, passava o quadril pela coluna
## traseira (brasa_hc) e, sentando ou levantando curvado, a cabeça a 6 cm da dobradiça (sedã). Sentado,
## só conta quem está debruçado para fora.
func _funnel(clip_time: float) -> void:
	var door = vehicle.get("door_presentation")
	var layout: Dictionary = vehicle.door_layout(side) if vehicle.has_method("door_layout") else {}
	if door == null or layout.is_empty(): return
	var skin := float(layout.skin)
	var seated := _seat_weight(clip_time) > .9
	var front := float(door.spec.zf)
	var rear := float(door.spec.zr)
	var shift := 0.0
	for entry in [["Hips", .13, .01], ["Spine02", .2, .05], ["Head", .22, .05]]:
		var bone: int = actor._combat_bones.get(entry[0], -1)
		if bone < 0: continue
		var point: Vector3 = vehicle.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone).origin))
		if absf(point.x) >= skin + .14 or absf(point.x) <= skin - (.25 if seated else .55): continue
		var low := front + float(entry[1])
		var high := rear - float(entry[2])
		if point.z + shift < low: shift = low - point.z
		elif point.z + shift > high: shift = minf(shift, high - point.z)
	if shift != 0.0: actor.global_position += vehicle.global_basis * Vector3(0.0, 0.0, shift)

## Cabeça abaixo do teto do vão. O carro do mocap era mais alto que os nossos baixos: a cabeça passava
## 16–40 cm acima do vão (test_vehicle_doors). Cruzando a porta o corpo se curva para a frente, como
## quem entra num carro baixo; sentado, encolhe primeiro até a escala que o motorista terá no banco
## (VehicleInterior._fit); no limite, abaixa o corpo. Sobe na hora e volta devagar, sem tremer.
func _duck(clip_time: float) -> void:
	var door = vehicle.get("door_presentation")
	var layout: Dictionary = vehicle.door_layout(side) if vehicle.has_method("door_layout") else {}
	var head_bone: int = actor._combat_bones.get("Head", -1)
	if door == null or layout.is_empty() or head_bone < 0: return
	var dt := maxf(0.0, clip_time - _duck_clock) / speed if _duck_clock >= 0.0 else 1.0 / 60.0
	_duck_clock = clip_time
	var roof: float = float(door.spec.top) * vehicle.visual.scale.y - .04
	var seated := _seat_weight(clip_time) > .5
	var fit := 1.0
	if seated:
		var cabin := INTERIOR.spec(vehicle)
		if not cabin.is_empty(): fit = float(cabin.scale)
	var needed_shrink := 1.0
	var over := _head_over(head_bone, roof, layout, door.spec)
	if seated and over > 0.0:
		needed_shrink = clampf(1.0 - over / 1.25, minf(fit, .9), 1.0)
		_scale_about_hips(needed_shrink, true)
		over = _head_over(head_bone, roof, layout, door.spec)
	var needed_bend := 0.0
	while over > 0.0 and needed_bend < DUCK_MAX:
		_bend_torso(DUCK_STEP)
		needed_bend += DUCK_STEP
		over = _head_over(head_bone, roof, layout, door.spec)
	if not seated and over > 0.0:
		needed_shrink = clampf(1.0 - over / 1.25, .82, 1.0)
		_scale_about_hips(needed_shrink, seated)
		over = _head_over(head_bone, roof, layout, door.spec)
	if over > 0.0: actor.visual.position.y -= minf(over, .18)
	# Volta devagar ao corpo do clipe: sem isto a cabeça subiria e desceria a cada quadro na beira do vão.
	var relax := maxf(dt, 1.0 / 120.0)
	_bend = maxf(needed_bend, move_toward(_bend, 0.0, 1.2 * relax))
	_shrink = minf(needed_shrink, move_toward(_shrink, 1.0, .25 * relax))
	if _bend > needed_bend + .001: _bend_torso(_bend - needed_bend)
	if _shrink < needed_shrink - .001: _scale_about_hips(_shrink, seated)

## Encolhe o corpo em volta do quadril (a origem do Actor fica longe do corpo no mocap). De pé os pés
## continuam no chão (só o plano é mantido); sentado a pelve inteira fica no banco.
func _scale_about_hips(factor: float, keep_height: bool) -> void:
	var before: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.hips).origin)
	actor.visual.scale = base_scale * factor
	var shift: Vector3 = before - actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.hips).origin)
	if not keep_height: shift.y = 0.0
	actor.visual.global_position += shift

func _head_over(head_bone: int, roof: float, layout: Dictionary, spec: Dictionary) -> float:
	var head: Vector3 = vehicle.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(head_bone).origin))
	var hips: Vector3 = vehicle.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.hips).origin))
	var skin := float(layout.skin)
	# Um pouco antes do vão: quem entra abaixa a cabeça ao chegar nele, não depois (e o funil, que roda
	# depois, pode trazer o corpo alguns centímetros para dentro).
	var inside := func(point: Vector3) -> bool:
		return absf(point.x) < skin + .1 and point.z > float(spec.zf) - .2 and point.z < float(spec.zr) + .45
	if not inside.call(head) and not inside.call(hips): return 0.0
	return head.y + HEAD_TOP - roof

## Curva o tronco para a frente (rad), em volta do eixo lateral do quadril.
func _bend_torso(angle: float) -> void:
	var skeleton: Skeleton3D = actor.skeleton
	var to_skeleton := skeleton.global_basis.orthonormalized().inverse()
	var up := (to_skeleton * Vector3.UP).normalized()
	var hips: Basis = skeleton.get_bone_global_pose(actor.hips).basis * skeleton.get_bone_global_rest(actor.hips).basis.inverse()
	var front: Vector3 = hips.orthonormalized() * Vector3(0, 0, 1)
	front = (front - up * front.dot(up)).normalized()
	var axis := up.cross(front).normalized()
	for entry in [["Spine01", .5], ["Spine02", .3], ["neck", .2]]:
		var bone: int = actor._combat_bones.get(entry[0], -1)
		if bone >= 0: actor._set_combat_bone_rotation(bone, Basis(axis, angle * float(entry[1])) * skeleton.get_bone_global_pose(bone).basis)

## Porta: nos trechos em que a mão puxa a maçaneta, empurra a folha de dentro ou a fecha, o ângulo
## vem da mão (a folha vai aonde a mão está); entre eles a porta fica aberta inteira. E nunca atravessa
## o corpo: ponto do corpo dentro do arco da folha e do lado de fora dela limita a abertura (a porta
## para nele); do lado de dentro (no vão) segura a porta aberta até ele passar. Antes (28/10, 1ª versão)
## a porta abria e fechava por tempo e o vidro atravessava o Dante (relato do usuário).
func _doors(clip_time: float) -> void:
	var door = vehicle.get("door_presentation")
	var layout: Dictionary = vehicle.door_layout(side) if vehicle.has_method("door_layout") else {}
	if door == null or layout.is_empty():
		_doors_timed(clip_time)
		return
	var limit := maxf(float(door.angle), DOOR_LIMIT)
	var current: float = door.current_angle(side)
	var hand := _hand_angle(layout)
	var target := limit
	if marks.has("door_open"):
		var open_at := float(marks.door_open)
		var opened_at := float(marks.door_opened)
		if clip_time < open_at: target = 0.0
		# Puxada, a folha não volta sozinha: a mão do clipe recua para o corpo depois de soltar a maçaneta.
		elif clip_time < opened_at: target = maxf(current, lerpf(maxf(hand, 0.0), limit, smoothstep(opened_at - .35, opened_at, clip_time)))
	if marks.has("door_close") and clip_time >= float(marks.door_close):
		var closed_at := float(marks.door_closed)
		target = 0.0 if clip_time >= closed_at else lerpf(clampf(hand, 0.0, current), 0.0, smoothstep(closed_at - .2, closed_at, clip_time))
	# Inércia da folha: no máximo DOOR_SPEED rad/s, nos dois sentidos.
	var dt := maxf(0.0, clip_time - _door_clock) / speed if _door_clock >= 0.0 else 1.0 / 60.0
	_door_clock = clip_time
	var seated := _seat_weight(clip_time) > .5
	# Corpo do lado de fora só impede a folha de abrir mais; corpo no vão só impede de fechar. O recuo
	# planejado (`_clearance`) já tirou o tronco do arco antes de a folha andar; isto é a rede de segurança.
	var bounds := _body_bounds(layout, current, limit, SEATED_RADIUS if seated else BODY_RADIUS)
	var wanted := target
	if target > current: wanted = minf(target, maxf(bounds.y, current))
	if wanted < current: wanted = maxf(wanted, minf(bounds.x, current))
	# Quem passa pelo vão encostado na folha a empurra mais aberta (quadril, mão), até o batente dela.
	wanted = maxf(wanted, minf(bounds.x, DOOR_HARD_LIMIT))
	var angle := move_toward(current, clampf(wanted, 0.0, maxf(limit, DOOR_HARD_LIMIT)), DOOR_SPEED * maxf(dt, 1.0 / 120.0))
	var sound := 0
	if current <= .01 and angle > .01: sound = 1
	elif current > .01 and angle <= .01: sound = -1
	vehicle.pose_driver_door(side, angle, maxf(limit, DOOR_HARD_LIMIT), sound)

## Ângulo da mão esquerda em volta da dobradiça (rad; 0 = folha fechada, positivo = para fora).
func _hand_angle(layout: Dictionary) -> float:
	var bone: int = actor._combat_bones.get("LeftHand", -1)
	if bone < 0: return 0.0
	var hand: Vector3 = vehicle.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone).origin))
	var hinge: Vector3 = layout.hinge
	return atan2(float(side) * (hand.x - hinge.x), hand.z - hinge.z)

## (mínimo, máximo) do ângulo da folha pelo corpo: cada ponto dentro do arco (raio da folha + corpo)
## está fora da folha (ângulo ≥ o atual: a porta para antes dele) ou no vão (a porta fica além dele).
func _body_bounds(layout: Dictionary, current: float, limit: float, radius := BODY_RADIUS) -> Vector2:
	var hinge: Vector3 = layout.hinge
	var reach := float(layout.length) + radius
	var lower := 0.0
	var upper := limit
	var points: Array[Vector3] = []
	for bone_name in DOOR_POINTS:
		var bone: int = actor._combat_bones.get(bone_name, -1)
		if bone >= 0: points.append(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone).origin))
	for node in obstacles:
		if is_instance_valid(node): points.append(node.global_position)
	for world_point in points:
		var point: Vector3 = vehicle.to_local(world_point)
		# Abaixo da borda de baixo da folha (pé, alguém deitado no chão) a porta passa por cima.
		if point.y < DOOR_BOTTOM: continue
		var offset := Vector2(float(side) * (point.x - hinge.x), point.z - hinge.z)
		var distance := offset.length()
		if distance < .12 or distance > reach: continue
		var at := atan2(offset.x, offset.y)
		var margin := asin(clampf(radius / distance, 0.0, 1.0))
		if at >= current: upper = minf(upper, at - margin)
		else: lower = maxf(lower, at + margin)
	return Vector2(lower, upper)

## Sem a folha medida (porta ainda sendo recortada): abre e fecha por tempo, como antes.
func _doors_timed(clip_time: float) -> void:
	if not _door_opened and marks.has("door_open") and clip_time >= float(marks.door_open):
		_door_opened = true
		vehicle.animate_driver_door(side, true, (float(marks.door_opened) - float(marks.door_open)) / speed)
	if not _door_closed and marks.has("door_close") and clip_time >= float(marks.door_close):
		_door_closed = true
		vehicle.animate_driver_door(side, false, (float(marks.door_closed) - float(marks.door_close)) / speed)

## Voltando para trás (desistiu de entrar): o clipe de trás para frente leva a porta junto (mão e corpo).
func pose_reverse(clip_time: float) -> void:
	_place(clip_time)
	actor._pose_clip(clip, clip_time)
	_door_clock = -1.0
	_doors(clip_time)

## A porta ainda está aberta (o corpo ficou no caminho dela)?
func door_open() -> bool:
	var door = vehicle.get("door_presentation")
	return door != null and float(door.current_angle(side)) > .01

func door_closed() -> bool:
	return _door_closed
