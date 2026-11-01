extends RefCounted
## Camada de arma do Actor: empunhadura (IK de dois ossos dos braços com polo contínuo, solver de pegada
## do taco/machado, restrição bilateral do apoio), coluna e quadril do golpe, troca clipe ↔ carregar da
## katana, blend shapes das mãos e a transformação final do prop na palma resolvida. Separado em 01/11
## (Onda 3 de docs/plano-divisao-arquivos-grandes-20261101.md) só para o Actor.gd caber na leitura;
## _apply_combat_weapon_pose (216 linhas) e _solve_combat_arm (176) viraram etapas, na mesma ordem.
## É componente com estado próprio só no que ninguém de fora lê (grep campo a campo em 01/11):
## `_arm_blends`, `_presented_arm_rotations`, `_elbow_solved`, `_grip_fingers`, os `_sword_*` da troca
## da katana e as constantes do solver (FOREARM_TWIST_MAX, GRIP_*, SWORD_SWITCH_*, PALM_ROLL) moram aqui.
## O que outros arquivos leem continua no Actor: combat_weapon_pose/combat_weapon_id/_mount/_grip (35
## arquivos), _combat_bones (17), _elbow_previous e _twist_previous (MountainProgression), _clip_palms
## (BlitzBrother), _pose_delta (Ferry, BlitzBrother) e FREE_ARM_BONES (locomoção). O Actor mantém cada
## função antiga como delegação de uma linha com a mesma assinatura; set_combat_weapon_mount e
## clear_combat_weapon_pose, de duas linhas, ficaram lá inteiras.
## `g` fica como CharacterBody3D, e não como o script do Actor, para não criar preload cíclico. Nenhuma
## subclasse sobrescreve funções de pose (conferido em 01/11): as daqui se chamam direto, sem despacho
## dinâmico; _solve_leg (ActorLocomotionPose) é chamada por `g.`.
## Roda por quadro e por osso no jogador: esqueleto, visual, tabelas de osso e a malha das mãos são
## cópias tipadas (sync_refs), e as etapas recebem os valores por parâmetro, sem alocar nada novo.

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host
	sync_refs()

## Cópias tipadas de referências do Actor, atualizadas pelo dono (`_sync_pose_refs`) em toda atribuição.
var visual: Node3D
var skeleton: Skeleton3D
var _combat_bones: Dictionary = {}
var _combat_rests: Array[Transform3D] = []
var _combat_skin: MeshInstance3D

func sync_refs() -> void:
	visual = g.visual
	skeleton = g.skeleton
	_combat_bones = g._combat_bones
	_combat_rests = g._combat_rests
	_combat_skin = g._combat_skin

var _arm_blends: Dictionary = {}
var _presented_arm_rotations: Dictionary = {}
var _elbow_solved: Dictionary = {}
## Direção dos dedos da pegada no quadro anterior por lado (solver de pegada).
var _grip_fingers: Dictionary = {}
## Limite da torção do antebraço na pegada de duas mãos (rad, ~126°).
const FOREARM_TWIST_MAX := 2.2
## Solver de pegada: quanto o cotovelo pode sair do polo autorado (rad) e quão rápido
## ele gira em torno do eixo ombro–pulso (rad/s; o polo comum gira a 8).
const GRIP_ELBOW_SWING := 0.6
const GRIP_ELBOW_RATE := 14.0
## Componente vertical máxima da direção do cotovelo no solver de pegada (0 = horizontal,
## negativo = pendendo): cotovelo sempre um pouco para baixo, como num braço relaxado.
const GRIP_ELBOW_UP_MAX := -0.1
## Rotação máxima da mão em torno do cabo (rad/s) no taco/machado.
const GRIP_FINGER_RATE := 6.0
## Katana: troca entre o clipe nativo (golpe, sacar/guardar) e a pose de carregar. Os braços e a lâmina
## passam de uma para a outra nesse tempo; antes a espada girava de uma vez e os braços pulavam para a
## pose de antes do golpe (`_presented_arm_rotations` não andava durante o clipe). Entrar no golpe é
## curto para não atrasar a preparação; sair é mais longo: o fim do clipe deixa a lâmina ~90° longe do
## carregar, e em 0,14 s ela girava ~13°/quadro.
const SWORD_SWITCH_INTO_CLIP := 0.10
const SWORD_SWITCH_OUT_OF_CLIP := 0.24
var _sword_native_last := false
var _sword_switch_age := 1.0
var _sword_native_grip := Transform3D.IDENTITY
var _sword_carry_basis := Basis.IDENTITY
## Lâmina apresentada (no espaço do `visual`) no último quadro antes da troca.
var _sword_from_basis := Basis.IDENTITY

## Gameplay escreve um pacote pronto em espaço local do Actor. O pacote é
## aplicado depois da locomoção, para que pernas/corpo continuem animados e os
## braços mantenham contato real com as empunhaduras.
func set_combat_weapon_pose(id: String, pose: Dictionary) -> void:
	if id != g.combat_weapon_id:
		# Torção e dedos da pegada são da arma anterior: herdados, o antebraço saltava
		# 154° no primeiro golpe com o machado depois do taco.
		g._twist_previous.clear()
		_grip_fingers.clear()
	g.combat_weapon_id = id
	g.combat_weapon_pose = pose



## Espada de duas mãos dos clipes do Mixamo: presa à mão direita pela pegada `grip` (medida na guarda) e,
## quando as duas mãos estão no cabo, alinhada à linha entre elas (os clipes giram a espada entre as mãos).
func _two_hand_sword_transform(grip: Transform3D) -> Transform3D:
	var right_bone: int = _combat_bones.get("RightHand", -1)
	var left_bone: int = _combat_bones.get("LeftHand", -1)
	if right_bone < 0: return combat_weapon_transform(g.combat_weapon_grip)
	var right := (skeleton.global_transform * skeleton.get_bone_global_pose(right_bone)).orthonormalized()
	# As pegadas escritas são arredondadas; normaliza depois da composição para o slerp receber
	# uma rotação válida mesmo quando a própria mão já estava ortonormalizada.
	var result := (right * grip).orthonormalized()
	# Espada e escudo: a esquerda segura o escudo e nunca entra no cabo, mesmo passando perto dele.
	if left_bone >= 0 and g.combat_weapon_id != "sword_shield":
		var left := skeleton.global_transform * skeleton.get_bone_global_pose(left_bone)
		var axis := right.origin - left.origin
		var weight := clampf((0.30 - axis.length()) / 0.10, 0.0, 1.0)
		if weight > 0.0 and axis.length_squared() > 0.0001:
			var aligned := Basis.looking_at(axis.normalized(), result.basis.y)
			result.basis = result.basis.slerp(aligned, weight)
	return result

