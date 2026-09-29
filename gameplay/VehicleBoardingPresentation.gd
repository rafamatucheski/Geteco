extends Node
## V1 boarding rhythm adapted to native 3D: approach, door, step, occlusion, seat.
## Bone presentation stays owned by Actor through its existing animation sampler.

signal entered
signal exited(point: Vector3)
signal cancelled(reason: String, point: Vector3)

const INTERIOR := preload("res://gameplay/VehicleInterior.gd")

var world: Node
var vehicle: CharacterBody3D
var actor: CharacterBody3D
var side := -1
var duration := 1.85
var progress := 0.0
var active := false
var exiting := false
var phase := "idle"
var _start := Vector3.ZERO
var _door := Vector3.ZERO
var _seat := Vector3.ZERO
var _landing := Vector3.ZERO
## Canto por onde o corpo contorna a lataria até a porta (ou da porta até o chão).
var _corner := Vector3.ZERO
var _motion: Tween
var _visual_yaw := 0.0
var _visual_position := Vector3.ZERO
var _finishing := false
var _kind := "car"
var _step := 0.0
## Embarque por porta (carro, picape, van, caminhão): usa a geometria real da folha em vez
## dos pontos fixos do cálculo antigo. Vazio para moto, buggy, empilhadeira e ônibus.
var _layout: Dictionary = {}
var _path: Array[Vector3] = []
var _path_length := 0.0
var _approach := .22
var _approach_seconds := .4
var _walk_seconds := .4
var _reach_world := Vector3.ZERO
var _gate_world := Vector3.ZERO
var _stand_world := Vector3.ZERO
var _grip_side := "Right"
## Agachamento e encolhimento do corpo para a cabeça passar sob o teto do vão. Medidos no
## início: cada modelo tem um teto diferente, e a caixa assada não se ajusta ao corpo.
var _crouch := .44
var _body_scale := 1.0
var _scale_now := 1.0
var _visual_scale := Vector3.ONE
## A porta só começa a abrir quando o corpo já saiu do círculo que a folha varre; antes ela
## abria por cima de quem estava parado ao lado do carro (o F é apertado colado na porta).
var _door_started := false
var _door_start_progress := 0.0
## O veículo mostra o motorista sentado (VehicleInterior): o corpo não some no fim da entrada
## (assenta no banco misturando a pose da animação para a de motorista) e a saída começa já
## sentado (mistura da pose de motorista para a animação de saída), sem estalos.
var _seated_driver := false
var _seat_from_pose: Array = []
var _seat_from_pelvis := Vector3.INF
var _seat_from_scale := Vector3.ONE
var _seat_blend := 1.0
const BODY_SECONDS := {"car": 1.45, "tall": 1.7, "truck": 2.1}
const CLOSE_SECONDS := .28
## Do osso da cabeça ao topo do cabelo (medido no Dante: o osso fica na base do crânio).
const HEAD_TOP := .26

func begin_entry(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, entry_side: int) -> void:
	world = owner_world
	vehicle = car
	actor = pedestrian
	side = entry_side
	_configure_kind()
	_seated_driver = vehicle.has_method("shows_seated_driver") and vehicle.shows_seated_driver()
	_start = actor.global_position
	_door = vehicle.driver_door_anchor(side)
	_seat = vehicle.driver_seat_anchor()
	_landing = _start
	_corner = _outside_corner(_start)
	_prepare_door_path(_start, true)
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	_visual_scale = actor.visual.scale
	_fit_body()
	active = true
	phase = "approach"
	if _layout.is_empty() or not _inside_swing(_start): _open_door()
	_motion = create_tween().set_trans(Tween.TRANS_LINEAR if not _layout.is_empty() else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 1.0, duration-CLOSE_SECONDS if not _layout.is_empty() else duration-.28)
	_motion.tween_callback(_begin_close_entry)
	_motion.tween_interval(.28)
	_motion.tween_callback(_finish_entry)
	_apply()

