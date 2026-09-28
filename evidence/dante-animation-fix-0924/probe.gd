extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var a=load("res://scripts/Actor.gd").new()
	a.is_player=true
	root.add_child(a)
	a.set_physics_process(false)
	for id in ["smg","fists","grenade"]:
		var p=load("res://gameplay/WeaponRigPose.gd").new()
		for tick in 240:
			if tick==45: p.attack(id)
			a._pose_locomotion(Vector3.ZERO,3.5,Vector3.ZERO,0.0)
			var packet=p.update(id,1.0/60.0,tick<220,tick>=120 and tick<210 and id=="smg",float(tick-120)/90.0,false,false,a.phase)
			a.set_combat_weapon_pose(id,packet)
			a._apply_combat_weapon_pose()
			if (id=="smg" and tick in [208,209,210,211]) or (id=="fists" and tick in [49,50,51,52]) or (id=="grenade" and tick in [82,83,84,85]):
				print(id," ",tick," target=",packet.right," basis=",packet.right_basis.get_euler()," torso=",packet.torso_yaw)
				for name in ["RightArm","RightForeArm","RightHand","LeftForeArm"]:
					var b=a.skeleton.find_bone(name)
					print(name," pos=",a.skeleton.get_bone_global_pose(b).origin," rot=",a.skeleton.get_bone_pose_rotation(b))
	quit()