## Mistura da troca clipe ↔ carregar. A orientação parte da lâmina apresentada no quadro da troca (fixa
## no corpo) e chega à do modo novo; derivá-la da mão a cada quadro fazia a lâmina herdar o giro do
## pulso, que o IK limita a 18 rad/s (picos de 34°/quadro na saída do golpe). A posição fica presa à mão
## atual: cabo na palma com a orientação mostrada, indo para a pegada do clipe ao entrar nele.
func _sword_switch_transform() -> Transform3D:
	var held := _two_hand_sword_transform(_sword_native_grip)
	var weight := smoothstep(0.0, _sword_switch_length(), _sword_switch_age)
	var body := visual.global_basis.orthonormalized()
	var target := held.basis if _sword_native_last else (body * _sword_carry_basis).orthonormalized()
	var blade_basis := (body * _sword_from_basis).orthonormalized().slerp(target, weight).orthonormalized()
	var at_palm: Vector3 = combat_palm_position("Right") - blade_basis * g.combat_weapon_grip
	return Transform3D(blade_basis, at_palm.lerp(held.origin, weight) if _sword_native_last else held.origin.lerp(at_palm, weight))

func _sword_switch_length() -> float:
	return SWORD_SWITCH_INTO_CLIP if _sword_native_last else SWORD_SWITCH_OUT_OF_CLIP

func _sword_switching() -> bool:
	return g.combat_weapon_id in g.NATIVE_SWORDS and _sword_switch_age < _sword_switch_length()

func _track_sword_switch(native: bool) -> void:
	if native == _sword_native_last:
		_sword_switch_age += g._pose_delta
	else:
		_sword_native_last = native
		_sword_switch_age = 0.0
		if is_instance_valid(g.combat_weapon_mount):
			_sword_from_basis = (visual.global_basis.orthonormalized().inverse() * g.combat_weapon_mount.global_basis).orthonormalized()
		if not native:
			# O solver de pegada recomeça da pose apresentada no fim do clipe, não da de antes do golpe.
			_grip_fingers.clear()
			_elbow_solved.clear()
			g._twist_previous.clear()
	if native and not g.combat_weapon_pose.has("hand_grip"):
		# Clipe sem pegada medida (`native_sword_basis`): não há o que misturar.
		_sword_switch_age = SWORD_SWITCH_OUT_OF_CLIP
	elif native: _sword_native_grip = g.combat_weapon_pose.hand_grip
	elif g.combat_weapon_pose.has("basis"): _sword_carry_basis = g.combat_weapon_pose.basis

## Entrando no clipe, os braços saem da pose de carregar (não da locomoção crua) e chegam ao clipe em
## SWORD_SWITCH_INTO_CLIP; o que foi apresentado fica guardado para a saída partir do fim do clipe.
func _present_native_sword_arms() -> void:
	var weight := smoothstep(0.0, SWORD_SWITCH_INTO_CLIP, _sword_switch_age)
	for side in ["Right", "Left"]:
		for part in ["Shoulder", "Arm", "ForeArm", "Hand"]:
			var bone: int = _combat_bones.get(side + part, -1)
			if bone < 0: continue
			var rotation := skeleton.get_bone_pose_rotation(bone)
			if weight < 1.0 and _presented_arm_rotations.has(bone):
				rotation = (_presented_arm_rotations[bone] as Quaternion).slerp(rotation, weight).normalized()
				skeleton.set_bone_pose_rotation(bone, rotation)
			_presented_arm_rotations[bone] = rotation

