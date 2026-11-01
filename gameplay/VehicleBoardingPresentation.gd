extends Node
## V1 boarding rhythm adapted to native 3D: approach, door, step, occlusion, seat.
## Bone presentation stays owned by Actor through its existing animation sampler.

signal entered
signal exited(point: Vector3)
signal cancelled(reason: String, point: Vector3)

const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const BREAK_IN := preload("res://gameplay/VehicleBreakIn.gd")
const MOCAP := preload("res://gameplay/VehicleBoardingMocap.gd")
const CARJACKING := preload("res://gameplay/VehicleCarjacking.gd")
## Mocap, caminho e movimento pela porta em auxiliares (01/11, Onda 2 do plano de divisão): estado e
## sinais ficam aqui, e cada função antiga continua como delegação de uma linha.
const PATH_PLANNER := preload("res://gameplay/BoardingPathPlanner.gd")
const DOOR_MOTION := preload("res://gameplay/BoardingDoorMotion.gd")
const MOCAP_DRIVER := preload("res://gameplay/BoardingMocapDriver.gd")
var _path_planner: PATH_PLANNER = PATH_PLANNER.new(self)
var _door_motion: DOOR_MOTION = DOOR_MOTION.new(self)
var _mocap_driver: MOCAP_DRIVER = MOCAP_DRIVER.new(self)
## Entrada/saída pela porta do motorista com o mocap (`VehicleBoardingMocap`); null = embarque antigo.
var _mocap: RefCounted
var _mocap_blending := false
## Roubo de carro com mocap: anda até a porta, abre ("Entering Car" até 1,8 s), puxa o motorista ("Pull
## Pilot From Seat" espelhado, com a vítima no par dela 2,5 s atrás), senta, fecha a porta e pega o
## volante (cauda do "Entering Car").
const PULL := "mixveh/pull_from_seat_m"
## Ladrão: começa já agarrando (o clipe abre com ~3 s de luta), vira e arremessa (4,5–6,0 s), volta e senta.
const PULL_MARKS := {"start": 3.4, "sit_from": 7.9, "sit_to": 8.6, "end": 8.6, "speed": 1.4}
const PULL_OFFSET := 2.5
const ENTER_DOOR_END := 1.8
const ENTER_TAIL := 3.75
var _mocap_carjack := false
var _pull: RefCounted
var _segments: Array[float] = []
var _segment := -1
var _frame_delta := 1.0 / 60.0
var carjacking: RefCounted
var _extracting := false
var _extraction_progress := 0.0
var break_in: RefCounted
var _breaking := false
var _break_progress := 0.0
var _break_seconds := 0.0
var _break_layout: Dictionary = {}
var _break_retreat := false
var _planning_closed := false
var _retreat_seconds := 0.0

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
## Moto: o corpo termina a entrada (e começa a saída) já na pose de guidão que o Driving mantém
## montado. Antes ele sumia no fim do passo, ~30 cm abaixo e de mãos soltas, e reaparecia
## montado: o salto lia como teletransporte (relato de 13/10).
var _motorcycle := false
const BODY_SECONDS := {"car": 1.15, "tall": 1.4, "truck": 1.8}
const CLOSE_SECONDS := .28
## Do osso da cabeça ao topo do cabelo (medido no Dante: o osso fica na base do crânio).
const HEAD_TOP := .26

