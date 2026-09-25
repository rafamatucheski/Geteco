extends CharacterBody3D

const DANTE := preload("res://assets/dante.glb")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const OUTFIT_APPEARANCE := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STEERING := preload("res://gameplay/crowd/PedestrianSteering.gd")
## Civis longe da câmera e fora de controle alheio andam em passo de LOD: física a cada LOD_STRIDE quadros com o
## delta acumulado. Mantém rota e posição coerentes e corta ~2/3 do custo de move_and_slide + pose de quem não se vê.
const LOD_DISTANCE := 45.0
const LOD_STRIDE := 3
var _steering: RefCounted
var _lod_frame := 0
var _lod_delta := 0.0
var outfit_id := "dante_classic"
var outfit_material: ShaderMaterial
var is_player := false
var identity := 0
var camera: Camera3D
var visual: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var hips := -1
var hip_rest := Vector3.ZERO
var route := PackedVector3Array()
var waypoint := 0
var speed := 1.6
var automatic_direction := Vector3.ZERO
var controlled_automatically := false
var input_locked := false
var ski_controller
var health := 100.0
var dead := false
var travelled := 0.0
var phase := 0.0
var last_position := Vector3.ZERO
## Camada de apresentação de combate, ESCRITA por `Gameplay` e só lida aqui (nada decide dano).
## `combat_facing`: rumo visual forçado (rad, mesma convenção de `visual.rotation.y`); NAN = livre
## (a caminhada volta a girar o corpo). `combat_clip`/`combat_clip_time`: clipe do `dante.glb` a exibir no
## lugar de Walking/Running enquanto o nome não for vazio; a caminhada retoma sozinha ao esvaziar.
var combat_facing := NAN
var combat_clip := ""
var combat_clip_time := 0.0
## Postura de arma enquanto mira: "gun" (arma de fogo), "grenade" ou "" (mãos livres/corpo a corpo). Só vale com
## `combat_facing` ativo; escolhe a locomoção armada direcional.
var combat_stance := ""
## Alvos de empunhadura calculados por Gameplay/WeaponRigPose. São apresentação
## apenas: Gameplay resolve o dano no contato da ação.
var combat_weapon_pose: Dictionary = {}
var combat_weapon_id := ""
var combat_weapon_mount: Node3D
var combat_weapon_grip := Vector3.ZERO
var _reaction_tween: Tween
const FALL_TIME := 0.22
const FLINCH_ANGLE := 0.22
## Mistura curta entre locomoção e clipe de golpe (0 = só locomoção, 1 = só o clipe), tempo em `COMBAT_BLEND`.
var _combat_weight := 0.0
var _last_clip := ""
var _last_clip_time := 0.0
## Pesos perceptivos equivalentes aos do Dante V1: a fase só avança com
## deslocamento real, enquanto o corpo entra/sai da passada suavemente.
var _locomotion_weight := 0.0
var _run_weight := 0.0
var _idle_pose: Array = []
var _combat_bones: Dictionary = {}
var _combat_rests: Array[Transform3D] = []
var _combat_skin: MeshInstance3D
var _idle_clock := 0.0
var _directional_weight := 0.0
var _gait_direction := Vector2(0, 1)
var _cycle_starts: Dictionary = {}
var _feet_yaw := 0.0
var _feet_initialized := false
var _turn_time := 1.0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_feet: Dictionary = {}
var _idle_feet: Dictionary = {}
var _hit_age := 1.0
var _traversal_roots: Dictionary = {}
var _arm_blends: Dictionary = {}
var _presented_arm_rotations: Dictionary = {}
var _pose_delta := 1.0 / 60.0
var _elbow_previous: Dictionary = {}
var _elbow_solved: Dictionary = {}
## Duração da mistura de poses ao entrar e sair do clipe de golpe (não calibrada).
const COMBAT_BLEND := 0.08
const LOCOMOTION_BLEND_RATE := 7.0
const RUN_BLEND_RATE := 4.5
const MOVING_SPEED_EPSILON := 0.12
const WALK_START := 0.067
func _ready() -> void:
	set_meta("gameplay_role","player" if is_player else "civilian")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	if is_player:
		var model := DANTE.instantiate() as Node3D
		model.scale = Vector3.ONE * 1.03
		model.rotation.y = PI
		visual.add_child(model)
		animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton:
			hips = skeleton.find_bone("Hips")
			if hips >= 0: hip_rest = skeleton.get_bone_rest(hips).origin
			for bone_index in skeleton.get_bone_count():
				_combat_bones[skeleton.get_bone_name(bone_index)] = bone_index
				_combat_rests.append(skeleton.get_bone_rest(bone_index))
			_combat_skin = model.find_child("Mesh0", true, false) as MeshInstance3D
		if animation:
			animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_build_idle_pose()
		set_outfit(outfit_id)
	else:
		var model := CIVILIAN.new()
		model.appearance_locked = true
		model.appearance_variant = identity
		model.coat_color = [Color("426c70"), Color("a35d42"), Color("d3c3a1"), Color("42556f"), Color("8e5362"), Color("70835d")][identity % 6]
		model.pants_color = [Color("293849"), Color("484644"), Color("615342")][identity % 3]
		model.rotation.y = PI
		visual.add_child(model)
	last_position = global_position