func _apply_combat_weapon_pose() -> void:
	var native_sword: bool = g.combat_weapon_pose.get("native_sword", false) and skeleton != null
	if g.combat_weapon_id in g.NATIVE_SWORDS: _track_sword_switch(native_sword)
	if native_sword:
		# Preserva o golpe de espada importado, incluindo os arcos de cotovelo e pulso.
		# A esquerda fecha no cabo quando o clipe a põe junto da direita (guarda, andar e golpes de duas mãos).
		var two_hands := _clip_palm("Left").distance_to(_clip_palm("Right")) < 0.25
		_set_combat_grips(true, two_hands, true, two_hands, false, not two_hands)
		if g.combat_weapon_id in g.NATIVE_SWORDS: _present_native_sword_arms()
		if is_instance_valid(g.combat_weapon_mount):
			if _sword_switching(): g.combat_weapon_mount.global_transform = _sword_switch_transform()
			else: g.combat_weapon_mount.global_transform = _two_hand_sword_transform(g.combat_weapon_pose.hand_grip) if g.combat_weapon_pose.has("hand_grip") else combat_weapon_transform(g.combat_weapon_grip)
		return
	g._elbow_previous = _elbow_solved.duplicate()
	var support_hand_before: Quaternion = _presented_arm_rotations.get(_combat_bones.get("LeftHand", -1), Quaternion.IDENTITY)
	var had_support_hand := _presented_arm_rotations.has(_combat_bones.get("LeftHand", -1))
	var support_fore_before: Quaternion = _presented_arm_rotations.get(_combat_bones.get("LeftForeArm", -1), Quaternion.IDENTITY)
	var support_upper_before := {}
	for part in ["LeftShoulder", "LeftArm"]:
		var upper_bone: int = _combat_bones.get(part, -1)
		if _presented_arm_rotations.has(upper_bone): support_upper_before[upper_bone] = _presented_arm_rotations[upper_bone]
	if skeleton == null or g.combat_weapon_pose.is_empty():
		_set_combat_grips(false, false)
		_stabilize_combat_pose()
		return
	for required in ["RightArm", "RightForeArm", "RightHand", "LeftArm", "LeftForeArm", "LeftHand"]:
		if not _combat_bones.has(required): return
	var pose: Dictionary = g.combat_weapon_pose
	# Soqueira correndo / soco por clipe: alvo = palma do clipe DESTE quadro, lida antes de a
	# camada de arma mexer em quadril, coluna e clavícula. O jogo a guarda em `_clip_palms`
	# logo depois da locomoção; quem chama `_pose_locomotion` direto (testes, tiras de
	# quadros) não, e o padrão antigo (`combat_palm_position` lido no meio desta função, com a
	# coluna já endireitada) não era a palma do clipe: correndo, a mão esquerda subia à frente
	# do rosto (test_weapon_locomotion, 18 quadros; com a palma do clipe, nenhum).
	var follow_clip := clampf(float(pose.get("follow_clip", 0.0)), 0.0, 1.0)
	var clip_palms: Dictionary = g._clip_palms
	if follow_clip > 0.0 and clip_palms.is_empty(): clip_palms = {"Left": _clip_palm("Left"), "Right": _clip_palm("Right")}
	var armed := bool(pose.get("armed", g.combat_weapon_id != "fists"))
	var right_grip := bool(pose.get("right_grip", false))
	var left_grip := bool(pose.get("left_grip", false))
	# Braço que a pose não pede fica com o clipe de locomoção (como o braço livre
	# da V1, que seguia Walking/Running em vez de um alvo procedural).
	var right_solve := bool(pose.get("right_solve", right_grip or g.combat_weapon_id != "fists"))
	var left_solve := bool(pose.get("left_solve", left_grip))
	var right_basis: Basis = pose.get("right_basis", pose.basis)
	var left_basis: Basis = pose.get("left_basis", pose.basis)
	# V1 `MeshyDanteRig.prepare_pose`/`sync_shoulders`: armado, a coluna baixa volta
	# ao repouso e a de cima recebe só o giro de postura. Senão o clipe de
	# caminhada torce a camisa contra braços já resolvidos no espaço da mira.
	var clip_punch := bool(pose.get("clip_punch", false))
	var torso_yaw := 0.0 if clip_punch else float(pose.get("torso_yaw", 0.0))
	# A passada já posiciona quadril e pés. O giro de ataque fica no tronco
	# enquanto anda; aplicar o mesmo giro na raiz arrastava as duas pernas.
	# Golpe parado: o quadril gira antes do tronco (cadeia cinética), o peso vai à
	# frente ("step") e os joelhos cedem ("dip") com os pés plantados pelo IK de
	# perna. Andando, a passada é dona do quadril e só o tronco participa.
	var hip_yaw := 0.0 if clip_punch else float(pose.get("hip_yaw", torso_yaw * 0.35))
	var dip := 0.0 if clip_punch else float(pose.get("dip", 0.0))
	var step := 0.0 if clip_punch else float(pose.get("step", 0.0))
	var weight_shift := absf(dip) > 0.0005 or absf(step) > 0.0005
	_shift_combat_hips(hip_yaw, dip, step, weight_shift)
	_pose_combat_torso(pose, armed, torso_yaw)
	var lock_support := _solve_combat_arms(pose, follow_clip, clip_palms, right_grip, left_grip, right_solve, left_solve, right_basis, left_basis)
	_hold_support_and_mount(lock_support, pose, left_basis, right_solve, armed, support_hand_before, had_support_hand, support_fore_before, support_upper_before)

## Etapa do golpe parado: quadril gira antes do tronco, o peso vai à frente e os joelhos cedem com os
## pés plantados pelo IK de perna. Andando, a passada é dona do quadril e nada muda aqui.
func _shift_combat_hips(hip_yaw: float, dip: float, step: float, weight_shift: bool) -> void:
	if g.combat_weapon_id in ["fists", "knuckles", "knife", "axe", "bat", "katana", "sword_shield"] and (absf(hip_yaw) > 0.001 or weight_shift) and g._locomotion_weight <= 0.0 and g.hips >= 0:
		var chest_before: Basis = skeleton.get_bone_global_pose(_combat_bones.Spine02).basis
		var planted: bool = g._turn_time >= 1.0
		if planted and weight_shift:
			# Deslocamento em metros do Actor (−Z é a frente) levado ao espaço do pai do quadril.
			var shift := skeleton.global_basis.inverse() * (visual.global_basis.orthonormalized() * Vector3(0.0, -dip, -step))
			var parent := skeleton.get_bone_parent(g.hips)
			if parent >= 0: shift = skeleton.get_bone_global_pose(parent).basis.inverse() * shift
			skeleton.set_bone_pose_position(g.hips, skeleton.get_bone_pose_position(g.hips) + shift)
		_set_combat_bone_rotation(g.hips, Basis(Vector3.UP, hip_yaw) * skeleton.get_bone_global_pose(g.hips).basis)
		_set_combat_bone_rotation(_combat_bones.Spine02, chest_before)
		if planted:
			for side in ["Left", "Right"]:
				g._solve_leg(side, g.global_transform * (Basis(Vector3.UP, g._feet_yaw) * (g._idle_feet[side] as Vector3)))

