extends CharacterBody3D

const DANTE := preload("res://assets/dante.glb")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const OUTFIT_APPEARANCE := preload("res://assets/outfits/MeshyDanteAppearance.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
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
## `combat_facing` ativo; escolhe a locomoção armada (`_armed_clip`).
var combat_stance := ""
## Alvos de empunhadura calculados por Gameplay/WeaponRigPose. São apresentação
## apenas: o dano continua resolvido antes, em Gameplay.fire_at.
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
var _armed_phase := 0.0
## Pesos perceptivos equivalentes aos do Dante V1: a fase só avança com
## deslocamento real, enquanto o corpo entra/sai da passada suavemente.
var _locomotion_weight := 0.0
var _run_weight := 0.0
var _idle_pose: Array = []
var _combat_bones: Dictionary = {}
var _combat_rests: Array[Transform3D] = []
var _combat_skin: MeshInstance3D
## Duração da mistura de poses ao entrar e sair do clipe de golpe (não calibrada).
const COMBAT_BLEND := 0.08
const LOCOMOTION_BLEND_RATE := 7.0
const RUN_BLEND_RATE := 4.5
const MOVING_SPEED_EPSILON := 0.12
const WALK_START := 0.067
## Locomoção armada, medida nas chaves do `dante.glb` (esqueleto Y para cima, rosto em +Z; esquerda anatômica = +X
## pelos pés `LeftFoot`/`RightFoot`). `stride` = quanto o quadril anda em UM ciclo do clipe (o clipe tem movimento de raiz;
## `_physics_process` o zera, então o ciclo é travado na distância percorrida, como a caminhada). `speed` = stride ÷ duração.
##   Walk_Backward_with_Gun     quadril −0,91 m em 1,07 s (para trás)
##   Walk_Backward_with_Grenade quadril −1,06 m em 1,30 s (para trás)
##   Walk_Left_with_Gun         quadril −0,89 m em 1,30 s no eixo X: para o lado DIREITO do personagem (o pé direito
##                              lidera). O nome do clipe diz "Left"; a medição diz direita. Usado só como passo à direita.
## Não há clipe de passo à esquerda nem de frente armado: nesses casos (e sem espelhar o rig) fica a caminhada comum.
const ARMED_CLIPS := {
	"back_gun": {"clip": "Walk_Backward_with_Gun", "stride": 0.91, "speed": 0.85},
	"back_grenade": {"clip": "Walk_Backward_with_Grenade", "stride": 1.06, "speed": 0.82},
	"side_gun": {"clip": "Walk_Left_with_Gun", "stride": 0.89, "speed": 0.68},
}
## Só usa o clipe armado se a velocidade real ficar até este múltiplo da velocidade nativa do clipe. A caminhada comum
## já roda ~2× (1,8 m por ciclo de 1,03 s contra 3,5 m/s); acima disso o passo vira borrão. A 3,5 m/s o corte recusa
## os três clipes (nativos ≤ 0,85 m/s); só passam com inclinação parcial do direcional analógico.
const ARMED_MAX_RATE := 2.0

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
		var offset := route[waypoint] - global_position
		offset.y = 0
		if offset.length() < 0.4:
			waypoint = (waypoint + 1) % route.size()
			offset = route[waypoint] - global_position
			offset.y = 0
		direction = offset.normalized()
	if is_player and not input_locked and is_instance_valid(ski_controller) and ski_controller.skiing:
		var motion: Vector3 = ski_controller.motion(delta,direction)
		direction = motion.normalized()
		target_speed = motion.length()
	if input_locked: direction = Vector3.ZERO
	velocity.x = direction.x * target_speed
	velocity.z = direction.z * target_speed
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	var displacement := global_position - last_position
	displacement.y = 0
	travelled += displacement.length()
	var actual_speed := displacement.length() / maxf(delta, 0.001)
	last_position = global_position
	if direction.length_squared() > 0.01:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-14.0 * delta))
	# Mirando/atacando, o corpo segue o rumo do disparo, não o do movimento.
	if is_player and not is_nan(combat_facing): visual.rotation.y = combat_facing
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
		if is_player: _apply_combat_weapon_pose()
	else:
		if visual.get_child(0).get("walking") != null: visual.get_child(0).walking = actual_speed > 0.1