func _physics_process(delta: float) -> void:
	var lod_scale := 1.0
	if not is_player and not controlled_automatically:
		var view_camera := get_viewport().get_camera_3d()
		if view_camera != null and view_camera.global_position.distance_squared_to(global_position) > LOD_DISTANCE * LOD_DISTANCE:
			_lod_frame += 1
			_lod_delta += delta
			if _lod_frame < LOD_STRIDE: return
			lod_scale = _lod_delta / maxf(delta, 0.0001)
			delta = _lod_delta
		_lod_frame = 0
		_lod_delta = 0.0
	var direction := Vector3.ZERO
	var target_speed := speed
	if controlled_automatically:
		direction = automatic_direction
	elif is_player:
		var axis: Vector2 = get_node("/root/GameInput").movement()
		if camera:
			var right := camera.global_basis.x
			var back := camera.global_basis.z
			right.y = 0
			back.y = 0
			direction = (right.normalized() * axis.x + back.normalized() * axis.y).limit_length()
		# Corrida pelo `GameInput`: no controle é alternável (`sprint_toggled`), no teclado é segurar.
		target_speed = 6.5 if get_node("/root/GameInput").sprinting() else 3.5
	elif route.size() > 1:
		# Mira a faixa da direita do trecho, não o eixo: quem vem no sentido oposto usa a outra faixa.
		var previous := route[(waypoint - 1 + route.size()) % route.size()]
		var offset := STEERING.lane_point(previous, route[waypoint]) - global_position
		offset.y = 0
		if offset.length() < 0.5:
			waypoint = (waypoint + 1) % route.size()
			offset = STEERING.lane_point(route[(waypoint - 1 + route.size()) % route.size()], route[waypoint]) - global_position
			offset.y = 0
		direction = offset.normalized()
	if not is_player and direction.length_squared() > 0.01:
		if _steering == null: _steering = STEERING.new()
		direction = _steering.steer(self, direction, delta)
		# Travou de verdade na rota própria: desiste deste ponto e segue para o próximo (volta pela calçada).
		if _steering.stuck and not controlled_automatically and route.size() > 1:
			waypoint = (waypoint + 1) % route.size()
	if is_player and not input_locked and is_instance_valid(ski_controller) and ski_controller.skiing:
		var motion: Vector3 = ski_controller.motion(delta,direction)
		direction = motion.normalized()
		target_speed = motion.length()
	if input_locked: direction = Vector3.ZERO
	if is_player and not is_nan(combat_facing) and direction.length_squared() > 0.001:
		# A braced backwards/side step is not a forward sprint played in reverse.
		# Match actual displacement to the native directional clips' stride.
		var forward := Vector3(-sin(combat_facing), 0, -cos(combat_facing))
		var alignment := direction.normalized().dot(forward)
		var combat_speed := lerpf(1.35, 1.65 if alignment < 0.0 else 2.5, absf(alignment))
		target_speed = minf(target_speed, combat_speed)
	velocity.x = direction.x * target_speed * lod_scale
	velocity.z = direction.z * target_speed * lod_scale
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if lod_scale != 1.0:
		velocity.x /= lod_scale
		velocity.z /= lod_scale
	var displacement := global_position - last_position
	displacement.y = 0
	travelled += displacement.length()
	var actual_speed := displacement.length() / maxf(delta, 0.001)
	last_position = global_position
	if direction.length_squared() > 0.01 and (not is_player or is_nan(combat_facing)):
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-14.0 * delta))
	# Mirando/atacando, o corpo segue o rumo do disparo, não o do movimento.
	if is_player and not is_nan(combat_facing):
		visual.rotation.y = rotate_toward(visual.rotation.y, combat_facing, delta * 9.0)
	if animation:
		# Camada de combate: o clipe de golpe entra e sai com uma mistura curta de poses (nada de corte seco); sem
		# clipe, só locomoção. A pose é sempre escolhida aqui; `Gameplay` só informa clipe e tempo.
		var combat_wanted := is_player and combat_clip != "" and animation.has_animation(combat_clip)
		if combat_wanted:
			_last_clip = combat_clip
			_last_clip_time = combat_clip_time
		_combat_weight = move_toward(_combat_weight, 1.0 if combat_wanted else 0.0, delta / COMBAT_BLEND)
		if _combat_weight <= 0.0:
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
		elif _combat_weight >= 1.0:
			_pose_clip(_last_clip, _last_clip_time)
		elif is_instance_valid(skeleton):
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
			var locomotion_pose := _capture_pose()
			_pose_clip(_last_clip, _last_clip_time)
			_apply_blend(locomotion_pose, _capture_pose(), _combat_weight)
		else:
			_pose_locomotion(direction, target_speed, displacement, actual_speed, delta)
		if hips >= 0:
			var hip_position := skeleton.get_bone_pose_position(hips)
			hip_position.x = hip_rest.x
			hip_position.z = hip_rest.z
			skeleton.set_bone_pose_position(hips, hip_position)
		if is_player:
			_hit_age += delta
			visual.rotation.x = sin(_hit_age / 0.28 * PI) * 0.06 if _hit_age < 0.28 else 0.0
			_apply_combat_weapon_pose()
	else:
		if visual.get_child(0).get("walking") != null: visual.get_child(0).walking = actual_speed > 0.1

## Caminhada/corrida comuns (fase travada na distância) ou, se couber, a
## locomoção armada. A entrada/saída usa o deslocamento REAL: soltar o comando,
## bater num sólido ou encerrar um deslocamento automático converge para a
## mesma postura parada em vez de congelar o último passo.
func _pose_locomotion(direction: Vector3, target_speed: float, displacement: Vector3, actual_speed: float, delta: float = 1.0 / 60.0) -> void:
	_pose_delta = delta
	_idle_clock += delta
	var moving := actual_speed > MOVING_SPEED_EPSILON
	var directional := is_player and not is_nan(combat_facing)
	_locomotion_weight = move_toward(_locomotion_weight, 1.0 if moving else 0.0, delta * LOCOMOTION_BLEND_RATE)
	_run_weight = move_toward(_run_weight, smoothstep(3.8, 6.0, actual_speed) if moving and not directional else 0.0, delta * RUN_BLEND_RATE)
	_directional_weight = move_toward(_directional_weight, 1.0 if directional else 0.0, delta * 8.0)
	if _locomotion_weight <= 0.0 and not _idle_pose.is_empty():
		# Mantém um nome produtivo no AnimationPlayer para consumidores existentes,
		# mas aplica a postura simétrica cacheada; `restpose` é uma T-pose.
		animation.play("Walking")
		_apply_pose(_idle_pose)
		_apply_idle_breath()
		_pose_turn(delta, false)
		return
	var local_move := visual.global_basis.inverse() * (displacement.normalized() if moving else direction)
	_gait_direction = _gait_direction.move_toward(Vector2(local_move.x, -local_move.z), delta * 7.0)
	var lateral := absf(_gait_direction.x)
	var backward := maxf(0, -_gait_direction.y)
	var directional_stride := lerpf(1.8, 1.06 if combat_stance == "grenade" else 0.91, clampf(backward, 0, 1))
	directional_stride = lerpf(directional_stride, 0.89, clampf(lateral, 0, 1))
	var stride := lerpf(lerpf(1.8, 3.4, _run_weight), directional_stride, _directional_weight)
	phase = fposmod(phase + displacement.length() / stride, 1.0)
	_pose_cycle("Walking", phase, WALK_START)
	if _run_weight > 0.0:
		var walk_pose := _capture_pose()
		_pose_cycle("Running", phase, 0.0)
		if _run_weight < 1.0: _apply_blend(walk_pose, _capture_pose(), _run_weight)
	if _directional_weight > 0.0:
		# Só guardar a pose anterior quando ela realmente entra na mistura.
		# Recuo/lateral puros evitam quatro cópias do esqueleto por quadro.
		var ordinary: Array = _capture_pose() if _directional_weight < 1.0 else []
		if backward > 0.001:
			var longitudinal: Array = _capture_pose() if backward < 1.0 else []
			_pose_cycle("Walk_Backward_with_Gun" if combat_stance != "grenade" else "Walk_Backward_with_Grenade", phase, 0.0)
			if backward < 1.0: _apply_blend(longitudinal, _capture_pose(), clampf(backward, 0, 1))
		if lateral > 0.001:
			var longitudinal: Array = _capture_pose() if lateral < 1.0 else []
			_pose_cycle("Walk_Left_with_Gun", phase, 0.0)
			if _gait_direction.x < 0.0: _mirror_current_pose()
			if lateral < 1.0: _apply_blend(longitudinal, _capture_pose(), clampf(lateral, 0, 1))
		if _directional_weight < 1.0: _apply_blend(ordinary, _capture_pose(), _directional_weight)
	if _locomotion_weight < 1.0 and not _idle_pose.is_empty():
		var moving_pose := _capture_pose()
		_apply_blend(_idle_pose, moving_pose, _locomotion_weight)
	var hip := skeleton.get_bone_pose_position(hips)
	hip.x = hip_rest.x
	hip.z = hip_rest.z
	skeleton.set_bone_pose_position(hips, hip)
	_pose_turn(delta, moving)

