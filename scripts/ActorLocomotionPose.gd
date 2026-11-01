extends RefCounted
## Pose de locomoção do Actor (jogador e Dante dos atores de cena): caminhada/corrida com a fase travada
## na distância, locomoção armada direcional e da katana, guarda parada, pose parada calculada, giro no
## lugar com os pés plantados, IK de perna, clipe avulso (escada, morte) e ciclo com emenda. Separado em
## 01/11 (Onda 3 de docs/plano-divisao-arquivos-grandes-20261101.md) só para o Actor.gd caber na leitura.
## Não tem estado próprio: pesos de passada (_locomotion_weight, _run_weight, _directional_weight), fase,
## pose parada, pés de giro e caches de clipe continuam no Actor, lidos por testes, BlitzBrother, Ferry e
## KatanaMoveset; o Actor mantém cada função antiga como delegação de uma linha com a mesma assinatura.
## `g` fica como CharacterBody3D, e não como o script do Actor, para não criar preload cíclico. Pose
## capturada, mistura e rotação de osso continuam chamadas por `g.` (são do Actor e de ActorCombatPose);
## nenhuma subclasse sobrescreve funções de pose (conferido em 01/11), então as deste arquivo se chamam
## direto, sem o despacho dinâmico.
## Roda por quadro e por osso (_apply_pose, _mirror_current_pose, _pose_cycle): esqueleto, visual,
## AnimationPlayer e tabelas de osso são cópias tipadas, não `g.` dinâmico (ver sync_refs).

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host
	sync_refs()

## Cópias tipadas de referências do Actor, atualizadas pelo dono (`_sync_pose_refs`) em toda atribuição.
var visual: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var _combat_bones: Dictionary = {}
var _combat_rests: Array[Transform3D] = []

func sync_refs() -> void:
	visual = g.visual
	animation = g.animation
	skeleton = g.skeleton
	_combat_bones = g._combat_bones
	_combat_rests = g._combat_rests