func begin_exit(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, destination: Vector3, exit_side: int) -> void:
	world = owner_world
	vehicle = car
	actor = pedestrian
	side = exit_side
	_configure_kind()
	_seated_driver = vehicle.has_method("shows_seated_driver") and vehicle.shows_seated_driver()
	_leave_seat()
	_start = destination
	_landing = destination
	_door = vehicle.driver_door_anchor(side)
	_seat = vehicle.driver_seat_anchor()
	_corner = _outside_corner(_start)
	_prepare_door_path(destination, false)
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	_visual_scale = actor.visual.scale
	_fit_body()
	progress = 1.0
	exiting = true
	active = true
	phase = "open"
	actor.global_position = _seat
	if not _seated_driver: actor.hide()
	_open_door()
	_motion = create_tween().set_trans(Tween.TRANS_LINEAR if not _layout.is_empty() else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, duration - CLOSE_SECONDS if not _layout.is_empty() else duration)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	_apply()

func reverse_entry_to_exit() -> bool:
	if not active or exiting: return false
	exiting = true
	if is_instance_valid(_motion): _motion.kill()
	var seconds := maxf(.45, (duration-.28) * progress)
	vehicle.animate_driver_door(side, true, .20)
	_motion = create_tween().set_trans(Tween.TRANS_LINEAR if not _layout.is_empty() else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, seconds)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	return true

func abort(reason: String) -> void:
	if _finishing: return
	_finishing = true
	if is_instance_valid(_motion): _motion.kill()
	active = false
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, .18)
	_restore_actor(_landing if _landing.is_finite() else _start)
	cancelled.emit(reason, actor.global_position if is_instance_valid(actor) else _start)
	queue_free()