## Etapa da coluna: armado, a lombar volta ao repouso; tronco gira/inclina e a cabeça devolve o giro.
func _pose_combat_torso(pose: Dictionary, armed: bool, torso_yaw: float) -> void:
	if armed and _combat_bones.has("Spine02"):
		var lower: int = _combat_bones.Spine02
		_set_combat_bone_rotation(lower, skeleton.get_bone_global_rest(lower).basis)
	var lean := float(pose.get("lean", 0.0))
	if _combat_bones.has("Spine") and (armed or absf(torso_yaw) > 0.001 or absf(lean) > 0.001):
		var spine: int = _combat_bones.Spine
		var head: int = _combat_bones.get("Head", -1)
		var gaze: Basis = skeleton.get_bone_global_pose(head).basis if head >= 0 else Basis.IDENTITY
		var chest := skeleton.get_bone_global_rest(spine).basis if armed else skeleton.get_bone_global_pose(spine).basis
		# Inclinação no espaço do esqueleto (o modelo é girado 180°: +Z é a frente do Dante).
		_set_combat_bone_rotation(spine, Basis(Vector3.UP, torso_yaw) * Basis(Vector3.RIGHT, lean) * chest)
		if head >= 0 and bool(pose.get("melee_action", false)):
			# Os olhos ficam no alvo: a cabeça devolve boa parte do giro do tronco no
			# golpe. Some com a passada, sem salto ao começar a andar no meio do golpe.
			_set_combat_bone_rotation(head, skeleton.get_bone_global_pose(head).basis.slerp(gaze, 0.6 * (1.0 - g._locomotion_weight)))
		elif head >= 0 and float(pose.get("head_counter", 0.0)) > 0.0:
			# Fuzil no ombro: o tronco fica de lado, mas a cabeça olha pela linha do cano
			# (sem isso o rosto apontava 40° para fora da mira).
			_set_combat_bone_rotation(head, skeleton.get_bone_global_pose(head).basis.slerp(gaze, float(pose.head_counter)))

## Etapa dos braços: guarda o clipe do braço misturado, resolve direita e esquerda (com a restrição
## bilateral do apoio), pulso reto do soco, mãos e o limite de velocidade das juntas. Devolve se o
## apoio da esquerda ficou travado no cabo, para a etapa seguinte.
func _solve_combat_arms(pose: Dictionary, follow_clip: float, clip_palms: Dictionary, right_grip: bool, left_grip: bool, right_solve: bool, left_solve: bool, right_basis: Basis, left_basis: Basis) -> bool:
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
	# Soqueira correndo: alvo = palma do clipe de corrida (antes de qualquer solução de braço neste quadro).
	if follow_clip > 0.0: right_target = right_target.lerp(visual.to_local(clip_palms.Right), follow_clip)
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
		if follow_clip > 0.0: left_target = left_target.lerp(visual.to_local(clip_palms.Left), follow_clip)
		if lock_support:
			var realised_delta: Vector3 = visual.global_basis * (pose.left - pose.right)
			left_target = visual.to_local(combat_palm_position("Right") + realised_delta)
		_solve_combat_arm("Left", left_target, left_basis, left_grip, -1.0, left_free)
		for entry in left_clip:
			_blend_arm_bone(entry[0], entry[1], left_weight)
	# Punho fechado no soco: pulso reto na linha do antebraço, só girando em torno
	# dele (vertical na guarda, palma para baixo no impacto). Com a palma presa a uma
	# base fixa o pulso dobrava e o punho apontava para baixo, lendo como garra.
	for side in ["Right", "Left"]:
		var roll: Variant = pose.get(side.to_lower() + "_wrist_roll", null)
		if roll is float and (right_solve if side == "Right" else left_solve):
			var hand_bone: int = _combat_bones[side + "Hand"]
			var axis := (_combat_rests[hand_bone].origin as Vector3).normalized()
			var straight_rotation := Quaternion(axis, float(roll) * (1.0 if side == "Right" else -1.0)) * _combat_rests[hand_bone].basis.get_rotation_quaternion()
			var weight := right_weight if side == "Right" else left_weight
			skeleton.set_bone_pose_rotation(hand_bone, skeleton.get_bone_pose_rotation(hand_bone).slerp(straight_rotation, weight).normalized())
	# Taco/machado: a forma "agarrar" do modelo só dobra os dedos pela metade e a mão
	# lia espalmada no cabo; o punho fechado (polegar corrigido) envolve o cabo.
	var fist_grip := bool(pose.get("grip_as_fist", false))
	_set_combat_grips(right_grip, left_grip, bool(pose.get("right_fist", false)) or (fist_grip and right_grip), bool(pose.get("left_fist", false)) or (fist_grip and left_grip), not right_solve, not left_solve or left_weight < 0.5)
	_stabilize_combat_pose()
	return lock_support

