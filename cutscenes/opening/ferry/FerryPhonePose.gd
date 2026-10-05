extends RefCounted
## Authored FK pose: the wrist follows its forearm, never a weapon's palm basis.
static func apply(actor, prop: Node3D, weight: float, forearm_roll := 1.5, wrist_curl := .65) -> void:
	var rig: Skeleton3D = actor.skeleton
	var upper: int = actor._combat_bones.RightArm
	var fore: int = actor._combat_bones.RightForeArm
	var hand: int = actor._combat_bones.RightHand
	var idle := [rig.get_bone_pose_rotation(upper),rig.get_bone_pose_rotation(fore)]
	var elbow := rig.to_local(actor.visual.to_global(Vector3(.31,1.03,-.10)))
	actor._point_combat_bone(upper,fore,elbow)
	var wrist := rig.to_local(actor.visual.to_global(Vector3(.26,1.29,-.32)))
	actor._point_combat_bone(fore,hand,wrist)
	var fore_axis := rig.get_bone_rest(hand).origin.normalized()
	rig.set_bone_pose_rotation(fore,rig.get_bone_pose_rotation(fore)*Quaternion(fore_axis,forearm_roll))
	var raised := [rig.get_bone_pose_rotation(upper),rig.get_bone_pose_rotation(fore)]
	rig.set_bone_pose_rotation(upper,idle[0].slerp(raised[0],weight))
	rig.set_bone_pose_rotation(fore,idle[1].slerp(raised[1],weight))
	rig.set_bone_pose_rotation(hand,rig.get_bone_pose_rotation(hand)*Quaternion(Vector3.RIGHT,wrist_curl*weight))
	# Curl the fingers around the thin handset, with the screen outside the palm.
	if actor._combat_skin.get_blend_shape_count() > 0:
		actor._combat_skin.set_blend_shape_value(0,.45)
	prop.global_transform = rig.global_transform * rig.get_bone_global_pose(hand) * Transform3D(Basis.IDENTITY,Vector3(0,.108,.034))