## A animação importada não possui Idle: `restpose` é a T-pose vista no
## modelo. A média de duas fases opostas de Walking cancela a passada e produz
## uma base ereta/simétrica. É calculada uma vez; não adiciona avaliação de
## animação ao custo do repouso.
func _build_idle_pose() -> void:
	if not is_instance_valid(skeleton) or not animation.has_animation("Walking"): return
	_pose_cycle("Walking", 0.0, WALK_START)
	var first := _capture_pose()
	_pose_cycle("Walking", 0.5, WALK_START)
	_apply_blend(first, _capture_pose(), 0.5)
	if hips >= 0:
		var hip_position := skeleton.get_bone_pose_position(hips)
		hip_position.x = hip_rest.x
		hip_position.z = hip_rest.z
		skeleton.set_bone_pose_position(hips, hip_position)
	var upright := skeleton.get_bone_pose_position(hips)
	upright.y += 0.012
	skeleton.set_bone_pose_position(hips, upright)
	for side in ["Left", "Right"]:
		var foot: int = _combat_bones[side + "Foot"]
		var point := visual.to_local(skeleton.to_global(skeleton.get_bone_global_pose(foot).origin))
		point.x = -0.12 if side == "Left" else 0.12
		point.z = -0.025 if side == "Left" else 0.025
		_solve_leg(side, visual.to_global(point))
	_idle_pose = _capture_pose()
	for side in ["Left", "Right"]:
		var foot: int = _combat_bones[side + "Foot"]
		_idle_feet[side] = visual.to_local(skeleton.to_global(skeleton.get_bone_global_pose(foot).origin))

func _pose_cycle(clip: String, normalized_phase: float, start: float) -> void:
	var anim := animation.get_animation(clip)
	animation.play(clip)
	if not _cycle_starts.has(clip):
		animation.seek(start, true)
		_cycle_starts[clip] = _capture_pose()
	var p := fposmod(normalized_phase, 1.0)
	animation.seek(start + p * maxf(0.01, anim.length - start), true)
	if p > 0.90: _apply_blend(_capture_pose(), _cycle_starts[clip], smoothstep(0.90, 1.0, p))

func _mirror_current_pose() -> void:
	var original := _capture_pose()
	for bone in original.size():
		var name := skeleton.get_bone_name(bone)
		var other := name.replace("Left", "Right") if name.begins_with("Left") else name.replace("Right", "Left")
		var source: int = _combat_bones.get(other, bone)
		var q: Quaternion = original[source][1]
		var rest := _combat_rests[source].basis.get_rotation_quaternion()
		var mirrored := Quaternion(q.x, -q.y, -q.z, q.w)
		var reflected_rest := Quaternion(rest.x, -rest.y, -rest.z, rest.w)
		skeleton.set_bone_pose_rotation(bone, (_combat_rests[bone].basis.get_rotation_quaternion() * reflected_rest.inverse() * mirrored).normalized())

func _apply_idle_breath() -> void:
	var chest: int = _combat_bones.get("Spine02", -1)
	if chest >= 0:
		var breath := sin(_idle_clock * 1.65) * 0.009
		skeleton.set_bone_pose_rotation(chest, skeleton.get_bone_pose_rotation(chest) * Quaternion(Vector3.RIGHT, breath))

func _pose_turn(delta: float, moving: bool) -> void:
	if _idle_feet.is_empty(): return
	if not _feet_initialized or moving:
		_feet_yaw = visual.rotation.y
		_feet_initialized = true
		_turn_time = 1.0
		_turn_feet.clear()
		return
	var difference := wrapf(visual.rotation.y - _feet_yaw, -PI, PI)
	if _turn_time >= 1.0 and absf(difference) > 0.20:
		_turn_from = _feet_yaw
		_turn_to = _feet_yaw + clampf(difference, -PI * 0.5, PI * 0.5)
		_turn_time = 0.0
		for side in ["Left", "Right"]:
			_turn_feet[side] = global_transform * (Basis(Vector3.UP, _turn_from) * (_idle_feet[side] as Vector3))
	if _turn_time < 1.0:
		_turn_time = minf(1.0, _turn_time + delta / 0.36)
		_feet_yaw = lerp_angle(_turn_from, _turn_to, smoothstep(0.0, 1.0, _turn_time))
	var offset := clampf(wrapf(_feet_yaw - visual.rotation.y, -PI, PI), -0.65, 0.65)
	var chest: int = _combat_bones.get("Spine02", -1)
	var chest_basis := skeleton.get_bone_global_pose(chest).basis
	_set_combat_bone_rotation(hips, Basis(Vector3.UP, offset) * skeleton.get_bone_global_pose(hips).basis)
	_set_combat_bone_rotation(chest, chest_basis)
	if not _turn_feet.is_empty():
		for side in ["Left", "Right"]:
			var first: bool = (side == "Left") == (_turn_to > _turn_from)
			var t := clampf(_turn_time * 2.0 - (0.0 if first else 1.0), 0.0, 1.0)
			var target := global_transform * (Basis(Vector3.UP, _turn_to) * (_idle_feet[side] as Vector3))
			var foot: Vector3 = (_turn_feet[side] as Vector3).lerp(target, smoothstep(0, 1, t))
			foot.y += sin(t * PI) * 0.075
			_solve_leg(side, foot)