## Caminhada/corrida comuns (fase travada na distância) ou, se couber, a
## locomoção armada. A entrada/saída usa o deslocamento REAL: soltar o comando,
## bater num sólido ou encerrar um deslocamento automático converge para a
## mesma postura parada em vez de congelar o último passo.
func _pose_locomotion(direction: Vector3, _target_speed: float, displacement: Vector3, actual_speed: float, delta: float = 1.0 / 60.0) -> void:
	g._pose_delta = delta
	g._idle_clock += delta
	var moving: bool = actual_speed > g.MOVING_SPEED_EPSILON
	var directional: bool = g.is_player and not is_nan(g.combat_facing)
	var melee_directional: bool = directional and g.combat_stance == "melee"
	g._locomotion_weight = move_toward(g._locomotion_weight, 1.0 if moving else 0.0, delta * g.LOCOMOTION_BLEND_RATE)
	g._run_weight = move_toward(g._run_weight, smoothstep(3.8, 6.0, actual_speed) if moving and (not directional or melee_directional) else 0.0, delta * g.RUN_BLEND_RATE)
	g._directional_weight = move_toward(g._directional_weight, 1.0 if directional else 0.0, delta * 8.0)
	var sword: bool = g.sword_locomotion and has_sword_locomotion()
	if g._locomotion_weight <= 0.0 and sword:
		_pose_sword_idle()
		# A guarda gira inteira: o passo de virar planta os pés da postura comum, não os da guarda larga.
		_pose_turn(delta, true)
		return
	if g._locomotion_weight <= 0.0 and not g._idle_pose.is_empty():
		# Mantém um nome produtivo no AnimationPlayer para consumidores existentes,
		# mas aplica a postura simétrica cacheada; `restpose` é uma T-pose.
		animation.play("Walking")
		_apply_pose(g._idle_pose)
		_apply_idle_breath()
		_pose_turn(delta, false)
		return
	var local_move := visual.global_basis.inverse() * (displacement.normalized() if moving else direction)
	g._gait_direction = g._gait_direction.move_toward(Vector2(local_move.x, -local_move.z), delta * 7.0)
	var lateral := absf(g._gait_direction.x)
	var backward := maxf(0, -g._gait_direction.y)
	var walk_stride: float = g.SWORD_WALK_STRIDE if sword else 1.8
	var directional_stride := lerpf(walk_stride, 1.06 if g.combat_stance == "grenade" else 0.91, clampf(backward, 0, 1))
	directional_stride = lerpf(directional_stride, 0.89, clampf(lateral, 0, 1))
	if melee_directional:
		# O movimento de corpo a corpo para frente agora pode correr de verdade. Mantém a passada
		# escrita de lado/para trás onde esses clipes assumem em vez de acelerar uma caminhada para frente.
		var forward_share := (1.0 - clampf(backward, 0.0, 1.0)) * (1.0 - clampf(lateral, 0.0, 1.0))
		directional_stride = lerpf(directional_stride, g.SWORD_RUN_STRIDE if sword else 3.4, g._run_weight * forward_share)
	var stride := lerpf(lerpf(walk_stride, g.SWORD_RUN_STRIDE if sword else 3.4, g._run_weight), directional_stride, g._directional_weight)
	g.phase = fposmod(g.phase + displacement.length() / stride, 1.0)
	_pose_cycle(g.SWORD_WALK % g.sword_clip_set if sword else "Walking", g.phase, 0.0 if sword else g.WALK_START)
	if g._run_weight > 0.0:
		var walk_pose: Array = g._capture_pose()
		_pose_cycle(g.SWORD_RUN % g.sword_clip_set if sword else "Running", g.phase, 0.0)
		if g._run_weight < 1.0: g._apply_blend(walk_pose, g._capture_pose(), g._run_weight)
	if g._directional_weight > 0.0:
		# Os clipes "with_Gun" seguram um fuzil imaginário com os dois braços erguidos.
		# O braço que a arma não resolve (granada, taco, machado, faca, a esquerda da
		# pistola baixa) herdava isso e ficava erguido junto do rosto andando de lado ou
		# para trás: os braços ficam com a passada comum.
		var free_arms := {}
		for bone_name in g.FREE_ARM_BONES:
			var bone: int = _combat_bones.get(bone_name, -1)
			if bone >= 0: free_arms[bone] = skeleton.get_bone_pose_rotation(bone)
		# Só guardar a pose anterior quando ela realmente entra na mistura.
		# Recuo/lateral puros evitam quatro cópias do esqueleto por quadro.
		var ordinary: Array = g._capture_pose() if g._directional_weight < 1.0 else []
		if backward > 0.001:
			var longitudinal: Array = g._capture_pose() if backward < 1.0 else []
			_pose_cycle("Walk_Backward_with_Gun" if g.combat_stance != "grenade" else "Walk_Backward_with_Grenade", g.phase, 0.0)
			if backward < 1.0: g._apply_blend(longitudinal, g._capture_pose(), clampf(backward, 0, 1))
		if lateral > 0.001:
			var longitudinal: Array = g._capture_pose() if lateral < 1.0 else []
			_pose_cycle("Walk_Left_with_Gun", g.phase, 0.0)
			if g._gait_direction.x < 0.0: _mirror_current_pose()
			if lateral < 1.0: g._apply_blend(longitudinal, g._capture_pose(), clampf(lateral, 0, 1))
		if g._directional_weight < 1.0: g._apply_blend(ordinary, g._capture_pose(), g._directional_weight)
		for bone in free_arms: skeleton.set_bone_pose_rotation(bone, free_arms[bone])
	if g._locomotion_weight < 1.0 and sword:
		var moving_pose: Array = g._capture_pose()
		_pose_sword_idle()
		g._apply_blend(g._capture_pose(), moving_pose, g._locomotion_weight)
	elif g._locomotion_weight < 1.0 and not g._idle_pose.is_empty():
		var moving_pose: Array = g._capture_pose()
		g._apply_blend(g._idle_pose, moving_pose, g._locomotion_weight)
	var hip := skeleton.get_bone_pose_position(g.hips)
	hip.x = g.hip_rest.x
	hip.z = g.hip_rest.z
	skeleton.set_bone_pose_position(g.hips, hip)
	_pose_turn(delta, moving)

func has_sword_locomotion() -> bool:
	return animation != null and animation.has_animation(g.SWORD_IDLE % g.sword_clip_set) and animation.has_animation(g.SWORD_WALK % g.sword_clip_set) and animation.has_animation(g.SWORD_RUN % g.sword_clip_set)

