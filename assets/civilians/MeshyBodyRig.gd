extends RefCounted
## Corpo importado do Meshy (GLB com esqueleto `mixamorig_*`) para um `CivilianModel`.
##
## O modelo mantém a API inteira (locomoção por IK, `hand_targets`, `sit_amount`, `take_hit`, `activity`, os
## nomes das juntas que a queda e as mortes do Mixamo procuram), mas as juntas viram nós SEM malha: só carregam
## a pose. Quem desenha o corpo é o esqueleto do GLB, que recebe a rotação das juntas. Assim existe um só
## corpo visível e nenhum corpo antigo escondido para atualizar.
##
## Convenção de lados: `left_*` do CivilianModel fica em -X; no GLB do Meshy o "Left" fica em +X. O
## mapeamento é feito pelo lado geométrico, não pelo nome.
const TARGET_HEIGHT := 1.76
const BONE_PREFIX := "mixamorig_"
## Giro da mão em torno do antebraço (palma para a coxa). Variável só para experimentos de captura.
static var hand_roll := deg_to_rad(-70.0)
## Interruptor de diagnóstico A/B na mesma sessão, sem trocar arquivos nem esconder a arma.
static var correct_hand_reach := true
static var palm_grips := true
## Interruptor A/B para o mesmo esqueleto e pose, sem reduzir frequência ou geometria.
static var optimize_pose_chain := true
const SHADER := preload("res://assets/civilians/civilian_meshy.gdshader")
const ACCESSORIES := preload("res://assets/civilians/MeshyAccessories.gd")
## Topo do cabelo do kit acima da origem da cabeça: a peça é alinhada pelo topo do crânio do corpo importado.
const KIT_CROWN := 0.30
# Índices em `_joint_bases`.
const JB_PELVIS := 0
const JB_SPINE := 1 # 3 frações do tronco: 1/3, 2/3, 1
const JB_NECK := 4
const JB_HEAD := 5
const JB_LIMBS := 6 # por lado, 5 entradas: coxa, canela, pé, braço, antebraço
## Materiais por superfície do GLB, compartilhados pela multidão (cor/matiz variam por instância).
static var _materials: Dictionary = {}

var skeleton: Skeleton3D
var mesh_node: MeshInstance3D
var glb_root: Node3D
var driver: Node
var _model: Node3D
var _pelvis: Node3D
var _spine: Node3D
var _head: Node3D
var _thighs: Array[Node3D] = []
var _shins: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _forearms: Array[Node3D] = []
var _scale := 1.0
var _hips_offset := Vector3.ZERO
# Uma entrada por osso da cadeia, em ordem pai → filho, em arrays paralelos (sem Dictionary: o laço roda
# por NPC por quadro e a busca por chave dominava o custo medido).
var _e_bone := PackedInt32Array()
var _e_parent := PackedInt32Array()
var _e_jb := PackedInt32Array()
var _e_hand := PackedInt32Array()
var _e_need_origin := PackedByteArray()
var _e_neutral: Array[Basis] = []
var _e_rest: Array[Basis] = []
var _e_position: Array[Vector3] = []
var _globals: Array[Basis] = []
var _global_origins: Array[Vector3] = []
var _joint_bases: Array[Basis] = []
var _tracked: Array[Node3D] = []
var _cache: Array[Transform3D] = []
var _hand_frames: Array = [null, null]
var _hand_sources: Array[Basis] = []
var _hand_bones := PackedInt32Array()
var _hand_profile: Array = []
var _has_palms := false
var _grip_shapes := PackedInt32Array()
var _grip_values := Vector2.ZERO

## Nó separado: o pai pára de chamar `_process` quando o ator morre e a queda escreve nas juntas depois disso.
class PoseDriver extends Node:
	var rig: RefCounted
	var model: Node3D
	func _process(delta: float) -> void:
		if is_instance_valid(model) and model.is_visible_in_tree(): rig.sync(delta)

# --- Construção ---------------------------------------------------------------

func _bone(short_name: String) -> int:
	var index := skeleton.find_bone(BONE_PREFIX + short_name)
	if index < 0: index = skeleton.find_bone("mixamorig:" + short_name)
	return index

func _rest_origin(bone: int) -> Vector3:
	return skeleton.get_bone_global_rest(bone).origin

func _model_position(bone: int) -> Vector3:
	return glb_root.position + _rest_origin(bone) * _scale