func _solve_leg(side: String, world_foot: Vector3) -> void:
	var upper: int = _combat_bones[side + "UpLeg"]
	var lower: int = _combat_bones[side + "Leg"]
	var foot: int = _combat_bones[side + "Foot"]
	var foot_basis := skeleton.get_bone_global_pose(foot).basis
	var origin := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(world_foot)
	var a := _combat_rests[lower].origin.length()
	var b := _combat_rests[foot].origin.length()
	var axis := (target - origin).normalized()
	var distance := clampf(origin.distance_to(target), 0.05, a + b - 0.001)
	var pole := Vector3(0, 0, 1)
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var along := (a*a - b*b + distance*distance) / (2.0 * distance)
	var knee := origin + axis * along + bend * sqrt(maxf(0, a*a - along*along))
	_point_combat_bone(upper, lower, knee)
	_point_combat_bone(lower, foot, target)
	_set_combat_bone_rotation(foot, foot_basis)

func _apply_pose(pose: Array) -> void:
	if not is_instance_valid(skeleton): return
	for bone in mini(pose.size(), skeleton.get_bone_count()):
		skeleton.set_bone_pose_position(bone, pose[bone][0] as Vector3)
		skeleton.set_bone_pose_rotation(bone, pose[bone][1] as Quaternion)
		skeleton.set_bone_pose_scale(bone, pose[bone][2] as Vector3)

func _pose_clip(clip: String, time: float) -> void:
	if not animation.has_animation(clip): return
	animation.play(clip)
	if clip == "Fast_Ladder_Climb" and not _traversal_roots.has(clip):
		animation.seek(0.0, true)
		var first := skeleton.get_bone_pose_position(hips)
		animation.seek(animation.get_animation(clip).length, true)
		_traversal_roots[clip] = [first, skeleton.get_bone_pose_position(hips)]
	animation.seek(clampf(time, 0.0, animation.get_animation(clip).length), true)
	if clip == "Fast_Ladder_Climb":
		var endpoints: Array = _traversal_roots[clip]
		var progress := clampf(time / animation.get_animation(clip).length, 0, 1)
		var hip := skeleton.get_bone_pose_position(hips)
		hip -= (endpoints[0] as Vector3).lerp(endpoints[1], progress) - hip_rest
		hip.x = hip_rest.x
		hip.z = hip_rest.z
		skeleton.set_bone_pose_position(hips, hip)

func pose_vehicle(sitting: float, stepping: float = 0.0, side: int = -1, reach: float = 1.0, handlebars: Dictionary = {}) -> void:
	_apply_pose(_idle_pose)
	if handlebars.size() == 2:
		var center: Vector3 = visual.to_local((handlebars.Left.origin + handlebars.Right.origin) * .5)
		if hips >= 0:
			# Lean from the waist instead of stretching arm bones to a distant bar.
			var toward := Vector3(center.x, 0, center.z).normalized()
			var lean := clampf(Vector2(center.x, center.z).length() * 1.8, .5, 1.3)
			var bar_axis: Vector3 = visual.global_basis.orthonormalized().inverse() * (handlebars.Right.basis.y as Vector3)
			var turn := atan2(-bar_axis.z, bar_axis.x)
			var forward_lean := visual.global_basis.orthonormalized() * Basis(Vector3.UP.cross(toward), lean) * Basis(Vector3.UP, turn) * visual.global_basis.orthonormalized().inverse()
			var local_lean := skeleton.global_basis.orthonormalized().inverse() * forward_lean * skeleton.global_basis.orthonormalized()
			_set_combat_bone_rotation(hips, local_lean * skeleton.get_bone_global_pose(hips).basis)
			_fit_motorcycle_reach(handlebars)
	for limb in ["Left", "Right"]:
		var sign_side := -1.0 if limb == "Left" else 1.0
		var target: Vector3 = (_idle_feet[limb] as Vector3).lerp(Vector3(sign_side * 0.15, 0.50, -0.38), sitting)
		if (limb == "Left") == (side < 0): target += Vector3(sign_side * 0.22, 0.48, -0.04) * stepping
		_solve_leg(limb, visual.to_global(target))
		var hand := Vector3(sign_side * 0.23, lerpf(0.86, 1.05, sitting), -0.28)
		var palm_basis := Basis.IDENTITY
		if handlebars.has(limb):
			var hold: Transform3D = handlebars[limb]
			hand = visual.to_local(hold.origin)
			palm_basis = visual.global_basis.orthonormalized().inverse() * hold.basis
		_solve_combat_arm(limb, hand, palm_basis, not handlebars.is_empty(), sign_side)
	_set_combat_grips(not handlebars.is_empty(), not handlebars.is_empty())
	if reach < 1.0: _apply_blend(_idle_pose, _capture_pose(), clampf(reach, 0.0, 1.0))

func _fit_motorcycle_reach(handlebars: Dictionary) -> void:
	var shift := Vector3.ZERO
	for limb in ["Left", "Right"]:
		var hold: Transform3D = handlebars[limb]
		var roll := .358 if limb == "Right" else -.392
		var hand_basis := hold.basis * Basis(Vector3.RIGHT, -PI * .5) * Basis(Vector3.UP, -roll)
		var wrist := hold.origin - hand_basis * Vector3(0, .065, 0) * skeleton.global_basis.get_scale().x
		var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(_combat_bones[limb + "Arm"]).origin)
		var length: float = (_combat_rests[_combat_bones[limb + "ForeArm"]].origin.length() + _combat_rests[_combat_bones[limb + "Hand"]].origin.length() - .045) * skeleton.global_basis.get_scale().x
		var offset := wrist - shoulder
		var correction := offset.normalized() * maxf(0.0, offset.length() - length)
		if correction.length_squared() > shift.length_squared(): shift = correction
	# The outside grip travels farther during steering. Scoot on the saddle
	# within 28 cm instead of stretching the arm; leg IK keeps both foot targets.
	shift = shift.limit_length(.28)
	var parent := skeleton.get_bone_parent(hips)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var local_shift := parent_basis.inverse() * skeleton.global_basis.inverse() * shift
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + local_shift)

func _capture_pose() -> Array:
	var pose: Array = []
	for bone in skeleton.get_bone_count(): pose.append([skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone), skeleton.get_bone_pose_scale(bone)])
	return pose

func _apply_blend(from_pose: Array, to_pose: Array, weight: float) -> void:
	for bone in from_pose.size():
		skeleton.set_bone_pose_position(bone, (from_pose[bone][0] as Vector3).lerp(to_pose[bone][0], weight))
		skeleton.set_bone_pose_rotation(bone, (from_pose[bone][1] as Quaternion).slerp(to_pose[bone][1], weight))
		skeleton.set_bone_pose_scale(bone, (from_pose[bone][2] as Vector3).lerp(to_pose[bone][2], weight))