## Caminhada/corrida comuns (fase travada na distância) ou, se couber, a
## locomoção armada. A entrada/saída usa o deslocamento REAL: soltar o comando,
## bater num sólido ou encerrar um deslocamento automático converge para a
## mesma postura parada em vez de congelar o último passo.
func _pose_locomotion(direction: Vector3, target_speed: float, displacement: Vector3, actual_speed: float, delta: float = 1.0 / 60.0) -> void:
	var moving := actual_speed > MOVING_SPEED_EPSILON
	_locomotion_weight = move_toward(_locomotion_weight, 1.0 if moving else 0.0, delta * LOCOMOTION_BLEND_RATE)
	_run_weight = move_toward(_run_weight, 1.0 if moving and target_speed > 4.0 else 0.0, delta * RUN_BLEND_RATE)
	if _locomotion_weight <= 0.0 and not _idle_pose.is_empty():
		# Mantém um nome produtivo no AnimationPlayer para consumidores existentes,
		# mas aplica a postura simétrica cacheada; `restpose` é uma T-pose.
		animation.play("Walking")
		_apply_pose(_idle_pose)
		return
	var armed := _armed_clip(direction, actual_speed)
	if not armed.is_empty():
		var armed_animation := animation.get_animation(armed.clip)
		_armed_phase = fposmod(_armed_phase + displacement.length() / float(armed.stride), 1.0)
		animation.play(armed.clip)
		animation.seek(_armed_phase * armed_animation.length, true)
	else:
		# Andando de costas em relação à mira, sem clipe armado que caiba na
		# velocidade: a fase comum roda ao contrário. Caminhada e corrida usam a
		# mesma fase e se misturam, evitando um corte ao apertar/soltar corrida.
		var stride := lerpf(1.8, 3.4, _run_weight)
		var step := displacement.length() / stride
		phase = fposmod(phase - step if _moving_backward(direction) else phase + step, 1.0)
		_pose_cycle("Walking", phase, WALK_START)
		if _run_weight > 0.0:
			var walk_pose := _capture_pose()
			_pose_cycle("Running", phase, 0.0)
			if _run_weight < 1.0: _apply_blend(walk_pose, _capture_pose(), _run_weight)
	if _locomotion_weight < 1.0 and not _idle_pose.is_empty():
		var moving_pose := _capture_pose()
		_apply_blend(_idle_pose, moving_pose, _locomotion_weight)

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
	_idle_pose = _capture_pose()

func _pose_cycle(clip: String, normalized_phase: float, start: float) -> void:
	var anim := animation.get_animation(clip)
	animation.play(clip)
	animation.seek(start + fposmod(normalized_phase, 1.0) * maxf(0.01, anim.length - start), true)

func _apply_pose(pose: Array) -> void:
	if not is_instance_valid(skeleton): return
	for bone in mini(pose.size(), skeleton.get_bone_count()):
		skeleton.set_bone_pose_position(bone, pose[bone][0] as Vector3)
		skeleton.set_bone_pose_rotation(bone, pose[bone][1] as Quaternion)

func _pose_clip(clip: String, time: float) -> void:
	if not animation.has_animation(clip): return
	animation.play(clip)
	animation.seek(clampf(time, 0.0, animation.get_animation(clip).length), true)

## Locomoção armada pela direção do movimento RELATIVA À MIRA: para trás (arma de fogo ou granada) ou para a direita
## (arma de fogo). Devolve {} (caminhada comum) se não está mirando, parado, fora dos cones de ±45° em torno de trás/direita,
## sem o clipe no rig ou com velocidade acima de ARMED_MAX_RATE × a nativa do clipe.
func _armed_clip(direction: Vector3, actual_speed: float) -> Dictionary:
	if not is_player or is_nan(combat_facing) or combat_stance == "" or actual_speed < 0.3: return {}
	var move := Vector3(direction.x, 0.0, direction.z)
	if move.length_squared() < 0.01: return {}
	move = move.normalized()
	var forward := Vector3(-sin(combat_facing), 0.0, -cos(combat_facing))
	var right := Vector3(cos(combat_facing), 0.0, -sin(combat_facing))
	var key := ""
	if move.dot(forward) <= -0.7: key = "back_" + combat_stance
	elif move.dot(right) >= 0.7 and combat_stance == "gun": key = "side_gun"
	if not ARMED_CLIPS.has(key): return {}
	var spec: Dictionary = ARMED_CLIPS[key]
	if not animation.has_animation(spec.clip) or actual_speed / float(spec.speed) > ARMED_MAX_RATE: return {}
	return spec

## Movimento em cone de ±45° para trás do rumo de mira (só com o corpo forçado a mirar).
func _moving_backward(direction: Vector3) -> bool:
	if not is_player or is_nan(combat_facing): return false
	var move := Vector3(direction.x, 0.0, direction.z)
	if move.length_squared() < 0.01: return false
	return move.normalized().dot(Vector3(-sin(combat_facing), 0.0, -cos(combat_facing))) <= -0.7

