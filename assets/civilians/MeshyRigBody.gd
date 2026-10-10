extends "res://assets/CivilianModel.gd"
## Corpo único de NPC com malha e esqueleto importados do Meshy (GLB com ossos `mixamorig_*`).
##
## Mantém a API inteira do `CivilianModel` (locomoção por IK, `hand_targets`, `sit_amount`, `take_hit`,
## `activity`, nomes das juntas que a queda e as mortes do Mixamo procuram), mas as juntas são nós
## SEM malha: só carregam a pose. Quem desenha o corpo é o esqueleto do GLB, que recebe a rotação das
## juntas a cada quadro. Assim existe um só corpo visível e nenhum corpo antigo escondido para atualizar.
##
## Convenção de lados: `left_*` do CivilianModel fica em -X; no GLB do Meshy o "Left" fica em +X.
## O mapeamento é feito pelo lado geométrico, não pelo nome.
const TARGET_HEIGHT := 1.76
const BONE_PREFIX := "mixamorig_"
const HAND_ROLL := deg_to_rad(70.0)

## Caminho do GLB (esqueleto + malha). Definido por quem instancia, antes de entrar na árvore.
var source_path := ""
var skeleton: Skeleton3D
var mesh_node: MeshInstance3D
var glb_root: Node3D

var _scale := 1.0
var _hips_offset := Vector3.ZERO
# Uma entrada por osso da cadeia, em ordem pai → filho, em arrays paralelos (sem Dictionary: o laço roda
# por NPC por quadro e a busca por chave dominava o custo medido).
var _e_bone := PackedInt32Array()
var _e_parent := PackedInt32Array()
var _e_jb := PackedInt32Array()
var _e_neutral: Array[Basis] = []
var _e_rest: Array[Basis] = []
var _globals: Array[Basis] = []
var _joint_bases: Array[Basis] = []
var _tracked: Array[Node3D] = []
var _cache: Array[Transform3D] = []
var _driver: Node
static var _materials: Dictionary = {}

# Índices em `_joint_bases`.
const JB_PELVIS := 0
const JB_SPINE := 1 # 3 frações do tronco: 1/3, 2/3, 1
const JB_NECK := 4
const JB_HEAD := 5
const JB_LIMBS := 6 # por lado, 5 entradas: coxa, canela, pé, braço, antebraço

func _choose_wardrobe(_identity: int) -> void:
	wardrobe = {"female": false, "height": 1.0, "build": 1, "top_color": coat_color, "bottom_color": pants_color}

func _apply_colors() -> void:
	pass # cor vem da textura do GLB

func _ready() -> void:
	super()
	_sync_bones()
	_driver = PoseDriver.new()
	_driver.body = self
	_driver.process_priority = 1000
	add_child(_driver)

## O pai só pára de chamar `_process` quando o ator morre; a queda escreve nas juntas depois disso.
## Por isso a cópia para os ossos roda neste nó separado.
class PoseDriver extends Node:
	var body: Node
	func _process(_delta: float) -> void:
		if is_instance_valid(body) and body.is_visible_in_tree(): body._sync_bones()

# --- Construção ---------------------------------------------------------------

func _bone(short_name: String) -> int:
	var index := skeleton.find_bone(BONE_PREFIX + short_name)
	if index < 0: index = skeleton.find_bone("mixamorig:" + short_name)
	return index

func _rest_origin(bone: int) -> Vector3:
	return skeleton.get_bone_global_rest(bone).origin

func _model_position(bone: int) -> Vector3:
	return glb_root.position + _rest_origin(bone) * _scale