## Etapa final: apoio da esquerda resolvido contra a arma realizada (taco/machado com limite de
## velocidade) e o mount da arma preso à palma do quadro. `left_free` é relido da pose (como antes).
func _hold_support_and_mount(lock_support: bool, pose: Dictionary, left_basis: Basis, right_solve: bool, armed: bool, support_hand_before: Quaternion, had_support_hand: bool, support_fore_before: Quaternion, support_upper_before: Dictionary) -> void:
	var left_free := float(pose.get("left_free", 0.0))
	if lock_support and bool(pose.get("support_locked", false)):
		# Resolve o apoio contra a arma realizada (com restrição angular),
		# nunca a mão antes da interpolação. Isso mantém as duas palmas no objeto.
		var delta_world: Vector3 = visual.global_basis * (pose.left - pose.right)
		var support_target := visual.to_local(combat_palm_position("Right") + delta_world)
		_solve_combat_arm("Left", support_target, left_basis, true, -1.0, left_free)
		if bool(pose.get("grip_solver", false)):
			# Taco/machado: a mão esquerda chega ao cabo vinda do passo (ou de outra
			# arma). Sem limite aqui o braço saltava 85° num quadro quando a pegada
			# de duas mãos travava, alcançando o cabo de uma vez.
			var upper_rate := float(pose.get("arm_rate", 18.0))
			for upper_bone in support_upper_before:
				var previous_upper: Quaternion = support_upper_before[upper_bone]
				var wanted_upper := skeleton.get_bone_pose_rotation(upper_bone)
				var upper_angle := previous_upper.angle_to(wanted_upper)
				skeleton.set_bone_pose_rotation(upper_bone, previous_upper.slerp(wanted_upper, minf(1.0, upper_rate * g._pose_delta / maxf(upper_angle, 0.0001))).normalized())
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
			# Limita a rolagem axial sem tirar o pulso do cabo.
			# Limites da prontidão (14 e 18 rad/s) escalados pela taxa do golpe: o cabo do
			# taco gira mais rápido que isso e a palma de apoio escorregava do cabo.
			# Teto de 1,4×: o antebraço também recebe o balanço do IK (sem limite), e
			# torção + balanço juntos não podem passar de 35°/quadro.
			var rate_scale := clampf(float(pose.get("arm_rate", 18.0)) / 18.0, 1.0, 1.4)
			var twist_rate := 14.0 * rate_scale
			# Taco/machado: no contato a mão de apoio pede 45–65°/quadro em relação ao
			# antebraço; com a torção presa a 19°/quadro o resto caía no pulso, que
			# satura, e a palma saía até 4 cm do cabo. A torção leva sua parte.
			if bool(pose.get("grip_solver", false)): twist_rate = float(pose.get("arm_rate", 18.0))
			var fore_rotation := (support_fore_before * swing * Quaternion(axis, clampf(turn, -twist_rate * g._pose_delta, twist_rate * g._pose_delta))).normalized()
			if bool(pose.get("grip_solver", false)):
				# A dobra (swing) não tinha limite: com a torção já no teto, o antebraço de
				# apoio do machado chegava a 36–38°/quadro golpeando em movimento.
				var fore_limit: float = float(pose.get("arm_rate", 18.0)) * 1.1 * g._pose_delta
				var fore_angle := support_fore_before.angle_to(fore_rotation)
				if fore_angle > fore_limit: fore_rotation = support_fore_before.slerp(fore_rotation, fore_limit / fore_angle).normalized()
			skeleton.set_bone_pose_rotation(fore, fore_rotation)
			_set_combat_bone_rotation(hand, hand_basis)
			var desired := skeleton.get_bone_pose_rotation(hand)
			var angle := support_hand_before.angle_to(desired)
			# Taco/machado: a mão de apoio gira com o cabo, que no contato passa de
			# 40°/quadro; a 25 rad/s a palma ficava até 5 cm atrás dele.
			var hand_rate := 18.0 * rate_scale
			if bool(pose.get("grip_solver", false)): hand_rate = maxf(hand_rate, float(pose.get("arm_rate", 18.0)) * 1.2)
			skeleton.set_bone_pose_rotation(hand, support_hand_before.slerp(desired, minf(1.0, hand_rate * g._pose_delta / maxf(angle, 0.0001))))
		for part in ["Shoulder", "Arm", "ForeArm", "Hand"]:
			var bone: int = _combat_bones["Left" + part]
			_presented_arm_rotations[bone] = skeleton.get_bone_pose_rotation(bone)
	# Actor é processado antes de Gameplay na árvore produtiva. Atualizar o
	# mount aqui elimina o atraso visual de um quadro entre esqueleto e arma.
	if is_instance_valid(g.combat_weapon_mount) and right_solve and armed:
		g.combat_weapon_mount.global_transform = combat_weapon_transform(g.combat_weapon_grip)

func _stabilize_combat_pose() -> void:
	# 18 rad/s na prontidão; o golpe pede mais (`WeaponRigPose.STRIKE_ARM_RATE`).
	var arm_rate := float(g.combat_weapon_pose.get("arm_rate", 18.0))
	# A velocidade angular da junta faz parte da restrição de apresentação, incluindo
	# entrada/saída e mudanças nas restrições de alcance. Os suportes seguem a mão
	# realizada depois desta passada, então a interpolação não solta a arma empunhada.
	for side in ["Right", "Left"]:
		for part in ["Shoulder", "Arm", "ForeArm", "Hand"]:
			var bone: int = _combat_bones.get(side + part, -1)
			if bone < 0: continue
			var target := skeleton.get_bone_pose_rotation(bone).normalized()
			if _presented_arm_rotations.has(bone):
				var previous: Quaternion = _presented_arm_rotations[bone]
				var angle := previous.angle_to(target)
				target = previous.slerp(target, minf(1.0, arm_rate * g._pose_delta / maxf(angle, 0.0001))).normalized()
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
	var blended := clip.slerp(solved, weight) if g.combat_weapon_id == "fists" else clip.slerpni(solved, weight)
	skeleton.set_bone_pose_rotation(bone, blended.normalized())

## Blend shapes do `dante.glb`: 0/1 = mão fechada no cabo (GripRight/GripLeft),
## 2/3 = punho cerrado (FistRight/FistLeft, soco e soqueira). Mão que segue o
## clipe de locomoção fica levemente curvada (0,18), como na V1.
func _set_combat_grips(right: bool, left: bool, right_fist := false, left_fist := false, right_relaxed := false, left_relaxed := false) -> void:
	if not is_instance_valid(_combat_skin): return
	var count := _combat_skin.get_blend_shape_count()
	if count >= 2:
		_combat_skin.set_blend_shape_value(0, move_toward(_combat_skin.get_blend_shape_value(0), 1.0 if right and not right_fist else (0.18 if right_relaxed else 0.0), g._pose_delta * 14.0))
		_combat_skin.set_blend_shape_value(1, move_toward(_combat_skin.get_blend_shape_value(1), 1.0 if left and not left_fist else (0.18 if left_relaxed else 0.0), g._pose_delta * 14.0))
	if count >= 4:
		_combat_skin.set_blend_shape_value(2, move_toward(_combat_skin.get_blend_shape_value(2), 1.0 if right_fist else 0.0, g._pose_delta * 14.0))
		_combat_skin.set_blend_shape_value(3, move_toward(_combat_skin.get_blend_shape_value(3), 1.0 if left_fist else 0.0, g._pose_delta * 14.0))
	if skeleton != null:
		for side in ["Right", "Left"]:
			if _combat_bones.has(side + "Hand"):
				skeleton.set_bone_pose_scale(_combat_bones[side + "Hand"], Vector3.ONE * 0.95)

## Rolagem fixa entre a palma pedida e o osso da mão (V1), usada pelo IK e pela
## inversa em `combat_realized_palm_basis`.
const PALM_ROLL := {"Right": 0.358, "Left": -0.392}