func _capture_pose() -> Array:
	var pose: Array = []
	for bone in skeleton.get_bone_count(): pose.append([skeleton.get_bone_pose_position(bone), skeleton.get_bone_pose_rotation(bone)])
	return pose

func _apply_blend(from_pose: Array, to_pose: Array, weight: float) -> void:
	for bone in from_pose.size():
		skeleton.set_bone_pose_position(bone, (from_pose[bone][0] as Vector3).lerp(to_pose[bone][0], weight))
		skeleton.set_bone_pose_rotation(bone, (from_pose[bone][1] as Quaternion).slerp(to_pose[bone][1], weight))

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
	if skeleton == null or combat_weapon_pose.is_empty():
		_set_combat_grips(false, false)
		return
	for required in ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]:
		if not _combat_bones.has(required): return
	var torso_yaw := float(combat_weapon_pose.get("torso_yaw", 0.0))
	if absf(torso_yaw) > 0.001 and _combat_bones.has("Spine"):
		var spine: int = _combat_bones.Spine
		var spine_pose := skeleton.get_bone_global_pose(spine)
		spine_pose.basis = Basis(Vector3.UP, torso_yaw) * spine_pose.basis
		skeleton.set_bone_global_pose(spine, spine_pose)
	var right_grip := bool(combat_weapon_pose.get("right_grip", false))
	var left_grip := bool(combat_weapon_pose.get("left_grip", false))
	var right_shift_world := Vector3.ZERO
	var right_target: Vector3 = combat_weapon_pose.right
	var lock_support := left_grip and bool(combat_weapon_pose.get("support_locked", false))
	if (right_grip or combat_weapon_id != "fists") and lock_support:
		# Mesma restrição bilateral do V1: projeta o conjunto até cabo e apoio
		# caberem simultaneamente no alcance dos dois braços. Sem isso a arma
		# fica na mão direita, mas o guarda-mão flutua 8–11 cm da esquerda.
		var relative_world: Vector3 = visual.global_basis * (combat_weapon_pose.left - combat_weapon_pose.right)
		for iteration in 8:
			_solve_combat_arm("Right", right_target, combat_weapon_pose.basis, right_grip, 1.0)
			var desired_left_world: Vector3 = combat_palm_position("Right") + relative_world
			_solve_combat_arm("Left", visual.to_local(desired_left_world), combat_weapon_pose.left_basis, true, -1.0)
			var support_error: Vector3 = combat_palm_position("Left") - desired_left_world
			if support_error.length() < 0.004: break
			right_target = visual.to_local(visual.to_global(right_target) + support_error * 0.72)
	if right_grip or combat_weapon_id != "fists":
		_solve_combat_arm("Right", right_target, combat_weapon_pose.basis, right_grip, 1.0)
		right_shift_world = combat_palm_position("Right") - visual.to_global(combat_weapon_pose.right)
	if left_grip:
		var shifted_left: Vector3
		if lock_support:
			var realised_delta: Vector3 = visual.global_basis * (combat_weapon_pose.left - combat_weapon_pose.right)
			shifted_left = visual.to_local(combat_palm_position("Right") + realised_delta)
		else:
			shifted_left = visual.to_local(visual.to_global(combat_weapon_pose.left) + right_shift_world)
		_solve_combat_arm("Left", shifted_left, combat_weapon_pose.left_basis, true, -1.0)
	_set_combat_grips(right_grip, left_grip)
	# Actor é processado antes de Gameplay na árvore produtiva. Atualizar o
	# mount aqui elimina o atraso visual de um quadro entre esqueleto e arma.
	if is_instance_valid(combat_weapon_mount) and right_grip:
		combat_weapon_mount.global_transform = combat_weapon_transform(combat_weapon_grip)

func _set_combat_grips(right: bool, left: bool) -> void:
	if not is_instance_valid(_combat_skin): return
	if _combat_skin.get_blend_shape_count() >= 2:
		_combat_skin.set_blend_shape_value(0, 1.0 if right else 0.0)
		_combat_skin.set_blend_shape_value(1, 1.0 if left else 0.0)
	if skeleton != null:
		for side in ["Right", "Left"]:
			if _combat_bones.has(side + "Hand"):
				skeleton.set_bone_pose_scale(_combat_bones[side + "Hand"], Vector3.ONE * 0.95)