## `tint`: {"hue": -0.5..0.5, "brightness": 0.5..1.5} nas roupas coloridas e `tone` (Color) como multiplicador das roupas.
func build(model: Node3D, source_path: String, tint := {}) -> void:
	_model = model
	var packed := load(source_path) as PackedScene
	assert(packed != null, "MeshyBodyRig: GLB ausente em " + source_path)
	glb_root = packed.instantiate() as Node3D
	skeleton = glb_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	mesh_node = glb_root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_hand_profile = mesh_node.get_meta("extras", {}).get("npc_hand_profile", [])
	_has_palms = _hand_profile.size() == 2
	model.palm_grip_enabled = _has_palms
	for side in ["Right", "Left"]:
		_grip_shapes.append(mesh_node.find_blend_shape_by_name("Grip" + side))
	for side in 2:
		if _grip_shapes[side] >= 0: _grip_values[side] = mesh_node.get_blend_shape_value(_grip_shapes[side])
	# Os clipes do Meshy não são usados em jogo: a pose vem das juntas.
	for player in glb_root.find_children("*", "AnimationPlayer", true, false):
		player.get_parent().remove_child(player)
		player.free()
	_scale = TARGET_HEIGHT / mesh_node.get_aabb().size.y
	glb_root.scale = Vector3.ONE * _scale
	_apply_material(source_path, tint)

	var hips := _bone("Hips")
	var side_names := ["Right", "Left"] # lado -X (i = 0) é o "Right" do Mixamo
	# Centraliza o corpo sob a origem pela média dos quadris.
	var hip_mid := (_rest_origin(_bone("RightUpLeg")) + _rest_origin(_bone("LeftUpLeg"))) * 0.5
	glb_root.position = Vector3(-hip_mid.x * _scale, 0.0, -hip_mid.z * _scale)
	model.add_child(glb_root)
	model.skeleton = skeleton
	model.mesh_node = mesh_node

	# Medidas do próprio corpo para a IK.
	var pelvis_y := _model_position(hips).y
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
		model.arm_lengths.append(Vector2(
			_model_position(_bone(mix_name + "Arm")).distance_to(_model_position(_bone(mix_name + "ForeArm"))),
			_model_position(_bone(mix_name + "ForeArm")).distance_to(_model_position(_bone(mix_name + "Hand")))))
	model.pelvis_y = pelvis_y
	model.thigh_len = thigh_total * 0.5
	model.shin_len = shin_total * 0.5
	model.upper_arm_len = upper_total * 0.5
	model.forearm_len = fore_total * 0.5
	model.arm_reach_limits = Vector2(model.arm_lengths[0].x + model.arm_lengths[0].y,
		model.arm_lengths[1].x + model.arm_lengths[1].y) - Vector2.ONE * 0.002
	model.ankle_height = (_model_position(_bone("RightFoot")).y + _model_position(_bone("LeftFoot")).y) * 0.5
	_hips_offset = _model_position(hips) - Vector3(0, pelvis_y, 0)

	_pelvis = model._joint(model, "Pelvis", Vector3(0, pelvis_y, 0), null)
	_spine = model._joint(_pelvis, "Spine", model.SPINE_OFFSET, null)
	_head = model._joint(_spine, "Head", model.NECK, null)
	model.pelvis = _pelvis
	model.spine = _spine
	model.head_node = _head
	model._head_scale = Vector3.ONE
	var spine_origin: Vector3 = Vector3(0, pelvis_y, 0) + model.SPINE_OFFSET
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var prefix := "left_" if i == 0 else "right_"
		var title := "Left" if i == 0 else "Right"
		var mix: String = side_names[i]
		model._hip_offsets.append(_model_position(_bone(mix + "UpLeg")) - Vector3(0, pelvis_y, 0))
		model._shoulders.append(_model_position(_bone(mix + "Arm")) - spine_origin)
		var thigh: Node3D = model._joint(_pelvis, prefix + "upper_leg", model._hip_offsets[i], null)
		var shin: Node3D = model._joint(thigh, prefix + "lower_leg", Vector3(0, -model.thigh_len, 0), null)
		var foot: Node3D = model._joint(shin, title + "Foot", Vector3(0, -model.shin_len, 0), null)
		var arm: Node3D = model._joint(_spine, prefix + "upper_arm", model._shoulders[i], null)
		var fore: Node3D = model._joint(arm, title + "Forearm", Vector3(0, -model.arm_lengths[i].x, 0), null)
		model.thighs.append(thigh)
		model.shins.append(shin)
		model.feet.append(foot)
		model.upper_arms.append(arm)
		model.forearms.append(fore)
		_thighs.append(thigh)
		_shins.append(shin)
		_feet.append(foot)
		_arms.append(arm)
		_forearms.append(fore)
		model._idle_stance.append(Vector3(side * 0.018, 0, (0.045 if (i == 0) == (posmod(model.appearance_variant, 2) == 0) else -0.02)))
	model.limbs.assign([model.thighs[0], model.upper_arms[0], model.thighs[1], model.upper_arms[1]])
	_build_chain(side_names)
	_tracked.assign([_pelvis, _spine, _head, _thighs[0], _thighs[1], _shins[0], _shins[1], _feet[0], _feet[1],
		_arms[0], _arms[1], _forearms[0], _forearms[1]])
	_cache.resize(_tracked.size())
	_joint_bases.resize(JB_LIMBS + 10)
	driver = PoseDriver.new()
	driver.rig = self
	driver.model = model
	driver.process_priority = 1000
	model.add_child(driver)