## Gameplay escreve um pacote pronto em espaço local do Actor. O pacote é
## aplicado depois da locomoção, para que pernas/corpo continuem animados e os
## braços mantenham contato real com as empunhaduras.
func set_combat_weapon_pose(id: String, pose: Dictionary) -> void:
	combat_weapon_id = id
	combat_weapon_pose = pose

func set_combat_weapon_mount(node: Node3D, grip: Vector3) -> void:
	combat_weapon_mount = node
	combat_weapon_grip = grip

func clear_combat_weapon_pose() -> void:
	combat_weapon_id = ""
	combat_weapon_pose = {}

func _apply_combat_weapon_pose() -> void:
	_elbow_previous = _elbow_solved.duplicate()
	var support_hand_before: Quaternion = _presented_arm_rotations.get(_combat_bones.get("LeftHand", -1), Quaternion.IDENTITY)
	var had_support_hand := _presented_arm_rotations.has(_combat_bones.get("LeftHand", -1))
	var support_fore_before: Quaternion = _presented_arm_rotations.get(_combat_bones.get("LeftForeArm", -1), Quaternion.IDENTITY)
	if skeleton == null or combat_weapon_pose.is_empty():
		_set_combat_grips(false, false)
		_stabilize_combat_pose()
		return
	for required in ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]:
		if not _combat_bones.has(required): return
	var pose := combat_weapon_pose
	var armed := bool(pose.get("armed", combat_weapon_id != "fists"))
	var right_grip := bool(pose.get("right_grip", false))
	var left_grip := bool(pose.get("left_grip", false))
	# Braço que a pose não pede fica com o clipe de locomoção (como o braço livre
	# da V1, que seguia Walking/Running em vez de um alvo procedural).
	var right_solve := bool(pose.get("right_solve", right_grip or combat_weapon_id != "fists"))
	var left_solve := bool(pose.get("left_solve", left_grip))
	var right_basis: Basis = pose.get("right_basis", pose.basis)
	var left_basis: Basis = pose.get("left_basis", pose.basis)
	# V1 `MeshyDanteRig.prepare_pose`/`sync_shoulders`: armado, a coluna baixa volta
	# ao repouso e a de cima recebe só o giro de postura. Senão o clipe de
	# caminhada torce a camisa contra braços já resolvidos no espaço da mira.
	var torso_yaw := float(pose.get("torso_yaw", 0.0))
	if combat_weapon_id in ["fists", "knuckles", "knife", "axe", "bat"] and absf(torso_yaw) > 0.001:
		var chest_before: Basis = skeleton.get_bone_global_pose(_combat_bones.Spine02).basis
		_set_combat_bone_rotation(hips, Basis(Vector3.UP, torso_yaw * 0.35) * skeleton.get_bone_global_pose(hips).basis)
		_set_combat_bone_rotation(_combat_bones.Spine02, chest_before)
		if _locomotion_weight <= 0.0 and _turn_time >= 1.0:
			for side in ["Left", "Right"]:
				_solve_leg(side, global_transform * (Basis(Vector3.UP, _feet_yaw) * (_idle_feet[side] as Vector3)))
	if armed and _combat_bones.has("Spine02"):
		var lower: int = _combat_bones.Spine02
		_set_combat_bone_rotation(lower, skeleton.get_bone_global_rest(lower).basis)
	if _combat_bones.has("Spine") and (armed or absf(torso_yaw) > 0.001):
		var spine: int = _combat_bones.Spine
		var chest := skeleton.get_bone_global_rest(spine).basis if armed else skeleton.get_bone_global_pose(spine).basis
		_set_combat_bone_rotation(spine, Basis(Vector3.UP, torso_yaw) * chest)
	var right_weight := clampf(float(pose.get("right_weight", 1.0)), 0.0, 1.0)
	var right_clip: Array = []
	if right_solve and right_weight < 1.0:
		for bone_name in ["RightShoulder", "RightArm", "RightForeArm", "RightHand"]:
			if _combat_bones.has(bone_name): right_clip.append([_combat_bones[bone_name], skeleton.get_bone_pose_rotation(_combat_bones[bone_name])])
	var left_weight := clampf(float(pose.get("left_weight", 1.0)), 0.0, 1.0)
	var left_clip: Array = []
	if left_solve and left_weight < 1.0:
		for bone_name in ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"]:
			if _combat_bones.has(bone_name): left_clip.append([_combat_bones[bone_name], skeleton.get_bone_pose_rotation(_combat_bones[bone_name])])
	if right_solve: _protract_clavicle("Right")
	if left_solve: _protract_clavicle("Left")
	var right_free := float(pose.get("right_free", 0.0))
	var left_free := float(pose.get("left_free", 0.0))
	var right_target: Vector3 = pose.right
	var support_weight := float(pose.get("support_weight", 1.0 if pose.get("support_locked", false) else 0.0))
	var lock_support := right_solve and left_solve and left_grip and support_weight > 0.0
	if lock_support:
		# Mesma restrição bilateral do V1: projeta o conjunto até cabo e apoio
		# caberem simultaneamente no alcance dos dois braços. Sem isso a arma
		# fica na mão direita, mas o guarda-mão flutua 8–11 cm da esquerda.
		var relative_world: Vector3 = visual.global_basis * (pose.left - pose.right)
		for iteration in 8:
			_solve_combat_arm("Right", right_target, right_basis, right_grip, 1.0, right_free)
			var desired_left_world: Vector3 = combat_palm_position("Right") + relative_world
			_solve_combat_arm("Left", visual.to_local(desired_left_world), left_basis, true, -1.0, left_free)
			var support_error: Vector3 = combat_palm_position("Left") - desired_left_world
			if support_error.length() < 0.004: break
			right_target = visual.to_local(visual.to_global(right_target) + support_error * 0.72 * support_weight)
	if right_solve:
		_solve_combat_arm("Right", right_target, right_basis, right_grip, 1.0, right_free)
		for entry in right_clip:
			_blend_arm_bone(entry[0], entry[1], right_weight)
	if left_solve:
		var left_target: Vector3 = pose.left
		if lock_support:
			var realised_delta: Vector3 = visual.global_basis * (pose.left - pose.right)
			left_target = visual.to_local(combat_palm_position("Right") + realised_delta)
		_solve_combat_arm("Left", left_target, left_basis, left_grip, -1.0, left_free)
		for entry in left_clip:
			_blend_arm_bone(entry[0], entry[1], left_weight)
	_set_combat_grips(right_grip, left_grip, bool(pose.get("right_fist", false)), bool(pose.get("left_fist", false)), not right_solve, not left_solve or left_weight < 0.5)
	_stabilize_combat_pose()
	if lock_support and bool(pose.get("support_locked", false)):
		# Resolve support against the realized (angularly constrained) weapon,
		# never the pre-interpolation hand. This keeps both palms on the prop.
		var delta_world: Vector3 = visual.global_basis * (pose.left - pose.right)
		var support_target := visual.to_local(combat_palm_position("Right") + delta_world)
		_solve_combat_arm("Left", support_target, left_basis, true, -1.0, left_free)
		if had_support_hand:
			var hand: int = _combat_bones.LeftHand
			var fore: int = _combat_bones.LeftForeArm
			var hand_basis := skeleton.get_bone_global_pose(hand).basis
			var fore_target := skeleton.get_bone_pose_rotation(fore)
			var change := (support_fore_before.inverse() * fore_target).normalized()
			if change.w < 0: change = -change
			var axis := _combat_rests[hand].origin.normalized()
			var projected := axis * Vector3(change.x, change.y, change.z).dot(axis)
			var twist := Quaternion(projected.x, projected.y, projected.z, change.w).normalized()
			var turn := 2.0 * atan2(Vector3(twist.x, twist.y, twist.z).dot(axis), twist.w)
			var swing := change * twist.inverse()
			# Bound axial roll without moving the wrist off the handle.
			skeleton.set_bone_pose_rotation(fore, (support_fore_before * swing * Quaternion(axis, clampf(turn, -14.0 * _pose_delta, 14.0 * _pose_delta))).normalized())
			_set_combat_bone_rotation(hand, hand_basis)
			var desired := skeleton.get_bone_pose_rotation(hand)
			var angle := support_hand_before.angle_to(desired)
			skeleton.set_bone_pose_rotation(hand, support_hand_before.slerp(desired, minf(1.0, 18.0 * _pose_delta / maxf(angle, 0.0001))))
		for part in ["Shoulder", "Arm", "ForeArm", "Hand"]:
			var bone: int = _combat_bones["Left" + part]
			_presented_arm_rotations[bone] = skeleton.get_bone_pose_rotation(bone)
	# Actor é processado antes de Gameplay na árvore produtiva. Atualizar o
	# mount aqui elimina o atraso visual de um quadro entre esqueleto e arma.
	if is_instance_valid(combat_weapon_mount) and right_solve and armed:
		combat_weapon_mount.global_transform = combat_weapon_transform(combat_weapon_grip)