## IK de dois ossos adaptado do rig Meshy da V1. `target_local` e
## `palm_basis_local` usam o espaço de frente do Actor, com o cano em -Z.
## Mão aberta e fechada usam a mesma cadeia e o mesmo polo contínuo.
func _solve_combat_arm(side: String, target_local: Vector3, palm_basis_local: Basis, _gripping: bool, sign_side: float, _free_weight: float = 0.0) -> void:
	var upper: int = _combat_bones[side + "Arm"]
	var fore: int = _combat_bones[side + "ForeArm"]
	var hand: int = _combat_bones[side + "Hand"]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var target := skeleton.to_local(visual.to_global(target_local))
	var palm_world_basis := visual.global_basis.orthonormalized() * palm_basis_local.orthonormalized()
	var model_basis := skeleton.global_basis.orthonormalized().inverse() * palm_world_basis
	var roll: float = PALM_ROLL[side]
	# Abrir os dedos não pode mudar o solver do pulso nem o comprimento do osso.
	# Punhos, recargas e pegadas respeitam todos a orientação de palma escrita.
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
	var long_weapon := bool(g.combat_weapon_pose.get("long_weapon", g.combat_weapon_id in ["smg", "shotgun", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "axe", "bat"]))
	var pole_world: Vector3 = visual.global_basis * Vector3(sign_side * (1.10 if long_weapon else 0.65), -1.5, -1.35 if long_weapon else -0.5)
	# Golpes pedem o próprio polo: cotovelo aberto e alto no gancho, por baixo no uppercut.
	var authored_pole: Variant = g.combat_weapon_pose.get("right_pole" if side == "Right" else "left_pole", null)
	if authored_pole is Vector3: pole_world = visual.global_basis * (authored_pole as Vector3)
	# Granada: dobra posterior do cotovelo (+Z local), não o polo anterior
	# das armas apoiadas. Mover só a mão não corrige o lado da articulação.
	if g.combat_weapon_id == "grenade" and side == "Right":
		pole_world = visual.global_basis * Vector3(0.35, -0.6, 1.5)
	var pole := skeleton.global_basis.inverse() * pole_world
	var bend := (pole - axis * pole.dot(axis)).normalized()
	var grip_solver := bool(g.combat_weapon_pose.get("grip_solver", false))
	# Taco/machado: a continuidade fica só no fim do solver de pegada. Aplicada aqui
	# também, ela virava a referência do solver e prendia o cotovelo virado para
	# dentro/para cima (no carregar, no meio do peito).
	if g._elbow_previous.has(side) and not grip_solver:
		var previous: Vector3 = g._elbow_previous[side]
		previous = (previous - axis * previous.dot(axis)).normalized()
		if not previous.is_zero_approx() and not bend.is_zero_approx():
			var angle := atan2(axis.dot(previous.cross(bend)), previous.dot(bend))
			bend = Basis(axis, clampf(angle, -8.0 * g._pose_delta, 8.0 * g._pose_delta)) * previous
	_elbow_solved[side] = bend
	if bend.is_zero_approx(): bend = Vector3(sign_side, -0.4, -0.2).normalized()
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var elbow := shoulder + axis * along + bend * sqrt(maxf(0.0, a * a - along * along))
	_solve_grip_arm(side, upper, fore, hand, sign_side, grip_solver, shoulder, target, palm_offset, pole, a, b, soft_start, distance, along, axis, bend, elbow, wrist, hand_basis)

## Etapa do braço: solver de pegada do taco/machado (só com `grip_solver`) e, para todo braço, a
## orientação final. Os valores da cadeia chegam por parâmetro (cópias de Vector3/Basis, sem alocar) e
## o solver de pegada os reescreve antes de passar a _orient_combat_arm.
func _solve_grip_arm(side: String, upper: int, fore: int, hand: int, sign_side: float, grip_solver: bool, shoulder: Vector3, target: Vector3, palm_offset: Vector3, pole: Vector3, a: float, b: float, soft_start: float, distance: float, along: float, axis: Vector3, bend: Vector3, elbow: Vector3, wrist: Vector3, hand_basis: Basis) -> void:
	if grip_solver:
		# Pegada de taco/machado: a mão não copia a base da arma. O cabo passa pela
		# linha dos nós dos dedos (polegar para a cabeça da arma) e os dedos seguem o
		# antebraço; copiando a base da arma o pulso dobrava 65–176° e a mão lia como
		# virada ao contrário. O cotovelo gira em torno do eixo ombro–pulso até o
		# antebraço ficar perpendicular ao cabo, como numa pegada real: paralelo, o
		# cabo entrava no antebraço e a mão virava de repente (palma saltava 10 cm).
		var head_local: Vector3 = (g.combat_weapon_pose.basis as Basis).orthonormalized() * Vector3(0, 0, -1)
		var handle := (skeleton.global_basis.orthonormalized().inverse() * (visual.global_basis.orthonormalized() * head_local)).normalized()
		var pole_bend := bend
		for iteration in 2:
			var center := shoulder + axis * along
			var radius := sqrt(maxf(0.0, a * a - along * along))
			var across := handle - axis * handle.dot(axis)
			if across.length() > 0.05 and radius > 0.01:
				var ratio := clampf((wrist - center).dot(handle) / radius / across.length(), -1.0, 1.0)
				var toward := across.normalized()
				var side_dir := axis.cross(toward)
				var angle := acos(ratio)
				var first := toward * cos(angle) + side_dir * sin(angle)
				var second := toward * cos(angle) - side_dir * sin(angle)
				var perpendicular := first if first.dot(pole_bend) >= second.dot(pole_bend) else second
				# No máximo GRIP_ELBOW_SWING do polo autorado: cotovelo para cima ou
				# para dentro do peito seria pior que um pulso um pouco dobrado.
				var swing_angle := pole_bend.signed_angle_to(perpendicular, axis)
				# Só desvia do polo natural quanto precisa: com o antebraço do polo a mais
				# de ~60° do cabo a pegada já é possível; puxar o cotovelo para o
				# perpendicular cruzava o braço no peito no carregar.
				var natural_forearm := (wrist - (center + pole_bend * radius)).normalized()
				var need := smoothstep(0.5, 0.85, absf(natural_forearm.dot(handle)))
				bend = pole_bend.rotated(axis, clampf(swing_angle, -GRIP_ELBOW_SWING, GRIP_ELBOW_SWING) * need)
				# Cotovelo nunca virado para cima: o braço "de baixo para cima" lia como
				# articulação invertida. Volta em direção ao polo autorado (para baixo).
				for attempt in 6:
					if bend.y <= GRIP_ELBOW_UP_MAX: break
					bend = bend.slerp(pole_bend, 0.5).normalized()
			if g._elbow_previous.has(side):
				var previous: Vector3 = g._elbow_previous[side]
				previous = (previous - axis * previous.dot(axis)).normalized()
				if not previous.is_zero_approx() and not bend.is_zero_approx():
					var step_angle := atan2(axis.dot(previous.cross(bend)), previous.dot(bend))
					bend = Basis(axis, clampf(step_angle, -GRIP_ELBOW_RATE * g._pose_delta, GRIP_ELBOW_RATE * g._pose_delta)) * previous
			_elbow_solved[side] = bend
			elbow = center + bend * radius
			var forearm := (wrist - elbow).normalized()
			var fingers := forearm - handle * forearm.dot(handle)
			# Antebraço quase paralelo ao cabo (sem cotovelo possível que o deixe
			# perpendicular): a direção dos dedos degenera e a mão viraria de repente.
			# Mantém a do quadro anterior, só reprojetada no cabo novo.
			var held: Vector3 = _grip_fingers.get(side, Vector3.ZERO)
			held = held - handle * held.dot(handle)
			if held.length_squared() > 0.0001:
				var trust := smoothstep(0.25, 0.5, fingers.length())
				fingers = fingers.normalized() * trust + held.normalized() * (1.0 - trust) if fingers.length_squared() > 0.000001 else held
			if fingers.length_squared() < 0.0001: break
			fingers = fingers.normalized()
			# Quando o antebraço cruza a linha do cabo, a direção dos dedos troca de
			# lado e a mão giraria até 156° num quadro; o limitador de articulação
			# segurava a mão e a palma de apoio saía 12 cm do cabo. Girando os dedos em
			# torno do próprio cabo, a palma continua nele enquanto o pulso alcança.
			if held.length_squared() > 0.0001:
				var held_dir := held.normalized()
				var finger_turn := atan2(handle.dot(held_dir.cross(fingers)), held_dir.dot(fingers))
				fingers = Basis(handle, clampf(finger_turn, -GRIP_FINGER_RATE * g._pose_delta, GRIP_FINGER_RATE * g._pose_delta)) * held_dir
			if iteration == 1: _grip_fingers[side] = fingers
			hand_basis = _grip_hand_basis(hand, handle, fingers)
			wrist = target - hand_basis * palm_offset
			axis = (wrist - shoulder).normalized()
			distance = maxf(shoulder.distance_to(wrist), absf(a - b) + 0.001)
			if distance > soft_start:
				distance = soft_start + 0.050 * (1.0 - exp(-(distance - soft_start) / 0.050))
			wrist = shoulder + axis * distance
			bend = (bend - axis * bend.dot(axis)).normalized()
			pole_bend = (pole - axis * pole.dot(axis)).normalized()
			if bend.is_zero_approx(): bend = Vector3(sign_side, -0.4, -0.2).normalized()
			if pole_bend.is_zero_approx(): pole_bend = bend
			along = (a * a - b * b + distance * distance) / (2.0 * distance)
			elbow = shoulder + axis * along + bend * sqrt(maxf(0.0, a * a - along * along))
	_orient_combat_arm(side, upper, fore, hand, shoulder, elbow, wrist, axis, bend, hand_basis)