## Prende peças de cabeça ({"kind", "color", "band"}, ver `MeshyAccessories`) ao osso `Head`. A origem do desenho
## do kit fica sob o crânio, com o topo do cabelo do kit (`KIT_CROWN`) no topo da malha do corpo; o
## `BoneAttachment3D` herda a escala do GLB, então a transformação filha a desfaz.
func attach_accessories(list: Array) -> Array[Node3D]:
	var pieces: Array[Node3D] = []
	if list.is_empty() or skeleton == null: return pieces
	var head := _bone("Head")
	if head < 0: return pieces
	var top := glb_root.position.y + mesh_node.get_aabb().end.y * _scale
	var head_model := _model_position(head)
	var origin_model := Vector3(head_model.x, top - KIT_CROWN, head_model.z + 0.012)
	var origin_skeleton := (origin_model - glb_root.position) / _scale
	var attachment := BoneAttachment3D.new()
	attachment.name = "HeadAccessories"
	attachment.bone_name = skeleton.get_bone_name(head)
	skeleton.add_child(attachment)
	var rest := skeleton.get_bone_global_rest(head)
	var local := rest.affine_inverse() * Transform3D(Basis.from_scale(Vector3.ONE / _scale), origin_skeleton)
	for descriptor in list:
		var piece := ACCESSORIES.make_piece(descriptor)
		piece.transform = local
		attachment.add_child(piece)
		pieces.append(piece)
	return pieces

## Materiais compartilhados por GLB/superfície; as texturas vêm do arquivo original.
func _apply_material(source_path: String, tint: Dictionary) -> void:
	# A mão reaproveitada conserva sua textura na mesma malha/esqueleto do corpo.
	for surface in mesh_node.mesh.get_surface_count():
		var key := "%s:%d" % [source_path, surface]
		if not _materials.has(key):
			var original := mesh_node.get_active_material(surface) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = SHADER
			if original != null and original.albedo_texture != null: material.set_shader_parameter("albedo_texture", original.albedo_texture)
			_materials[key] = material
		mesh_node.set_surface_override_material(surface, _materials[key])
	if tint.has("hue"): mesh_node.set_instance_shader_parameter("hue_shift", float(tint.hue))
	if tint.has("brightness"): mesh_node.set_instance_shader_parameter("brightness", float(tint.brightness))
	if tint.has("tone"): mesh_node.set_instance_shader_parameter("tone", tint.tone)

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
	_e_hand.append(-1)
	_e_neutral.append(_neutral(bone, child, toward, roll) if jb >= 0 else Basis.IDENTITY)
	_e_rest.append(skeleton.get_bone_rest(bone).basis.orthonormalized())
	_e_position.append(skeleton.get_bone_rest(bone).origin)