func _process(delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		abort("vehicle_removed")
		return
	if _seat_blend < 1.0: _seat_blend = minf(1.0, _seat_blend + delta / INTERIOR.SEAT_BLEND_SECONDS)
	_apply()

## Ritmo por porte (`Vehicle.boarding_class`). Antes todo veículo usava o mesmo trecho
## de "subir escada" enquanto o corpo deslizava de pé para dentro da lataria: no carro
## pequeno parecia escalar a porta, e no ônibus/caminhão entrava pelo meio da carroceria.
func _configure_kind() -> void:
	_kind = str(vehicle.boarding_class()) if vehicle.has_method("boarding_class") else "car"
	_step = float(vehicle.boarding_step_height()) if vehicle.has_method("boarding_step_height") else 0.0
	match _kind:
		"open": duration = 1.05
		"bus": duration = 1.7
		"truck": duration = 2.5
		"tall": duration = 2.0
		_: duration = 1.75 + (.30 if side > 0 else 0.0)

func _apply() -> void:
	_apply_body()
	_apply_seat_blend()

## Saída de veículo com motorista sentado: guarda a pose, o quadril e a escala do banco e tira o
## corpo da base do carro (ele voltará a ser o Actor comum, animado por esta apresentação).
func _leave_seat() -> void:
	_seat_from_pose = []
	_seat_blend = 1.0
	if not _seated_driver or not actor.seated or not is_instance_valid(actor.skeleton): return
	_seat_from_pose = actor._capture_pose()
	_seat_from_pelvis = INTERIOR.pelvis_world(actor)
	_seat_from_scale = actor.visual.scale
	_seat_blend = 0.0
	actor.release_seated(true)

## Mistura, nos primeiros instantes da saída, da pose de motorista para a animação de saída:
## pose, quadril e escala partem do banco e chegam ao que a animação pede.
func _apply_seat_blend() -> void:
	if _seat_blend >= 1.0 or _seat_from_pose.is_empty() or not is_instance_valid(actor): return
	var k := smoothstep(0.0, 1.0, _seat_blend)
	actor._apply_blend(_seat_from_pose, actor._capture_pose(), k)
	actor.visual.scale = _seat_from_scale.lerp(actor.visual.scale, k)
	actor.global_position += (_seat_from_pelvis - INTERIOR.pelvis_world(actor)) * (1.0 - k)

func _apply_body() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(vehicle): return
	if phase == "close":
		# Sentado ele continua no banco enquanto a porta fecha (VehicleInterior assenta o corpo).
		if not _seated_driver: actor.hide()
		return
	if phase == "close_outside":
		actor.global_position = _landing
		actor.show()
		return
	var t := clampf(progress, 0.0, 1.0)
	if not _layout.is_empty():
		_apply_door(t)
		return
	var face_car: float = _car_yaws()[0]
	var yaw := face_car
	var drop := 0.0
	var hidden_after := .82
	if t < .22:
		phase = "approach"
		var walk := _walk_along(smoothstep(0.0, .22, t))
		_pose_cycle("Walking", t / .22 * 1.5)
		walk.y = 0
		if walk.length_squared() > .01: yaw = lerp_angle(atan2(-walk.x, -walk.z), face_car, smoothstep(.12, .22, t))
	else:
		match _kind:
			"open": hidden_after = _apply_open(t)
			"bus": hidden_after = _apply_bus(t)
			"truck", "tall": hidden_after = _apply_climb(t)
			_: hidden_after = _apply_car(t)
		yaw = _yaw
		drop = _drop
	actor.visual.position = _visual_position + Vector3.UP * drop
	actor.visual.rotation.y = yaw
	actor.visible = _seated_driver or t < hidden_after

var _yaw := 0.0
var _drop := 0.0

## De frente para a porta, perpendicular à lateral. Antes mirava o centro do veículo:
## no caminhão a cabine fica na ponta, e o corpo parava na porta olhando para a carga.
func _car_yaws() -> Array:
	var inward := -vehicle.global_basis.x * float(side)
	return [atan2(-inward.x, -inward.z), vehicle.global_rotation.y]

## Ponto de fora da lataria alinhado à porta. Quem está na frente ou atrás do veículo
## vai primeiro até a lateral e depois acompanha a lataria, em vez de atravessá-la.
func _outside_corner(from: Vector3) -> Vector3:
	var local: Vector3 = vehicle.to_local(from)
	var door_local: Vector3 = vehicle.to_local(_door)
	var lateral := absf(door_local.x)
	if signf(local.x) == float(side) and absf(local.x) >= float(vehicle.half_width) + .10: return _door.lerp(from, .5)
	var margin := float(vehicle.half_length) + .45
	var z := clampf(local.z, -margin, margin)
	if absf(local.z) < margin:
		# Do lado errado e ao lado da lataria: contorna pela ponta mais próxima da porta.
		z = -margin if door_local.z < 0 else margin
	var corner: Vector3 = vehicle.to_global(Vector3(float(side) * lateral, door_local.y, z))
	corner.y = _door.y
	return corner

## Caminho em dois trechos (início → canto → porta), com velocidade constante.
func _walk_along(k: float) -> Vector3:
	var first := _start.distance_to(_corner)
	var total := first + _corner.distance_to(_door)
	if total < .001:
		actor.global_position = _door
		return Vector3.ZERO
	var travelled := k * total
	if travelled <= first:
		actor.global_position = _start.lerp(_corner, travelled / maxf(first, .001))
		return _corner - _start
	actor.global_position = _corner.lerp(_door, (travelled - first) / maxf(total - first, .001))
	return _door - _corner

## Carro baixo: para na porta, vira de costas para o banco, abaixa e desliza sentado.
func _apply_car(t: float) -> float:
	var yaws := _car_yaws()
	if t < .38:
		phase = "reach"
		actor.global_position = _door
		_pose_idle()
		actor.pose_vehicle(0.0, 0.0, side, smoothstep(.22, .38, t))
		_yaw = lerp_angle(yaws[0], yaws[1], smoothstep(.22, .38, t))
		_drop = 0.0
	else:
		phase = "step"
		var k := smoothstep(.38, .80, t)
		actor.global_position = _door.lerp(_seat, k)
		_pose_idle()
		_yaw = yaws[1]
		# Dobra os joelhos: o quadril desce até a altura do banco antes de sumir na porta.
		_drop = -.42 * smoothstep(.38, .60, t)
		actor.pose_vehicle(smoothstep(.38, .66, t))
	return .80

## Caminhonete e caminhão: de frente para a cabine, sobe pelo estribo (ciclo de escada
## do próprio esqueleto, só na subida) e entra de lado ao alcançar o piso.
func _apply_climb(t: float) -> float:
	var yaws := _car_yaws()
	var inside := _door.lerp(_seat, .45)
	inside.y = _seat.y
	var climb_end := .66 if _kind == "truck" else .52
	if t < climb_end:
		phase = "reach"
		var k := smoothstep(.22, climb_end, t)
		var point := _door.lerp(inside, k * .35)
		point.y = lerpf(_door.y, _seat.y, k)
		actor.global_position = point
		_pose_transition(.05 + k * (.55 if _kind == "truck" else .30))
		_yaw = yaws[0]
		_drop = 0.0
	else:
		phase = "step"
		var k := smoothstep(climb_end, .84, t)
		actor.global_position = _door.lerp(inside, .35).lerp(_seat, k)
		actor.global_position.y = _seat.y
		_pose_idle()
		_yaw = lerp_angle(yaws[0], yaws[1], k)
		_drop = -.36 * k
		actor.pose_vehicle(k)
		var seated: Array = actor._capture_pose()
		_pose_transition(.60 if _kind == "truck" else .35)
		actor._apply_blend(actor._capture_pose(), seated, smoothstep(0.0, .30, k))
	return .84

## Ônibus: porta de serviço sem folha; sobe os degraus andando e vira para o volante.
func _apply_bus(t: float) -> float:
	var yaws := _car_yaws()
	phase = "step" if t > .30 else "reach"
	var k := smoothstep(.22, .84, t)
	var point := _door.lerp(_seat, k)
	point.y = lerpf(_door.y, _seat.y, smoothstep(.22, .6, t))
	actor.global_position = point
	_pose_cycle("Walking", t * 3.0)
	var walk := _seat - _door
	walk.y = 0
	_yaw = lerp_angle(atan2(-walk.x, -walk.z), yaws[1], smoothstep(.6, .84, t))
	_drop = -.3 * smoothstep(.72, .88, t)
	if t > .72:
		var walking: Array = actor._capture_pose()
		actor.pose_vehicle(smoothstep(.72, .88, t))
		actor._apply_blend(walking, actor._capture_pose(), smoothstep(.72, .84, t))
	return .9

## Moto, buggy e empilhadeira: sem porta, passa a perna por cima e assenta.
func _apply_open(t: float) -> float:
	var yaws := _car_yaws()
	phase = "step"
	var k := smoothstep(.22, .85, t)
	actor.global_position = _door.lerp(_seat, k)
	_pose_idle()
	_yaw = lerp_angle(yaws[0], yaws[1], smoothstep(.22, .5, t))
	_drop = -.3 * smoothstep(.5, .85, t)
	actor.pose_vehicle(smoothstep(.50, .85, t), sin(smoothstep(.22, .65, t) * PI), side, smoothstep(.22, .36, t))
	return .92

# --- Embarque por porta -------------------------------------------------------------
# A folha aberta ocupa um arco em volta da dobradiça. O corpo espera fora dele (atrás do
# vão), entra pelo vão com a mão no batente e sai pelo mesmo caminho: nunca atravessa a
# folha nem a lataria, e ao fechar a porta ninguém está dentro do arco.

func _prepare_door_path(outside: Vector3, entering: bool) -> void:
	_layout = {}
	_path = []
	if not vehicle.has_method("door_layout") or not (_kind in ["car", "tall", "truck"]): return
	var found: Dictionary = vehicle.door_layout(side)
	if found.is_empty(): return
	_layout = found
	_stand_world = vehicle.to_global(_flat(_layout.stand, .04))
	_reach_world = vehicle.to_global(_flat(_layout.reach, .04))
	_gate_world = vehicle.to_global(_flat(_layout.gate, .04))
	_grip_side = "Right" if side < 0 else "Left"
	var ground := vehicle.global_position.y + .04
	var outside_local: Vector3 = vehicle.to_local(outside)
	var route: Array[Vector2] = _plan(Vector2(outside_local.x, outside_local.z), Vector2(_layout.stand.x, _layout.stand.z))
	_path.append(outside)
	for index in range(1, route.size()):
		var point: Vector3 = vehicle.to_global(Vector3(route[index].x, 0.0, route[index].y))
		point.y = ground if index == route.size() - 1 else lerpf(outside.y, ground, float(index) / float(route.size() - 1))
		_path.append(point)
	_path_length = 0.0
	for index in range(1, _path.size()): _path_length += _path[index - 1].distance_to(_path[index])
	_walk_seconds = clampf(_path_length / 2.3, .3, 3.2)
	# Quem aperta o F colado na porta dá um passo para trás e só então a porta abre; o corpo
	# espera a folha terminar de abrir antes de se aproximar do vão.
	var wait := .32 if entering and _inside_swing(outside) else 0.0
	_approach_seconds = _walk_seconds + wait
	var body: float = BODY_SECONDS.get(_kind, 1.5)
	duration = _approach_seconds + body + CLOSE_SECONDS
	_approach = _approach_seconds / (_approach_seconds + body)

## Quanto o corpo precisa se abaixar (e, se não bastar, encolher até 80 %) para a cabeça
## passar sob o teto do vão com o pé no piso da cabine.
func _fit_body() -> void:
	_crouch = .44
	_body_scale = 1.0
	if _layout.is_empty(): return
	_pose_idle()
	var head_index: int = actor._combat_bones.get("Head", -1)
	if head_index < 0: return
	var head: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(head_index).origin)
	var standing := head.y - actor.global_position.y + HEAD_TOP
	var roof: float = float(vehicle.door_presentation.spec.top) * vehicle.visual.scale.y - .03
	var floor_height: float = _seat.y - vehicle.global_position.y
	var needed := floor_height + standing - roof
	_crouch = clampf(needed, .3, .6)
	if needed > _crouch: _body_scale = clampf(1.0 - (needed - _crouch) / standing, .8, 1.0)

