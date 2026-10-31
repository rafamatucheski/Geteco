extends RefCounted
## Coreografia finita, pertencente ao embarque. O ator deslocado mantém a identidade
## e só retoma a IA original depois de chegar a um ponto de aterrissagem checado contra colisão.
const ACTOR := preload("res://scripts/Actor.gd")
const BODY_FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")
## Arrastar e arremessar (2026-10-14): antes a vítima deslizava em linha reta do banco para trás do ladrão,
## levantando ainda dentro do carro (a cabeça atravessava o teto). Agora sai agachada pela porta, o ladrão
## gira e joga, e o voo/queda/levantar é o do atropelamento, sem dano nem sangue. GETECO_CARJACK_THROW=0 volta.
static var throw_enabled := OS.get_environment("GETECO_CARJACK_THROW") != "0"
const DRAG_END := .62
const THROW_AT := .72
const THROW_SPEED := 7.5
## Empurrão do ragdoll: um puxão de braço joga a pessoa a 1,5–2,5 m (o voo varrido usava 7,5).
const SHOVE_SPEED := 3.4
const THROW_DOWN_SECONDS := 1.3
var thrown := false
var flight: Node
var world: Node3D
var vehicle: CharacterBody3D
var victim: CharacterBody3D
var landing := Vector3.INF
var gate := Vector3.ZERO
var seat := Vector3.ZERO
var motorcycle := false
var released := false
var hit := false
var side := -1
var _layer := 2
var _mask := 7
var _physics := true
var _visual_transform := Transform3D.IDENTITY
var _seat_visual := Transform3D.IDENTITY
var _seat_root := Transform3D.IDENTITY
var _weapon: Node3D
var _weapon_visible := false
var _body: Node3D

static func driver_side(car: CharacterBody3D) -> int:
	return 1 if car.has_method("boarding_class") and car.boarding_class() == "bus" else -1

static func landing_point(owner_world: Node3D, car: CharacterBody3D, entry_side: int) -> Vector3:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.72
	var door: Vector3 = car.driver_door_anchor(entry_side) if car.has_method("driver_door_anchor") else car.global_position + car.global_basis.x * float(entry_side)
	var layout: Dictionary = car.door_layout(entry_side) if car.has_method("door_layout") else {}
	var base: Vector3 = car.to_global(layout.stand) if not layout.is_empty() else door
	var offsets: Array[float] = [1.25,1.8,2.4]
	# A boarding tube can occupy the pavement behind a bus's front door.
	# Its open front apron is still a legitimate, collision-checked landing.
	var lateral: Array[float] = [.5]
	if car.has_method("boarding_class") and car.boarding_class()=="bus":
		offsets=[0.0,1.25,1.8,2.4,-1.25,-1.8,-2.4]
		lateral=[.5,.9,1.3]
	var samples: Array[Vector2]=[]
	for back in offsets:
		for outward in lateral: samples.append(Vector2(back,outward))
	for sample in samples:
		var point: Vector3 = base + car.global_basis.z * sample.x + car.global_basis.x * float(entry_side) * sample.y
		var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 4, 1, [car.get_rid()])
		var floor_hit := owner_world.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if floor_hit.is_empty(): continue
		point.y = floor_hit.position.y + .04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .9)
		query.collision_mask = 7
		query.exclude = [car.get_rid(), owner_world.player.get_rid()]
		if owner_world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return point
	return Vector3.INF