func _stabilize_combat_pose() -> void:
	# Joint angular velocity is part of the presentation constraint, including
	# entry/exit and changes of reach constraints. Mounts follow the realized
	# hand after this pass, so interpolation cannot detach the held weapon.
	for side in ["Right", "Left"]:
		for part in ["Shoulder", "Arm", "ForeArm", "Hand"]:
			var bone: int = _combat_bones.get(side + part, -1)
			if bone < 0: continue
			var target := skeleton.get_bone_pose_rotation(bone).normalized()
			if _presented_arm_rotations.has(bone):
				var previous: Quaternion = _presented_arm_rotations[bone]
				var angle := previous.angle_to(target)
				target = previous.slerp(target, minf(1.0, 18.0 * _pose_delta / maxf(angle, 0.0001))).normalized()
			skeleton.set_bone_pose_rotation(bone, target)
			_presented_arm_rotations[bone] = target

## V1 `sync_shoulders`: leve protração da clavícula ao estender o braço. Com a
## clavícula da T-pose presa atrás do peito, as mangas eram puxadas para dentro.
func _protract_clavicle(side: String) -> void:
	if not _combat_bones.has(side + "Shoulder"): return
	var clavicle: int = _combat_bones[side + "Shoulder"]
	skeleton.set_bone_pose_rotation(clavicle, _combat_rests[clavicle].basis.get_rotation_quaternion())
	var clavicle_basis := skeleton.get_bone_global_pose(clavicle).basis
	_set_combat_bone_rotation(clavicle, Basis(Vector3.UP, 0.20 if side == "Right" else -0.20) * clavicle_basis)

func _blend_arm_bone(bone: int, clip: Quaternion, weight: float) -> void:
	var solved := skeleton.get_bone_pose_rotation(bone)
	if _arm_blends.has(bone):
		var previous: Array = _arm_blends[bone]
		if clip.dot(previous[0]) < 0: clip = -clip
		if solved.dot(previous[1]) < 0: solved = -solved
	elif clip.dot(solved) < 0:
		solved = -solved
	_arm_blends[bone] = [clip, solved]
	# Ao baixar a guarda, use o arco curto até o repouso. A continuidade de
	# sinal entre quadros pode escolher o arco longo entre estas duas poses.
	var blended := clip.slerp(solved, weight) if combat_weapon_id == "fists" else clip.slerpni(solved, weight)
	skeleton.set_bone_pose_rotation(bone, blended.normalized())

## Blend shapes do `dante.glb`: 0/1 = mão fechada no cabo (GripRight/GripLeft),
## 2/3 = punho cerrado (FistRight/FistLeft, soco e soqueira). Mão que segue o
## clipe de locomoção fica levemente curvada (0,18), como na V1.
func _set_combat_grips(right: bool, left: bool, right_fist := false, left_fist := false, right_relaxed := false, left_relaxed := false) -> void:
	if not is_instance_valid(_combat_skin): return
	var count := _combat_skin.get_blend_shape_count()
	if count >= 2:
		_combat_skin.set_blend_shape_value(0, move_toward(_combat_skin.get_blend_shape_value(0), 1.0 if right and not right_fist else (0.18 if right_relaxed else 0.0), _pose_delta * 14.0))
		_combat_skin.set_blend_shape_value(1, move_toward(_combat_skin.get_blend_shape_value(1), 1.0 if left and not left_fist else (0.18 if left_relaxed else 0.0), _pose_delta * 14.0))
	if count >= 4:
		_combat_skin.set_blend_shape_value(2, move_toward(_combat_skin.get_blend_shape_value(2), 1.0 if right_fist else 0.0, _pose_delta * 14.0))
		_combat_skin.set_blend_shape_value(3, move_toward(_combat_skin.get_blend_shape_value(3), 1.0 if left_fist else 0.0, _pose_delta * 14.0))
	if skeleton != null:
		for side in ["Right", "Left"]:
			if _combat_bones.has(side + "Hand"):
				skeleton.set_bone_pose_scale(_combat_bones[side + "Hand"], Vector3.ONE * 0.95)