func begin_entry(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, entry_side: int, locked := false, displaced_driver: RefCounted = null) -> void:
	carjacking = displaced_driver
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
	if not locked and displaced_driver == null and MOCAP.available(actor, vehicle, side, _kind):
		_begin_mocap_entry()
		return
	if not locked and displaced_driver != null and MOCAP.available(actor, vehicle, side, _kind) \
		and actor.animation.has_animation(PULL) and displaced_driver.mocap_available():
		_begin_mocap_carjack()
		return
	_prepare_door_path(_start, true)
	if locked and not _layout.is_empty():
		break_in = BREAK_IN.new()
		break_in.choose(randf(), randf())
		_prepare_locked_path()
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	_visual_scale = actor.visual.scale
	_fit_body()
	var body_seconds := duration - CLOSE_SECONDS
	if break_in != null:
		_break_seconds = break_in.seconds()
		duration += _break_seconds + _retreat_seconds
	active = true
	phase = "approach"
	if _layout.is_empty(): _open_door()
	_motion = create_tween().set_trans(Tween.TRANS_LINEAR if not _layout.is_empty() else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if break_in != null:
		_motion.tween_property(self, "progress", _approach, _approach_seconds)
		_motion.tween_callback(_begin_break_in)
		_motion.tween_property(self, "_break_progress", 1.0, _break_seconds)
		_motion.tween_callback(_finish_break_in)
		_motion.tween_property(self, "progress", _approach, _retreat_seconds).from(0.0)
		_motion.tween_callback(_finish_break_retreat)
		_motion.tween_property(self, "progress", 1.0, body_seconds - _approach_seconds)
	elif carjacking != null:
		var approach := _approach if not _layout.is_empty() else .22
		var walk_seconds := _approach_seconds if not _layout.is_empty() else (duration - CLOSE_SECONDS) * approach
		_motion.tween_property(self, "progress", approach, walk_seconds)
		_motion.tween_callback(_begin_extraction)
		_motion.tween_property(self, "_extraction_progress", 1.0, 1.15)
		_motion.tween_callback(_finish_extraction)
		_motion.tween_property(self, "progress", 1.0, maxf(.2, body_seconds - walk_seconds))
		duration += 1.15
	else:
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
	if _seated_driver and MOCAP.available(actor, vehicle, side, _kind) and _begin_mocap_exit(): return
	actor.global_position = _seat
	if not _seated_driver and not _motorcycle: actor.hide()
	_open_door()
	_motion = create_tween().set_trans(Tween.TRANS_LINEAR if not _layout.is_empty() else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, duration - CLOSE_SECONDS if not _layout.is_empty() else duration)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	_apply()

func reverse_entry_to_exit() -> bool:
	if not active or exiting: return false
	if carjacking != null and not carjacking.released:
		abort("theft_cancelled")
		return true
	if break_in != null and (_breaking or _break_retreat or not break_in.committed):
		abort("break_in_cancelled")
		return true
	# Roubo com mocap depois de arrancar o motorista: segue até sentar.
	if _mocap_carjack: return false
	if _mocap != null: return _reverse_mocap_entry()
	exiting = true
	if is_instance_valid(_motion): _motion.kill()
	var seconds := maxf(.45, (duration - _break_seconds - .28) * progress)
	if _door_started: vehicle.animate_driver_door(side, true, .20)
	_motion = create_tween().set_trans(Tween.TRANS_LINEAR if not _layout.is_empty() else Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not _layout.is_empty() and _door_started:
		# Fecha a folha no ponto de espera antes de refazer a aproximação curta,
		# que foi planejada com a porta fechada.
		if progress > _approach:
			_motion.tween_property(self, "progress", _approach, seconds * (progress - _approach) / progress)
		_motion.tween_callback(func(): vehicle.animate_driver_door(side, false, .28))
		_motion.tween_interval(.32)
		_motion.tween_property(self, "progress", 0.0, maxf(.3, _walk_seconds))
	else:
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
	if carjacking != null: carjacking.release()
	if break_in != null: break_in.dispose()
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
	_frame_delta = delta
	_apply()

## Ritmo por porte (`Vehicle.boarding_class`). Antes todo veículo usava o mesmo trecho
## de "subir escada" enquanto o corpo deslizava de pé para dentro da lataria: no carro
## pequeno parecia escalar a porta, e no ônibus/caminhão entrava pelo meio da carroceria.
func _configure_kind() -> void:
	_kind = str(vehicle.boarding_class()) if vehicle.has_method("boarding_class") else "car"
	_motorcycle = str(vehicle.get("archetype")).begins_with("bike_") and vehicle.has_method("motorcycle_handholds")
	_step = float(vehicle.boarding_step_height()) if vehicle.has_method("boarding_step_height") else 0.0
	match _kind:
		"open": duration = 1.05
		"bus": duration = 1.7
		"truck": duration = 2.5
		"tall": duration = 2.0
		_: duration = 1.75 + (.30 if side > 0 else 0.0)

func _begin_extraction() -> void:
	_extracting = true
	phase = "punch" if carjacking.motorcycle else "pull_driver"
	_open_door()

func _finish_extraction() -> void:
	carjacking.apply(actor, 1.0)
	carjacking.release()
	_extracting = false

func _apply() -> void:
	if carjacking != null and not carjacking.released and not _mocap_carjack:
		if _extracting:
			carjacking.apply(actor, _extraction_progress)
			return
		carjacking.follow_seat()
	if _breaking:
		_apply_break_in()
		return
	_apply_body()
	_apply_seat_blend()

func _begin_break_in() -> void:
	if not active: return
	_breaking = true
	phase = "break_in"
	actor.global_position = vehicle.to_global(_break_layout.stand)
	actor.visual.position = _visual_position
	actor.visual.scale = _visual_scale
	actor.show()
	_apply_break_in()

func _apply_break_in() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(vehicle): return
	break_in.pose(actor, vehicle, side, _break_layout, _break_progress)
	var impact := .43 if break_in.method == "window" else .76
	if _break_progress >= impact:
		break_in.commit(vehicle, side, vehicle.to_global(_break_layout.grip))

func _finish_break_in() -> void:
	if not active: return
	break_in.commit(vehicle, side, vehicle.to_global(_break_layout.grip))
	break_in.dispose()
	_breaking = false
	_break_retreat = true
	_path = [vehicle.to_global(_break_layout.stand), _stand_world]
	_path_length = _path[0].distance_to(_path[1])
	_walk_seconds = _retreat_seconds
	_approach_seconds = _retreat_seconds
	progress = 0.0

func _finish_break_retreat() -> void:
	_break_retreat = false
	if _seated_driver:
		INTERIOR.attach(vehicle)
		# Abrir o interior troca os materiais dos vidros; mantém ausente o vidro já
		# quebrado por esta entrada depois dessa preparação de material.
		if break_in.method == "window": BREAK_IN._break_window(vehicle, side)
	_open_door()

func _prepare_locked_path() -> void: _path_planner._prepare_locked_path()

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
		if _motorcycle: _hold_mounted()
		elif not _seated_driver: actor.hide()
		return
	if phase == "close_outside":
		actor.global_position = _landing
		actor.show()
		return
	var t := clampf(progress, 0.0, 1.0)
	if _mocap_carjack:
		_apply_mocap_carjack(t)
		return
	if _mocap != null:
		_apply_mocap(t)
		return
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

func _outside_corner(from: Vector3) -> Vector3: return _path_planner._outside_corner(from)
func _walk_along(k: float) -> Vector3: return _path_planner._walk_along(k)

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
	# A moto não abaixa o visual: o banco dela (driver_seat_anchor) já põe o quadril na sela.
	_drop = 0.0 if _motorcycle else -.3 * smoothstep(.5, .85, t)
	if _motorcycle:
		# A pose montada lê manoplas no espaço do visual; aplica antes o giro/altura deste quadro.
		actor.visual.position = _visual_position + Vector3.UP * _drop
		actor.visual.rotation.y = _yaw
	actor.pose_vehicle(smoothstep(.50, .85, t), sin(smoothstep(.22, .65, t) * PI), side, smoothstep(.22, .36, t))
	if _motorcycle:
		_blend_mounted(smoothstep(.68, .92, t))
		return 2.0
	return .92

## Mistura a pose do passo com a pose de guidão (a mesma de Driving._update_mounted_player).
func _blend_mounted(weight: float) -> void:
	if weight <= 0.0: return
	var holds: Dictionary = vehicle.motorcycle_handholds()
	if not (holds.has("Left") and holds.has("Right")): return
	var stepping: Array = actor._capture_pose()
	actor.pose_vehicle(1.0, 0.0, -1, 1.0, holds)
	if weight >= 1.0: return
	actor._apply_blend(stepping, actor._capture_pose(), weight)
	actor._set_combat_grips(weight > .5, weight > .5)

## Enquanto a apresentação fecha, o corpo já fica como o Driving o deixará montado.
func _hold_mounted() -> void:
	actor.global_position = vehicle.driver_seat_anchor()
	actor.visual.position = _visual_position
	actor.visual.global_basis = vehicle.visual.global_basis.orthonormalized()
	actor.pose_vehicle(1.0, 0.0, -1, 1.0, vehicle.motorcycle_handholds())
	actor.show()

# --- Mocap (porta do motorista do carro baixo) ---------------------------------------
# Anda até o ponto em que o clipe começa (fora do arco da folha, que ainda está fechada) e toca o
# "Entering Car": a porta abre e fecha nos instantes em que a mão do clipe puxa a maçaneta e a porta.

func _begin_mocap_entry() -> void: _mocap_driver._begin_mocap_entry()
func _begin_mocap_exit() -> bool: return _mocap_driver._begin_mocap_exit()
func _landing_clear(point: Vector3) -> bool: return _mocap_driver._landing_clear(point)
func _begin_mocap_carjack() -> void: _mocap_driver._begin_mocap_carjack()
func _apply_mocap_carjack(t: float) -> void: _mocap_driver._apply_mocap_carjack(t)
func _mocap_walk(t: float) -> void: _mocap_driver._mocap_walk(t)
func _apply_mocap(t: float) -> void: _mocap_driver._apply_mocap(t)
func _reverse_mocap_entry() -> bool: return _mocap_driver._reverse_mocap_entry()

# --- Embarque por porta -------------------------------------------------------------
# A folha aberta ocupa um arco em volta da dobradiça. O corpo espera fora dele (atrás do
# vão), entra pelo vão com a mão no batente e sai pelo mesmo caminho: nunca atravessa a
# folha nem a lataria, e ao fechar a porta ninguém está dentro do arco.

func _prepare_door_path(outside: Vector3, entering: bool) -> void: _path_planner._prepare_door_path(outside, entering)

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
	if break_in != null and (not break_in.committed or _breaking or _break_retreat): return
	if _door_started: return
	_door_started = true
	_door_start_progress = progress
	vehicle.animate_driver_door(side, true, .28)

func _inside_swing(point: Vector3, margin := .30) -> bool: return _path_planner._inside_swing(point, margin)
func _flat(local: Vector3, height: float) -> Vector3: return _path_planner._flat(local, height)
func _plan(from2: Vector2, to2: Vector2) -> Array[Vector2]: return _path_planner._plan(from2, to2)
func _clear(a: Vector2, b: Vector2) -> bool: return _path_planner._clear(a, b)
static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float: return PATH_PLANNER._distance_to_segment(point, a, b)
func _path_at(k: float) -> Vector3: return _path_planner._path_at(k)
func _path_heading(k: float) -> Vector3: return _path_planner._path_heading(k)
func _yaw_toward(direction: Vector3) -> float: return _path_planner._yaw_toward(direction)
func _grip_pose(weight: float, feet_y: float) -> void: _door_motion._grip_pose(weight, feet_y)
func _apply_door(t: float) -> void: _door_motion._apply_door(t)
func _door_car(u: float, yaws: Array) -> void: _door_motion._door_car(u, yaws)
func _door_climb(u: float, yaws: Array) -> void: _door_motion._door_climb(u, yaws)

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
	if _motorcycle: _hold_mounted()
	elif not _seated_driver: actor.hide()
	vehicle.animate_driver_door(side, false, .28)

func _begin_close_exit() -> void:
	if not active: return
	phase = "close_outside"
	# Na moto o Driving alinha o visual ao rumo da moto antes da saída; restaurar esse giro aqui
	# virava o corpo 90° num quadro, de frente para a lateral da moto para o rumo dela.
	if _motorcycle: _visual_yaw = actor.visual.rotation.y
	_restore_actor(_landing)
	if _inside_swing(_landing, .30):
		# Pouso alternativo (o ponto de espera estava bloqueado) dentro do arco: a porta espera
		# o jogador se afastar em vez de fechar em cima dele.
		_close_door_later(1.6)
		return
	vehicle.animate_driver_door(side, false, .32)

func _close_door_later(delay: float) -> void:
	# O carro pode sair do mundo antes de este fechamento atrasado da porta rodar.
	# Capturar uma WeakRef também evita um argumento de lambda com objeto já liberado.
	var door_vehicle_ref: WeakRef = weakref(vehicle)
	var door_side := side
	vehicle.get_tree().create_timer(delay).timeout.connect(func():
		var door_vehicle = door_vehicle_ref.get_ref()
		if is_instance_valid(door_vehicle): door_vehicle.animate_driver_door(door_side, false, .32))

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
		# O agachamento pertence só a esta apresentação. Mantê-lo no ator escondido
		# fazia a próxima saída usar uma base já rebaixada, afundando a cada viagem.
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
	if is_instance_valid(vehicle):
		# Mocap: se o corpo ainda segura a folha aberta, ela fecha depois que ele se afasta.
		if _mocap != null and _mocap.door_open(): _close_door_later(1.2)
		else: vehicle.animate_driver_door(side, false, 0.0)
	if _mocap != null and _mocap.clip == MOCAP.EXIT and is_instance_valid(actor):
		# O fim do clipe mais o recuo que a folha pediu: o corpo fica onde está, sem voltar ao ponto previsto.
		var pelvis: Vector3 = INTERIOR.pelvis_world(actor)
		_landing = Vector3(pelvis.x, _landing.y, pelvis.z)
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
	if carjacking != null: carjacking.release()
	if break_in != null: break_in.dispose()
	if active and not _finishing:
		if is_instance_valid(_motion): _motion.kill()
		if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
		_restore_actor(_landing if _landing.is_finite() else _start)
