extends "res://PlayerCombatPose.gd"
## Pistola centralizada, com a mão de apoio envolvendo a empunhadura.
## Escopeta, recarga e recuo continuam usando as poses compartilhadas.
var _bank_hand := Vector3(.04,.91,-.30)

func update(rig: Node2D, delta: float, aiming: bool, sprinting: bool, arm_swing: float) -> void:
	super.update(rig,delta,aiming,sprinting,arm_swing)
	if rig.active_weapon_id!="pistol" or rig.is_reloading(): return
	var engaged := aiming or action_age<.45
	var target := Vector3(.04,.99 if engaged else .91,-.32 if engaged else -.30)
	target.z+=recoil*.22
	_bank_hand=_bank_hand.lerp(target,1.0-exp(-22.0*delta))
	var gun_basis := Basis(Vector3.RIGHT,_carry_pitch+recoil)
	_solve_pistol_arm(rig.right_upper_arm,rig.right_lower_arm,_bank_hand,1.0)
	rig.weapon_mount_node.position=Vector3(0,-HAND_REACH,0)
	rig.weapon_mount_node.basis=(rig.right_upper_arm.basis*rig.right_lower_arm.basis).inverse()*gun_basis
	var support: Vector3=rig.model_root.to_local(rig.weapon_mount_node.to_global(Vector3(-.055,-.01,.018)))
	_solve_pistol_arm(rig.left_upper_arm,rig.left_lower_arm,support,-1.0)
	for arm in [rig.right_lower_arm,rig.left_lower_arm]:
		arm.get_node("Palm").basis=(arm.get_parent().basis*arm.basis).inverse()*gun_basis

func _solve_pistol_arm(upper: Node3D, lower: Node3D, target: Vector3, side: float) -> void:
	var direction := target-upper.position
	var distance := clampf(direction.length(),.05,.419)
	direction=direction.normalized()
	# Cotovelos ao lado do colete mantêm os antebraços legíveis na câmera alta.
	var bend := Vector3(side*.8,-.35,.2)
	bend=(bend-direction*bend.dot(direction)).normalized()
	var along := (.22*.22-HAND_REACH*HAND_REACH+distance*distance)/(2.0*distance)
	var elbow := upper.position+direction*along+bend*sqrt(maxf(0,.22*.22-along*along))
	upper.quaternion=Quaternion(Vector3.DOWN,(elbow-upper.position).normalized())
	lower.quaternion=Quaternion(Vector3.DOWN,upper.basis.inverse()*(upper.position+direction*distance-elbow).normalized())