## Two-bone IK adapted from the V1 Meshy rig. `target_local` and
## `palm_basis_local` use the Actor's facing space, with the muzzle along -Z.
## Mão aberta e fechada usam a mesma cadeia e o mesmo polo contínuo.
func _solve_combat_arm(side: String, target_local: Vector3, palm_basis_local: Basis, _gripping: bool, sign_side: float, _free_weight: float = 0.0) -> void:
	var upper: int = _combat_bones[side + "Arm"]
	var fore: int = _combat_bones[side + "ForeArm"]
	var hand: int = _combat_bones[side + "Hand"]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(visual.to_global(target_local))
	var palm_world_basis := visual.global_basis.orthonormalized() * palm_basis_local.orthonormalized()
	var model_basis := skeleton.global_basis.orthonormalized().inverse() * palm_world_basis
	var roll := 0.358 if side == "Right" else -0.392
	# Opening the fingers must not change the wrist solver or bone length.
	# Fists, reloads and grips all honor the authored palm orientation.
	var wrist_alignment := Basis(Vector3.RIGHT, -PI * 0.5)
	var hand_basis := model_basis * wrist_alignment * Basis(Vector3.UP, -roll)
	var palm_offset := Vector3(0, 0.065, 0)
	var wrist := target - hand_basis * palm_offset
	var a: float = _combat_rests[fore].origin.length()
	var b: float = _combat_rests[hand].origin.length()
	var axis := (wrist - shoulder).normalized()
	if axis.is_zero_approx(): return
	var distance := maxf(shoulder.distance_to(wrist), absf(a - b) + 0.001)
	var soft_start := a + b - 0.055
	if distance > soft_start:
		distance = soft_start + 0.050 * (1.0 - exp(-(distance - soft_start) / 0.050))
	wrist = shoulder + axis * distance
	# Cotovelo por fora e à frente da jaqueta (valores da V1), em vez de dobrar
	# pelas costelas quando as mãos se encontram à frente do peito.
	var long_weapon := bool(combat_weapon_pose.get("long_weapon", combat_weapon_id in ["smg", "shotgun", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "axe", "bat"]))
	var pole_world: Vector3 = visual.global_basis * Vector3(sign_side * (1.10 if long_weapon else 0.65), -1.5, -1.35 if long_weapon else -0.5)
	var pole := skeleton.global_basis.inverse() * pole_world
	var bend := (pole - axis * pole.dot(axis)).normalized()
	if _elbow_previous.has(side):
		var previous: Vector3 = _elbow_previous[side]
		previous = (previous - axis * previous.dot(axis)).normalized()
		if not previous.is_zero_approx() and not bend.is_zero_approx():
			var angle := atan2(axis.dot(previous.cross(bend)), previous.dot(bend))
			bend = Basis(axis, clampf(angle, -8.0 * _pose_delta, 8.0 * _pose_delta)) * previous
	_elbow_solved[side] = bend
	if bend.is_zero_approx(): bend = Vector3(sign_side, -0.4, -0.2).normalized()
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var elbow := shoulder + axis * along + bend * sqrt(maxf(0.0, a * a - along * along))
	# Build both segment frames from the elbow plane, not from the previous
	# clip's arbitrary axial roll. This avoids the shortest-arc singularity
	# when a punch or a reload crosses that clip's reference direction.
	var rest_upper := skeleton.get_bone_global_rest(upper)
	var rest_fore := skeleton.get_bone_global_rest(fore)
	var rest_hand := skeleton.get_bone_global_rest(hand)
	var rest_plane := (rest_fore.origin - rest_upper.origin).cross(rest_hand.origin - rest_fore.origin).normalized()
	if rest_plane.length_squared() < 0.1: rest_plane = Vector3.BACK
	var plane := bend.cross(axis).normalized()
	_orient_arm_segment(upper, fore, elbow - shoulder, plane, rest_plane)
	_orient_arm_segment(fore, hand, wrist - elbow, plane, rest_plane)
	var fore_pose := skeleton.get_bone_global_pose(fore)
	var axis_fore := (skeleton.get_bone_global_pose(hand).origin - fore_pose.origin).normalized()
	var current_normal := skeleton.get_bone_global_pose(hand).basis.x
	var desired_normal := hand_basis.x
	current_normal = (current_normal - axis_fore * current_normal.dot(axis_fore)).normalized()
	desired_normal = (desired_normal - axis_fore * desired_normal.dot(axis_fore)).normalized()
	if not current_normal.is_zero_approx() and not desired_normal.is_zero_approx():
		# A maior parte da rotação de pegada fica no pulso: rolar muito o
		# antebraço colapsa a manga na dobra interna do cotovelo.
		var twist := atan2(axis_fore.dot(current_normal.cross(desired_normal)), current_normal.dot(desired_normal))
		# clamp(atan2(...), -1.2, 1.2) jumped by 2.4 rad at the +/-PI
		# branch cut. A periodic bounded share has no discontinuity there;
		# the wrist still realizes the exact requested palm orientation.
		fore_pose.basis = Basis(axis_fore, 1.2 * sin(twist)) * fore_pose.basis
		_set_combat_bone_rotation(fore, fore_pose.basis)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	hand_pose.basis = hand_basis
	_set_combat_bone_rotation(hand, hand_pose.basis)

func _orient_arm_segment(bone: int, child: int, direction: Vector3, plane: Vector3, rest_plane: Vector3) -> void:
	var y := direction.normalized()
	var x := (plane - y * plane.dot(y)).normalized()
	if x.is_zero_approx() or y.is_zero_approx(): return
	var source_y := _combat_rests[child].origin.normalized()
	var source_x := skeleton.get_bone_global_rest(bone).basis.orthonormalized().transposed() * rest_plane
	source_x = (source_x - source_y * source_x.dot(source_y)).normalized()
	var source := Basis(source_x, source_y, source_x.cross(source_y)).orthonormalized()
	var target := Basis(x, y, x.cross(y)).orthonormalized()
	_set_combat_bone_rotation(bone, target * source.transposed())

