extends RefCounted
static func apply(actor: Node, role: String) -> void:
	if actor.has_meta("uniform_detailed"): return
	actor.set_meta("uniform_detailed", true)
	var build := preload("res://world/shared/pedestrians/CitizenDetails.gd")
	var root: Node3D=actor.model_root
	var torso: Node3D=actor.torso_node
	var head: Node3D=actor.head_node
	if role == "police":
		root.scale = Vector3.ONE
	else:
		root.scale=Vector3(randf_range(.93,1.10),randf_range(.94,1.10),1)
	var skin := [Color("c68c67"),Color("8f5f48"),Color("e1b599")].pick_random() as Color
	if role == "police" and actor.has_meta("police_appearance"):
		skin = Color(actor.get_meta("police_appearance").skin)
	for child in head.get_children():
		if child is MeshInstance3D and child.mesh is SphereMesh and child.position.is_zero_approx():
			child.material_override=child.material_override.duplicate()
			child.material_override.albedo_color=skin
	for side in [-1,1]:
		build.piece(head,Vector3(.04,.06,.04),Vector3(side*.17,0,0),skin,true)
		build.piece(head,Vector3(.035,.017,.02),Vector3(side*.065,.015,-.16),Color("252728"))
	build.piece(head,Vector3(.045,.055,.05),Vector3(0,-.025,-.17),skin,true)
	build.piece(torso,Vector3(.36,.035,.35),Vector3(0,-.19,0),Color("272a2e"))
	build.piece(torso,Vector3(.065,.09,.04),Vector3(-.13,.09,-.19),Color("242b32"))
	build.piece(torso,Vector3(.012,.10,.012),Vector3(-.15,.18,-.19),Color("383d40"))
	if role=="fire":
		for y in [-.13,.08]: build.piece(torso,Vector3(.35,.035,.35),Vector3(0,y,0),Color("ded77a"))
		for side in [-1,1]:
			build.piece(root,Vector3(.11,.39,.13),Vector3(side*.08,.86,.24),Color("c8bd58"),true)
	elif role=="medic":
		build.piece(torso,Vector3(.31,.045,.035),Vector3(0,.09,-.18),Color("d8e4df"))
		build.piece(torso,Vector3(.08,.08,.025),Vector3(.09,.02,-.2),Color("eee5d4"))
		build.piece(torso,Vector3(.018,.065,.03),Vector3(.09,.02,-.215),Color("b6453d"))
		build.piece(torso,Vector3(.06,.018,.03),Vector3(.09,.02,-.215),Color("b6453d"))
	else:
		build.piece(torso,Vector3(.06,.025,.025),Vector3(.11,.12,-.19),Color("bdc2b3"))
		for side in [-1,1]: build.piece(torso,Vector3(.09,.10,.035),Vector3(side*.09,-.01,-.18),Color("1f2a3a"))
	build.finish_rig(actor, role)
	for side in [-1,1]:
		var shoulder: Node3D = actor.left_upper_arm if side<0 else actor.right_upper_arm
		build.piece(shoulder,Vector3(.015,.095,.08),Vector3(side*.055,-.06,0),Color("586b7c") if role=="police" else Color("d7d6be"))
		var leg: Node3D = actor.left_lower_leg if side<0 else actor.right_lower_leg
		build.piece(leg,Vector3(.10,.018,.12),Vector3(0,-.235,-.035),Color("4c5054"))
	if role=="police":
		var tactical: bool = actor.tier >= 2
		build.piece(head,Vector3(.055,.050,.020),Vector3(0,.135,-.181),Color("d2b365"))
		for side in [-1,1]:
			build.piece(torso,Vector3(.075,.12,.07),Vector3(side*.18,-.14,-.07),Color("30363e"))
			if tactical:
				build.piece(head,Vector3(.04,.14,.055),Vector3(side*.15,-.045,-.07),Color("30353c")).rotation.z=side*-.2
				var knee: Node3D = actor.left_lower_leg if side<0 else actor.right_lower_leg
				build.piece(knee,Vector3(.105,.115,.045),Vector3(0,-.025,-.06),Color("313b40"),true)
		if tactical:
			for x in [-.10,0,.10]: build.piece(torso,Vector3(.075,.13,.06),Vector3(x,.0,-.21),Color("39434b"))
	elif role=="fire":
		build.piece(head,Vector3(.085,.075,.025),Vector3(0,.095,-.183),Color("e7d6a2"))
		for side in [-1,1]:
			build.piece(torso,Vector3(.035,.37,.045),Vector3(side*.12,.025,-.18),Color("303839"))
			var leg: Node3D = actor.left_lower_leg if side<0 else actor.right_lower_leg
			build.piece(leg,Vector3(.125,.035,.13),Vector3(0,-.15,0),Color("ded77a"))