## Guarda parada da katana em laço, no relógio do parado (sem a respiração procedural: o clipe tem a sua).
func _pose_sword_idle() -> void:
	var clip: String = g.SHIELD_BLOCK_IDLE if g.sword_block and animation.has_animation(g.SHIELD_BLOCK_IDLE) else g.SWORD_IDLE % g.sword_clip_set
	_pose_cycle(clip, fposmod(g._idle_clock / animation.get_animation(clip).length, 1.0), 0.0)

## A animação importada não possui Idle: `restpose` é a T-pose vista no
## modelo. A média de duas fases opostas de Walking cancela a passada e produz
## uma base ereta/simétrica. É calculada uma vez; não adiciona avaliação de
## animação ao custo do repouso.
func _build_idle_pose() -> void:
	if not is_instance_valid(skeleton) or not animation.has_animation("Walking"): return
	_pose_cycle("Walking", 0.0, g.WALK_START)
	var first: Array = g._capture_pose()
	_pose_cycle("Walking", 0.5, g.WALK_START)
	g._apply_blend(first, g._capture_pose(), 0.5)
	if g.hips >= 0:
		var hip_position := skeleton.get_bone_pose_position(g.hips)
		hip_position.x = g.hip_rest.x
		hip_position.y = g.hip_rest.y
		hip_position.z = g.hip_rest.z
		skeleton.set_bone_pose_position(g.hips, hip_position)
	for side in ["Left", "Right"]:
		var foot: int = _combat_bones[side + "Foot"]
		var foot_rest := skeleton.get_bone_global_rest(foot)
		# Os pés mesclados da caminhada ainda apontam para baixo: a ponta pode tocar o chão
		# enquanto o calcanhar flutua ~10 cm. Monta um pé plano apoiado uma vez, antes
		# de guardar os alvos de parado e de giro, sem mudar os clipes em movimento.
		# O calcanhar também segue os pesos de pele da canela. Este pequeno pitch mantém
		# a sola nivelada depois que a postura parada mais aberta dobra os joelhos.
		g._set_combat_bone_rotation(foot, Basis(Vector3.RIGHT, deg_to_rad(-1.0)) * foot_rest.basis)
		var toe: int = _combat_bones[side + "ToeBase"]
		skeleton.set_bone_pose(toe, skeleton.get_bone_rest(toe))
		var point := visual.to_local(skeleton.to_global(foot_rest.origin))
		# A base da cápsula fica .01 acima da origem do Actor; compensa os últimos
		# 3 mm de elevação da sola vindos dos pesos da canela, com ponta e calcanhar livres.
		point.y += 0.007
		point.x = -0.12 if side == "Left" else 0.12
		point.z = -0.025 if side == "Left" else 0.025
		_solve_leg(side, visual.to_global(point))
	g._idle_pose = g._capture_pose()
	for side in ["Left", "Right"]:
		var foot: int = _combat_bones[side + "Foot"]
		g._idle_feet[side] = visual.to_local(skeleton.to_global(skeleton.get_bone_global_pose(foot).origin))

func _pose_cycle(clip: String, normalized_phase: float, start: float) -> void:
	var anim := animation.get_animation(clip)
	animation.play(clip)
	if not g._cycle_starts.has(clip):
		animation.seek(start, true)
		g._cycle_starts[clip] = g._capture_pose()
	var p := fposmod(normalized_phase, 1.0)
	animation.seek(start + p * maxf(0.01, anim.length - start), true)
	if p > 0.90: g._apply_blend(g._capture_pose(), g._cycle_starts[clip], smoothstep(0.90, 1.0, p))

func _mirror_current_pose() -> void:
	var original: Array = g._capture_pose()
	for bone in original.size():
		var entry_name := skeleton.get_bone_name(bone)
		var other := entry_name.replace("Left", "Right") if entry_name.begins_with("Left") else entry_name.replace("Right", "Left")
		var source: int = _combat_bones.get(other, bone)
		var q: Quaternion = original[source][1]
		var rest := _combat_rests[source].basis.get_rotation_quaternion()
		var mirrored := Quaternion(q.x, -q.y, -q.z, q.w)
		var reflected_rest := Quaternion(rest.x, -rest.y, -rest.z, rest.w)
		skeleton.set_bone_pose_rotation(bone, (_combat_rests[bone].basis.get_rotation_quaternion() * reflected_rest.inverse() * mirrored).normalized())