func prepare(owner_world: Node3D, car: CharacterBody3D, person: CharacterBody3D, entry_side: int, destination: Vector3, bike := false) -> void:
	world = owner_world
	vehicle = car
	victim = person
	side = entry_side
	landing = destination
	motorcycle = bike
	seat = car.driver_seat_anchor() if car.has_method("driver_seat_anchor") else car.global_position + Vector3.UP * .96
	gate = car.driver_door_anchor(side) if car.has_method("driver_door_anchor") else car.global_position + car.global_basis.x * float(side)
	var layout: Dictionary = car.door_layout(side) if car.has_method("door_layout") else {}
	if not layout.is_empty(): gate = car.to_global(layout.gate)
	if car.has_method("boarding_class") and car.boarding_class()=="bus": gate.y=maxf(gate.y,landing.y)
	_layer = victim.collision_layer
	_mask = victim.collision_mask
	_physics = victim.is_physics_processing()
	_visual_transform = victim.visual.transform
	if motorcycle and victim.get_script() == ACTOR and not victim.has_method("pose_vehicle"):
		_visual_transform = Transform3D(Basis.IDENTITY, Vector3(0,.77,0))
	victim.set_physics_process(false)
	victim.collision_layer = 0
	victim.collision_mask = 0
	victim.add_collision_exception_with(car)
	if victim.visual.get("weapon") is Node3D:
		_weapon = victim.visual.weapon
		_weapon_visible = _weapon.visible
		_weapon.hide()
	if victim.get("skeleton") is Skeleton3D and victim.has_method("pose_vehicle"):
		victim.global_position = seat
		victim.rotation.y = car.global_rotation.y
		victim.pose_vehicle(1.0)
		victim.visual.position.y -= .40 if motorcycle else .48
		victim.visual.scale *= .88 if not motorcycle else 1.0
	else:
		victim.global_position = seat
		victim.rotation.y = car.global_rotation.y
		if victim.visual.get("body") is Node3D: _body = victim.visual.body
		elif victim.visual.get_child_count() > 0 and victim.visual.get_child(0).get("sit_amount") != null: _body = victim.visual.get_child(0)
		if is_instance_valid(_body):
			_body.sit_amount = 1.0
			_body.seat_height = .38
			if not motorcycle and car.has_method("door_layout"):
				# Pelve no banco medido do interior (o mesmo do Dante), não 0,38 m acima da âncora: a cabeça
				# (e o chapéu) da vítima saía pelo teto do sedã enquanto ela esperava ser puxada (captura de 28/10).
				var hip: Vector3 = preload("res://gameplay/VehicleBoardingMocap.gd").seat_pelvis(car)
				# Cabine baixa: o corpo encolhe como o do Dante ao volante (VehicleInterior._fit), senão a cabeça,
				# o chapéu e as mãos erguidas atravessam o teto e o para-brisa. Volta ao tamanho ao ser arrancado.
				var cabin := preload("res://gameplay/VehicleInterior.gd").spec(car)
				if not cabin.is_empty():
					var room := float(cabin.roof) - .06 - (float(cabin.floor) + float(cabin.hip))
					var crown := .84 * _body.global_basis.get_scale().y + .08
					_seat_fit = clampf(room / crown, .78, 1.0)
					victim.visual.scale = _visual_transform.basis.get_scale() * _seat_fit
				var lift: float = .08 * _body.global_basis.get_scale().y
				victim.global_position = Vector3(hip.x, hip.y - .45, hip.z)
				_body.seat_height = maxf(.05, .45 - lift)
			if motorcycle and _body.get("motorcycle_helmet_color") != null: _body.motorcycle_helmet_color = Color("dce2df")
	_seat_root = car.global_transform.affine_inverse() * victim.global_transform
	_seat_visual = victim.visual.transform
	victim.show()

func follow_seat() -> void:
	if released or not is_instance_valid(victim) or not is_instance_valid(vehicle): return
	victim.global_transform = vehicle.global_transform * _seat_root

func apply(thief: CharacterBody3D, progress: float) -> void:
	if released or not is_instance_valid(victim): return
	var t := clampf(progress, 0.0, 1.0)
	var grip := victim.global_position + Vector3.UP * 1.05
	var toward := grip - thief.global_position
	toward.y = 0
	thief.visual.rotation.y = atan2(-toward.x, -toward.z) - thief.global_rotation.y
	thief.show()
	if motorcycle and t < .32:
		if is_instance_valid(thief.animation) and thief.animation.has_animation("ual/Punch_Cross"):
			thief._pose_clip("ual/Punch_Cross", t / .32 * .38)
		else:
			thief.pose_vehicle(0.0)
	else:
		thief.pose_vehicle(0.0)
		var reach := smoothstep(0.0, .18, t) * (1.0 - (smoothstep(THROW_AT, .86, t) if throw_enabled else smoothstep(.68, 1.0, t)))
		for arm in ["Left", "Right"]:
			var sign_side := -1.0 if arm == "Left" else 1.0
			var idle := Vector3(sign_side * .23, .9, -.28)
			var target := idle.lerp(thief.visual.to_local(grip + Vector3.UP * .12), reach)
			thief._solve_combat_arm(arm, target, Basis.IDENTITY, true, sign_side)
		thief._set_combat_grips(reach > .5, reach > .5, motorcycle, motorcycle)
	if t >= .26 and not hit:
		hit = true
		if victim.has_method("present_hit"): victim.present_hit()
		if is_instance_valid(_body) and _body.has_method("take_hit"): _body.take_hit(vehicle.global_basis.x * float(side), .65)
		if motorcycle and is_instance_valid(world.get("gameplay")) and world.gameplay.has_method("_melee_hit_sound"):
			world.gameplay._melee_hit_sound("fists", victim, grip, 0.0)
	if throw_enabled:
		_drag_and_throw(thief, t)
		return
	var pull := smoothstep(.26, .78, t)
	if is_instance_valid(_body): _body.sit_amount = 1.0 - pull
	var seat_now: Vector3 = vehicle.to_global(_seat_root.origin)
	# Primeiro pelo vão real da porta, depois por trás do ladrão e fora do arco de abertura.
	victim.global_position = seat_now.lerp(gate, minf(pull * 2.0, 1.0)).lerp(landing, maxf(pull * 2.0 - 1.0, 0.0))
	victim.visual.transform = _seat_visual.interpolate_with(_visual_transform, pull)
	victim.visual.rotation.z += float(side) * sin(pull * PI) * (.85 if motorcycle else .45)
	victim.visual.position.y -= sin(pull * PI) * .32
	if t >= 1.0: release()