func _point_combat_bone(bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var desired := (target - pose.origin).normalized()
	if current.is_zero_approx() or desired.is_zero_approx(): return
	pose.basis = Basis(Quaternion(current, desired)) * pose.basis
	_set_combat_bone_rotation(bone, pose.basis)

## IK changes orientation only. Decomposing a global Transform3D back into a
## local pose on each bilateral iteration feeds floating-point scale/shear
## back into the next solve. Animation rotation tracks do not reset that scale;
## over hundreds of frames it grows until the sleeves span the screen.
## Keep authored translations/scales and convert only orthonormal rotations.
func _set_combat_bone_rotation(bone: int, global_rotation: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := Basis.IDENTITY
	if parent >= 0:
		parent_rotation = skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var local_rotation := parent_rotation.transposed() * global_rotation.orthonormalized()
	skeleton.set_bone_pose_rotation(bone, local_rotation.get_rotation_quaternion().normalized())

func combat_palm_position(side: String) -> Vector3:
	if skeleton == null or not _combat_bones.has(side + "Hand"): return global_position
	var pose := skeleton.get_bone_global_pose(_combat_bones[side + "Hand"])
	return skeleton.to_global(pose * Vector3(0, 0.065, 0))

## Transformação final do prop baseada na palma efetivamente resolvida pelo IK.
## `grip` é o centro da empunhadura no espaço local do modelo da arma.
func combat_weapon_transform(grip: Vector3) -> Transform3D:
	if combat_weapon_pose.is_empty() or not is_instance_valid(visual):
		return Transform3D(global_basis, global_position)
	var local_basis: Basis = combat_weapon_pose.basis
	var weapon_basis := (visual.global_basis * local_basis).orthonormalized()
	# Na V1 a arma não escalava junto com o Dante; `weapon_scale` repõe essa proporção.
	var weapon_scale := float(combat_weapon_pose.get("weapon_scale", 1.0))
	return Transform3D(weapon_basis.scaled_local(Vector3.ONE * weapon_scale), combat_palm_position("Right") - weapon_basis * grip * weapon_scale)

## Palma esquerda resolvida, com a orientação pedida pela pose (segunda soqueira).
func combat_left_palm_transform() -> Transform3D:
	var local_basis: Basis = combat_weapon_pose.get("left_basis", Basis.IDENTITY)
	var weapon_scale := float(combat_weapon_pose.get("weapon_scale", 1.0))
	var palm_basis := (visual.global_basis * local_basis).orthonormalized()
	return Transform3D(palm_basis.scaled_local(Vector3.ONE * weapon_scale), combat_palm_position("Left"))

## Subida do quadril no passo, em metros do Actor — o que a V1 lia de
## `torso_node.position` para acompanhar o carregar da arma com o corpo.
func combat_rig_info() -> Dictionary:
	if skeleton == null or hips < 0: return {}
	return {"body_bob": (skeleton.get_bone_pose_position(hips).y - hip_rest.y) * skeleton.global_basis.get_scale().y / maxf(visual.global_basis.get_scale().y, 0.001)}

func teleport(point: Vector3) -> void:
	global_position = point
	last_position = point
	velocity = Vector3.ZERO
	_feet_initialized = false
	_turn_time = -1.0
	_turn_feet.clear()
	reset_physics_interpolation()

func set_outfit(id: String) -> bool:
	if not is_player or not OUTFIT_APPEARANCE.OUTFITS.has(id): return false
	if not is_instance_valid(skeleton):
		outfit_id = id
		return true
	var skin_mesh := visual.find_child("Mesh0", true, false) as MeshInstance3D
	if skin_mesh == null: return false
	outfit_material = OUTFIT_APPEARANCE.apply(skin_mesh, skeleton, id)
	outfit_id = id
	return outfit_material != null

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or amount <= 0: return
	# Alvo marcado (ele ou um ancestral) não sofre dano por nenhum caminho direto.
	if PROTECTION.is_protected(self): return
	if is_player:
		var gameplay = get_parent().get("gameplay")
		if gameplay: gameplay.damage_player(amount)
		return
	var vehicle_source: bool = is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source()
	health = maxf(0,health-amount)
	if health <= 0:
		dead = true
		if has_meta("v2_burning"):
			preload("res://gameplay/BurningActor.gd").char_body(self)
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		var impact_dir: Vector3 = (global_position - (source as Node3D).global_position).normalized() if source is Node3D else Vector3.ZERO
		_fall_over(impact_dir)
	else:
		_flinch()
	var gameplay = get_parent().get("gameplay")
	# A autoria continua no veículo real. A denúncia só é encaminhada depois de
	# `dead` refletir o resultado deste impacto, inclusive no golpe fatal.
	if vehicle_source:
		if gameplay and gameplay.has_method("report_vehicle_assault"): gameplay.report_vehicle_assault(self,source)
		elif gameplay: gameplay.register_crime(25,global_position)
	if gameplay and gameplay.get("emergency") != null: gameplay.emergency.report_injury(self,dead)

## Queda com articulação de membros, rotação direcional e quique suave no solo (V1).
func _fall_over(impact := Vector3.ZERO) -> void:
	if not is_instance_valid(visual): return
	if _reaction_tween != null: _reaction_tween.kill()
	preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self, visual, impact)

func on_player_death() -> void:
	if dead: return
	dead = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	if animation != null and animation.has_animation("dying_backwards"):
		if _reaction_tween != null: _reaction_tween.kill()
		var from_pose := _capture_pose()
		clear_combat_weapon_pose()
		visual.rotation.x = 0.0
		_reaction_tween = create_tween()
		_reaction_tween.tween_method(func(time: float):
			_pose_clip("dying_backwards", time)
			if time < 0.20: _apply_blend(from_pose, _capture_pose(), smoothstep(0, 0.20, time))
			var hip := skeleton.get_bone_pose_position(hips)
			hip.x = hip_rest.x
			hip.z = hip_rest.z
			skeleton.set_bone_pose_position(hips, hip)
		, 0.0, animation.get_animation("dying_backwards").length, animation.get_animation("dying_backwards").length)
	else:
		_fall_over(Vector3.BACK)

func present_hit() -> void:
	if is_player and not dead: _hit_age = 0.0

func respawn_player() -> void:
	if not is_player: return
	dead = false
	health = 100.0
	if _reaction_tween != null: _reaction_tween.kill()
	visual.position = Vector3.ZERO
	visual.rotation.x = 0.0
	visual.rotation.z = 0.0
	if animation != null and not _idle_pose.is_empty():
		animation.play("Walking")
		_apply_pose(_idle_pose)
	clear_combat_weapon_pose()
	_hit_age = 1.0
	_presented_arm_rotations.clear()
	_arm_blends.clear()
	_feet_initialized = false
	_turn_feet.clear()
	_locomotion_weight = 0.0
	_run_weight = 0.0
	_directional_weight = 0.0
	last_position = global_position
	velocity = Vector3.ZERO

## Reação curta ao ferimento (o civil se curva para trás e volta): só apresentação, o dano já foi aplicado acima.
func _flinch() -> void:
	if not is_instance_valid(visual) or is_player: return
	if _reaction_tween != null: _reaction_tween.kill()
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(visual, "rotation:x", -FLINCH_ANGLE, 0.06)
	_reaction_tween.tween_property(visual, "rotation:x", 0.0, 0.14)

func recover_from_injury() -> void:
	if dead: return
	health = maxf(health,60)