func _open_door() -> void:
	if _door_started: return
	_door_started = true
	_door_start_progress = progress
	vehicle.animate_driver_door(side, true, .28)

## O ponto (mundo) está dentro do círculo que a ponta da folha varre, com uma folga?
func _inside_swing(point: Vector3, margin := .30) -> bool:
	if _layout.is_empty(): return false
	var local: Vector3 = vehicle.to_local(point)
	var hinge: Vector3 = _layout.hinge
	return Vector2(local.x - hinge.x, local.z - hinge.z).length() < float(_layout.length) + margin

func _flat(local: Vector3, height: float) -> Vector3:
	return Vector3(local.x, height, local.z)

## Menor caminho (grafo de visibilidade) entre dois pontos do plano do veículo, desviando do
## casco e da folha aberta. Nós: origem, destino, quatro cantos folgados do casco e dois
## pontos além da ponta da folha. Poucos nós: custo desprezível, roda só ao iniciar.
func _plan(from2: Vector2, to2: Vector2) -> Array[Vector2]:
	var nodes: Array[Vector2] = [from2, to2]
	var ring_x: float = vehicle.half_width + .55
	var ring_z: float = vehicle.half_length + .55
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]: nodes.append(Vector2(sx * ring_x, sz * ring_z))
	var tip: Vector3 = _layout.tip
	var hinge: Vector3 = _layout.hinge
	nodes.append(Vector2(tip.x + float(side) * .55, tip.z + .1))
	nodes.append(Vector2(tip.x + float(side) * .55, hinge.z - .55))
	var count := nodes.size()
	var cost: Array[float] = []
	var previous: Array[int] = []
	var done: Array[bool] = []
	for i in count:
		cost.append(INF)
		previous.append(-1)
		done.append(false)
	cost[0] = 0.0
	for round_index in count:
		var current := -1
		for i in count:
			if not done[i] and (current < 0 or cost[i] < cost[current]): current = i
		if current < 0 or cost[current] == INF: break
		done[current] = true
		if current == 1: break
		for other in count:
			if done[other] or not _clear(nodes[current], nodes[other]): continue
			var through := cost[current] + nodes[current].distance_to(nodes[other])
			if through < cost[other]:
				cost[other] = through
				previous[other] = current
	var route: Array[Vector2] = []
	if cost[1] == INF:
		route.append(from2)
		route.append(to2)
		return route
	var cursor := 1
	while cursor >= 0:
		route.push_front(nodes[cursor])
		cursor = previous[cursor]
	return route