func _build_chain(side_names: Array) -> void:
	_globals.resize(skeleton.get_bone_count())
	_global_origins.resize(skeleton.get_bone_count())
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
		_entry(_bone(mix + "Hand"), base + 4, _bone(mix + "Hand"), _bone(mix + "ForeArm"), hand_roll * (-1.0 if i == 0 else 1.0))
		_e_hand[-1] = i
		var fingers := (_rest_origin(_bone(mix + "Hand")) - _rest_origin(_bone(mix + "ForeArm"))).normalized()
		var normal := (Vector3.BACK - fingers * fingers.dot(Vector3.BACK)).normalized()
		if _model.palm_grip_enabled:
			var profile: Dictionary = _hand_profile[i]
			fingers = Vector3(profile.fingers[0], profile.fingers[1], profile.fingers[2]).normalized()
			normal = Vector3(profile.normal[0], profile.normal[1], profile.normal[2]).normalized()
			normal = (normal - fingers * fingers.dot(normal)).normalized()
			_model.palm_offsets[i] = Vector3(profile.palm_offset[0], profile.palm_offset[1], profile.palm_offset[2])
			if profile.has("weapon_frame"):
				var axes: Array = profile.weapon_frame
				_model.weapon_hand_frames[i] = Basis(Vector3(axes[0][0], axes[0][1], axes[0][2]), Vector3(axes[1][0], axes[1][1], axes[1][2]), Vector3(axes[2][0], axes[2][1], axes[2][2]))
		var anatomical := Basis(fingers.cross(normal), fingers, normal)
		_hand_sources.append(anatomical.transposed() * skeleton.get_bone_global_rest(_bone(mix + "Hand")).basis.orthonormalized())
		_hand_bones.append(_bone(mix + "Hand"))
		if _model.palm_grip_enabled:
			var relaxed_normal := Vector3.RIGHT if i == 0 else Vector3.LEFT
			_e_neutral[-1] = Basis(Vector3.DOWN.cross(relaxed_normal), Vector3.DOWN, relaxed_normal) * _hand_sources.back()
		_entry(_bone(mix + "UpLeg"), base, _bone(mix + "Leg"))
		_entry(_bone(mix + "Leg"), base + 1, _bone(mix + "Foot"))
		var foot := _bone(mix + "Foot")
		var foot_parent := skeleton.get_bone_parent(foot)
		if foot_parent != _bone(mix + "Leg"): _entry(foot_parent, -1)
		_entry(foot, base + 2)
	# Só os ancestrais dos ombros alimentam posições que serão escritas no
	# esqueleto. As demais origens eram propagadas sem nenhum consumidor.
	var origin_bones := {}
	for mix in side_names:
		var ancestor := skeleton.get_bone_parent(_bone(mix + "Arm"))
		while ancestor >= 0:
			origin_bones[ancestor] = true
			ancestor = skeleton.get_bone_parent(ancestor)
	for bone in _e_bone: _e_need_origin.append(1 if origin_bones.has(bone) else 0)

# --- Pose -----------------------------------------------------------------------

func palm_position(side: int) -> Vector3:
	if not _model.palm_grip_enabled or not palm_grips:
		return skeleton.to_global(skeleton.get_bone_global_pose(_hand_bones[side]).origin)
	var offset: Vector3 = _hand_sources[side].transposed() * _model.palm_offsets[side] / _scale
	return skeleton.to_global(skeleton.get_bone_global_pose(_hand_bones[side]) * offset)