## Etapa final do braço: segmentos pelo plano do cotovelo, torção do antebraço e base da mão.
func _orient_combat_arm(side: String, upper: int, fore: int, hand: int, shoulder: Vector3, elbow: Vector3, wrist: Vector3, axis: Vector3, bend: Vector3, hand_basis: Basis) -> void:
	# Monta os dois referenciais de segmento a partir do plano do cotovelo, não da rolagem
	# axial arbitrária do clipe anterior. Isso evita a singularidade do arco mais curto
	# quando um soco ou uma recarga cruza a direção de referência desse clipe.
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
		# clamp(atan2(...), -1.2, 1.2) pulava 2.4 rad no corte de ramo
		# em +/-PI. Uma fração periódica limitada não tem descontinuidade ali;
		# o pulso ainda realiza exatamente a orientação de palma pedida.
		var share := float(g.combat_weapon_pose.get("forearm_twist_share", 0.0))
		if share > 0.0:
			# Pegada de taco/machado: o antebraço gira (pronação/supinação) e o pulso
			# fica quase reto. Sem isso o pulso ficava 140–176° torcido e a mão lia
			# como "virada ao contrário". A torção é desembrulhada contra o quadro
			# anterior, então não salta no corte de ±π.
			if g._twist_previous.has(side):
				var previous_twist: float = g._twist_previous[side]
				twist = previous_twist + wrapf(twist - previous_twist, -PI, PI)
			twist = clampf(twist, -1.5 * PI, 1.5 * PI)
			g._twist_previous[side] = twist
			fore_pose.basis = Basis(axis_fore, clampf(twist * share, -FOREARM_TWIST_MAX, FOREARM_TWIST_MAX)) * fore_pose.basis
		else:
			g._twist_previous.erase(side)
			fore_pose.basis = Basis(axis_fore, 1.2 * sin(twist)) * fore_pose.basis
		_set_combat_bone_rotation(fore, fore_pose.basis)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	hand_pose.basis = hand_basis
	_set_combat_bone_rotation(hand, hand_pose.basis)

## Base global do osso da mão (espaço do esqueleto) com o eixo lateral da mão
## (mindinho → indicador; +Z da malha na T-pose, nas duas mãos) ao longo de
## `handle` e o eixo dos dedos (Hand → Hand_End) ao longo de `fingers`.
func _grip_hand_basis(hand: int, handle: Vector3, fingers: Vector3) -> Basis:
	var rest := skeleton.get_bone_global_rest(hand).basis.orthonormalized()
	var lateral_local := (rest.inverse() * Vector3(0, 0, 1)).normalized()
	var fingers_local := _combat_hand_tip(hand)
	lateral_local = (lateral_local - fingers_local * lateral_local.dot(fingers_local)).normalized()
	var source := Basis(lateral_local, fingers_local, lateral_local.cross(fingers_local))
	var lateral := (handle - fingers * handle.dot(fingers)).normalized()
	var target := Basis(lateral, fingers, lateral.cross(fingers))
	return (target * source.inverse()).orthonormalized()