## O segmento passa livre do casco (com folga) e da folha aberta? Amostragem a cada 10 cm,
## ignorando os primeiros e últimos 25 cm (quem começa colado no carro não fica preso).
func _clear(a: Vector2, b: Vector2) -> bool:
	var length := a.distance_to(b)
	if length < .001: return true
	var hull_x: float = vehicle.half_width + .12
	var hull_z: float = vehicle.half_length + .12
	var hinge2 := Vector2(_layout.hinge.x, _layout.hinge.z)
	var tip2 := Vector2(_layout.tip.x, _layout.tip.z)
	var steps := int(ceil(length / .1))
	for i in range(steps + 1):
		var travelled := length * float(i) / float(steps)
		if travelled < .25 or length - travelled < .25: continue
		var point := a.lerp(b, float(i) / float(steps))
		if absf(point.x) < hull_x and absf(point.y) < hull_z: return false
		if _distance_to_segment(point, hinge2, tip2) < .44: return false
	return true

static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), .0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

func _path_at(k: float) -> Vector3:
	if _path.size() < 2 or _path_length < .001: return _stand_world
	var target := clampf(k, 0.0, 1.0) * _path_length
	for index in range(1, _path.size()):
		var segment := _path[index - 1].distance_to(_path[index])
		if target <= segment or index == _path.size() - 1:
			return _path[index - 1].lerp(_path[index], clampf(target / maxf(segment, .001), 0.0, 1.0))
		target -= segment
	return _path[_path.size() - 1]

