extends RefCounted
## Conduz o esqueleto do Meshy a partir das âncoras articuladas do rig antigo
## (TorsoNode, HeadNode, braços, pernas). Embarque em veículo, esqui, queda,
## cabine, moto e prévia da loja já animam essas âncoras; reescrever cada um para
## o esqueleto novo duplicaria toda a coreografia. Copia apenas direções de
## segmento, não comprimentos, para não esticar as proporções do modelo importado.

const LEGACY_HIP_HEIGHT := 0.684

static func find_anchors(root: Node3D) -> Dictionary:
	var anchors := {}
	for key in ["TorsoNode", "HeadNode", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg"]:
		var node := root.get_node_or_null(key) as Node3D
		if node == null: return {}
		anchors[key] = node
	for side in ["Left", "Right"]:
		var lower_arm := (anchors[side + "UpperArm"] as Node3D).get_node_or_null(side + "LowerArm") as Node3D
		var lower_leg := (anchors[side + "UpperLeg"] as Node3D).get_node_or_null(side + "LowerLeg") as Node3D
		if lower_arm == null or lower_leg == null: return {}
		anchors[side + "LowerArm"] = lower_arm
		anchors[side + "Palm"] = lower_arm.get_node_or_null("Palm")
		anchors[side + "LowerLeg"] = lower_leg
		anchors[side + "Foot"] = lower_leg.get_node_or_null("Foot")
	return anchors

static func apply(skeleton: Skeleton3D, bones: Dictionary, rests: Array[Transform3D], root: Node3D, anchors: Dictionary) -> void:
	if anchors.is_empty() or not skeleton.is_inside_tree() or not root.is_inside_tree(): return
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose(i, rests[i])
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var to_root := root.global_transform.affine_inverse()
	var skeleton_basis := skeleton.global_basis.orthonormalized()
	var root_basis := root.global_basis.orthonormalized()
	# Pelve: deslocamento do meio dos quadris em relação à altura de repouso antiga
	# (agachar na cabine, flexionar no esqui, subir na moto).
	var hips: int = bones.Hips
	var middle := (to_root * (anchors.LeftUpperLeg as Node3D).global_position + to_root * (anchors.RightUpperLeg as Node3D).global_position) * 0.5
	var world_offset := root.global_basis * (middle - Vector3(0, LEGACY_HIP_HEIGHT, 0))
	var hip_pose := rests[hips]
	hip_pose.origin += skeleton.global_basis.inverse() * world_offset
	skeleton.set_bone_pose(hips, hip_pose)
	_orient(skeleton, bones.Spine02, _relative(anchors.TorsoNode, root_basis, skeleton_basis))
	_orient(skeleton, bones.Head, _relative(anchors.HeadNode, root_basis, skeleton_basis))
	for side in ["Left", "Right"]:
		var upper_arm: Node3D = anchors[side + "UpperArm"]
		var lower_arm: Node3D = anchors[side + "LowerArm"]
		var palm: Node3D = anchors[side + "Palm"]
		var hand_point := palm.global_position if palm != null else lower_arm.to_global(Vector3(0, -0.20, 0))
		_aim(skeleton, bones[side + "Arm"], bones[side + "ForeArm"], to_skeleton * lower_arm.global_position - to_skeleton * upper_arm.global_position)
		_aim(skeleton, bones[side + "ForeArm"], bones[side + "Hand"], to_skeleton * hand_point - to_skeleton * lower_arm.global_position)
		var upper_leg: Node3D = anchors[side + "UpperLeg"]
		var lower_leg: Node3D = anchors[side + "LowerLeg"]
		var foot: Node3D = anchors[side + "Foot"]
		var ankle := foot.global_position if foot != null else lower_leg.to_global(Vector3(0, -0.30, 0))
		_aim(skeleton, bones[side + "UpLeg"], bones[side + "Leg"], to_skeleton * lower_leg.global_position - to_skeleton * upper_leg.global_position)
		_aim(skeleton, bones[side + "Leg"], bones[side + "Foot"], to_skeleton * ankle - to_skeleton * lower_leg.global_position)
		if foot != null:
			_orient(skeleton, bones[side + "Foot"], _relative(foot, root_basis, skeleton_basis))

## Rotação do nó em relação à raiz do rig antigo, expressa no espaço do esqueleto.
static func _relative(node: Node3D, root_basis: Basis, skeleton_basis: Basis) -> Basis:
	var world := node.global_basis.orthonormalized() * root_basis.inverse()
	return skeleton_basis.inverse() * world * skeleton_basis

static func _orient(skeleton: Skeleton3D, bone: int, rotation: Basis) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = rotation * skeleton.get_bone_global_rest(bone).basis
	skeleton.set_bone_global_pose(bone, pose)

static func _aim(skeleton: Skeleton3D, bone: int, child: int, desired: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	var current := skeleton.get_bone_global_pose(child).origin - pose.origin
	if desired.length_squared() < 1e-10 or current.length_squared() < 1e-10: return
	var from := current.normalized()
	var to := desired.normalized()
	if from.dot(to) < -0.9999:
		# Arco de meia volta: Quaternion(from, to) é indefinido; gira por um eixo perpendicular.
		var axis := from.cross(Vector3.RIGHT if absf(from.x) < 0.9 else Vector3.UP).normalized()
		pose.basis = Basis(axis, PI) * pose.basis
	else:
		pose.basis = Basis(Quaternion(from, to)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