## Banco → porta agachada → giro → voo. A raiz da vítima fica na altura do banco até passar a porta e o corpo
## continua sentado: assim a cabeça não sai pelo teto nem pela moldura.
func _drag_and_throw(thief: CharacterBody3D, t: float) -> void:
	var outward: Vector3 = vehicle.global_basis.x * float(side)
	var seat_now: Vector3 = vehicle.to_global(_seat_root.origin)
	var door_out := gate + outward * .35
	door_out.y = seat_now.y
	var drag := smoothstep(.26, DRAG_END, t)
	var swing := smoothstep(DRAG_END, THROW_AT, t)
	# Sentado até metade da porta, depois meio agachado: nada de ficar em pé ainda dentro do carro.
	if is_instance_valid(_body): _body.sit_amount = lerpf(1.0, .55, smoothstep(.55, 1.0, drag)) * (1.0 - swing * .6)
	if victim.get("skeleton") is Skeleton3D and victim.has_method("pose_vehicle"): victim.pose_vehicle(lerpf(1.0, .5, smoothstep(.55, 1.0, drag)) * (1.0 - swing * .6))
	var along := seat_now.lerp(door_out, drag)
	# No giro o ladrão puxa a vítima para o lado dele, a caminho do ponto de pouso verificado.
	var toward_landing := landing if landing.is_finite() else door_out + outward * 1.5
	toward_landing.y = door_out.y
	victim.global_position = along.lerp(door_out.lerp(toward_landing, .35), swing)
	victim.visual.transform = _seat_visual.interpolate_with(_visual_transform, swing * .5)
	# Tronco inclinado para fora, puxado pela gola; no giro a vítima vira de frente para o ladrão.
	victim.visual.rotation.z += float(side) * (sin(drag * PI * .5) * .35 + swing * .25)
	victim.visual.rotation.y += float(side) * swing * 1.1
	victim.visual.position.y -= sin(drag * PI) * .12
	if t >= THROW_AT: _throw(thief)

func _throw(thief: CharacterBody3D) -> void:
	if thrown: return
	thrown = true
	var from := victim.global_position
	var target := landing if landing.is_finite() else from + vehicle.global_basis.x * float(side) * 2.0
	var direction := target - from
	direction.y = 0.0
	if direction.length_squared() < .01: direction = vehicle.global_basis.x * float(side)
	# Solta na altura do chão do pouso: o voo começa fora do casco e quica no chão de verdade.
	landing = Vector3(from.x, target.y, from.z)
	release()
	if not is_instance_valid(victim) or not victim.is_inside_tree() or victim.get("dead") == true: return
	# Ragdoll de empurrão (28/10): o corpo tropeça e cai de verdade no chão; o voo varrido antigo (corpo
	# girando como tábua) só fica quando não há ragdoll disponível (corpo sem juntas ou acima do teto).
	flight = BODY_FLIGHT.launch(victim, direction.normalized() * SHOVE_SPEED, false, null, thief, true, true)
	if is_instance_valid(flight):
		flight.min_down = THROW_DOWN_SECONDS
		# Sem ragdoll: o voo tomba a partir da pose de pé em 0,38 s; começar no meio da queda continua a
		# inclinação do puxão em vez de mostrar a vítima de pé por um instante (captura de 14/10, quadro de 80%).
		if flight.ragdoll == null: flight._age = .16