func _build_rig() -> void:
	var packed := load(source_path) as PackedScene
	assert(packed != null, "MeshyRigBody: GLB ausente em " + source_path)
	glb_root = packed.instantiate() as Node3D
	skeleton = glb_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	mesh_node = glb_root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	# Os clipes do Meshy não são usados em jogo: a pose vem das juntas.
	for player in glb_root.find_children("*", "AnimationPlayer", true, false):
		player.get_parent().remove_child(player)
		player.free()
	_scale = TARGET_HEIGHT / mesh_node.get_aabb().size.y
	glb_root.scale = Vector3.ONE * _scale
	_apply_material()

	var hips := _bone("Hips")
	var side_names := ["Right", "Left"] # lado -X (i = 0) é o "Right" do Mixamo
	# Centraliza o corpo sob a origem pela média dos quadris.
	var hip_mid := (_rest_origin(_bone("RightUpLeg")) + _rest_origin(_bone("LeftUpLeg"))) * 0.5
	glb_root.position = Vector3(-hip_mid.x * _scale, 0.0, -hip_mid.z * _scale)
	add_child(glb_root)

	# Medidas do próprio corpo para a IK.
	pelvis_y = _model_position(hips).y
	var thigh_total := 0.0
	var shin_total := 0.0
	var upper_total := 0.0
	var fore_total := 0.0
	for mix_name in side_names:
		var up := _model_position(_bone(mix_name + "UpLeg"))
		var knee := _model_position(_bone(mix_name + "Leg"))
		var ankle := _model_position(_bone(mix_name + "Foot"))
		thigh_total += up.distance_to(knee)
		shin_total += knee.distance_to(ankle)
		upper_total += _model_position(_bone(mix_name + "Arm")).distance_to(_model_position(_bone(mix_name + "ForeArm")))
		fore_total += _model_position(_bone(mix_name + "ForeArm")).distance_to(_model_position(_bone(mix_name + "Hand")))
	thigh_len = thigh_total * 0.5
	shin_len = shin_total * 0.5
	upper_arm_len = upper_total * 0.5
	forearm_len = fore_total * 0.5
	ankle_height = (_model_position(_bone("RightFoot")).y + _model_position(_bone("LeftFoot")).y) * 0.5
	_hips_offset = _model_position(hips) - Vector3(0, pelvis_y, 0)

	pelvis = _joint(self, "Pelvis", Vector3(0, pelvis_y, 0), null)
	spine = _joint(pelvis, "Spine", SPINE_OFFSET, null)
	head_node = _joint(spine, "Head", NECK, null)
	_head_scale = Vector3.ONE
	var spine_origin := Vector3(0, pelvis_y, 0) + SPINE_OFFSET
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var prefix := "left_" if i == 0 else "right_"
		var title := "Left" if i == 0 else "Right"
		var mix: String = side_names[i]
		_hip_offsets.append(_model_position(_bone(mix + "UpLeg")) - Vector3(0, pelvis_y, 0))
		_shoulders.append(_model_position(_bone(mix + "Arm")) - spine_origin)
		var thigh := _joint(pelvis, prefix + "upper_leg", _hip_offsets[i], null)
		var shin := _joint(thigh, prefix + "lower_leg", Vector3(0, -thigh_len, 0), null)
		var foot := _joint(shin, title + "Foot", Vector3(0, -shin_len, 0), null)
		var arm := _joint(spine, prefix + "upper_arm", _shoulders[i], null)
		var fore := _joint(arm, title + "Forearm", Vector3(0, -upper_arm_len, 0), null)
		thighs.append(thigh)
		shins.append(shin)
		feet.append(foot)
		upper_arms.append(arm)
		forearms.append(fore)
		_idle_stance.append(Vector3(side * 0.018, 0, (0.045 if (i == 0) == (posmod(appearance_variant, 2) == 0) else -0.02)))
	limbs.assign([thighs[0], upper_arms[0], thighs[1], upper_arms[1]])
	_build_chain(side_names)
	_tracked.assign([pelvis, spine, head_node, thighs[0], thighs[1], shins[0], shins[1], feet[0], feet[1],
		upper_arms[0], upper_arms[1], forearms[0], forearms[1]])
	_cache.resize(_tracked.size())
	_joint_bases.resize(JB_LIMBS + 10)

## A malha do Meshy vem com as duas faces desenhadas; a multidão só precisa da face externa.
func _apply_material() -> void:
	if not _materials.has(source_path):
		var original := mesh_node.get_active_material(0) as StandardMaterial3D
		var material := original.duplicate() as StandardMaterial3D if original != null else StandardMaterial3D.new()
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.roughness = 0.85
		material.metallic = 0.0
		_materials[source_path] = material
	mesh_node.material_override = _materials[source_path]

## Base de repouso girada para a pose neutra das juntas: braços e pernas pendurados em -Y.
## `toward` dá a direção do osso quando ela vem de outro par de ossos (a mão segue o antebraço);
## `roll` gira em torno do eixo do membro (palma voltada para a coxa em vez de para a frente).
func _neutral(bone: int, child: int, toward := -1, roll := 0.0) -> Basis:
	var rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	if child < 0: return rest
	var from_bone := toward if toward >= 0 else bone
	var direction := (_rest_origin(child) - _rest_origin(from_bone)).normalized()
	return Basis(Quaternion(Vector3.DOWN, roll)) * Basis(Quaternion(direction, Vector3.DOWN)) * rest