func _apply_idle_breath() -> void:
	var chest: int = _combat_bones.get("Spine02", -1)
	if chest >= 0:
		var breath := sin(g._idle_clock * 1.65) * 0.009
		skeleton.set_bone_pose_rotation(chest, skeleton.get_bone_pose_rotation(chest) * Quaternion(Vector3.RIGHT, breath))

func _pose_turn(delta: float, moving: bool) -> void:
	if g._idle_feet.is_empty(): return
	if not g._feet_initialized or moving:
		g._feet_yaw = visual.rotation.y
		g._feet_initialized = true
		g._turn_time = 1.0
		g._turn_feet.clear()
		return
	var difference := wrapf(visual.rotation.y - g._feet_yaw, -PI, PI)
	if g._turn_time >= 1.0 and absf(difference) > 0.20:
		g._turn_from = g._feet_yaw
		g._turn_to = g._feet_yaw + clampf(difference, -PI * 0.5, PI * 0.5)
		g._turn_time = 0.0
		for side in ["Left", "Right"]:
			g._turn_feet[side] = g.global_transform * (Basis(Vector3.UP, g._turn_from) * (g._idle_feet[side] as Vector3))
	if g._turn_time < 1.0:
		g._turn_time = minf(1.0, g._turn_time + delta / 0.36)
		g._feet_yaw = lerp_angle(g._turn_from, g._turn_to, smoothstep(0.0, 1.0, g._turn_time))
	var offset := clampf(wrapf(g._feet_yaw - visual.rotation.y, -PI, PI), -0.65, 0.65)
	var chest: int = _combat_bones.get("Spine02", -1)
	var chest_basis := skeleton.get_bone_global_pose(chest).basis
	g._set_combat_bone_rotation(g.hips, Basis(Vector3.UP, offset) * skeleton.get_bone_global_pose(g.hips).basis)
	g._set_combat_bone_rotation(chest, chest_basis)
	if not g._turn_feet.is_empty():
		for side in ["Left", "Right"]:
			var first: bool = (side == "Left") == (g._turn_to > g._turn_from)
			var t := clampf(g._turn_time * 2.0 - (0.0 if first else 1.0), 0.0, 1.0)
			var target := g.global_transform * (Basis(Vector3.UP, g._turn_to) * (g._idle_feet[side] as Vector3))
			var foot: Vector3 = (g._turn_feet[side] as Vector3).lerp(target, smoothstep(0, 1, t))
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
	g._point_combat_bone(upper, lower, knee)
	g._point_combat_bone(lower, foot, target)
	g._set_combat_bone_rotation(foot, foot_basis)

func _apply_pose(pose: Array) -> void:
	if not is_instance_valid(skeleton): return
	for bone in mini(pose.size(), skeleton.get_bone_count()):
		skeleton.set_bone_pose_position(bone, pose[bone][0] as Vector3)
		skeleton.set_bone_pose_rotation(bone, pose[bone][1] as Quaternion)
		skeleton.set_bone_pose_scale(bone, pose[bone][2] as Vector3)

func _pose_clip(clip: String, time: float) -> void:
	if not animation.has_animation(clip): return
	animation.play(clip)
	if clip in g.LADDER_CLIPS and not g._traversal_roots.has(clip):
		animation.seek(0.0, true)
		var first := skeleton.get_bone_pose_position(g.hips)
		animation.seek(animation.get_animation(clip).length, true)
		g._traversal_roots[clip] = [first, skeleton.get_bone_pose_position(g.hips)]
	animation.seek(clampf(time, 0.0, animation.get_animation(clip).length), true)
	if clip in g.LADDER_CLIPS:
		var endpoints: Array = g._traversal_roots[clip]
		var progress := clampf(time / animation.get_animation(clip).length, 0, 1)
		var hip := skeleton.get_bone_pose_position(g.hips)
		hip -= (endpoints[0] as Vector3).lerp(endpoints[1], progress) - g.hip_rest
		hip.x = g.hip_rest.x
		hip.z = g.hip_rest.z
		skeleton.set_bone_pose_position(g.hips, hip)