# --- Roubo de carro com mocap ----------------------------------------------------------
# A vítima toca "Pulled From Seat" (espelhado para a porta esquerda) sincronizada ao "Pull Pilot From
# Seat" do Dante (VehicleBoardingPresentation): fica sentada, ergue as mãos quando é agarrada, é
# arrancada pelo vão e, já no ar fora da porta, vira ragdoll com a velocidade do clipe; o chão de
# verdade decide como ela cai, e o levantar é o do mocap (BodyGetUp3D).
const GET_UP := preload("res://gameplay/street_physics/BodyGetUp3D.gd")
const MIXAMO_DEATH := preload("res://gameplay/MixamoDeath.gd")
const PULLED := "pulled_from_seat_m"
## s do clipe da vítima: arrancada (2,0–2,5 s), no ar a ~1 m da porta em 2,9 s, no chão em 3,5 s.
const MOCAP_THROW_AT := 2.9
## Da pose sentada do modelo para o clipe.
const MOCAP_BLEND := 0.3
var mocap_active := false
var _mocap_clip: Animation
var _mocap_joints: Dictionary = {}
var _mocap_tracks: Dictionary = {}
var _mocap_position_track := -1
var _mocap_start: Dictionary = {}
var _mocap_start_position := Vector3.ZERO
var _mocap_root := Vector3.ZERO
var _mocap_ground := 0.0
var _mocap_first := -1.0
var _mocap_last := Vector3.INF
var _mocap_velocity := Vector3.ZERO
## Escala do corpo sentado na cabine baixa (1 = tamanho normal), desfeita ao ser arrancado.
var _seat_fit := 1.0

static var mocap_enabled := OS.get_environment("GETECO_MOCAP_CARJACK") != "0"

## Juntas da vítima que a porta não pode atravessar enquanto ela é arrancada pelo vão.
func door_obstacles() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_instance_valid(victim): return result
	var joints := MIXAMO_DEATH.joints_of(victim.visual)
	for joint_name in ["Pelvis", "Spine", "Head", "left_lower_leg", "right_lower_leg"]:
		if joints.has(joint_name): result.append(joints[joint_name])
	return result

func mocap_available() -> bool:
	if not mocap_enabled or motorcycle or released or not is_instance_valid(victim) or not is_instance_valid(_body): return false
	var lib := GET_UP.library()
	return lib != null and lib.has_animation(PULLED) and not MIXAMO_DEATH.joints_of(victim.visual).is_empty()

## Prende o clipe ao corpo sentado: a pelve do primeiro quadro (sentado) fica sobre a pelve atual.
func mocap_begin(victim_time: float) -> bool:
	if not mocap_available(): return false
	_mocap_clip = GET_UP.library().get_animation(PULLED)
	_mocap_joints = MIXAMO_DEATH.joints_of(victim.visual)
	_mocap_tracks.clear()
	_mocap_position_track = -1
	for track in _mocap_clip.get_track_count():
		if _mocap_clip.track_get_type(track) == Animation.TYPE_ROTATION_3D: _mocap_tracks[String(_mocap_clip.track_get_path(track))] = track
		elif _mocap_clip.track_get_type(track) == Animation.TYPE_POSITION_3D: _mocap_position_track = track
	if _mocap_position_track < 0: return false
	var pelvis: Node3D = _mocap_joints["Pelvis"]
	var frame := pelvis.get_parent() as Node3D
	var seated := pelvis.global_position
	for joint_name in _mocap_joints: _mocap_start[joint_name] = (_mocap_joints[joint_name] as Node3D).quaternion
	_mocap_start_position = pelvis.position
	_body.set_process(false)
	var clip_pelvis := frame.to_global(_mocap_clip.position_track_interpolate(_mocap_position_track, victim_time))
	_mocap_root = victim.global_position + (seated - clip_pelvis)
	_mocap_ground = landing.y if landing.is_finite() else vehicle.global_position.y
	_mocap_first = victim_time
	_mocap_last = Vector3.INF
	mocap_active = true
	return true