## Two-bone IK adapted from the V1 Meshy rig. `target_local` and
## `palm_basis_local` use the Actor's facing space, with the muzzle along -Z.
func _solve_combat_arm(side: String, target_local: Vector3, palm_basis_local: Basis, gripping: bool, sign_side: float) -> void:
	var upper: int = _combat_bones[side + "Arm"]
	var fore: int = _combat_bones[side + "ForeArm"]
	var hand: int = _combat_bones[side + "Hand"]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(visual.to_global(target_local))
	var palm_world_basis := visual.global_basis.orthonormalized() * palm_basis_local.orthonormalized()
	var model_basis := skeleton.global_basis.orthonormalized().inverse() * palm_world_basis
	var roll := 0.358 if side == "Right" else -0.392
	var wrist_alignment := Basis(Vector3.RIGHT, -PI * 0.5 if gripping else PI)
	var hand_basis := model_basis * wrist_alignment * Basis(Vector3.UP, -roll)
	var palm_offset := Vector3(0, 0.065, 0)
	var wrist := target - hand_basis * palm_offset
	var a: float = _combat_rests[fore].origin.length()
	var b: float = _combat_rests[hand].origin.length()
	if not gripping:
		wrist = target
		b = (_combat_rests[hand].origin + _combat_rests[hand].basis * palm_offset).length()
	var axis := (wrist - shoulder).normalized()
	if axis.is_zero_approx(): return
	var distance := clampf(shoulder.distance_to(wrist), absf(a - b) + 0.001, a + b - 0.001)
	var long_weapon := combat_weapon_id in ["smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "axe", "bat"]
	var pole_world: Vector3 = visual.global_basis * Vector3(sign_side * (1.05 if long_weapon else 0.66), -1.5, -1.25 if long_weapon else -0.48)
	var pole := skeleton.global_basis.inverse() * pole_world
	var bend := (pole - axis * pole.dot(axis)).normalized()
	if bend.is_zero_approx(): bend = Vector3(sign_side, -0.4, -0.2).normalized()
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var elbow := shoulder + axis * along + bend * sqrt(maxf(0.0, a * a - along * along))
	_point_combat_bone(upper, fore, elbow)
	_point_combat_bone(fore, hand, wrist)
	var fore_pose := skeleton.get_bone_global_pose(fore)
	var axis_fore := (skeleton.get_bone_global_pose(hand).origin - fore_pose.origin).normalized()
	var current_normal := skeleton.get_bone_global_pose(hand).basis.x
	var desired_normal := hand_basis.x
	current_normal = (current_normal - axis_fore * current_normal.dot(axis_fore)).normalized()
	desired_normal = (desired_normal - axis_fore * desired_normal.dot(axis_fore)).normalized()
	if not current_normal.is_zero_approx() and not desired_normal.is_zero_approx():
		var twist := atan2(axis_fore.dot(current_normal.cross(desired_normal)), current_normal.dot(desired_normal))
		fore_pose.basis = Basis(axis_fore, clampf(twist, -1.2, 1.2)) * fore_pose.basis
		skeleton.set_bone_global_pose(fore, fore_pose)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	hand_pose.basis = hand_basis
	skeleton.set_bone_global_pose(hand, hand_pose)

func _point_combat_bone(bone: int, child: int, target: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var desired := (target - pose.origin).normalized()
	if current.is_zero_approx() or desired.is_zero_approx(): return
	pose.basis = Basis(Quaternion(current, desired)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)

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
	return Transform3D(weapon_basis, combat_palm_position("Right") - weapon_basis * grip)

func teleport(point: Vector3) -> void:
	global_position = point
	last_position = point
	velocity = Vector3.ZERO
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
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		_fall_over()
	else:
		_flinch()
	var gameplay = get_parent().get("gameplay")
	# A autoria continua no veículo real. A denúncia só é encaminhada depois de
	# `dead` refletir o resultado deste impacto, inclusive no golpe fatal.
	if vehicle_source:
		if gameplay and gameplay.has_method("report_vehicle_assault"): gameplay.report_vehicle_assault(self,source)
		elif gameplay: gameplay.register_crime(25,global_position)
	if gameplay and gameplay.get("emergency") != null: gameplay.emergency.report_injury(self,dead)

## Queda em 0,22 s (antes o corpo virava de uma vez, num quadro). O estado final é o mesmo de antes: deitado de lado, 0,3 m.
func _fall_over() -> void:
	if not is_instance_valid(visual): return
	if _reaction_tween != null: _reaction_tween.kill()
	visual.rotation.x = 0.0
	_reaction_tween = create_tween()
	_reaction_tween.set_parallel(true)
	_reaction_tween.tween_property(visual, "rotation:z", PI / 2.0, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_reaction_tween.tween_property(visual, "position:y", 0.3, FALL_TIME)

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