func sync(delta := 1.0 / 60.0) -> void:
	if skeleton == null: return
	var changed := false
	if _has_palms:
		var alive: bool = not is_instance_valid(_model._owner_actor) or _model._owner_actor.get("dead") != true
		for i in 2:
			var frame: Variant = _model.hand_frames[i] if alive and palm_grips and _model.hand_targets[i] is Vector3 else null
			if frame != _hand_frames[i]:
				_hand_frames[i] = frame
				changed = true
			if _grip_shapes[i] >= 0:
				var weight: float = _model.hand_grip_weights[i] if frame is Basis else (.18 if alive else 0.0)
				# Este driver é o único escritor: não consultar o servidor por quadro
				# quando a mão já chegou à forma solicitada.
				if not is_equal_approx(_grip_values[i], weight):
					_grip_values[i] = move_toward(_grip_values[i], weight, delta * 14.0)
					mesh_node.set_blend_shape_value(_grip_shapes[i], _grip_values[i])
	for k in _tracked.size():
		var transform_now := _tracked[k].transform
		if transform_now != _cache[k]:
			_cache[k] = transform_now
			changed = true
	if not changed: return
	var optimized := optimize_pose_chain and _has_palms
	# A varredura acima acabou de ler todas essas transformações, sem yield nem
	# mutação intermediária. Reaproveitar o snapshot evita getters repetidos.
	var t_pelvis := _cache[0] if optimized else _pelvis.transform
	var spine_local := _cache[1] if optimized else _spine.transform
	var head_local := _cache[2] if optimized else _head.transform
	var t_spine := t_pelvis * spine_local
	var spine_q := spine_local.basis.get_rotation_quaternion()
	var head_q := head_local.basis.orthonormalized().get_rotation_quaternion()
	var arm_origin_0 := Vector3.ZERO
	var arm_origin_1 := Vector3.ZERO
	_joint_bases[JB_PELVIS] = t_pelvis.basis
	for f in 3:
		_joint_bases[JB_SPINE + f] = t_pelvis.basis * Basis(Quaternion.IDENTITY.slerp(spine_q, (f + 1) / 3.0))
	_joint_bases[JB_NECK] = t_spine.basis * Basis(Quaternion.IDENTITY.slerp(head_q, 0.4))
	_joint_bases[JB_HEAD] = t_spine.basis * Basis(head_q)
	for i in 2:
		var base := JB_LIMBS + i * 5
		var t_thigh := t_pelvis * (_cache[3 + i] if optimized else _thighs[i].transform)
		var t_shin := t_thigh * (_cache[5 + i] if optimized else _shins[i].transform)
		var t_foot := t_shin * (_cache[7 + i] if optimized else _feet[i].transform)
		var t_arm := t_spine * (_cache[9 + i] if optimized else _arms[i].transform)
		var t_fore := t_arm * (_cache[11 + i] if optimized else _forearms[i].transform)
		if i == 0: arm_origin_0 = t_arm.origin
		else: arm_origin_1 = t_arm.origin
		_joint_bases[base] = t_thigh.basis
		_joint_bases[base + 1] = t_shin.basis
		_joint_bases[base + 2] = t_foot.basis
		_joint_bases[base + 3] = t_arm.basis
		_joint_bases[base + 4] = t_fore.basis
	var glb_position := glb_root.position
	for k in _e_bone.size():
		var bone := _e_bone[k]
		var parent := _e_parent[k]
		var parent_global: Basis = _globals[parent] if parent >= 0 else Basis.IDENTITY
		var jb := _e_jb[k]
		var need_origin := not optimized or _e_need_origin[k] != 0
		var is_arm := jb == JB_LIMBS + 3 or jb == JB_LIMBS + 8
		var parent_origin: Vector3 = _global_origins[parent] if parent >= 0 and (need_origin or is_arm) else Vector3.ZERO
		if jb < 0:
			_globals[bone] = parent_global * _e_rest[k]
			if need_origin: _global_origins[bone] = parent_origin + parent_global * _e_position[k]
			continue
		var desired: Basis = _joint_bases[jb] * _e_neutral[k]
		# A arma pede uma palma orientada; o punho não deve herdar a rotação do cotovelo.
		if _has_palms and _e_hand[k] >= 0:
			var side := _e_hand[k]
			if _hand_frames[side] is Basis: desired = _hand_frames[side] * _hand_sources[side]
		_globals[bone] = desired
		# Bases ortonormais: a inversa é a transposta.
		skeleton.set_bone_pose_rotation(bone, (parent_global.transposed() * desired).get_rotation_quaternion())
		var bone_position := _e_position[k]
		if is_arm:
			# A coluna do GLB distribui a inclinação por três ossos. A junta da IK tem um só pivô;
			# alinhar as origens elimina o deslocamento comum dos dois punhos durante a corrida.
			if correct_hand_reach:
				var side := 0 if jb == JB_LIMBS + 3 else 1
				var arm_origin: Vector3 = (arm_origin_0 if side == 0 else arm_origin_1) if optimized else (t_spine * _arms[side].transform).origin
				var target_origin := (arm_origin - glb_position) / _scale
				# Consultar duas vezes o esqueleto sujo forçava reavaliação; usa a mesma cadeia já calculada.
				bone_position = parent_global.transposed() * (target_origin - parent_origin)
			else:
				bone_position = _e_position[k]
			skeleton.set_bone_pose_position(bone, bone_position)
		if parent < 0:
			bone_position = (t_pelvis.origin + t_pelvis.basis * _hips_offset - glb_position) / _scale
			skeleton.set_bone_pose_position(bone, bone_position)
		if need_origin: _global_origins[bone] = parent_origin + parent_global * bone_position