## Pose da vítima no instante `victim_time` do clipe; arremessa ao passar de MOCAP_THROW_AT.
func mocap_pose(thief: CharacterBody3D, victim_time: float, delta: float) -> void:
	if not mocap_active or released or not is_instance_valid(victim): return
	var blend := smoothstep(0.0, MOCAP_BLEND, victim_time - _mocap_first)
	for joint_name in _mocap_tracks:
		var node: Node3D = _mocap_joints.get(joint_name)
		if not is_instance_valid(node): continue
		var target: Quaternion = _mocap_clip.rotation_track_interpolate(_mocap_tracks[joint_name], victim_time)
		node.quaternion = (_mocap_start.get(joint_name, target) as Quaternion).slerp(target, blend)
	var pelvis: Node3D = _mocap_joints["Pelvis"]
	pelvis.position = _mocap_start_position.lerp(_mocap_clip.position_track_interpolate(_mocap_position_track, victim_time), blend)
	# O chão do clipe fica na altura do banco ajustado; ao ser arrancada a vítima pisa no chão de verdade.
	var standing := smoothstep(1.8, 2.6, victim_time)
	var to_ground := (_mocap_ground - _mocap_root.y) * standing
	victim.global_position = _mocap_root + Vector3.UP * to_ground
	if _seat_fit < 1.0: victim.visual.scale = _visual_transform.basis.get_scale() * lerpf(_seat_fit, 1.0, standing)
	if victim_time >= 1.6 and not hit:
		hit = true
		if victim.has_method("present_hit"): victim.present_hit()
	var now := pelvis.global_position
	if _mocap_last.is_finite() and delta > 0.0:
		_mocap_velocity = _mocap_velocity.lerp((now - _mocap_last) / delta, .5)
	_mocap_last = now
	if victim_time >= MOCAP_THROW_AT: _mocap_throw(thief)

func _mocap_throw(thief: CharacterBody3D) -> void:
	mocap_active = false
	thrown = true
	var push := Vector3(_mocap_velocity.x, 0.0, _mocap_velocity.z)
	if push.length() < 2.0: push = (push.normalized() if push.length_squared() > .01 else vehicle.global_basis.x * float(side)) * 2.0
	landing = Vector3(victim.global_position.x, _mocap_ground, victim.global_position.z)
	release()
	if not is_instance_valid(victim) or not victim.is_inside_tree() or victim.get("dead") == true: return
	# O ragdoll registra quem anima o corpo e para o modelo durante o voo; ele precisa estar ligado agora
	# para voltar a andar quando a vítima levantar.
	if is_instance_valid(_body): _body.set_process(true)
	flight = BODY_FLIGHT.launch(victim, push.limit_length(4.5), false, null, thief, true, true)
	if is_instance_valid(flight): flight.min_down = THROW_DOWN_SECONDS

func release() -> void:
	if released: return
	released = true
	if mocap_active:
		# Interrompido no meio do clipe (desistiu, carro sumiu): o modelo volta a se animar sozinho.
		mocap_active = false
		if is_instance_valid(_body): _body.set_process(true)
	if not is_instance_valid(victim): return
	if not victim.is_inside_tree() or not is_instance_valid(world) or not world.is_inside_tree(): return
	victim.global_position = landing
	victim.visual.transform = _visual_transform
	# A locomoção do ator orienta Visual no yaw do mundo. Remove a rotação de raiz
	# do assento mantendo a aparência atual antes de devolver a IA.
	if victim.get_script() == ACTOR:
		var facing: Basis = victim.visual.global_basis
		victim.global_rotation = Vector3.ZERO
		victim.visual.global_basis = facing
	if victim.get("skeleton") is Skeleton3D and victim.has_method("release_seated"): victim.release_seated()
	if is_instance_valid(_body): _body.sit_amount = 0.0
	if victim.has_method("_finish_exit"): victim._finish_exit()
	if victim.get("mode") == "disembark": victim.mode = "combat"
	if is_instance_valid(_weapon): _weapon.visible = _weapon_visible
	var dead: bool = victim.get("dead") == true
	victim.collision_layer = 0 if dead else _layer
	victim.collision_mask = 0 if dead else _mask
	victim.velocity = Vector3.ZERO
	victim.reset_physics_interpolation()
	victim.set_physics_process(_physics and not dead)
	if victim.get_script() == ACTOR:
		victim.route = PackedVector3Array([landing, landing + (landing - vehicle.global_position).normalized() * 8]) if is_instance_valid(vehicle) and vehicle.is_inside_tree() else PackedVector3Array([landing])
		if is_instance_valid(world.player) and world.player.is_inside_tree() and is_instance_valid(world.get("production")):
			var reactions = world.production.get("civilian_reactions")
			if is_instance_valid(reactions): reactions.report_assault(victim, world.player)