func _path_heading(k: float) -> Vector3:
	var direction := _path_at(minf(k + .04, 1.0)) - _path_at(maxf(k - .04, 0.0))
	direction.y = 0.0
	# Saindo, o corpo percorre o caminho de volta: ele anda de frente para onde vai.
	return -direction if exiting else direction

func _yaw_toward(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

## Mão no batente traseiro do vão. O alvo sobe junto com o corpo no degrau (a mão desliza
## no montante) e nunca fica acima do alcance do braço.
func _grip_pose(weight: float, feet_y: float) -> void:
	if weight <= .02: return
	var grip: Vector3 = vehicle.to_global(_layout.grip)
	grip.y = clampf(feet_y + 1.12, feet_y + .9, maxf(grip.y, feet_y + 1.0))
	var sign_side := -1.0 if _grip_side == "Left" else 1.0
	var default_hand := Vector3(.23 * sign_side, .90, -.28)
	var target: Vector3 = default_hand.lerp(actor.visual.to_local(grip), clampf(weight, 0.0, 1.0))
	actor._solve_combat_arm(_grip_side, target, Basis.IDENTITY, true, sign_side)
	actor._set_combat_grips(_grip_side == "Right" and weight > .5, _grip_side == "Left" and weight > .5)

func _apply_door(t: float) -> void:
	var yaws := _car_yaws()
	var hidden_after := .96
	var drop := 0.0
	var yaw := 0.0
	_scale_now = 1.0
	if t < _approach:
		phase = "approach"
		var k := clampf(t / maxf(_approach, .001) * _approach_seconds / maxf(_walk_seconds, .001), 0.0, 1.0)
		actor.global_position = _path_at(k)
		if not _door_started and not _inside_swing(actor.global_position): _open_door()
		var cycles := maxf(_path_length / 1.35, .5)
		if k >= 1.0 and not exiting: _pose_idle()
		else: _pose_cycle("Walking", (1.0 - k if exiting else k) * cycles)
		var heading := _path_heading(k)
		var face := _yaw_toward(_gate_world - actor.global_position)
		yaw = _yaw_toward(heading) if heading.length_squared() > .0004 else face
		if not exiting: yaw = lerp_angle(yaw, face, smoothstep(.8, 1.0, k))
		else: yaw = lerp_angle(yaw, face, 1.0 - smoothstep(.0, .2, k))
	else:
		var u := clampf((t - _approach) / maxf(1.0 - _approach, .001), 0.0, 1.0)
		_open_door()
		if _kind == "car": _door_car(u, yaws)
		else: _door_climb(u, yaws)
		yaw = _yaw
		drop = _drop
	actor.visual.position = _visual_position + Vector3.UP * drop
	actor.visual.rotation.y = yaw
	actor.visual.scale = _visual_scale * _scale_now
	actor.visible = _seated_driver or t < _approach + (1.0 - _approach) * hidden_after

## Carro baixo. Espera fora do arco, dá um passo até o vão olhando para o banco, segura o
## batente e desliza para dentro abaixado, virando para o volante já sentado.
func _door_car(u: float, yaws: Array) -> void:
	var face_gate := _yaw_toward(_gate_world - _stand_world)
	var reach_k := smoothstep(0.0, .2, u)
	var gate_k := smoothstep(.2, .55, u)
	var seat_k := smoothstep(.55, .88, u)
	var point := _stand_world.lerp(_reach_world, reach_k).lerp(_gate_world, gate_k).lerp(_seat, seat_k)
	actor.global_position = point
	phase = "reach" if u < .2 else "step"
	_pose_idle()
	actor.pose_vehicle(smoothstep(.35, .95, u), 0.0, side, 1.0)
	_grip_pose(smoothstep(.02, .18, u) * (1.0 - smoothstep(.62, .82, u)), point.y)
	_yaw = lerp_angle(face_gate, yaws[1], smoothstep(.6, .95, u))
	# O quadril desce até o banco antes de cruzar a lataria: a cabeça passa sob o teto do vão.
	_drop = -_crouch * smoothstep(.12, .5, u)
	_scale_now = lerpf(1.0, _body_scale, smoothstep(.12, .5, u))

## Picape, SUV, van e caminhão: espera fora do arco, sobe no estribo (ciclo de escada) com a
## mão no montante e só então cruza o vão até o banco.
func _door_climb(u: float, yaws: Array) -> void:
	var truck := _kind == "truck"
	var climb_end := .62 if truck else .50
	var floor_y := _seat.y
	var face_gate := _yaw_toward(_gate_world - _stand_world)
	var step_point := _reach_world.lerp(_gate_world, .35)
	var point: Vector3
	if u < climb_end:
		phase = "reach"
		var k := smoothstep(.06, climb_end, u)
		point = _stand_world.lerp(_reach_world, smoothstep(0.0, .12, u)).lerp(step_point, k)
		point.y = lerpf(_stand_world.y, floor_y, k)
		actor.global_position = point
		_pose_transition(.05 + k * (.55 if truck else .30))
		_grip_pose(smoothstep(.0, .1, u), point.y)
		_yaw = face_gate
		_drop = 0.0
	else:
		phase = "step"
		var k := smoothstep(climb_end, .9, (u))
		var inside := _gate_world
		point = step_point.lerp(inside, smoothstep(0.0, .5, k)).lerp(_seat, smoothstep(.4, 1.0, k))
		point.y = floor_y
		actor.global_position = point
		_pose_idle()
		actor.pose_vehicle(k, 0.0, side, 1.0)
		var seated: Array = actor._capture_pose()
		_pose_transition(.60 if truck else .35)
		actor._apply_blend(actor._capture_pose(), seated, smoothstep(0.0, .35, k))
		_grip_pose(1.0 - smoothstep(.1, .5, k), point.y)
		_yaw = lerp_angle(face_gate, yaws[1], smoothstep(.3, 1.0, k))
		_drop = -_crouch * smoothstep(0.0, .35, k)
		_scale_now = lerpf(1.0, _body_scale, smoothstep(0.0, .35, k))

func _pose_idle() -> void:
	var pose: Array = actor.get("_idle_pose") if actor.get("_idle_pose") != null else []
	if pose.is_empty() and actor.has_method("_build_idle_pose"):
		actor._build_idle_pose()
		pose = actor.get("_idle_pose")
	if not pose.is_empty() and actor.has_method("_apply_pose"): actor._apply_pose(pose)
	else: _pose_cycle("Walking", 0.0)

func _begin_close_entry() -> void:
	if not active or exiting: return
	phase = "close"
	if not _seated_driver: actor.hide()
	vehicle.animate_driver_door(side, false, .28)

func _begin_close_exit() -> void:
	if not active: return
	phase = "close_outside"
	_restore_actor(_landing)
	if _inside_swing(_landing, .30):
		# Pouso alternativo (o ponto de espera estava bloqueado) dentro do arco: a porta espera
		# o jogador se afastar em vez de fechar em cima dele.
		var door_vehicle := vehicle
		var door_side := side
		vehicle.get_tree().create_timer(1.6).timeout.connect(func():
			if is_instance_valid(door_vehicle): door_vehicle.animate_driver_door(door_side, false, .32))
		return
	vehicle.animate_driver_door(side, false, .32)

func _pose_cycle(clip: String, normalized: float) -> void:
	if not is_instance_valid(actor.animation) or not actor.animation.has_animation(clip): return
	actor._pose_cycle(clip, normalized, actor.WALK_START if clip == "Walking" else 0.0)
	var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
	hip.x = actor.hip_rest.x
	hip.z = actor.hip_rest.z
	actor.skeleton.set_bone_pose_position(actor.hips, hip)

func _pose_transition(normalized: float) -> void:
	var clip := "Fast_Ladder_Climb"
	if not is_instance_valid(actor.animation) or not actor.animation.has_animation(clip):
		_pose_cycle("Walking", normalized)
		return
	actor._pose_clip(clip, clampf(normalized, 0.0, 1.0) * actor.animation.get_animation(clip).length)

func _finish_entry() -> void:
	if _finishing or not is_instance_valid(actor) or not is_instance_valid(vehicle):
		abort("invalid_entry")
		return
	_finishing = true
	active = false
	if _seated_driver and vehicle.is_inside_tree():
		# Continua visível ao volante. O agachamento e a escala da animação não voltam ao normal
		# aqui: o interior assenta o corpo a partir deles (mistura curta), e só a saída restaura a
		# linha de base do visual (`_leave_seat` / `Actor.teleport`).
		INTERIOR.attach(vehicle)
		INTERIOR.seat_driver(actor, vehicle, INTERIOR.SEAT_BLEND_SECONDS)
		actor.show()
	else:
		# The crouch belongs to this presentation only. Keeping it on the hidden
		# actor made the next exit use an already lowered baseline, sinking each trip.
		actor.visual.position = _visual_position
		actor.visual.rotation.y = _visual_yaw
		actor.visual.scale = _visual_scale
		actor.hide()
		actor.global_position = vehicle.global_position
	vehicle.animate_driver_door(side, false, 0.0)
	entered.emit()
	queue_free()

func _finish_exit() -> void:
	if _finishing: return
	_finishing = true
	active = false
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
	_restore_actor(_landing)
	exited.emit(_landing)
	queue_free()

func _restore_actor(point: Vector3) -> void:
	if not is_instance_valid(actor): return
	actor.teleport(point)
	actor.visual.position = _visual_position
	actor.visual.rotation.y = _visual_yaw
	actor.visual.scale = _visual_scale
	actor.show()

func _exit_tree() -> void:
	if active and not _finishing:
		if is_instance_valid(_motion): _motion.kill()
		if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
		_restore_actor(_landing if _landing.is_finite() else _start)