## Direção dos dedos no espaço local do osso da mão (filho Hand_End na pose de repouso).
func _combat_hand_tip(hand: int) -> Vector3:
	for child in skeleton.get_bone_children(hand):
		return skeleton.get_bone_rest(child).origin.normalized()
	return Vector3.UP

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

## O IK muda só a orientação. Decompor um Transform3D global de volta em
## pose local a cada iteração bilateral realimenta escala/cisalhamento de ponto flutuante
## na próxima solução. As trilhas de rotação da animação não zeram essa escala;
## em centenas de quadros ela cresce até as mangas ocuparem a tela.
## Mantém translações/escalas escritas e converte só rotações ortonormais.
func _set_combat_bone_rotation(bone: int, p_global_rotation: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation := Basis.IDENTITY
	if parent >= 0:
		parent_rotation = skeleton.get_bone_global_pose(parent).basis.orthonormalized()
	var local_rotation := parent_rotation.transposed() * p_global_rotation.orthonormalized()
	skeleton.set_bone_pose_rotation(bone, local_rotation.get_rotation_quaternion().normalized())

## Palma da pose do clipe neste quadro, pela cadeia de ossos pais: `get_bone_global_pose` pode devolver
## o cache do quadro anterior logo depois de `set_bone_pose_*`.
func _clip_palm(side: String) -> Vector3:
	if skeleton == null or not _combat_bones.has(side + "Hand"): return g.global_position
	var bone: int = _combat_bones[side + "Hand"]
	var chain := skeleton.get_bone_pose(bone)
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		chain = skeleton.get_bone_pose(parent) * chain
		parent = skeleton.get_bone_parent(parent)
	return skeleton.to_global(chain * Vector3(0, 0.065, 0))

func combat_palm_position(side: String) -> Vector3:
	if skeleton == null or not _combat_bones.has(side + "Hand"): return g.global_position
	var pose := skeleton.get_bone_global_pose(_combat_bones[side + "Hand"])
	return skeleton.to_global(pose * Vector3(0, 0.065, 0))

## Orientação da palma realmente apresentada, no espaço do Actor: inverte o
## alinhamento que `_solve_combat_arm` aplica entre palma pedida e osso da mão.
func combat_realized_palm_basis(side: String) -> Basis:
	var hand: int = _combat_bones[side + "Hand"]
	var roll: float = PALM_ROLL[side]
	var bone := skeleton.get_bone_global_pose(hand).basis.orthonormalized()
	var palm := bone * (Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, -roll)).inverse()
	return (visual.global_basis.orthonormalized().inverse() * skeleton.global_basis.orthonormalized() * palm).orthonormalized()

## Transformação final do prop baseada na palma efetivamente resolvida pelo IK.
## `grip` é o centro da empunhadura no espaço local do modelo da arma.
func combat_weapon_transform(grip: Vector3) -> Transform3D:
	if g.combat_weapon_pose.is_empty() or not is_instance_valid(visual):
		return Transform3D(g.global_basis, g.global_position)
	if _sword_switching() and skeleton != null and _combat_bones.has("RightHand"):
		return _sword_switch_transform()
	if g.combat_weapon_pose.get("native_sword", false) and skeleton != null and _combat_bones.has("RightHand"):
		var index: int = _combat_bones.RightHand
		var chain := skeleton.get_bone_pose(index)
		var parent := skeleton.get_bone_parent(index)
		while parent >= 0:
			chain = skeleton.get_bone_pose(parent) * chain
			parent = skeleton.get_bone_parent(parent)
		var hand_basis := (skeleton.global_basis * chain.basis).orthonormalized()
		var blade_basis: Basis = hand_basis * g.combat_weapon_pose.get("native_sword_basis", Basis(Vector3.UP, PI))
		return Transform3D(blade_basis, _clip_palm("Right") - blade_basis * grip)
	var local_basis: Basis = g.combat_weapon_pose.basis
	if g.combat_weapon_pose.get("right_wrist_roll") is float:
		# Pulso reto (soqueira no soco): o prop segue a mão real, não a base pedida.
		var requested: Basis = g.combat_weapon_pose.get("right_basis", local_basis)
		local_basis = combat_realized_palm_basis("Right") * requested.orthonormalized().inverse() * local_basis.orthonormalized()
	var weapon_basis := (visual.global_basis * local_basis).orthonormalized()
	# Na V1 a arma não escalava junto com o Dante; `weapon_scale` repõe essa proporção.
	var weapon_scale := float(g.combat_weapon_pose.get("weapon_scale", 1.0))
	return Transform3D(weapon_basis.scaled_local(Vector3.ONE * weapon_scale), combat_palm_position("Right") - weapon_basis * grip * weapon_scale)

## Palma esquerda resolvida, com a orientação pedida pela pose (segunda soqueira).
func combat_left_palm_transform() -> Transform3D:
	var local_basis: Basis = g.combat_weapon_pose.get("left_basis", Basis.IDENTITY)
	if g.combat_weapon_pose.get("left_wrist_roll") is float: local_basis = combat_realized_palm_basis("Left")
	var weapon_scale := float(g.combat_weapon_pose.get("weapon_scale", 1.0))
	var palm_basis := (visual.global_basis * local_basis).orthonormalized()
	return Transform3D(palm_basis.scaled_local(Vector3.ONE * weapon_scale), combat_palm_position("Left"))

## Subida do quadril no passo, em metros do Actor — o que a V1 lia de
## `torso_node.position` para acompanhar o carregar da arma com o corpo.
func combat_rig_info() -> Dictionary:
	if skeleton == null or g.hips < 0: return {}
	return {"body_bob": (skeleton.get_bone_pose_position(g.hips).y - g.hip_rest.y) * skeleton.global_basis.get_scale().y / maxf(visual.global_basis.get_scale().y, 0.001)}

## respawn_player: o renascido parte da pose nova, sem a apresentação nem a continuidade de sinal
## dos braços da vida anterior.
func clear_presented_arms() -> void:
	_presented_arm_rotations.clear()
	_arm_blends.clear()