func _entry(bone: int, jb: int, child := -1, toward := -1, roll := 0.0) -> void:
	_e_bone.append(bone)
	_e_parent.append(skeleton.get_bone_parent(bone))
	_e_jb.append(jb)
	_e_neutral.append(_neutral(bone, child, toward, roll) if jb >= 0 else Basis.IDENTITY)
	_e_rest.append(skeleton.get_bone_rest(bone).basis.orthonormalized())

func _build_chain(side_names: Array) -> void:
	_globals.resize(skeleton.get_bone_count())
	_entry(_bone("Hips"), JB_PELVIS)
	_entry(_bone("Spine"), JB_SPINE)
	_entry(_bone("Spine1"), JB_SPINE + 1)
	_entry(_bone("Spine2"), JB_SPINE + 2)
	_entry(_bone("Neck"), JB_NECK)
	_entry(_bone("Head"), JB_HEAD)
	for i in 2:
		var mix: String = side_names[i]
		var base := JB_LIMBS + i * 5
		# Ossos sem junta (clavícula, torção do tornozelo) seguem a pose de repouso do pai.
		_entry(_bone(mix + "Shoulder"), -1)
		_entry(_bone(mix + "Arm"), base + 3, _bone(mix + "ForeArm"))
		_entry(_bone(mix + "ForeArm"), base + 4, _bone(mix + "Hand"))
		# A pose A do Meshy deixa a palma para a frente; relaxada, ela olha para a coxa.
		_entry(_bone(mix + "Hand"), base + 4, _bone(mix + "Hand"), _bone(mix + "ForeArm"), HAND_ROLL * (-1.0 if i == 0 else 1.0))
		_entry(_bone(mix + "UpLeg"), base, _bone(mix + "Leg"))
		_entry(_bone(mix + "Leg"), base + 1, _bone(mix + "Foot"))
		var foot := _bone(mix + "Foot")
		var foot_parent := skeleton.get_bone_parent(foot)
		if foot_parent != _bone(mix + "Leg"): _entry(foot_parent, -1)
		_entry(foot, base + 2)

# --- Pose -----------------------------------------------------------------------

func _sync_bones() -> void:
	if skeleton == null: return
	var changed := false
	for k in _tracked.size():
		var transform_now := _tracked[k].transform
		if transform_now != _cache[k]:
			_cache[k] = transform_now
			changed = true
	if not changed: return
	var t_pelvis := pelvis.transform
	var t_spine := t_pelvis * spine.transform
	var spine_q := spine.transform.basis.get_rotation_quaternion()
	var head_q := head_node.transform.basis.orthonormalized().get_rotation_quaternion()
	_joint_bases[JB_PELVIS] = t_pelvis.basis
	for f in 3:
		_joint_bases[JB_SPINE + f] = t_pelvis.basis * Basis(Quaternion.IDENTITY.slerp(spine_q, (f + 1) / 3.0))
	_joint_bases[JB_NECK] = t_spine.basis * Basis(Quaternion.IDENTITY.slerp(head_q, 0.4))
	_joint_bases[JB_HEAD] = t_spine.basis * Basis(head_q)
	for i in 2:
		var base := JB_LIMBS + i * 5
		var t_thigh := t_pelvis * thighs[i].transform
		var t_shin := t_thigh * shins[i].transform
		var t_foot := t_shin * feet[i].transform
		var t_arm := t_spine * upper_arms[i].transform
		var t_fore := t_arm * forearms[i].transform
		_joint_bases[base] = t_thigh.basis
		_joint_bases[base + 1] = t_shin.basis
		_joint_bases[base + 2] = t_foot.basis
		_joint_bases[base + 3] = t_arm.basis
		_joint_bases[base + 4] = t_fore.basis
	for k in _e_bone.size():
		var bone := _e_bone[k]
		var parent := _e_parent[k]
		var parent_global: Basis = _globals[parent] if parent >= 0 else Basis.IDENTITY
		var jb := _e_jb[k]
		if jb < 0:
			_globals[bone] = parent_global * _e_rest[k]
			continue
		var desired: Basis = _joint_bases[jb] * _e_neutral[k]
		_globals[bone] = desired
		# Bases ortonormais: a inversa é a transposta.
		skeleton.set_bone_pose_rotation(bone, (parent_global.transposed() * desired).get_rotation_quaternion())
		if parent < 0:
			skeleton.set_bone_pose_position(bone, (t_pelvis.origin + t_pelvis.basis * _hips_offset - glb_root.position) / _scale)
